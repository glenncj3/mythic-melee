--[[
	LocationRestrictions — single source of truth for location placement rules.

	Consolidates restriction checking previously duplicated across
	MatchManager (validation), BotPlayer (AI decisions), and MatchClient (UI).

	Table-driven: to add a new restriction type, add one entry to the checkers table.
]]

local LocationRestrictions = {}

-- ============================================================
-- Restriction checkers: each takes (location, cardDef, row, params)
-- and returns true if allowed, or false + reason string if not.
-- ============================================================

local restrictionCheckers = {}

restrictionCheckers["MinCost"] = function(_location, cardDef, _row, params)
	local minCost = tonumber(params[1]) or 0
	if cardDef and cardDef.cost < minCost then
		return false, (cardDef.name or "Card") .. " blocked (costs less than " .. minCost .. ")"
	end
	return true
end

restrictionCheckers["MaxCost"] = function(_location, cardDef, _row, params)
	local maxCost = tonumber(params[1]) or 99
	if cardDef and cardDef.cost > maxCost then
		return false, (cardDef.name or "Card") .. " blocked (costs more than " .. maxCost .. ")"
	end
	return true
end

restrictionCheckers["FrontRowOnly"] = function(_location, _cardDef, row, _params)
	if row and row ~= 1 then
		return false, "Only front row allowed at this location"
	end
	return true
end

restrictionCheckers["NoOngoing"] = function(_location, cardDef, _row, _params)
	if cardDef and cardDef.ability and string.find(cardDef.ability, "Ongoing:") then
		return false, (cardDef.name or "Card") .. " blocked (Ongoing cards not allowed)"
	end
	return true
end

restrictionCheckers["NoAbility"] = function(_location, cardDef, _row, _params)
	if cardDef and cardDef.ability then
		return false, (cardDef.name or "Card") .. " blocked (only vanilla cards allowed)"
	end
	return true
end

-- ============================================================
-- Public API
-- ============================================================

-- Check whether a card (by its definition) can be played at a location + row.
-- Supports compound restriction strings separated by |.
-- Returns true if allowed, false + reason string if not.
function LocationRestrictions.canPlayAt(location, cardDef, row)
	if not location or not location.effect then
		return true
	end

	-- Split compound effects and check each restriction segment
	local segments = string.split(location.effect, "|")
	for _, segment in ipairs(segments) do
		local parts = string.split(segment, ":")
		if parts[1] == "Restrict" and #parts >= 2 then
			local restrictType = parts[2]
			local params = {}
			for i = 3, #parts do
				table.insert(params, parts[i])
			end

			local checker = restrictionCheckers[restrictType]
			if checker then
				local allowed, reason = checker(location, cardDef, row, params)
				if not allowed then
					return false, reason
				end
			end
		end
	end

	return true
end

return LocationRestrictions
