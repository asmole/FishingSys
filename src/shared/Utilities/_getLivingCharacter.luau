-- Returns a player's character, only if it's actually alive
return function(player)
	local character = player.Character

	if (not character) then
		return
	end
	if (not character.Parent) then
		return
	end
	if (not character:FindFirstChild("Humanoid")) then
		return
	end
	if (character.Humanoid.Health == 0) then
		return
	end

	return character
end