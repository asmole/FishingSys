local ContextActionService = game:GetService("ContextActionService")

local FishMechanic = require(script.Parent.FishMechanic)

ContextActionService:BindAction("_a_", function(_, input_state)
	if (input_state == Enum.UserInputState.Begin) then
		FishMechanic:Perform()
	end
end, false, Enum.UserInputType.MouseButton1)