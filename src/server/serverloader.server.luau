local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

PhysicsService:RegisterCollisionGroup("Players")
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		if (not char.Parent) then
			char.AncestryChanged:Wait()
		end
		char:WaitForChild("Humanoid")

		for _, v in (char:GetDescendants()) do
			if (v:IsA("BasePart")) then
				v.CollisionGroup = "Players"
			end
		end
	end)
end)

require(script.Parent.FishingHandler)