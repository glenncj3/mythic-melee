--[[
	LocationEffectRegistry — registry for location on-play, start-of-turn,
	and end-of-turn effects.

	Supports compound effect strings separated by | (e.g. "OnPlay:AddPower:Self:-1|StartOfTurn:AddPower:AllHere:1").
	To add a new location effect, register it in the appropriate table below.

	Effect string format matches LocationDatabase: "TriggerType:EffectName:Param1:Param2:..."
]]

local GameConfig = require(script.Parent.GameConfig)
local GSU = require(script.Parent.GameStateUtils)

local LocationEffectRegistry = {}

-- ============================================================
-- Parsing (supports compound | strings)
-- ============================================================

local function parseEffect(effectString)
	if not effectString then return nil end
	local parts = string.split(effectString, ":")
	if #parts < 2 then return nil end
	local trigger = parts[1]  -- "OnPlay", "StartOfTurn", "EndOfTurn", "Restrict", "Suppress..."
	local effect = parts[2]
	local params = {}
	for i = 3, #parts do
		table.insert(params, parts[i])
	end
	return { trigger = trigger, effect = effect, params = params }
end

local function parseAll(effectString)
	if not effectString then return {} end
	local results = {}
	local segments = string.split(effectString, "|")
	for _, segment in ipairs(segments) do
		local parsed = parseEffect(segment)
		if parsed then
			table.insert(results, parsed)
		end
	end
	return results
end

-- ============================================================
-- On-Play effect resolvers (applied when a card is placed)
-- ============================================================

local onPlayResolvers = {}

-- OnPlay:AddPower:Self:N — modify the placed card's power
-- OnPlay:AddPower:Self:PerTurn — +1 per current turn number
onPlayResolvers["AddPower"] = function(location, cardState, playerID, gameState, params)
	local target = params[1]
	local amountStr = params[2]

	if target == "Self" then
		local amount
		if amountStr == "PerTurn" then
			amount = gameState.turn
		else
			amount = tonumber(amountStr) or 0
		end

		table.insert(cardState.powerModifiers, {
			source = location.id .. "_EFFECT",
			amount = amount,
		})
		local sign = amount >= 0 and "+" or ""
		print(string.format("[Match] %s effect: %s%d Power to %s",
			location.name, sign, amount, cardState.cardID))
	end
end

-- OnPlay:DrawCard:N — draw cards when playing here
onPlayResolvers["DrawCard"] = function(location, _cardState, playerID, gameState, params)
	local count = tonumber(params[1]) or 1
	local player = gameState.players[playerID]
	for _ = 1, count do
		if #player.hand < GameConfig.MAX_HAND_SIZE and #player.deck > 0 then
			local drawn = table.remove(player.deck, 1)
			table.insert(player.hand, drawn)
			print(string.format("[Match] %s effect: %s drew %s", location.name, playerID, drawn))
		end
	end
end

-- OnPlay:SummonToken:Opponent:Power — opponent gets a token when you play here
onPlayResolvers["SummonToken"] = function(location, _cardState, playerID, gameState, params)
	local target = params[1]
	local tokenPower = tonumber(params[2]) or 1

	if target == "Opponent" then
		local opponent = GSU.getOpponent(gameState, playerID)
		if not opponent then return end
		-- Find the location index for this location
		local locIdx = nil
		for li = 1, GameConfig.LOCATIONS_PER_GAME do
			if gameState.locations[li].id == location.id then
				locIdx = li
				break
			end
		end
		if not locIdx then return end

		local emptySlots = GSU.getEmptySlots(gameState, opponent, locIdx)
		local slot = GSU.pickRandom(emptySlots)
		if slot then
			local token = {
				cardID = "HAUNT_TOKEN",
				basePower = tokenPower,
				powerModifiers = {},
				currentPower = tokenPower,
				isToken = true,
				isImmune = false,
				turnPlayed = gameState.turn,
				playOrder = 999,
			}
			GSU.setCard(gameState, opponent, locIdx, slot.col, slot.row, token)
			print(string.format("[Match] %s effect: opponent gets %d-Power token at (%d,%d)",
				location.name, tokenPower, slot.col, slot.row))
		end
	end
end

-- ============================================================
-- Start-of-Turn effect resolvers
-- ============================================================

local startOfTurnResolvers = {}

-- StartOfTurn:AddPower:AllHere:N — buff all cards at this location each turn
startOfTurnResolvers["AddPower"] = function(location, locIdx, gameState, params)
	local target = params[1]
	local amount = tonumber(params[2]) or 0

	if target == "AllHere" then
		if gameState.turn <= 1 then return end  -- No cards on turn 1
		for pid, _ in pairs(gameState.players) do
			for row = 1, GameConfig.GRID_ROWS do
				for col = 1, GameConfig.GRID_COLUMNS do
					local card = GSU.getCard(gameState, pid, locIdx, col, row)
					if card then
						table.insert(card.powerModifiers, {
							source = location.id .. "_START",
							amount = amount,
						})
						print(string.format("[Match] %s: +%d Power to %s (%s) at loc %d (%d,%d)",
							location.name, amount, card.cardID, pid, locIdx, col, row))
					end
				end
			end
		end
	end
end

-- StartOfTurn:DrawCard:BothPlayers:N — both players draw cards each turn
startOfTurnResolvers["DrawCard"] = function(location, _locIdx, gameState, params)
	local target = params[1]
	local count = tonumber(params[2]) or 1

	if target == "BothPlayers" then
		if gameState.turn <= 1 then return end
		for pid, _ in pairs(gameState.players) do
			GSU.drawCards(gameState, pid, count)
			print(string.format("[Match] %s: %s draws %d card(s)", location.name, pid, count))
		end
	end
end

-- ============================================================
-- End-of-Turn effect resolvers
-- ============================================================

local endOfTurnResolvers = {}

-- EndOfTurn:DestroyWeakest:Here — destroy the weakest card at this location (either side)
endOfTurnResolvers["DestroyWeakest"] = function(location, locIdx, gameState, _params)
	local weakest = nil
	local weakestPower = math.huge
	local weakestPid = nil
	local weakestCol, weakestRow = nil, nil

	for pid, _ in pairs(gameState.players) do
		for row = 1, GameConfig.GRID_ROWS do
			for col = 1, GameConfig.GRID_COLUMNS do
				local card = GSU.getCard(gameState, pid, locIdx, col, row)
				if card then
					local power = GSU.getCurrentPower(card)
					if power < weakestPower then
						weakestPower = power
						weakest = card
						weakestPid = pid
						weakestCol = col
						weakestRow = row
					end
				end
			end
		end
	end

	if weakest then
		print(string.format("[Match] %s: destroying weakest card %s (Power %d) at (%d,%d)",
			location.name, weakest.cardID, weakestPower, weakestCol, weakestRow))
		GSU.destroyCard(gameState, weakestPid, locIdx, weakestCol, weakestRow)
	end
end

-- EndOfTurn:DamageAll:Here:N — -N to all cards at this location (both sides)
endOfTurnResolvers["DamageAll"] = function(location, locIdx, gameState, params)
	local _target = params[1]  -- "Here"
	local amount = tonumber(params[2]) or 1

	for pid, _ in pairs(gameState.players) do
		for row = 1, GameConfig.GRID_ROWS do
			for col = 1, GameConfig.GRID_COLUMNS do
				local card = GSU.getCard(gameState, pid, locIdx, col, row)
				if card then
					table.insert(card.powerModifiers, {
						source = location.id .. "_ENDOFTURN",
						amount = -amount,
					})
				end
			end
		end
	end
	print(string.format("[Match] %s: -%d Power to all cards here", location.name, amount))
end

-- ============================================================
-- Public API
-- ============================================================

-- Apply on-play effects for a location when a card is placed
function LocationEffectRegistry.applyOnPlay(location, cardState, playerID, gameState)
	if not location or not location.effect then return end
	local allParsed = parseAll(location.effect)
	for _, parsed in ipairs(allParsed) do
		if parsed.trigger == "OnPlay" then
			local resolver = onPlayResolvers[parsed.effect]
			if resolver then
				resolver(location, cardState, playerID, gameState, parsed.params)
			end
		end
	end
end

-- Apply start-of-turn effects for a location
function LocationEffectRegistry.applyStartOfTurn(location, locIdx, gameState)
	if not location or not location.effect then return end
	local allParsed = parseAll(location.effect)
	for _, parsed in ipairs(allParsed) do
		if parsed.trigger == "StartOfTurn" then
			local resolver = startOfTurnResolvers[parsed.effect]
			if resolver then
				resolver(location, locIdx, gameState, parsed.params)
			end
		end
	end
end

-- Apply end-of-turn effects for a location
function LocationEffectRegistry.applyEndOfTurn(location, locIdx, gameState)
	if not location or not location.effect then return end
	local allParsed = parseAll(location.effect)
	for _, parsed in ipairs(allParsed) do
		if parsed.trigger == "EndOfTurn" then
			local resolver = endOfTurnResolvers[parsed.effect]
			if resolver then
				resolver(location, locIdx, gameState, parsed.params)
			end
		end
	end
end

return LocationEffectRegistry
