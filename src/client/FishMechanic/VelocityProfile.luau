-- Calculates and outputs velocity with acceleration and deceleration physics involved for external scripts to use

local NOOP = function() end

local VelocityProfile = {}
VelocityProfile.__index = VelocityProfile

function VelocityProfile:_returnRunClosure(sign, clamp_function, limiter)
	local delta_timestamp = tick()
	local acceleration = (self.A * sign)

	return function()
		local delta_time = tick()-delta_timestamp
		local acceleration_step = (acceleration*delta_time)

		self.Velocity = clamp_function(self.Velocity+acceleration_step, limiter)
		if (self.Velocity == limiter) then -- Object is not accelerating or braking anymore
			self.Accelerating = false
			self.Braking = false
			self.UpdateFunction = NOOP -- Remove unnecessary overhead while removing the need for nil checks in loops
		end
		
		delta_timestamp = tick()
	end
end

function VelocityProfile.new(initial_velocity, final_velocity, acceleration)
	local self = setmetatable({}, VelocityProfile)
	
	self.UpdateFunction = NOOP -- Your thread does the acceleration/deceleration work
	
	self.Velocity = initial_velocity
	
	self.Accelerating = false
	self.Braking = false
	
	self.V0 = initial_velocity
	self.VF = final_velocity
	
	self.A = acceleration
	
	return self
end

function VelocityProfile:SecretReset() -- Useful when the object has no way to move but is still attempting to accelerate or decelerate, removes unnecessary overhead
	self.Velocity = 0
	self.UpdateFunction = NOOP
end

function VelocityProfile:GetDistance( delta_time )
	return self.Velocity*delta_time
end
function VelocityProfile:GetBrakingDistance()
	return (self.Velocity^2) / (2*self.A)
end

function VelocityProfile:Reset()
	self.Accelerating = false
	self.Braking = false
	
	self.Velocity = 0
	self.UpdateFunction = NOOP
end

function VelocityProfile:Accelerate()
	self.Accelerating = true
	self.Braking = false
	self.UpdateFunction = self:_returnRunClosure(1, math.min, self.VF)
end
function VelocityProfile:Brake()
	self.Braking = true
	self.Accelerating = false
	self.UpdateFunction = self:_returnRunClosure(-1, math.max, self.V0)
end

return VelocityProfile