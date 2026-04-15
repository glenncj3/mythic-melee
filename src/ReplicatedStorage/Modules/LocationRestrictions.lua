--[[
	LocationRestrictions — single source of truth for location placement rules.

	Consolidates restriction checking previously duplicated across
	MatchManager (validation), BotPlayer (AI decisions), and MatchClient (UI).

	To add a new restriction type, add one entry to the checkers table below.
]]

local LocationRestrictions = {}

-- Check whether a card (by its definition) can be played at a location + row.
-- Returns true if allowed, false + reason string if not.
function LocationRestrictions.canPlayAt(location, cardDef, row)
	if not location or not location.effect then
		return true
	end

	-- Sky Temple: only cards costing 3+
	if location.effect == "Restrict:MinCost:3" then
		if cardDef and cardDef.cost < 3 then
			return false, (cardDef.name or "Card") .. " blocked by " .. (location.name or "location")
		end
	end

	-- Dueling Grounds: front row only (row 1)
	if location.effect == "Restrict:FrontRowOnly" then
		if row and row ~= 1 then
			return false, "Only front row allowed at " .. (location.name or "location")
		end
	end

	return true
end

return LocationRestrictions
