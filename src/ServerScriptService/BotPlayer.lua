--[[
	BotPlayer — AI opponent logic for solo playtesting.

	Makes heuristic-based plays: sorts hand by cost descending,
	picks locations based on where it's losing, prefers empty slots,
	overwrites lowest-power card if all slots full.

	Usage:
		local BotPlayer = require(script.Parent.BotPlayer)
		local plays = BotPlayer.decidePlays(gameState, botPlayerID)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Modules.GameConfig)
local CardDatabase = require(Modules.CardDatabase)
local GSU = require(Modules.GameStateUtils)
local LocationRestrictions = require(Modules.LocationRestrictions)

local BotPlayer = {}

-- ============================================================
-- Location Picking
-- ============================================================

local function pickLocation(gameState, playerID)
	local opponent = GSU.getOpponent(gameState, playerID)

	local locScores = {}
	for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
		local myPower = GSU.sumPowerAtLocation(gameState, playerID, locIdx)
		local oppPower = opponent and GSU.sumPowerAtLocation(gameState, opponent, locIdx) or 0
		local pts = gameState.locations[locIdx].pointValue
		local emptySlots = GSU.getEmptySlots(gameState, playerID, locIdx)

		locScores[locIdx] = {
			locIdx = locIdx,
			diff = myPower - oppPower,
			pointValue = pts,
			emptyCount = #emptySlots,
		}
	end

	local best = nil
	for _, ls in pairs(locScores) do
		if best == nil then
			best = ls
		elseif ls.diff < 0 and best.diff >= 0 then
			best = ls
		elseif ls.diff < 0 and best.diff < 0 then
			if ls.pointValue > best.pointValue then
				best = ls
			end
		elseif ls.diff >= 0 and best.diff >= 0 then
			if ls.emptyCount > best.emptyCount then
				best = ls
			elseif ls.emptyCount == best.emptyCount then
				if math.random(2) == 1 then
					best = ls
				end
			end
		end
	end

	return best and best.locIdx or 1
end

-- ============================================================
-- Slot Picking
-- ============================================================

local function pickSlot(gameState, playerID, locIdx, newCardPower)
	local emptySlots = GSU.getEmptySlots(gameState, playerID, locIdx)
	if #emptySlots > 0 then
		return emptySlots[math.random(#emptySlots)]
	end

	-- All full — overwrite lowest-power own card if new card is stronger
	local occupied = GSU.getOccupiedSlots(gameState, playerID, locIdx)
	if #occupied > 0 then
		local weakest = occupied[1]
		if newCardPower > weakest.power then
			return { col = weakest.col, row = weakest.row }
		end
	end

	return nil
end

-- ============================================================
-- Main Decision Function
-- ============================================================

function BotPlayer.decidePlays(gameState, botPlayerID)
	local player = gameState.players[botPlayerID]
	if not player then
		print("[Bot] ERROR: no player data for " .. tostring(botPlayerID))
		return {}
	end

	local plays = {}
	local energyRemaining = player.energy
	local handCopy = {}
	for _, cardID in ipairs(player.hand) do
		table.insert(handCopy, cardID)
	end

	-- Sort hand by cost descending (play biggest cards first)
	table.sort(handCopy, function(a, b)
		local ca = CardDatabase[a]
		local cb = CardDatabase[b]
		if not ca or not cb then return false end
		return ca.cost > cb.cost
	end)

	-- Track which slots we've already planned to use this turn
	local plannedSlots = {}  -- { ["locIdx:col:row"] = true }

	for _, cardID in ipairs(handCopy) do
		local def = CardDatabase[cardID]
		if not def then continue end
		if def.cost > energyRemaining then continue end

		local locIdx = pickLocation(gameState, botPlayerID)

		-- Check if this card can be played at this location
		local location = gameState.locations[locIdx]
		if not LocationRestrictions.canPlayAt(location, def, 1) then
			-- Try the other location
			locIdx = (locIdx == 1) and 2 or 1
			location = gameState.locations[locIdx]
			if not LocationRestrictions.canPlayAt(location, def, 1) then
				continue -- Can't play this card anywhere
			end
		end

		local slot = pickSlot(gameState, botPlayerID, locIdx, def.power)

		-- Check if we've already planned a play for this slot
		if slot then
			local key = locIdx .. ":" .. slot.col .. ":" .. slot.row
			if plannedSlots[key] then
				-- Try finding another slot
				local found = false
				local emptySlots = GSU.getEmptySlots(gameState, botPlayerID, locIdx)
				for _, es in ipairs(emptySlots) do
					local ek = locIdx .. ":" .. es.col .. ":" .. es.row
					if not plannedSlots[ek] then
						slot = es
						found = true
						break
					end
				end
				if not found then
					-- Try other location
					local otherLoc = (locIdx == 1) and 2 or 1
					local otherLocation = gameState.locations[otherLoc]
					if not LocationRestrictions.canPlayAt(otherLocation, def, 1) then
						continue
					end
					slot = pickSlot(gameState, botPlayerID, otherLoc, def.power)
					if slot then
						local ek = otherLoc .. ":" .. slot.col .. ":" .. slot.row
						if plannedSlots[ek] then
							continue
						end
						locIdx = otherLoc
					else
						continue
					end
				end
			end
		end

		if slot then
			local key = locIdx .. ":" .. slot.col .. ":" .. slot.row
			plannedSlots[key] = true

			table.insert(plays, {
				cardID = cardID,
				locIdx = locIdx,
				col = slot.col,
				row = slot.row,
			})
			energyRemaining = energyRemaining - def.cost

			print(string.format("[Bot] %s plans: %s (cost %d) -> loc %d (%d,%d) -- %d energy left",
				botPlayerID, cardID, def.cost, locIdx, slot.col, slot.row, energyRemaining))
		end
	end

	if #plays == 0 then
		print(string.format("[Bot] %s passes (no affordable plays or no slots)", botPlayerID))
	end

	return plays
end

return BotPlayer
