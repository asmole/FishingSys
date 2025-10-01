-- Composed class, solely dependant on FishMechanic, this is just for code readability and shouldn't be used externally
-- Whole function, animation etc. relies mostly on fast call functions that are returned by methods

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Gui = PlayerGui:WaitForChild("Fishing")

local TemporaryVFX = Gui.TemporaryVFX

local ChargeBar = Gui.ChargeBar
local ReelBar = Gui.ReelBar
local ShakeGui = Gui.ShakeGui

-- Palette
local PERFECT_CHARGECOLOR = Color3.fromRGB(97, 157, 44)
local NORMAL_CHARGECOLOR = Color3.fromRGB(255, 255, 255)

local NORMAL_SLIDERCOLOR = Color3.fromRGB(154, 255, 71)
local FAILED_SLIDERCOLOR = Color3.fromRGB(255, 123, 125)

-- Tweens
local SHAKE_PRESS_TWEEN = TweenInfo.new(.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false)
local REEL_FAIL_TWEEN = TweenInfo.new(.75, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false)

-- Special configuration
local SHAKE_PADDING_SCALE = 0 -- Shake button can't get closer than ...% to the edge of the screen

local FishingGui = {}
FishingGui.__index = FishingGui
 
function FishingGui:_open(gui)
	if (self._opened) then
		self._opened.Visible = false
	end
	
	gui.Visible = true
	self._opened = gui
end
 
function FishingGui.new()
	local self = setmetatable({}, FishingGui)
	
	self.Gui = Gui
	
	self._opened = nil
	
	return self
end

function FishingGui:ClosePanel()
	if (not self._opened) then
		return
	end
	
	self._opened.Visible = false
	self._opened = nil
end

function FishingGui:Enable()
	self.Gui.Enabled = true
end
function FishingGui:Disable()
	self.Gui.Enabled = false
end

function FishingGui:RenderThrowing( perfect_charge )
	local charge_slider = ChargeBar.ChargeSlider
	
	self:_open(ChargeBar)
	
	local function update(y)
		if (y >= perfect_charge) then
			charge_slider.BackgroundColor3 = PERFECT_CHARGECOLOR
		else
			charge_slider.BackgroundColor3 = NORMAL_CHARGECOLOR
		end
		
		charge_slider.Size = UDim2.fromScale(1, y)
	end
	
	return update
end
function FishingGui:RenderShaking()
	local shake_button = ShakeGui.ShakeButton
	local press_effect = ShakeGui.PressEffect
	
	self:_open(ShakeGui)
	
	local function move_button()
		local viewport = Camera.ViewportSize
		
		local button_abssize = shake_button.AbsoluteSize
		
		local x_padding = math.max(viewport.X*SHAKE_PADDING_SCALE, button_abssize.X/2)
		local y_padding = math.max(viewport.Y*SHAKE_PADDING_SCALE, button_abssize.Y/2)
		
		local x = math.random(x_padding, viewport.X-x_padding)
		local y = math.random(y_padding, viewport.Y-y_padding)
		
		shake_button.Position = UDim2.fromOffset(x, y)
	end
	local function pressed()
		local effect_instance = press_effect:Clone()
		
		effect_instance.Parent = TemporaryVFX
		effect_instance.Position = shake_button.Position
		effect_instance.Size = shake_button.Size
		effect_instance.UIStroke.Transparency = 0
		TweenService:Create(effect_instance, SHAKE_PRESS_TWEEN, { Size = (shake_button.Size+UDim2.fromScale(.1, .1)) }):Play()
		TweenService:Create(effect_instance.UIStroke, SHAKE_PRESS_TWEEN, { Transparency = 1 }):Play()
		task.delay(1, effect_instance.Destroy, effect_instance)
		
		move_button()
	end
	
	move_button()
	return shake_button.Activated, pressed
end
function FishingGui:RenderReeling(length, size)
	local catch_area = ReelBar.CatchArea
	local fish = ReelBar.Fish
	local countdown_label = ReelBar.CountdownLabel
	
	self:_open(ReelBar)
	
	catch_area.Size = UDim2.new(size, 0, 1, 20)
	catch_area.BackgroundColor3 = NORMAL_SLIDERCOLOR
	countdown_label.Text = string.format("%.1f", length)
	
	local function update(slider_x, fish_x)
		catch_area.Position = UDim2.fromScale(slider_x, .5)
		fish.Position = UDim2.fromScale(fish_x, .5)
	end
	local function start_countdown()
		return task.spawn(function()
			local time_left = length

			while (time_left > 0) do
				time_left -= .1
				countdown_label.Text = string.format("%.1f", time_left)
				
				task.wait(.1)
			end
		end)
	end
	local function failed()
		TweenService:Create(catch_area, REEL_FAIL_TWEEN, { BackgroundColor3 = FAILED_SLIDERCOLOR }):Play()
	end
	
	return update, start_countdown, failed
end

return FishingGui.new()