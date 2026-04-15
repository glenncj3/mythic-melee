--[[
	AbilityRegistry — maps ability keyword strings to resolver functions.

	Keyword format: "TriggerType:EffectName:Param1:Param2:..."

	Resolver signature:
		function(gameState, sourceCard, sourcePlayerID, sourceLocIdx, sourceCol, sourceRow)
		Returns nothing — modifies gameState in place.

	gameState shape expected by resolvers:
		gameState.players[playerID].boards[locIdx][row][col] = cardState | nil
		gameState.players[playerID].hand = { cardID, ... }
		gameState.players[playerID].deck = { cardID, ... }
		gameState.turn = number
		gameState.turnPlays[playerID] = { { cardID, locIdx, col, row }, ... }

	cardState shape:
		{ cardID, basePower, powerModifiers = {}, currentPower, isToken, isImmune, turnPlayed, playOrder }
]]

local SlotGrid = require(script.Parent.SlotGrid)
local GameConfig = require(script.Parent.GameConfig)
local GSU = require(script.Parent.GameStateUtils)

local AbilityRegistry = {}

-- ============================================================
-- Helpers (AbilityRegistry-specific)
-- ============================================================

-- Count Ongoing cards a player controls (across all locations)
local function countOngoingCards(gameState, playerID, excludeCol, excludeRow, excludeLocIdx)
	local CardDatabase = require(script.Parent.CardDatabase)
	local count = 0
	for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
		for row = 1, GameConfig.GRID_ROWS do
			for col = 1, GameConfig.GRID_COLUMNS do
				if not (col == excludeCol and row == excludeRow and locIdx == excludeLocIdx) then
					local card = GSU.getCard(gameState, playerID, locIdx, col, row)
					if card then
						local def = CardDatabase[card.cardID]
						if def and def.ability and AbilityRegistry.isOngoing(def.ability) then
							count = count + 1
						end
					end
				end
			end
		end
	end
	return count
end

-- ============================================================
-- On Reveal resolvers
-- ============================================================

local onRevealResolvers = {}

-- OnReveal:DrawCard:N
onRevealResolvers["DrawCard"] = function(gameState, sourceCard, playerID, _locIdx, _col, _row, params)
	local amount = tonumber(params[1]) or 1
	print(string.format("  [Ability] %s draws %d card(s)", sourceCard.cardID, amount))
	GSU.drawCards(gameState, playerID, amount)
end

-- OnReveal:AddPower:Target:Amount
onRevealResolvers["AddPower"] = function(gameState, sourceCard, playerID, locIdx, col, row, params)
	local target = params[1]
	local amount = tonumber(params[2]) or 0
	local sourceName = sourceCard.cardID .. "_ONREVEAL"

	if target == "Location" then
		-- +N to all OTHER friendly cards at this location
		local friendlies = GSU.getFriendlyCardsAt(gameState, playerID, locIdx, col, row)
		for _, entry in ipairs(friendlies) do
			GSU.addModifier(entry.card, sourceName, amount, false)
			print(string.format("  [Ability] %s: +%d Power to %s at (%d,%d)",
				sourceCard.cardID, amount, entry.card.cardID, entry.col, entry.row))
		end

	elseif target == "Column" then
		-- +N to all friendly cards in the same column at this location (excluding self)
		local colSlots = SlotGrid.getColumn(col)
		for _, slot in ipairs(colSlots) do
			local card = GSU.getCard(gameState, playerID, locIdx, slot[1], slot[2])
			if card and not (slot[1] == col and slot[2] == row) then
				GSU.addModifier(card, sourceName, amount, false)
				print(string.format("  [Ability] %s: +%d Power to %s at (%d,%d)",
					sourceCard.cardID, amount, card.cardID, slot[1], slot[2]))
			end
		end

	elseif target == "Self" then
		GSU.addModifier(sourceCard, sourceName, amount, false)
		print(string.format("  [Ability] %s: +%d Power to self", sourceCard.cardID, amount))
	end
end

-- OnReveal:RemovePower:Target:Amount
onRevealResolvers["RemovePower"] = function(gameState, sourceCard, playerID, locIdx, col, row, params)
	local target = params[1]
	local amount = tonumber(params[2]) or 0
	local sourceName = sourceCard.cardID .. "_ONREVEAL"

	if target == "Random_Enemy_Here" then
		local enemies = GSU.getEnemyCardsAt(gameState, playerID, locIdx)
		local pick = GSU.pickRandom(enemies)
		if pick then
			GSU.addModifier(pick.card, sourceName, -amount, true)
			print(string.format("  [Ability] %s: -%d Power to enemy %s at (%d,%d)",
				sourceCard.cardID, amount, pick.card.cardID, pick.col, pick.row))
		end

	elseif target == "Random_Friendly_Here" then
		local friendlies = GSU.getFriendlyCardsAt(gameState, playerID, locIdx, col, row)
		local pick = GSU.pickRandom(friendlies)
		if pick then
			GSU.addModifier(pick.card, sourceName, -amount, false)
			print(string.format("  [Ability] %s: -%d Power to friendly %s at (%d,%d)",
				sourceCard.cardID, amount, pick.card.cardID, pick.col, pick.row))
		end

	elseif target == "All_Enemy_Here" then
		local enemies = GSU.getEnemyCardsAt(gameState, playerID, locIdx)
		for _, entry in ipairs(enemies) do
			GSU.addModifier(entry.card, sourceName, -amount, true)
			print(string.format("  [Ability] %s: -%d Power to enemy %s at (%d,%d)",
				sourceCard.cardID, amount, entry.card.cardID, entry.col, entry.row))
		end
	end
end

-- OnReveal:ConditionalPower:Condition:Amount
onRevealResolvers["ConditionalPower"] = function(gameState, sourceCard, playerID, locIdx, _col, _row, params)
	local condition = params[1]
	local amount = tonumber(params[2]) or 0
	local sourceName = sourceCard.cardID .. "_ONREVEAL"

	if condition == "Opponent_Played_Here" then
		local opponent = GSU.getOpponent(gameState, playerID)
		local opponentPlayed = false
		if opponent and gameState.turnPlays and gameState.turnPlays[opponent] then
			for _, play in ipairs(gameState.turnPlays[opponent]) do
				if play.locIdx == locIdx then
					opponentPlayed = true
					break
				end
			end
		end
		if opponentPlayed then
			GSU.addModifier(sourceCard, sourceName, amount, false)
			print(string.format("  [Ability] %s: condition met (opponent played here), +%d Power",
				sourceCard.cardID, amount))
		else
			print(string.format("  [Ability] %s: condition NOT met (opponent didn't play here)",
				sourceCard.cardID))
		end

	elseif condition == "Empty_Slots_Here" then
		local emptySlots = GSU.getEmptySlots(gameState, playerID, locIdx)
		local totalBonus = #emptySlots * amount
		if totalBonus > 0 then
			GSU.addModifier(sourceCard, sourceName, totalBonus, false)
			print(string.format("  [Ability] %s: %d empty slots, +%d Power",
				sourceCard.cardID, #emptySlots, totalBonus))
		end
	end
end

-- OnReveal:MoveThis:OtherLocation
onRevealResolvers["MoveThis"] = function(gameState, sourceCard, playerID, locIdx, col, row, _params)
	local otherLocIdx = (locIdx == 1) and 2 or 1
	local emptySlots = GSU.getEmptySlots(gameState, playerID, otherLocIdx)
	local pick = GSU.pickRandom(emptySlots)
	if pick then
		GSU.setCard(gameState, playerID, locIdx, col, row, nil)
		GSU.setCard(gameState, playerID, otherLocIdx, pick.col, pick.row, sourceCard)
		print(string.format("  [Ability] %s: moved from loc %d (%d,%d) to loc %d (%d,%d)",
			sourceCard.cardID, locIdx, col, row, otherLocIdx, pick.col, pick.row))
	else
		print(string.format("  [Ability] %s: no empty slot at other location, move failed",
			sourceCard.cardID))
	end
end

-- OnReveal:SetPower:Source
onRevealResolvers["SetPower"] = function(gameState, sourceCard, playerID, locIdx, _col, _row, params)
	local source = params[1]
	local sourceName = sourceCard.cardID .. "_ONREVEAL"

	if source == "Highest_Enemy_Here" then
		local enemies = GSU.getEnemyCardsAt(gameState, playerID, locIdx)
		local highest = 0
		for _, entry in ipairs(enemies) do
			local power = GSU.getCurrentPower(entry.card)
			if power > highest then
				highest = power
			end
		end
		local diff = highest - sourceCard.basePower
		if diff ~= 0 then
			GSU.addModifier(sourceCard, sourceName, diff, false)
			print(string.format("  [Ability] %s: set Power to match highest enemy (%d), +%d modifier",
				sourceCard.cardID, highest, diff))
		else
			print(string.format("  [Ability] %s: already matches highest enemy Power (%d)",
				sourceCard.cardID, highest))
		end
	end
end

-- OnReveal:DestroyBelow:PowerThreshold:Scope
onRevealResolvers["DestroyBelow"] = function(gameState, sourceCard, playerID, locIdx, col, row, params)
	local threshold = tonumber(params[1]) or 0
	local scope = params[2] or "Here_Both"

	local function destroyIfWeak(pid, loc)
		for r = 1, GameConfig.GRID_ROWS do
			for c = 1, GameConfig.GRID_COLUMNS do
				if not (pid == playerID and loc == locIdx and c == col and r == row) then
					local card = GSU.getCard(gameState, pid, loc, c, r)
					if card then
						local power = GSU.getCurrentPower(card)
						if power <= threshold then
							print(string.format("  [Ability] %s: destroying %s (Power %d <= %d) at loc %d (%d,%d)",
								sourceCard.cardID, card.cardID, power, threshold, loc, c, r))
							GSU.destroyCard(gameState, pid, loc, c, r)
						end
					end
				end
			end
		end
	end

	if scope == "Here_Both" then
		for pid, _ in pairs(gameState.players) do
			destroyIfWeak(pid, locIdx)
		end
	elseif scope == "Here_Friendly" then
		destroyIfWeak(playerID, locIdx)
	elseif scope == "Here_Enemy" then
		local opponent = GSU.getOpponent(gameState, playerID)
		if opponent then
			destroyIfWeak(opponent, locIdx)
		end
	end
end

-- OnReveal:SummonCopy:Target:Power
onRevealResolvers["SummonCopy"] = function(gameState, sourceCard, playerID, locIdx, col, row, params)
	local tokenPower = tonumber(params[2]) or 1

	local adjSlots = SlotGrid.getAdjacent(col, row)
	local emptyAdj = {}
	for _, slot in ipairs(adjSlots) do
		if not GSU.getCard(gameState, playerID, locIdx, slot[1], slot[2]) then
			table.insert(emptyAdj, { col = slot[1], row = slot[2] })
		end
	end

	local pick = GSU.pickRandom(emptyAdj)
	if pick then
		local token = {
			cardID = sourceCard.cardID,
			basePower = tokenPower,
			powerModifiers = {},
			currentPower = tokenPower,
			isToken = true,
			isImmune = false,
			turnPlayed = gameState.turn,
			playOrder = 999,
		}
		GSU.setCard(gameState, playerID, locIdx, pick.col, pick.row, token)
		print(string.format("  [Ability] %s: summoned a %d-Power copy at (%d,%d)",
			sourceCard.cardID, tokenPower, pick.col, pick.row))
	else
		print(string.format("  [Ability] %s: no empty adjacent slot for copy", sourceCard.cardID))
	end
end

-- ============================================================
-- Ongoing resolvers (called during recalculation sweep)
-- ============================================================

local ongoingResolvers = {}

-- Ongoing:AddPower:Target:Amount
ongoingResolvers["AddPower"] = function(gameState, sourceCard, playerID, locIdx, col, row, params)
	local target = params[1]
	local amount = tonumber(params[2]) or 0
	local sourceName = sourceCard.cardID .. "_ONGOING"

	if target == "Adjacent" then
		local adjSlots = SlotGrid.getAdjacent(col, row)
		for _, slot in ipairs(adjSlots) do
			local card = GSU.getCard(gameState, playerID, locIdx, slot[1], slot[2])
			if card then
				GSU.addModifier(card, sourceName, amount, false)
			end
		end

	elseif target == "Location" then
		local friendlies = GSU.getFriendlyCardsAt(gameState, playerID, locIdx, col, row)
		for _, entry in ipairs(friendlies) do
			GSU.addModifier(entry.card, sourceName, amount, false)
		end

	elseif target == "Row" then
		local rowSlots = SlotGrid.getRow(row)
		for _, slot in ipairs(rowSlots) do
			if not (slot[1] == col and slot[2] == row) then
				local card = GSU.getCard(gameState, playerID, locIdx, slot[1], slot[2])
				if card then
					GSU.addModifier(card, sourceName, amount, false)
				end
			end
		end

	elseif target == "AllLocations" then
		for li = 1, GameConfig.LOCATIONS_PER_GAME do
			for r = 1, GameConfig.GRID_ROWS do
				for c = 1, GameConfig.GRID_COLUMNS do
					if not (c == col and r == row and li == locIdx) then
						local card = GSU.getCard(gameState, playerID, li, c, r)
						if card then
							GSU.addModifier(card, sourceName, amount, false)
						end
					end
				end
			end
		end

	elseif target == "Self" and params[2] == "PerOngoing" then
		-- Sage: handled by AddPower_PerOngoing below
	end
end

-- Ongoing:AddPower:Self:PerOngoing (Sage)
ongoingResolvers["AddPower_PerOngoing"] = function(gameState, sourceCard, playerID, locIdx, col, row, _params)
	local sourceName = sourceCard.cardID .. "_ONGOING"
	local count = countOngoingCards(gameState, playerID, col, row, locIdx)
	if count > 0 then
		GSU.addModifier(sourceCard, sourceName, count, false)
	end
end

-- Ongoing:DoublePower:Location (Warlord)
ongoingResolvers["DoublePower"] = function(_gameState, sourceCard, _playerID, _locIdx, _col, _row, _params)
	sourceCard._doublesLocationPower = true
end

-- Ongoing:Immune (Colossus)
ongoingResolvers["Immune"] = function(_gameState, sourceCard, _playerID, _locIdx, _col, _row, _params)
	sourceCard.isImmune = true
end

-- ============================================================
-- On Destroy resolvers (fired when a card is removed from the board)
-- ============================================================

local onDestroyResolvers = {}

-- OnDestroy:DrawCard:N
onDestroyResolvers["DrawCard"] = function(gameState, sourceCard, playerID, _locIdx, _col, _row, params)
	local amount = tonumber(params[1]) or 1
	print(string.format("  [Ability] %s OnDestroy: draw %d card(s)", sourceCard.cardID, amount))
	GSU.drawCards(gameState, playerID, amount)
end

-- OnDestroy:AddPower:Target:Amount
onDestroyResolvers["AddPower"] = function(gameState, sourceCard, playerID, locIdx, col, row, params)
	local target = params[1]
	local amount = tonumber(params[2]) or 0
	local sourceName = sourceCard.cardID .. "_ONDESTROY"

	if target == "AllFriendlyHere" then
		local friendlies = GSU.getFriendlyCardsAt(gameState, playerID, locIdx, col, row)
		for _, entry in ipairs(friendlies) do
			GSU.addModifier(entry.card, sourceName, amount, false)
			print(string.format("  [Ability] %s OnDestroy: +%d Power to %s",
				sourceCard.cardID, amount, entry.card.cardID))
		end
	end
end

-- OnDestroy:SummonToken:Power
onDestroyResolvers["SummonToken"] = function(gameState, sourceCard, playerID, locIdx, col, row, params)
	local tokenPower = tonumber(params[1]) or 1
	-- Try to place token at the same slot (just vacated), or random empty
	local emptySlots = GSU.getEmptySlots(gameState, playerID, locIdx)
	-- The card's slot may already be nil (since destroy nils first), so include it
	local slot = nil
	for _, s in ipairs(emptySlots) do
		if s.col == col and s.row == row then
			slot = s
			break
		end
	end
	if not slot then
		slot = GSU.pickRandom(emptySlots)
	end
	if slot then
		local token = {
			cardID = sourceCard.cardID .. "_TOKEN",
			basePower = tokenPower,
			powerModifiers = {},
			currentPower = tokenPower,
			isToken = true,
			isImmune = false,
			turnPlayed = gameState.turn,
			playOrder = 999,
		}
		GSU.setCard(gameState, playerID, locIdx, slot.col, slot.row, token)
		print(string.format("  [Ability] %s OnDestroy: summoned %d-Power token at (%d,%d)",
			sourceCard.cardID, tokenPower, slot.col, slot.row))
	end
end

-- OnDestroy:Bounce:Self — return to hand instead of being destroyed
onDestroyResolvers["Bounce"] = function(gameState, sourceCard, playerID, _locIdx, _col, _row, params)
	local target = params[1] or "Self"
	if target == "Self" then
		local player = gameState.players[playerID]
		if #player.hand < GameConfig.MAX_HAND_SIZE then
			table.insert(player.hand, sourceCard.cardID)
			sourceCard._bouncedToHand = true
			print(string.format("  [Ability] %s OnDestroy: bounced back to hand", sourceCard.cardID))
		else
			print(string.format("  [Ability] %s OnDestroy: hand full, cannot bounce", sourceCard.cardID))
		end
	end
end

-- ============================================================
-- End of Turn resolvers (fired after Ongoing recalc each turn)
-- ============================================================

local endOfTurnResolvers = {}

-- EndOfTurn:AddPower:Target:Amount
endOfTurnResolvers["AddPower"] = function(gameState, sourceCard, playerID, locIdx, col, row, params)
	local target = params[1]
	local amount = tonumber(params[2]) or 0
	local sourceName = sourceCard.cardID .. "_ENDOFTURN"

	if target == "Self" then
		GSU.addModifier(sourceCard, sourceName, amount, false)
		print(string.format("  [Ability] %s EndOfTurn: +%d Power to self", sourceCard.cardID, amount))

	elseif target == "AllFriendlyHere" then
		local friendlies = GSU.getFriendlyCardsAt(gameState, playerID, locIdx, col, row)
		for _, entry in ipairs(friendlies) do
			GSU.addModifier(entry.card, sourceName, amount, false)
		end
		GSU.addModifier(sourceCard, sourceName, amount, false)
		print(string.format("  [Ability] %s EndOfTurn: +%d Power to all friendlies here",
			sourceCard.cardID, amount))
	end
end

-- EndOfTurn:DamageAll:Amount — -N to all enemy cards at this location
endOfTurnResolvers["DamageAll"] = function(gameState, sourceCard, playerID, locIdx, _col, _row, params)
	local amount = tonumber(params[1]) or 1
	local sourceName = sourceCard.cardID .. "_ENDOFTURN"
	local enemies = GSU.getEnemyCardsAt(gameState, playerID, locIdx)
	for _, entry in ipairs(enemies) do
		GSU.addModifier(entry.card, sourceName, -amount, true)
	end
	print(string.format("  [Ability] %s EndOfTurn: -%d Power to %d enemies here",
		sourceCard.cardID, amount, #enemies))
end

-- EndOfTurn:SummonToken:Power — summon a token in a random empty slot here
endOfTurnResolvers["SummonToken"] = function(gameState, sourceCard, playerID, locIdx, _col, _row, params)
	local tokenPower = tonumber(params[1]) or 1
	local emptySlots = GSU.getEmptySlots(gameState, playerID, locIdx)
	local slot = GSU.pickRandom(emptySlots)
	if slot then
		local token = {
			cardID = sourceCard.cardID .. "_TOKEN",
			basePower = tokenPower,
			powerModifiers = {},
			currentPower = tokenPower,
			isToken = true,
			isImmune = false,
			turnPlayed = gameState.turn,
			playOrder = 999,
		}
		GSU.setCard(gameState, playerID, locIdx, slot.col, slot.row, token)
		print(string.format("  [Ability] %s EndOfTurn: summoned %d-Power token at (%d,%d)",
			sourceCard.cardID, tokenPower, slot.col, slot.row))
	end
end

-- ============================================================
-- Public API
-- ============================================================

-- Parse a single ability segment into trigger, effect, and params
function AbilityRegistry.parse(abilityString)
	if not abilityString then return nil end
	local parts = string.split(abilityString, ":")
	if #parts < 2 then return nil end
	local trigger = parts[1]  -- "OnReveal", "Ongoing", "OnDestroy", "EndOfTurn"
	local effect = parts[2]   -- "AddPower", "RemovePower", etc.
	local params = {}
	for i = 3, #parts do
		table.insert(params, parts[i])
	end
	return { trigger = trigger, effect = effect, params = params }
end

-- Parse a compound ability string (pipe-separated) into an array of parsed sub-abilities
function AbilityRegistry.parseAll(abilityString)
	if not abilityString then return {} end
	local results = {}
	local segments = string.split(abilityString, "|")
	for _, segment in ipairs(segments) do
		local parsed = AbilityRegistry.parse(segment)
		if parsed then
			table.insert(results, parsed)
		end
	end
	return results
end

-- Resolve all On Reveal sub-abilities for a card
function AbilityRegistry.resolveOnReveal(gameState, sourceCard, playerID, locIdx, col, row)
	local CardDatabase = require(script.Parent.CardDatabase)
	local def = CardDatabase[sourceCard.cardID]
	if not def or not def.ability then return end

	-- Check if location suppresses On Reveal
	local location = gameState.locations[locIdx]
	if location and location.effect and string.find(location.effect, "SuppressOnReveal") then
		print(string.format("  [Ability] %s: On Reveal suppressed by %s",
			sourceCard.cardID, location.id))
		return
	end

	local allParsed = AbilityRegistry.parseAll(def.ability)
	for _, parsed in ipairs(allParsed) do
		if parsed.trigger == "OnReveal" then
			local resolver = onRevealResolvers[parsed.effect]
			if resolver then
				resolver(gameState, sourceCard, playerID, locIdx, col, row, parsed.params)
			else
				print(string.format("  [Ability] WARNING: no resolver for OnReveal effect '%s'", parsed.effect))
			end
		end
	end
end

-- Apply all Ongoing sub-abilities for a card (called during recalculation sweep)
function AbilityRegistry.applyOngoing(gameState, sourceCard, playerID, locIdx, col, row)
	local CardDatabase = require(script.Parent.CardDatabase)
	local def = CardDatabase[sourceCard.cardID]
	if not def or not def.ability then return end

	local allParsed = AbilityRegistry.parseAll(def.ability)
	for _, parsed in ipairs(allParsed) do
		if parsed.trigger == "Ongoing" then
			-- Special case: Sage (AddPower:Self:PerOngoing)
			if parsed.effect == "AddPower" and #parsed.params >= 2 and parsed.params[2] == "PerOngoing" then
				local resolver = ongoingResolvers["AddPower_PerOngoing"]
				if resolver then
					resolver(gameState, sourceCard, playerID, locIdx, col, row, parsed.params)
				end
			else
				local resolver = ongoingResolvers[parsed.effect]
				if resolver then
					resolver(gameState, sourceCard, playerID, locIdx, col, row, parsed.params)
				else
					print(string.format("  [Ability] WARNING: no resolver for Ongoing effect '%s'", parsed.effect))
				end
			end
		end
	end
end

-- Recalculate a card's currentPower from basePower + modifiers
function AbilityRegistry.recalculatePower(cardState)
	GSU.recalculatePower(cardState)
end

-- Clear all Ongoing-sourced modifiers from every card on the board
function AbilityRegistry.clearOngoingModifiers(gameState)
	for _, player in pairs(gameState.players) do
		for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
			for row = 1, GameConfig.GRID_ROWS do
				for col = 1, GameConfig.GRID_COLUMNS do
					local card = player.boards[locIdx][row][col]
					if card then
						local kept = {}
						for _, mod in ipairs(card.powerModifiers) do
							if not string.find(mod.source, "_ONGOING$") then
								table.insert(kept, mod)
							end
						end
						card.powerModifiers = kept
						card.isImmune = false
						card._doublesLocationPower = nil
					end
				end
			end
		end
	end
end

-- Check if any sub-ability is an Ongoing type
function AbilityRegistry.isOngoing(abilityString)
	if not abilityString then return false end
	for _, parsed in ipairs(AbilityRegistry.parseAll(abilityString)) do
		if parsed.trigger == "Ongoing" then return true end
	end
	return false
end

-- Check if any sub-ability is an OnReveal type
function AbilityRegistry.isOnReveal(abilityString)
	if not abilityString then return false end
	for _, parsed in ipairs(AbilityRegistry.parseAll(abilityString)) do
		if parsed.trigger == "OnReveal" then return true end
	end
	return false
end

-- Check if any sub-ability is an OnDestroy type
function AbilityRegistry.isOnDestroy(abilityString)
	if not abilityString then return false end
	for _, parsed in ipairs(AbilityRegistry.parseAll(abilityString)) do
		if parsed.trigger == "OnDestroy" then return true end
	end
	return false
end

-- Check if any sub-ability is an EndOfTurn type
function AbilityRegistry.isEndOfTurn(abilityString)
	if not abilityString then return false end
	for _, parsed in ipairs(AbilityRegistry.parseAll(abilityString)) do
		if parsed.trigger == "EndOfTurn" then return true end
	end
	return false
end

-- Resolve all OnDestroy sub-abilities for a card being destroyed
function AbilityRegistry.resolveOnDestroy(gameState, sourceCard, playerID, locIdx, col, row)
	local CardDatabase = require(script.Parent.CardDatabase)
	local def = CardDatabase[sourceCard.cardID]
	if not def or not def.ability then return end

	local allParsed = AbilityRegistry.parseAll(def.ability)
	for _, parsed in ipairs(allParsed) do
		if parsed.trigger == "OnDestroy" then
			local resolver = onDestroyResolvers[parsed.effect]
			if resolver then
				resolver(gameState, sourceCard, playerID, locIdx, col, row, parsed.params)
			else
				print(string.format("  [Ability] WARNING: no resolver for OnDestroy effect '%s'", parsed.effect))
			end
		end
	end
end

-- Resolve all EndOfTurn sub-abilities for a card on the board
function AbilityRegistry.resolveEndOfTurn(gameState, sourceCard, playerID, locIdx, col, row)
	local CardDatabase = require(script.Parent.CardDatabase)
	local def = CardDatabase[sourceCard.cardID]
	if not def or not def.ability then return end

	local allParsed = AbilityRegistry.parseAll(def.ability)
	for _, parsed in ipairs(allParsed) do
		if parsed.trigger == "EndOfTurn" then
			local resolver = endOfTurnResolvers[parsed.effect]
			if resolver then
				resolver(gameState, sourceCard, playerID, locIdx, col, row, parsed.params)
			else
				print(string.format("  [Ability] WARNING: no resolver for EndOfTurn effect '%s'", parsed.effect))
			end
		end
	end
end

-- ============================================================
-- Debug / test helpers
-- ============================================================

function AbilityRegistry.printAllAbilities()
	local CardDatabase = require(script.Parent.CardDatabase)
	print("=== Ability Registry — All Card Abilities ===")
	for _, id in ipairs(CardDatabase.getAllIDs()) do
		local c = CardDatabase[id]
		if c.ability then
			local allParsed = AbilityRegistry.parseAll(c.ability)
			for j, parsed in ipairs(allParsed) do
				print(string.format("  [%s] (%d/%d) trigger=%s, effect=%s, params={%s}",
					id, j, #allParsed, parsed.trigger, parsed.effect, table.concat(parsed.params, ", ")))
			end
		end
	end
end

function AbilityRegistry.testParse()
	print("=== AbilityRegistry Parse Test ===")
	local tests = {
		-- Single abilities
		"OnReveal:AddPower:Location:1",
		"OnReveal:RemovePower:Random_Enemy_Here:2",
		"OnReveal:ConditionalPower:Opponent_Played_Here:3",
		"OnReveal:MoveThis:OtherLocation",
		"OnReveal:DestroyBelow:2:Here_Both",
		"OnReveal:SetPower:Highest_Enemy_Here",
		"OnReveal:SummonCopy:Adjacent:1",
		"Ongoing:AddPower:Adjacent:1",
		"Ongoing:DoublePower:Location",
		"Ongoing:Immune",
		"Ongoing:AddPower:Self:PerOngoing",
		-- Compound abilities
		"OnReveal:DrawCard:1|Ongoing:AddPower:Adjacent:1",
		"OnReveal:RemovePower:Random_Enemy_Here:3|OnReveal:AddPower:Self:2",
		"EndOfTurn:AddPower:Self:2|Ongoing:AddPower:Adjacent:1",
	}
	for _, str in ipairs(tests) do
		local allParsed = AbilityRegistry.parseAll(str)
		if #allParsed > 0 then
			for j, parsed in ipairs(allParsed) do
				print(string.format("  OK [%d/%d]: %s -> trigger=%s, effect=%s, params={%s}",
					j, #allParsed, str, parsed.trigger, parsed.effect, table.concat(parsed.params, ", ")))
			end
		else
			print(string.format("  FAIL: %s -> parseAll returned empty", str))
		end
	end
end

return AbilityRegistry
