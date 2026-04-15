--[[
	LocationEffectRegistry — registry for location on-play and start-of-turn effects.

	Eliminates the hardcoded if/else chain in MatchManager.placeCards.
	To add a new location effect, register it in the appropriate table below.

	Effect string format matches LocationDatabase: "TriggerType:EffectName:Param1:Param2:..."
]]

local GameConfig = require(script.Parent.GameConfig)
local GSU = require(script.Parent.GameStateUtils)

local LocationEffectRegistry = {}

-- ============================================================
-- On-Play effect resolvers (applied when a card is placed)
-- ============================================================

local onPlayResolvers = {}

-- OnPlay:AddPower:Self:N — modify the placed card's power
onPlayResolvers["AddPower"] = function(location, cardState, playerID, gameState, params)
	local target = params[1]
	local amount = tonumber(params[2]) or 0

	if target == "Self" then
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

-- ============================================================
-- Public API
-- ============================================================

-- Parse an effect string into type, effect name, and params
local function parseEffect(effectString)
	if not effectString then return nil end
	local parts = string.split(effectString, ":")
	if #parts < 2 then return nil end
	local trigger = parts[1]  -- "OnPlay", "StartOfTurn", "Restrict", "Suppress..."
	local effect = parts[2]
	local params = {}
	for i = 3, #parts do
		table.insert(params, parts[i])
	end
	return { trigger = trigger, effect = effect, params = params }
end

-- Apply on-play effects for a location when a card is placed
function LocationEffectRegistry.applyOnPlay(location, cardState, playerID, gameState)
	if not location or not location.effect then return end
	local parsed = parseEffect(location.effect)
	if not parsed or parsed.trigger ~= "OnPlay" then return end

	local resolver = onPlayResolvers[parsed.effect]
	if resolver then
		resolver(location, cardState, playerID, gameState, parsed.params)
	end
end

-- Apply start-of-turn effects for a location
function LocationEffectRegistry.applyStartOfTurn(location, locIdx, gameState)
	if not location or not location.effect then return end
	local parsed = parseEffect(location.effect)
	if not parsed or parsed.trigger ~= "StartOfTurn" then return end

	local resolver = startOfTurnResolvers[parsed.effect]
	if resolver then
		resolver(location, locIdx, gameState, parsed.params)
	end
end

return LocationEffectRegistry
