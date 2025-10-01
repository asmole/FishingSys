local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local FishingGui = require(script.FishingGui)

local VelocityProfile = require(script.VelocityProfile)

local Common = ReplicatedStorage.FishCommon

local Pkgs = Common.Pkgs
local Maid = require(Pkgs.Maid)
local Signal = require(Pkgs.Signal)

local Communication = Common.Communication
local FishEvent = Communication.Client.FishEvent
local IncShake = Communication.Client.IncShake

local ReelState = Communication.Server.ReelState
local CaughtFish = Communication.Server.CaughtFish
local PauseEvent = Communication.Server.PauseEvent
local RestartEvent = Communication.Server.RestartEvent

local ServerCancelEvent = Communication["Server-CancelEvent"]
local ClientCancelEvent = Communication["Client-CancelEvent"]

local Utilities = Common.Utilities
local get_living_character = require(Utilities._getLivingCharacter)

local StateEnum = require(Common.StateEnum)

local CONSTANTS = require(Common.CONSTANTS)
local RANGE = CONSTANTS.RANGE
local ERROR_FLAGS = CONSTANTS.ERROR_FLAGS
local EVENT_LIFESPAN = CONSTANTS.EVENT_LIFESPAN
local CLIENT_REEL_READY_TIMEOUT = CONSTANTS.CLIENT_REEL_READY_TIMEOUT

-- Charge constants
local CHARGE_RATE = 200 -- Per second
local PERFECT_CHARGE = 95

-- Reel constants
local SLIDER_VELOCITY = 100 -- Maximum velocity in units/second
local SLIDER_ACCELERATION = 200

local FAIL_CLOSE_DELAY = 1 -- How much time the player gets after he fails before the event cancels

-- An exponential decay formula
		--[[
			x = difficulty
			y = wiggle_cooldown
			
			x = 150, y = 0.75
			x = 175, y = 0.675
			x = 200, y = 0.6075
			...
]]
local WIGGLE_COOLDOWN_FORMULA = function(difficulty)
	return .75*.9^((difficulty-150)/25)
end

local GET_DEVICESAFE_INPUT = function()
	if (UserInputService.MouseEnabled) then
		return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
	elseif (UserInputService.TouchEnabled) then
		return UserInputService:IsMouseButtonPressed(Enum.UserInputType.Touch)
	elseif (UserInputService.GamepadEnabled) then
		
	end

	return false
end

local function read_serverstatus(state)
	warn("[FishMechanic] Server refused to connect, because:")
	if (bit32.btest(state, ERROR_FLAGS.ARG)) then
		print("Invalid throw velocity passed.")
	end
	if (bit32.btest(state, ERROR_FLAGS.RUNNING)) then
		print("Already fishing, cancelling server fish event.")
	end
	if (bit32.btest(state, ERROR_FLAGS.CHARACTER)) then
		print("Player is state alive.")
	end
	warn(string.rep("-", 59))
end
local function establish_connection(force_velocity)
	local server_status = FishEvent:InvokeServer(force_velocity)

	if (server_status ~= 0b0000) then -- Event is already sanitized from these situations on the client side, this can only happen due to exploits or large network delay
		read_serverstatus(server_status)

		if (bit32.btest(server_status, ERROR_FLAGS.RUNNING)) then -- Weird situation where the client and server aren't coordinated, cancel the fish event
			ClientCancelEvent:FireServer()
		end
		return false
	end
	
	return true
end

local function get_throw_velocity(force)
	local character = LocalPlayer.Character

	local mouse = UserInputService:GetMouseLocation()
	local ray = Camera:ViewportPointToRay(mouse.X, mouse.Y, 0)

	local origin = (character:GetPivot().Position)
	local direction = (ray.Origin+Vector3.new(ray.Direction.X, 1, ray.Direction.Z)*1000 - origin).Unit
	local velocity = direction*(RANGE*force)
	
	return velocity
end

local FishMechanic = {}
FishMechanic.__index = FishMechanic

function FishMechanic:_chargeThrow( update )
	local force = 0
	
	local increment = CHARGE_RATE
	
	update(0)
	while (GET_DEVICESAFE_INPUT()) do
		local delta = RunService.Heartbeat:Wait()
		
		force += (increment*delta)
		if (force >= 100) then
			increment = -CHARGE_RATE
		elseif (force <= 0) then
			increment = CHARGE_RATE
		end
		
		update(force/100)
	end
	
	return force/100 -- Floating point operations are very unstable, better to use an integer then divide it
end
function FishMechanic:_shake( activated, pressed )
	self._Maid.activated = activated:Connect(function()
		IncShake:FireServer()
		pressed()
	end)
end
function FishMechanic:_reel( difficulty, slider_size, update, start_countdown, failed )
	local min_x = 100 * (slider_size/2)
	local max_x = 100-min_x
	
	self._Maid.reel = task.spawn(function()
		local slider_x = 50
		local slider_profile = VelocityProfile.new(0, SLIDER_VELOCITY, SLIDER_ACCELERATION)
		
		local holding_key = false
		local function process_slider(delta_time)
			local is_holding = GET_DEVICESAFE_INPUT()
			local update = (is_holding and not holding_key or not is_holding and holding_key)
			holding_key = is_holding
			
			if (update) then
				slider_profile:Brake() -- Decelerate, before moving in the other direction
			elseif (slider_profile.Velocity == 0 and not slider_profile.Accelerating) then
				slider_profile:Accelerate() -- Begin accelerating again
			end
			
			slider_profile.UpdateFunction()
			
			local distance = slider_profile:GetDistance(delta_time) * (holding_key and 1 or -1)
			if (slider_profile.Braking) then
				slider_x = math.clamp(slider_x-distance, min_x, max_x)
			else
				slider_x = math.clamp(slider_x+distance, min_x, max_x)
			end
			
			if (slider_x == min_x or slider_x == max_x) then
				slider_profile:SecretReset()
			end
		end
		
		local fish_acceleration = difficulty/2
		
		local fish_x = 50
		local fish_profile = VelocityProfile.new(0, difficulty, fish_acceleration)
		
		local fish_goal = 0
		local fish_sign = 0
		
		local wiggle_cooldown = WIGGLE_COOLDOWN_FORMULA(difficulty)
		
		local last_wiggle = 0
		local fish_wiggling = false
		
		local fish_clamp_function
		
		local function process_fish(delta_time)
			if (tick()-last_wiggle <= wiggle_cooldown) then
				return
			elseif (not fish_wiggling) then
				fish_wiggling = true
				fish_goal = math.random(0, 100)
				
				if (fish_x < fish_goal) then
					fish_sign = 1
					fish_clamp_function = math.min
				elseif (fish_x > fish_goal) then
					fish_sign = -1
					fish_clamp_function = math.max
				end
				
				fish_profile:Accelerate()
			end
			if (fish_x == fish_goal) then
				fish_wiggling = false
				last_wiggle = tick()
				fish_profile:Reset()
				
				return
			end
			
			if (not fish_profile.Braking and math.abs(fish_goal-fish_x) <= fish_profile:GetBrakingDistance()) then
				fish_profile:Brake()
			end
			
			fish_profile.UpdateFunction()
			fish_x = fish_clamp_function(fish_x+(fish_profile:GetDistance(delta_time)*fish_sign), fish_goal)
		end
		
		update(.5, .5)
		task.wait(CLIENT_REEL_READY_TIMEOUT) -- Player gets a moment to get ready
		
		self._Maid.gui_countdown = start_countdown()
		
		local reel_failed = false
		while (true) do
			local delta_time = RunService.Heartbeat:Wait()
			
			if not reel_failed and (fish_x < slider_x-min_x or fish_x > slider_x+min_x) then -- If the arrow's out of bounds, cancel
				reel_failed = true
				failed()
				self._Maid.scheduled_cancel = task.delay(FAIL_CLOSE_DELAY, self.CancelEvent, self) -- Give them a chance if they're close
			end
			
			process_slider(delta_time)
			process_fish(delta_time)
			
			update(slider_x/100, fish_x/100)
		end
	end)
end

-- Running thread for fishing as a whole, everything is done sequentally, if one thing fails the whole thing collapses, this is done for security, debugging and efficiency
function FishMechanic:_init(restarted)
	local function after_connection()
		self.State = StateEnum.Shaking
		self:_shake( FishingGui:RenderShaking() )

		local length, difficulty, slider_size = ReelState.OnClientEvent:Wait() -- Wait calls get collected automatically incase it timeouts, no memory leak!

		-- Client only knows about the difficulty of the catch, not the catch
		self.State = StateEnum.Reeling
		self:_reel( difficulty, slider_size, FishingGui:RenderReeling(length, slider_size) )

		local catch = CaughtFish.OnClientEvent:Wait()
		print(`[FishMechanic] Player has caught a {catch}!"`)

		self:CancelEvent( true ) -- The event has already ended on the server by then, only update the client
		
		self.EventEnded:Fire(catch)
	end
	
	local s, r
	if (restarted) then
		s, r = pcall(after_connection)
	else
		s, r = pcall(function()
			self._Maid.timeout_thr = task.delay(3, self.CancelEvent, self) -- Short timeout before server connection is established

			-- Not yet connected, server doesn't know about this
			self.Playing = true
			FishingGui:Enable()

			self.State = StateEnum.Throwing
			local force = self:_chargeThrow( FishingGui:RenderThrowing(PERFECT_CHARGE/100) )

			FishingGui:ClosePanel()

			self.State = StateEnum.Connecting
			if (not establish_connection( get_throw_velocity(force) )) then
				self:CancelEvent( true )
				return
			end
			
			self._Maid.timeout_thr = task.delay(EVENT_LIFESPAN, self.CancelEvent, self, true) -- Timeout independant of the server for security, such as in intense lag
			
			-- Connected, server is aware
			self.Connected = true
		end)
	end
	if (not s) then
		self:CancelEvent() -- No point in continuing if the client's not on board anymore
		
		warn("[FishMechanic] Something went wrong:")
		print(r)
	end
end

function FishMechanic.new()
	local self = setmetatable({}, FishMechanic)
	
	self.EventStarted = Signal.new()
	self.EventCancelled = Signal.new()
	
	self.EventEnded = Signal.new()
	
	self.State = StateEnum.None
	
	self.Playing = false
	self.Connected = false -- If the server knows about this
	
	self._Maid = Maid.new()
	
	ServerCancelEvent.OnClientEvent:Connect(function()
		self:CancelEvent(true)
	end)
	
	PauseEvent.OnClientEvent:Connect(function()
		if (not self.Playing) then
			ClientCancelEvent:FireServer()
			return
		end
		
		self.State = StateEnum.Paused
		
		FishingGui:Disable()
		self._Maid.main_thr = nil
	end)
	RestartEvent.OnClientEvent:Connect(function()
		if (not self.Playing) then
			ClientCancelEvent:FireServer()
			return
		end
		
		FishingGui:Enable()
		self._Maid.main_thr = task.spawn(self._init, self, true)
	end)
	
	LocalPlayer.CharacterRemoving:Connect(function()
		if (self.Playing) then
			self:CancelEvent()
		end
	end)
	
	return self
end

function FishMechanic:Perform()
	if (self.Playing) then
		print("[FishMechanic] Already fishing.")
		return
	end
	if (not get_living_character(LocalPlayer)) then
		print("[FishMechanic] Player is not alive.")
		return
	end
	
	self._Maid.died = LocalPlayer.Character:WaitForChild("Humanoid").Died:Once(function()
		self:CancelEvent()
	end)
	self._Maid.main_thr = task.spawn(self._init, self)
	
	self.EventStarted:Fire()
end

function FishMechanic:CancelEvent(_clientOnly) -- Abstracted
	if (not self.Playing) then
		print("[FishMechanic] Not fishing.")
		return
	end
	
	self._Maid:DoCleaning()
	FishingGui:Disable()
	
	if (not _clientOnly and self.Connected) then
		ClientCancelEvent:FireServer() -- Let the server know we don't want to proceed anymore
		self.Connected = false
	end
	self.State = StateEnum.None
	self.Playing = false
	
	self.EventCancelled:Fire()
end

return FishMechanic.new()