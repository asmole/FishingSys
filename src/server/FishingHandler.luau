local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

local Common = ReplicatedStorage.FishCommon

local Assets = Common.Assets
local BaitModel = Assets.Bait
local RopeConstraint = Assets.RopeConstraint

local Communication = Common.Communication

local FishEvent = Communication.Client.FishEvent
local IncShake = Communication.Client.IncShake

local ClientCancelEvent = Communication["Client-CancelEvent"]
local ServerCancelEvent = Communication["Server-CancelEvent"]

local ReelState = Communication.Server.ReelState
local CaughtFish = Communication.Server.CaughtFish
local RestartEvent = Communication.Server.RestartEvent
local PauseEvent = Communication.Server.PauseEvent

local get_living_character = require(Common.Utilities._getLivingCharacter)

local Pkgs = Common.Pkgs
local Maid = require(Pkgs.Maid)
local Signal = require(Pkgs.Signal)

local StateEnum = require(Common.StateEnum)

local CONSTANTS = require(Common.CONSTANTS)
local RANGE = CONSTANTS.RANGE+3 -- Reduce false negatives
local ERROR_FLAGS = CONSTANTS.ERROR_FLAGS
local EVENT_LIFESPAN = CONSTANTS.EVENT_LIFESPAN
local CLIENT_REEL_READY_TIMEOUT = CONSTANTS.CLIENT_REEL_READY_TIMEOUT

local SHAKE_BOOST = .5
local SHAKE_LENGTH = 5 -- 5 seconds

-- Anticheat
local LOOP_DELTA_TIME = .25

local BAIT_CHECK_RANGE_SPACING = 2

local BAIT_COLLISION_GROUP = "BaitCollisionGroup"
local PLAYER_COLLISION_GROUP = "Players"
PhysicsService:RegisterCollisionGroup(BAIT_COLLISION_GROUP)
PhysicsService:CollisionGroupSetCollidable(BAIT_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)

local function CATCH_LENGTH()
	return math.random(6, 8)
end

local function sanitize_shakeevent(fish_event)
	if (not fish_event) then
		return false
	end
	if (fish_event.State ~= StateEnum.Shaking) then
		return false
	end
	
	return true
end

local function sanitize_fishevent(events, player, force_velocity)
	local server_status = 0b0000
	
	if (not get_living_character(player)) then
		server_status = bit32.bor( server_status, ERROR_FLAGS.CHARACTER )
	end
	if (not force_velocity or force_velocity.Magnitude > RANGE) then
		server_status = bit32.bor( server_status, ERROR_FLAGS.ARG )
	end
	if (events[player]) then
		server_status = bit32.bor( server_status, ERROR_FLAGS.RUNNING )
	end
	
	return server_status
end

local function build_fishevent(player)
	return {
		Player = player,
		State = StateEnum.Paused,
		
		Fish = nil,
		
		_shakeTimestamp = tick(),
		
		_Maid = Maid.new(),
		
		_firstCharacter = player.Character,
	}
end

local function spawn_bait(fish_event, character, throw_velocity)
	local bait = BaitModel:Clone()
	bait.Parent = character
	bait.CanCollide = true
	bait.CollisionGroup = BAIT_COLLISION_GROUP
	
	local rope = RopeConstraint:Clone()
	rope.Parent = bait
	rope.Length = RANGE
	rope.Attachment0 = bait.Attachment
	rope.Attachment1 = character.RightHand.RightGripAttachment
	
	bait:PivotTo(character:GetPivot())
	bait:SetNetworkOwner(nil) -- Give control to the server temporarily to apply force properly
	bait:ApplyImpulse(throw_velocity)
	bait:SetNetworkOwnershipAuto() -- Give it back to the client
	
	fish_event._Maid.bait = bait
end

local FishingHandler = {}
FishingHandler.__index = FishingHandler

function FishingHandler:_rollFish( --[[Change this up to whatever system you have]] )
	local temp_pool = {
		{"Easy Fish", 150},
		{"Mid Fish", 175},
		{"Hard Fish", 200},
		{"Hardest Fish", 250},
	}
	
	local roll = temp_pool[math.random(1, #temp_pool)]
	
	return roll[1], roll[2]
end

function FishingHandler:_reel(fish_event)
	return task.spawn(function()
		local player = fish_event.Player
		
		local length = CATCH_LENGTH()
		local fish, difficulty = self:_rollFish()

		fish_event.State = StateEnum.Reeling
		fish_event.Fish = fish
		ReelState:FireClient(player, length, difficulty, .5)

		task.wait(CLIENT_REEL_READY_TIMEOUT + length)
		
		CaughtFish:FireClient(player, fish)
		self:CancelEvent(player, true)
		
		self.EventEnded:Fire(player, fish)
	end)
end

function FishingHandler:_initAnticheat()
	local params = RaycastParams.new()
	params.IgnoreWater = false
	params.RespectCanCollide = true
	params.FilterType = Enum.RaycastFilterType.Exclude
	
	local function pause_fishevent(fish_event)
		fish_event.State = StateEnum.Paused

		fish_event.Fish = nil

		PauseEvent:FireClient(fish_event.Player)
	end
	local function restart_fishevent(fish_event)
		fish_event.State = StateEnum.Shaking
		
		fish_event.Fish = nil
		fish_event._shakeTimestamp = tick()
		
		RestartEvent:FireClient(fish_event.Player)
	end
	
	while (task.wait(LOOP_DELTA_TIME)) do
		for _, fish_event in (self.Events) do
			-- There's a front end check already that's faster, this check is for security
			local first_character = fish_event._firstCharacter
			if (not first_character.Parent or not first_character:FindFirstChild("Humanoid") or first_character.Humanoid.Health == 0) then
				self:CancelEvent(fish_event.Player, true) -- Client should always be ahead in cancelling the event than this, unless it's been tampered with via exploits
				continue
			end
			
			local bait = fish_event._Maid.bait
			if (not bait) then
				self:CancelEvent(fish_event.Player)
				continue
			end
			
			local origin_offset = Vector3.new(0, (bait.Size.Y*BAIT_CHECK_RANGE_SPACING), 0)
			local direction = Vector3.new(0, -bait.Size.Y*BAIT_CHECK_RANGE_SPACING*2, 0)
			
			params.FilterDescendantsInstances = {bait}
			local raycast = workspace:Raycast(bait.Position+origin_offset, direction, params)
			
			if (not raycast or raycast.Material ~= Enum.Material.Water) then
				if (fish_event.State ~= StateEnum.Paused) then
					pause_fishevent(fish_event)
				end
			else
				if (fish_event.State == StateEnum.Paused) then
					restart_fishevent(fish_event)
				end
			end
		end
	end
end

function FishingHandler:_init()
	function FishEvent.OnServerInvoke(player, force_velocity)
		local server_status = sanitize_fishevent(self.Events, player, force_velocity) -- God forbid each function takes up more than 2 lines
		if (server_status == 0b0000) then
			self.Events[player] = build_fishevent(player)
			self.Events[player]._Maid.timeout = task.delay(EVENT_LIFESPAN, self.CancelEvent, self, player, true) -- Fish event ends either by a timeout, client request or by completing
			
			spawn_bait(self.Events[player], player.Character, force_velocity)
			
			self.EventStarted:Fire(self.Events[player])
		end
		
		return server_status
	end
	
	ClientCancelEvent.OnServerEvent:Connect(function(player)
		self:CancelEvent(player, true)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:CancelEvent(player, true)
	end)
	
	IncShake.OnServerEvent:Connect(function(player)
		local fish_event = self.Events[player]
		
		if (not sanitize_shakeevent(fish_event)) then
			return
		end
		
		fish_event._shakeTimestamp -= SHAKE_BOOST -- Only checks when the player presses the shake button (Anti afk)
		if (tick()-fish_event._shakeTimestamp >= SHAKE_LENGTH) then
			fish_event._Maid.reel = self:_reel(fish_event)
		end
	end)
	
	self:_initAnticheat()
end

function FishingHandler.new()
	local self = setmetatable({}, FishingHandler)
	
	self.EventStarted = Signal.new()
	self.EventCancelled = Signal.new()
	
	self.EventEnded = Signal.new()
	
	self.Events = {}
	
	self:_init()
	
	return self
end

function FishingHandler:CancelEvent( player, _dontUpdateClient ) -- 2nd and 3rd arguments are abstracted
	if (not self.Events[player]) then
		return
	end
	
	local state = self.Events[player].State
	
	self.Events[player]._Maid:Destroy()
	self.Events[player] = nil
	
	if (not _dontUpdateClient) then
		ServerCancelEvent:FireClient(player)
	end
	
	self.EventCancelled:Fire(player, state)
end

return FishingHandler.new()