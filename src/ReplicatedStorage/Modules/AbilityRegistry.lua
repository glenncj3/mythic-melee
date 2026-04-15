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

local AbilityRegistry = {}

-- ============================================================
-- Helpers
-- ============================================================

-- Get opponent player ID
local function getOpponent(gameState, playerID)
	for pid, _ in pairs(gameState.players) do
		if pid ~= playerID then
			return pid
		end
	end
	return nil
end

-- Get the card state at a specific slot
local function getCard(gameState, playerID, locIdx, col, row)
	local board = gameState.players[playerID].boards[locIdx]
	if board and board[row] and board[row][col] then
		return board[row][col]
	end
	return nil
end

-- Set a card state at a specific slot
local function setCard(gameState, playerID, locIdx, col, row, cardState)
	gameState.players[playerID].boards[locIdx][row][col] = cardState
end

-- Add a power modifier to a card (respects immunity for enemy-sourced debuffs)
local function addModifier(cardState, source, amount, isEnemySourced)
	if cardState.isImmune and isEnemySourced and amount < 0 then
		return -- immune to enemy debuffs
	end
	table.insert(cardState.powerModifiers, { source = source, amount = amount })
end

-- Get all friendly cards at a location (excluding a specific slot if provided)
local function getFriendlyCardsAt(gameState, playerID, locIdx, excludeCol, excludeRow)
	local cards = {}
	for row = 1, GameConfig.GRID_ROWS do
		for col = 1, GameConfig.GRID_COLUMNS do
			if not (col == excludeCol and row == excludeRow) then
				local card = getCard(gameState, playerID, locIdx, col, row)
				if card then
					table.insert(cards, { card = card, col = col, row = row, locIdx = locIdx })
				end
			end
		end
	end
	return cards
end

-- Get all enemy cards at a location
local function getEnemyCardsAt(gameState, playerID, locIdx)
	local opponent = getOpponent(gameState, playerID)
	if not opponent then return {} end
	local cards = {}
	for row = 1, GameConfig.GRID_ROWS do
		for col = 1, GameConfig.GRID_COLUMNS do
			local card = getCard(gameState, opponent, locIdx, col, row)
			if card then
				table.insert(cards, { card = card, col = col, row = row, locIdx = locIdx, playerID = opponent })
			end
		end
	end
	return cards
end

-- Get empty slots at a location for a player
local function getEmptySlots(gameState, playerID, locIdx)
	local slots = {}
	for row = 1, GameConfig.GRID_ROWS do
		for col = 1, GameConfig.GRID_COLUMNS do
			if not getCard(gameState, playerID, locIdx, col, row) then
				table.insert(slots, { col = col, row = row })
			end
		end
	end
	return slots
end

-- Pick a random element from a list
local function pickRandom(list)
	if #list == 0 then return nil end
	return list[math.random(#list)]
end

-- Draw N cards from a player's deck into hand
local function drawCards(gameState, playerID, count)
	local player = gameState.players[playerID]
	for _ = 1, count do
		if #player.hand >= GameConfig.MAX_HAND_SIZE then break end
		if #player.deck == 0 then break end
		local card = table.remove(player.deck, 1)
		table.insert(player.hand, card)
		print(string.format("  [Draw] %s drew a card (hand size: %d)", tostring(playerID), #player.hand))
	end
end

-- Count Ongoing cards a player controls (across all locations)
local function countOngoingCards(gameState, playerID, excludeCol, excludeRow, excludeLocIdx)
	local CardDatabase = require(script.Parent.CardDatabase)
	local count = 0
	for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
		for row = 1, GameConfig.GRID_ROWS do
			for col = 1, GameConfig.GRID_COLUMNS do
				if not (col == excludeCol and row == excludeRow and locIdx == excludeLocIdx) then
					local card = getCard(gameState, playerID, locIdx, col, row)
					if card then
						local def = CardDatabase[card.cardID]
						if def and def.ability and string.find(def.ability, "^Ongoing:") then
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
onRevealResolvers["DrawCard"] = function(gameState, sourceCard, playerID, locIdx, col, row, params)
	local amount = tonumber(params[1]) or 1
	print(string.format("  [Ability] %s draws %d card(s)", sourceCard.cardID, amount))
	drawCards(gameState, playerID, amount)
end

-- OnReveal:AddPower:Target:Amount
onRevealResolvers["AddPower"] = function(gameState, sourceCard, playerID, locIdx, col, row, params)
	local target = params[1]
	local amount = tonumber(params[2]) or 0
	local sourceName = sourceCard.cardID .. "_ONREVEAL"

	if target == "Location" then
		-- +N to all OTHER friendly cards at this location
		local friendlies = getFriendlyCardsAt(gameState, playerID, locIdx, col, row)
		for _, entry in ipairs(friendlies) do
			addModifier(entry.card, sourceName, amount, false)
			print(string.format("  [Ability] %s: +%d Power to %s at (%d,%d)",
				sourceCard.cardID, amount, entry.card.cardID, entry.col, entry.row))
		end

	elseif target == "Column" then
		-- +N to all friendly cards in the same column at this location (including self)
		local colSlots = SlotGrid.getColumn(col)
		for _, slot in ipairs(colSlots) do
			local card = getCard(gameState, playerID, locIdx, slot[1], slot[2])
			if card and not (slot[1] == col and slot[2] == row) then
				addModifier(card, sourceName, amount, false)
				print(string.format("  [Ability] %s: +%d Power to %s at (%d,%d)",
					sourceCard.cardID, amount, card.cardID, slot[1], slot[2]))
			end
		end

	elseif target == "Self" then
		addModifier(sourceCard, sourceName, amount, false)
		print(string.format("  [Ability] %s: +%d Power to self", sourceCard.cardID, amount))
	end
end

-- OnReveal:RemovePower:Target:Amount
onRevealResolvers["RemovePower"] = function(gameState, sourceCard, playerID, locIdx, col, row, params)
	local target = params[1]
	local amount = tonumber(params[2]) or 0
	local sourceName = sourceCard.cardID .. "_ONREVEAL"

	if target == "Random_Enemy_Here" then
		local enemies = getEnemyCardsAt(gameState, playerID, locIdx)
		local pick = pickRandom(enemies)
		if pick then
			addModifier(pick.card, sourceName, -amount, true)
			print(string.format("  [Ability] %s: -%d Power to enemy %s at (%d,%d)",
				sourceCard.cardID, amount, pick.card.cardID, pick.col, pick.row))
		end

	elseif target == "Random_Friendly_Here" then
		local friendlies = getFriendlyCardsAt(gameState, playerID, locIdx, col, row)
		local pick = pickRandom(friendlies)
		if pick then
			addModifier(pick.card, sourceName, -amount, false)
			print(string.format("  [Ability] %s: -%d Power to friendly %s at (%d,%d)",
				sourceCard.cardID, amount, pick.card.cardID, pick.col, pick.row))
		end

	elseif target == "All_Enemy_Here" then
		local enemies = getEnemyCardsAt(gameState, playerID, locIdx)
		for _, entry in ipairs(enemies) do
			addModifier(entry.card, sourceName, -amount, true)
			print(string.format("  [Ability] %s: -%d Power to enemy %s at (%d,%d)",
				sourceCard.cardID, amount, entry.card.cardID, entry.col, entry.row))
		end
	end
end

-- OnReveal:ConditionalPower:Condition:Amount
onRevealResolvers["ConditionalPower"] = function(gameState, sourceCard, playerID, locIdx, col, row, params)
	local condition = params[1]
	local amount = tonumber(params[2]) or 0
	local sourceName = sourceCard.cardID .. "_ONREVEAL"

	if condition == "Opponent_Played_Here" then
		-- Check if opponent played any card at this location this turn
		local opponent = getOpponent(gameState, playerID)
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
			addModifier(sourceCard, sourceName, amount, false)
			print(string.format("  [Ability] %s: condition met (opponent played here), +%d Power",
				sourceCard.cardID, amount))
		else
			print(string.format("  [Ability] %s: condition NOT met (opponent didn't play here)",
				sourceCard.cardID))
		end

	elseif condition == "Empty_Slots_Here" then
		-- +N per empty slot on your side of this location
		local emptySlots = getEmptySlots(gameState, playerID, locIdx)
		local totalBonus = #emptySlots * amount
		if totalBonus > 0 then
			addModifier(sourceCard, sourceName, totalBonus, false)
			print(string.format("  [Ability] %s: %d empty slots, +%d Power",
				sourceCard.cardID, #emptySlots, totalBonus))
		end
	end
end

-- OnReveal:MoveThis:OtherLocation
onRevealResolvers["MoveThis"] = function(gameState, sourceCard, playerID, locIdx, col, row, params)
	-- Find the other location index
	local otherLocIdx = (locIdx == 1) and 2 or 1
	local emptySlots = getEmptySlots(gameState, playerID, otherLocIdx)
	local pick = pickRandom(emptySlots)
	if pick then
		-- Remove from current location
		setCard(gameState, playerID, locIdx, col, row, nil)
		-- Place at new location
		setCard(gameState, playerID, otherLocIdx, pick.col, pick.row, sourceCard)
		print(string.format("  [Ability] %s: moved from loc %d (%d,%d) to loc %d (%d,%d)",
			sourceCard.cardID, locIdx, col, row, otherLocIdx, pick.col, pick.row))
	else
		print(string.format("  [Ability] %s: no empty slot at other location, move failed",
			sourceCard.cardID))
	end
end

-- OnReveal:SetPower:Source
onRevealResolvers["SetPower"] = function(gameState, sourceCard, playerID, locIdx, col, row, params)
	local source = params[1]
	local sourceName = sourceCard.cardID .. "_ONREVEAL"

	if source == "Highest_Enemy_Here" then
		local enemies = getEnemyCardsAt(gameState, playerID, locIdx)
		local highest = 0
		for _, entry in ipairs(enemies) do
			local power = entry.card.basePower
			for _, mod in ipairs(entry.card.powerModifiers) do
				power = power + mod.amount
			end
			if power > highest then
				highest = power
			end
		end
		-- Set base power to match (clear modifiers, set base)
		local diff = highest - sourceCard.basePower
		if diff ~= 0 then
			addModifier(sourceCard, sourceName, diff, false)
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
				-- Don't destroy the source card itself
				if not (pid == playerID and loc == locIdx and c == col and r == row) then
					local card = getCard(gameState, pid, loc, c, r)
					if card then
						local power = card.basePower
						for _, mod in ipairs(card.powerModifiers) do
							power = power + mod.amount
						end
						if power <= threshold then
							setCard(gameState, pid, loc, c, r, nil)
							print(string.format("  [Ability] %s: destroyed %s (Power %d <= %d) at loc %d (%d,%d)",
								sourceCard.cardID, card.cardID, power, threshold, loc, c, r))
						end
					end
				end
			end
		end
	end

	if scope == "Here_Both" then
		-- Destroy on both sides at this location
		for pid, _ in pairs(gameState.players) do
			destroyIfWeak(pid, locIdx)
		end
	elseif scope == "Here_Friendly" then
		destroyIfWeak(playerID, locIdx)
	elseif scope == "Here_Enemy" then
		local opponent = getOpponent(gameState, playerID)
		if opponent then
			destroyIfWeak(opponent, locIdx)
		end
	end
end

-- OnReveal:SummonCopy:Target:Power
onRevealResolvers["SummonCopy"] = function(gameState, sourceCard, playerID, locIdx, col, row, params)
	local tokenPower = tonumber(params[2]) or 1

	-- Find empty adjacent slots
	local adjSlots = SlotGrid.getAdjacent(col, row)
	local emptyAdj = {}
	for _, slot in ipairs(adjSlots) do
		if not getCard(gameState, playerID, locIdx, slot[1], slot[2]) then
			table.insert(emptyAdj, { col = slot[1], row = slot[2] })
		end
	end

	local pick = pickRandom(emptyAdj)
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
		setCard(gameState, playerID, locIdx, pick.col, pick.row, token)
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
			local card = getCard(gameState, playerID, locIdx, slot[1], slot[2])
			if card then
				addModifier(card, sourceName, amount, false)
			end
		end

	elseif target == "Location" then
		-- All OTHER friendly cards at this location
		local friendlies = getFriendlyCardsAt(gameState, playerID, locIdx, col, row)
		for _, entry in ipairs(friendlies) do
			addModifier(entry.card, sourceName, amount, false)
		end

	elseif target == "Row" then
		-- All OTHER friendly cards in the same row
		local rowSlots = SlotGrid.getRow(row)
		for _, slot in ipairs(rowSlots) do
			if not (slot[1] == col and slot[2] == row) then
				local card = getCard(gameState, playerID, locIdx, slot[1], slot[2])
				if card then
					addModifier(card, sourceName, amount, false)
				end
			end
		end

	elseif target == "AllLocations" then
		-- All OTHER friendly cards at BOTH locations
		for li = 1, GameConfig.LOCATIONS_PER_GAME do
			for r = 1, GameConfig.GRID_ROWS do
				for c = 1, GameConfig.GRID_COLUMNS do
					if not (c == col and r == row and li == locIdx) then
						local card = getCard(gameState, playerID, li, c, r)
						if card then
							addModifier(card, sourceName, amount, false)
						end
					end
				end
			end
		end

	elseif target == "Self" and params[2] == "PerOngoing" then
		-- Sage: +1 per other Ongoing card you control
		-- (handled specially below)
	end
end

-- Ongoing:AddPower:Self:PerOngoing (Sage)
ongoingResolvers["AddPower_PerOngoing"] = function(gameState, sourceCard, playerID, locIdx, col, row, _params)
	local sourceName = sourceCard.cardID .. "_ONGOING"
	local count = countOngoingCards(gameState, playerID, col, row, locIdx)
	if count > 0 then
		addModifier(sourceCard, sourceName, count, false)
	end
end

-- Ongoing:DoublePower:Location (Warlord)
-- This is special — handled in the power recalculation step, not as a modifier.
-- We flag it here so MatchManager knows to apply the doubling.
ongoingResolvers["DoublePower"] = function(_gameState, sourceCard, _playerID, _locIdx, _col, _row, _params)
	-- Warlord's effect is applied during the final power summation step in MatchManager.
	-- The MatchManager checks for cards with "Ongoing:DoublePower:Location" and doubles
	-- the player's total power at that location after all other modifiers.
	-- No modifier added here — just a flag check.
	sourceCard._doublesLocationPower = true
end

-- Ongoing:Immune (Colossus)
ongoingResolvers["Immune"] = function(_gameState, sourceCard, _playerID, _locIdx, _col, _row, _params)
	sourceCard.isImmune = true
end

-- ============================================================
-- Public API
-- ============================================================

-- Parse an ability string into trigger, effect, and params
function AbilityRegistry.parse(abilityString)
	if not abilityString then return nil end
	local parts = string.split(abilityString, ":")
	if #parts < 2 then return nil end
	local trigger = parts[1]  -- "OnReveal" or "Ongoing"
	local effect = parts[2]   -- "AddPower", "RemovePower", etc.
	local params = {}
	for i = 3, #parts do
		table.insert(params, parts[i])
	end
	return { trigger = trigger, effect = effect, params = params }
end

-- Resolve an On Reveal ability
function AbilityRegistry.resolveOnReveal(gameState, sourceCard, playerID, locIdx, col, row)
	local CardDatabase = require(script.Parent.CardDatabase)
	local def = CardDatabase[sourceCard.cardID]
	if not def or not def.ability then return end

	local parsed = AbilityRegistry.parse(def.ability)
	if not parsed or parsed.trigger ~= "OnReveal" then return end

	-- Check if location suppresses On Reveal
	local location = gameState.locations[locIdx]
	if location and location.effect == "SuppressOnReveal" then
		print(string.format("  [Ability] %s: On Reveal suppressed by %s",
			sourceCard.cardID, location.id))
		return
	end

	local resolver = onRevealResolvers[parsed.effect]
	if resolver then
		resolver(gameState, sourceCard, playerID, locIdx, col, row, parsed.params)
	else
		print(string.format("  [Ability] WARNING: no resolver for OnReveal effect '%s'", parsed.effect))
	end
end

-- Apply a single Ongoing card's effect (called during recalculation sweep)
function AbilityRegistry.applyOngoing(gameState, sourceCard, playerID, locIdx, col, row)
	local CardDatabase = require(script.Parent.CardDatabase)
	local def = CardDatabase[sourceCard.cardID]
	if not def or not def.ability then return end

	local parsed = AbilityRegistry.parse(def.ability)
	if not parsed or parsed.trigger ~= "Ongoing" then return end

	-- Special case: Sage (AddPower:Self:PerOngoing)
	if parsed.effect == "AddPower" and #parsed.params >= 2 and parsed.params[2] == "PerOngoing" then
		local resolver = ongoingResolvers["AddPower_PerOngoing"]
		if resolver then
			resolver(gameState, sourceCard, playerID, locIdx, col, row, parsed.params)
		end
		return
	end

	local resolver = ongoingResolvers[parsed.effect]
	if resolver then
		resolver(gameState, sourceCard, playerID, locIdx, col, row, parsed.params)
	else
		print(string.format("  [Ability] WARNING: no resolver for Ongoing effect '%s'", parsed.effect))
	end
end

-- Recalculate a card's currentPower from basePower + modifiers
function AbilityRegistry.recalculatePower(cardState)
	local total = cardState.basePower
	for _, mod in ipairs(cardState.powerModifiers) do
		total = total + mod.amount
	end
	cardState.currentPower = total
end

-- Clear all Ongoing-sourced modifiers from every card on the board
-- (Called before re-applying all Ongoing effects)
function AbilityRegistry.clearOngoingModifiers(gameState)
	for _, player in pairs(gameState.players) do
		for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
			for row = 1, GameConfig.GRID_ROWS do
				for col = 1, GameConfig.GRID_COLUMNS do
					local card = player.boards[locIdx][row][col]
					if card then
						-- Remove Ongoing modifiers, keep OnReveal and location modifiers
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

-- Check if an ability string is an Ongoing type
function AbilityRegistry.isOngoing(abilityString)
	if not abilityString then return false end
	return string.find(abilityString, "^Ongoing:") ~= nil
end

-- Check if an ability string is an OnReveal type
function AbilityRegistry.isOnReveal(abilityString)
	if not abilityString then return false end
	return string.find(abilityString, "^OnReveal:") ~= nil
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
			local parsed = AbilityRegistry.parse(c.ability)
			if parsed then
				print(string.format("  [%s] %s -> trigger=%s, effect=%s, params={%s}",
					id, c.ability, parsed.trigger, parsed.effect, table.concat(parsed.params, ", ")))
			end
		end
	end
end

function AbilityRegistry.testParse()
	print("=== AbilityRegistry Parse Test ===")
	local tests = {
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
	}
	for _, str in ipairs(tests) do
		local parsed = AbilityRegistry.parse(str)
		if parsed then
			print(string.format("  OK: %s -> trigger=%s, effect=%s, params={%s}",
				str, parsed.trigger, parsed.effect, table.concat(parsed.params, ", ")))
		else
			print(string.format("  FAIL: %s -> parse returned nil", str))
		end
	end
end

return AbilityRegistry
