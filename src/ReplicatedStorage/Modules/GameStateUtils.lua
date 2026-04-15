--[[
	GameStateUtils — shared game state query and mutation helpers.

	Eliminates duplication of getCard, getOpponent, getEmptySlots, etc.
	across AbilityRegistry, BotPlayer, and MatchManager.

	All functions take a gameState table as their first argument.

	gameState shape:
		gameState.players[playerID].boards[locIdx][row][col] = cardState | nil
		gameState.players[playerID].hand = { cardID, ... }
		gameState.players[playerID].deck = { cardID, ... }
		gameState.locations[locIdx] = { id, name, pointValue, effect, effectText }
		gameState.turn = number
]]

local GameConfig = require(script.Parent.GameConfig)

local GameStateUtils = {}

-- Get the opponent's player ID
function GameStateUtils.getOpponent(gameState, playerID)
	for pid, _ in pairs(gameState.players) do
		if pid ~= playerID then
			return pid
		end
	end
	return nil
end

-- Get the card state at a specific slot
function GameStateUtils.getCard(gameState, playerID, locIdx, col, row)
	local board = gameState.players[playerID].boards[locIdx]
	if board and board[row] and board[row][col] then
		return board[row][col]
	end
	return nil
end

-- Set a card state at a specific slot
function GameStateUtils.setCard(gameState, playerID, locIdx, col, row, cardState)
	gameState.players[playerID].boards[locIdx][row][col] = cardState
end

-- Calculate a card's current power from basePower + modifiers (read-only)
function GameStateUtils.getCurrentPower(cardState)
	local total = cardState.basePower
	for _, mod in ipairs(cardState.powerModifiers) do
		total = total + mod.amount
	end
	return total
end

-- Recalculate and update a card's currentPower field in place
function GameStateUtils.recalculatePower(cardState)
	cardState.currentPower = GameStateUtils.getCurrentPower(cardState)
end

-- Add a power modifier to a card (respects immunity for enemy-sourced debuffs)
function GameStateUtils.addModifier(cardState, source, amount, isEnemySourced)
	if cardState.isImmune and isEnemySourced and amount < 0 then
		return -- immune to enemy debuffs
	end
	table.insert(cardState.powerModifiers, { source = source, amount = amount })
end

-- Sum total power at a location for a player (includes Warlord doubler)
function GameStateUtils.sumPowerAtLocation(gameState, playerID, locIdx)
	local total = 0
	local hasDoubler = false
	for row = 1, GameConfig.GRID_ROWS do
		for col = 1, GameConfig.GRID_COLUMNS do
			local card = GameStateUtils.getCard(gameState, playerID, locIdx, col, row)
			if card then
				GameStateUtils.recalculatePower(card)
				total = total + card.currentPower
				if card._doublesLocationPower then
					hasDoubler = true
				end
			end
		end
	end
	if hasDoubler then
		total = total * 2
	end
	return total
end

-- Get all friendly cards at a location (excluding a specific slot if provided)
function GameStateUtils.getFriendlyCardsAt(gameState, playerID, locIdx, excludeCol, excludeRow)
	local cards = {}
	for row = 1, GameConfig.GRID_ROWS do
		for col = 1, GameConfig.GRID_COLUMNS do
			if not (col == excludeCol and row == excludeRow) then
				local card = GameStateUtils.getCard(gameState, playerID, locIdx, col, row)
				if card then
					table.insert(cards, { card = card, col = col, row = row, locIdx = locIdx })
				end
			end
		end
	end
	return cards
end

-- Get all enemy cards at a location
function GameStateUtils.getEnemyCardsAt(gameState, playerID, locIdx)
	local opponent = GameStateUtils.getOpponent(gameState, playerID)
	if not opponent then return {} end
	local cards = {}
	for row = 1, GameConfig.GRID_ROWS do
		for col = 1, GameConfig.GRID_COLUMNS do
			local card = GameStateUtils.getCard(gameState, opponent, locIdx, col, row)
			if card then
				table.insert(cards, { card = card, col = col, row = row, locIdx = locIdx, playerID = opponent })
			end
		end
	end
	return cards
end

-- Get empty slots at a location for a player (respects location restrictions)
function GameStateUtils.getEmptySlots(gameState, playerID, locIdx)
	local location = gameState.locations[locIdx]
	local slots = {}
	for row = 1, GameConfig.GRID_ROWS do
		for col = 1, GameConfig.GRID_COLUMNS do
			if not GameStateUtils.getCard(gameState, playerID, locIdx, col, row) then
				-- Check location restrictions on the slot itself
				local restricted = false
				if location and location.effect then
					if location.effect == "Restrict:FrontRowOnly" and row ~= 1 then
						restricted = true
					end
				end
				if not restricted then
					table.insert(slots, { col = col, row = row })
				end
			end
		end
	end
	return slots
end

-- Get occupied slots at a location sorted by power ascending (for overwrite targeting)
function GameStateUtils.getOccupiedSlots(gameState, playerID, locIdx)
	local slots = {}
	for row = 1, GameConfig.GRID_ROWS do
		for col = 1, GameConfig.GRID_COLUMNS do
			local card = GameStateUtils.getCard(gameState, playerID, locIdx, col, row)
			if card then
				local power = GameStateUtils.getCurrentPower(card)
				table.insert(slots, { col = col, row = row, power = power, cardID = card.cardID })
			end
		end
	end
	table.sort(slots, function(a, b) return a.power < b.power end)
	return slots
end

-- Pick a random element from a list
function GameStateUtils.pickRandom(list)
	if #list == 0 then return nil end
	return list[math.random(#list)]
end

-- Destroy a card at a specific slot, firing OnDestroy abilities first
-- Returns true if the card was actually removed (OnDestroy:Bounce:Self can prevent it)
function GameStateUtils.destroyCard(gameState, playerID, locIdx, col, row)
	local card = GameStateUtils.getCard(gameState, playerID, locIdx, col, row)
	if not card then return false end

	-- Fire OnDestroy abilities (requires AbilityRegistry — lazy require to avoid circular)
	local AbilityRegistry = require(script.Parent.AbilityRegistry)
	AbilityRegistry.resolveOnDestroy(gameState, card, playerID, locIdx, col, row)

	-- Check if the card bounced to hand (OnDestroy:Bounce:Self sets this flag)
	if card._bouncedToHand then
		GameStateUtils.setCard(gameState, playerID, locIdx, col, row, nil)
		return false  -- card went to hand, not truly destroyed
	end

	-- Remove the card from the board
	GameStateUtils.setCard(gameState, playerID, locIdx, col, row, nil)
	return true
end

-- Draw N cards from a player's deck into hand
function GameStateUtils.drawCards(gameState, playerID, count)
	local player = gameState.players[playerID]
	for _ = 1, count do
		if #player.hand >= GameConfig.MAX_HAND_SIZE then break end
		if #player.deck == 0 then break end
		local card = table.remove(player.deck, 1)
		table.insert(player.hand, card)
		print(string.format("  [Draw] %s drew a card (hand size: %d)", tostring(playerID), #player.hand))
	end
end

return GameStateUtils
