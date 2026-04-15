--[[
	MatchManager — the server-side game engine.

	Runs a complete match between two players (human or bot).
	Implements the full turn loop: energy, draw, planning, validation,
	placement, On Reveal resolution, Ongoing recalculation, scoring, win check.

	Usage:
		local MatchManager = require(script.Parent.MatchManager)
		local match = MatchManager.new(player1ID, player2ID, isBot2)
		match:start()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Events = ReplicatedStorage:WaitForChild("Events")

local GameConfig = require(Modules.GameConfig)
local CardDatabase = require(Modules.CardDatabase)
local LocationDatabase = require(Modules.LocationDatabase)
local AbilityRegistry = require(Modules.AbilityRegistry)
local SlotGrid = require(Modules.SlotGrid)
local GSU = require(Modules.GameStateUtils)
local LocationRestrictions = require(Modules.LocationRestrictions)
local LocationEffectRegistry = require(Modules.LocationEffectRegistry)

local MatchManager = {}
MatchManager.__index = MatchManager

-- ============================================================
-- Construction
-- ============================================================

function MatchManager.new(player1, player2, isPlayer2Bot)
	local self = setmetatable({}, MatchManager)

	self.player1 = player1  -- Player object or string ID
	self.player2 = player2  -- Player object or string ID (or "BOT")
	self.isPlayer2Bot = isPlayer2Bot or false

	-- Map player objects/IDs to internal keys
	self.playerIDs = {}
	self.playerObjects = {}

	-- Use UserId for real players to ensure consistency with RemoteEvent handlers
	local p1ID
	if typeof(player1) == "Instance" and player1:IsA("Player") then
		p1ID = tostring(player1.UserId)
	else
		p1ID = tostring(player1)
	end

	local p2ID
	if isPlayer2Bot then
		p2ID = "BOT"
	elseif typeof(player2) == "Instance" and player2:IsA("Player") then
		p2ID = tostring(player2.UserId)
	else
		p2ID = tostring(player2)
	end

	self.playerIDs[1] = p1ID
	self.playerIDs[2] = p2ID
	self.playerObjects[p1ID] = player1
	self.playerObjects[p2ID] = player2

	self.gameState = nil
	self.botModule = nil
	self.turnSubmissions = {}
	self.submissionEvents = {}  -- signals for waiting on submissions
	self.matchActive = false
	self.testMode = false  -- set true for bot-vs-bot test matches

	return self
end

-- ============================================================
-- Deck Utilities
-- ============================================================

local function shuffleDeck(deck)
	local n = #deck
	for i = n, 2, -1 do
		local j = math.random(i)
		deck[i], deck[j] = deck[j], deck[i]
	end
	return deck
end

local function copyDeck(deckTemplate)
	local deck = {}
	for _, cardID in ipairs(deckTemplate) do
		table.insert(deck, cardID)
	end
	return deck
end

-- ============================================================
-- Card State Helper (MatchManager-specific)
-- ============================================================

local function makeCardState(cardID, turnPlayed, playOrder)
	local def = CardDatabase[cardID]
	return {
		cardID = cardID,
		basePower = def.power,
		powerModifiers = {},
		currentPower = def.power,
		isToken = false,
		isImmune = false,
		turnPlayed = turnPlayed,
		playOrder = playOrder,
	}
end

-- ============================================================
-- Game State Initialization
-- ============================================================

function MatchManager:initGameState()
	local p1ID = self.playerIDs[1]
	local p2ID = self.playerIDs[2]

	-- Pick 2 random locations
	local allLocIDs = LocationDatabase.getAllIDs()
	local locIndices = {}
	for i = 1, #allLocIDs do locIndices[i] = i end
	-- Shuffle and pick first 2
	for i = #locIndices, 2, -1 do
		local j = math.random(i)
		locIndices[i], locIndices[j] = locIndices[j], locIndices[i]
	end
	local loc1ID = allLocIDs[locIndices[1]]
	local loc2ID = allLocIDs[locIndices[2]]
	local loc1 = LocationDatabase[loc1ID]
	local loc2 = LocationDatabase[loc2ID]

	print(string.format("[Match] Locations: %s (%d pts) and %s (%d pts)",
		loc1.name, loc1.pointValue, loc2.name, loc2.pointValue))

	-- Determine location priority (higher point value first)
	local locationPriority
	if loc1.pointValue > loc2.pointValue then
		locationPriority = { 1, 2 }
	elseif loc2.pointValue > loc1.pointValue then
		locationPriority = { 2, 1 }
	else
		if math.random(2) == 1 then
			locationPriority = { 1, 2 }
		else
			locationPriority = { 2, 1 }
		end
	end

	-- Random player priority for score ties
	local playerPriority
	if math.random(2) == 1 then
		playerPriority = { p1ID, p2ID }
	else
		playerPriority = { p2ID, p1ID }
	end

	-- Create and shuffle decks
	local deck1 = shuffleDeck(copyDeck(GameConfig.STARTER_DECK))
	local deck2 = shuffleDeck(copyDeck(GameConfig.STARTER_DECK))

	-- Draw starting hands
	local hand1 = {}
	for _ = 1, GameConfig.STARTING_HAND_SIZE do
		if #deck1 > 0 then
			table.insert(hand1, table.remove(deck1, 1))
		end
	end

	local hand2 = {}
	for _ = 1, GameConfig.STARTING_HAND_SIZE do
		if #deck2 > 0 then
			table.insert(hand2, table.remove(deck2, 1))
		end
	end

	-- Build empty boards
	local function makeEmptyBoard()
		local boards = {}
		for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
			boards[locIdx] = {}
			for row = 1, GameConfig.GRID_ROWS do
				boards[locIdx][row] = {}
				for col = 1, GameConfig.GRID_COLUMNS do
					boards[locIdx][row][col] = nil
				end
			end
		end
		return boards
	end

	self.gameState = {
		players = {
			[p1ID] = {
				score = 0,
				deck = deck1,
				hand = hand1,
				maxEnergy = GameConfig.STARTING_MAX_ENERGY,
				energy = GameConfig.STARTING_MAX_ENERGY,
				boards = makeEmptyBoard(),
			},
			[p2ID] = {
				score = 0,
				deck = deck2,
				hand = hand2,
				maxEnergy = GameConfig.STARTING_MAX_ENERGY,
				energy = GameConfig.STARTING_MAX_ENERGY,
				boards = makeEmptyBoard(),
			},
		},
		locations = {
			[1] = {
				id = loc1ID,
				name = loc1.name,
				pointValue = loc1.pointValue,
				effect = loc1.effect,
				effectText = loc1.effectText,
			},
			[2] = {
				id = loc2ID,
				name = loc2.name,
				pointValue = loc2.pointValue,
				effect = loc2.effect,
				effectText = loc2.effectText,
			},
		},
		locationPriority = locationPriority,
		playerPriority = playerPriority,
		turn = 0,
		phase = "WAITING_FOR_START",
		turnPlays = {},
		tiebreaker = false,
	}

	print(string.format("[Match] Player 1: %s (hand: %s)", p1ID, table.concat(hand1, ", ")))
	print(string.format("[Match] Player 2: %s (hand: %s)", p2ID, table.concat(hand2, ", ")))
end

-- ============================================================
-- Turn Flow
-- ============================================================

function MatchManager:start()
	self.matchActive = true
	self:initGameState()

	print("[Match] === MATCH STARTED ===")

	-- Connect SubmitTurn event for human players
	local submitEvent = Events:WaitForChild("SubmitTurn")
	self._submitConnection = submitEvent.OnServerEvent:Connect(function(player, plays)
		self:onPlayerSubmit(tostring(player.UserId), plays)
	end)

	-- Load bot module if needed
	if self.isPlayer2Bot then
		self.botModule = require(script.Parent.BotPlayer)
	end

	-- Run turns until game over
	while self.matchActive and self.gameState.phase ~= "GAME_OVER" do
		self:runTurn()
	end

	-- Cleanup
	if self._submitConnection then
		self._submitConnection:Disconnect()
		self._submitConnection = nil
	end

	print("[Match] === MATCH ENDED ===")
end

function MatchManager:runTurn()
	local gs = self.gameState
	local p1ID = self.playerIDs[1]
	local p2ID = self.playerIDs[2]

	-- 1. ADVANCE TURN
	gs.turn = gs.turn + 1
	print(string.format("\n[Match] ========== TURN %d ==========", gs.turn))

	-- 2. GRANT ENERGY (max increases by 1 each turn, then refill to max)
	for _, pid in ipairs({p1ID, p2ID}) do
		gs.players[pid].maxEnergy = gs.players[pid].maxEnergy + GameConfig.ENERGY_PER_TURN
		gs.players[pid].energy = gs.players[pid].maxEnergy
		print(string.format("[Match] %s energy: %d / %d", pid, gs.players[pid].energy, gs.players[pid].maxEnergy))
	end

	-- 3. DRAW CARDS
	for _, pid in ipairs({p1ID, p2ID}) do
		local player = gs.players[pid]
		if #player.hand < GameConfig.MAX_HAND_SIZE and #player.deck > 0 then
			local card = table.remove(player.deck, 1)
			table.insert(player.hand, card)
			print(string.format("[Match] %s drew %s (hand: %d, deck: %d)",
				pid, card, #player.hand, #player.deck))
		else
			if #player.hand >= GameConfig.MAX_HAND_SIZE then
				print(string.format("[Match] %s hand full (%d), draw skipped", pid, #player.hand))
			elseif #player.deck == 0 then
				print(string.format("[Match] %s deck empty, draw skipped", pid))
			end
		end
	end

	-- 4. APPLY START-OF-TURN LOCATION EFFECTS
	for _, locIdx in ipairs(gs.locationPriority) do
		self:applyStartOfTurnEffect(locIdx)
	end

	-- 5. SEND STATE TO CLIENTS
	gs.phase = "PLANNING"
	self:sendTurnStart()

	-- 6. WAIT FOR SUBMISSIONS
	self.turnSubmissions = {}
	self:waitForSubmissions()

	-- 7-8. VALIDATE AND PLACE
	gs.turnPlays = {}
	for _, pid in ipairs({p1ID, p2ID}) do
		local submission = self.turnSubmissions[pid] or {}
		local validPlays = self:validateSubmission(pid, submission)
		gs.turnPlays[pid] = validPlays
		self:placeCards(pid, validPlays)
	end

	-- 9. RESOLVE ON REVEAL ABILITIES
	self:resolveOnReveals()

	-- 10. RECALCULATE ALL ONGOING EFFECTS
	self:recalculateOngoing()

	-- 11. RESOLVE END-OF-TURN ABILITIES
	self:resolveEndOfTurn()

	-- 12. BROADCAST REVEAL RESULTS
	self:sendRevealResult()

	-- 12. SCORE LOCATIONS
	self:scoreLocations()

	-- 13. BROADCAST SCORES
	self:sendScoreUpdate()

	-- 14. CHECK WIN CONDITION
	self:checkWinCondition()
end

-- ============================================================
-- Start-of-Turn Location Effects
-- ============================================================

function MatchManager:applyStartOfTurnEffect(locIdx)
	local gs = self.gameState
	local location = gs.locations[locIdx]
	LocationEffectRegistry.applyStartOfTurn(location, locIdx, gs)
end

-- ============================================================
-- Client Communication
-- ============================================================

-- Fire a RemoteEvent to all human players in this match.
-- dataBuilderFn(pid, opponentID) should return the payload table for that player.
function MatchManager:fireClients(eventName, dataBuilderFn)
	local event = Events:FindFirstChild(eventName)
	if not event then return end

	local gs = self.gameState
	for _, pid in ipairs({self.playerIDs[1], self.playerIDs[2]}) do
		if pid ~= "BOT" then
			local playerObj = self.playerObjects[pid]
			if playerObj and typeof(playerObj) == "Instance" then
				local opponentID = GSU.getOpponent(gs, pid)
				local data = dataBuilderFn(pid, opponentID)
				event:FireClient(playerObj, data)
			end
		end
	end
end

function MatchManager:sendTurnStart()
	local gs = self.gameState
	self:fireClients("TurnStart", function(pid, opponentID)
		return {
			turn = gs.turn,
			phase = gs.phase,
			energy = gs.players[pid].energy,
			hand = gs.players[pid].hand,
			myBoards = gs.players[pid].boards,
			oppBoards = self:getVisibleOpponentBoards(opponentID),
			oppHandSize = #gs.players[opponentID].hand,
			myScore = gs.players[pid].score,
			oppScore = gs.players[opponentID].score,
			locations = gs.locations,
			deckSize = #gs.players[pid].deck,
		}
	end)
end

function MatchManager:getVisibleOpponentBoards(opponentID)
	local gs = self.gameState
	local boards = {}
	for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
		boards[locIdx] = {}
		for row = 1, GameConfig.GRID_ROWS do
			boards[locIdx][row] = {}
			for col = 1, GameConfig.GRID_COLUMNS do
				local card = GSU.getCard(gs, opponentID, locIdx, col, row)
				if card then
					GSU.recalculatePower(card)
					boards[locIdx][row][col] = {
						cardID = card.cardID,
						currentPower = card.currentPower,
						basePower = card.basePower,
						isToken = card.isToken,
					}
				else
					boards[locIdx][row][col] = nil
				end
			end
		end
	end
	return boards
end

function MatchManager:sendRevealResult()
	local gs = self.gameState
	self:fireClients("RevealResult", function(pid, opponentID)
		return {
			turn = gs.turn,
			myBoards = gs.players[pid].boards,
			oppBoards = self:getVisibleOpponentBoards(opponentID),
			myPlays = gs.turnPlays[pid] or {},
			oppPlays = gs.turnPlays[opponentID] or {},
			locations = gs.locations,
		}
	end)
end

function MatchManager:sendScoreUpdate()
	local gs = self.gameState
	self:fireClients("ScoreUpdate", function(pid, opponentID)
		return {
			turn = gs.turn,
			myScore = gs.players[pid].score,
			oppScore = gs.players[opponentID].score,
		}
	end)
end

function MatchManager:sendGameOver(winnerID)
	local gs = self.gameState
	self:fireClients("GameOver", function(pid, opponentID)
		return {
			won = (winnerID == pid),
			draw = (winnerID == "DRAW"),
			myFinalScore = gs.players[pid].score,
			oppFinalScore = gs.players[opponentID].score,
			totalTurns = gs.turn,
		}
	end)
end

function MatchManager:sendInvalidPlay(playerID, reason)
	if playerID == "BOT" then return end
	local playerObj = self.playerObjects[playerID]
	if not playerObj or typeof(playerObj) ~= "Instance" then return end

	local event = Events:FindFirstChild("InvalidPlay")
	if event then
		event:FireClient(playerObj, { reason = reason })
	end
end

-- ============================================================
-- Submission Handling
-- ============================================================

function MatchManager:onPlayerSubmit(playerID, plays)
	-- Only accept if we're waiting for submissions
	if self.gameState.phase ~= "PLANNING" then return end

	-- Only accept from players in this match
	local validPlayer = false
	for _, pid in ipairs(self.playerIDs) do
		if pid == playerID then validPlayer = true break end
	end
	if not validPlayer then return end

	-- Only accept first submission per turn
	if self.turnSubmissions[playerID] then return end

	print(string.format("[Match] %s submitted %d plays", playerID, #plays))
	self.turnSubmissions[playerID] = plays

	-- Signal that a submission arrived
	if self.submissionEvents[playerID] then
		self.submissionEvents[playerID] = true
	end
end

function MatchManager:waitForSubmissions()
	local gs = self.gameState
	local p1ID = self.playerIDs[1]
	local p2ID = self.playerIDs[2]

	-- Test mode: both players are bots, inject plays synchronously
	if self.testMode then
		local BotPlayer = require(script.Parent.BotPlayer)
		self.turnSubmissions[p1ID] = BotPlayer.decidePlays(gs, p1ID)
		self.turnSubmissions[p2ID] = BotPlayer.decidePlays(gs, p2ID)
		gs.phase = "RESOLVING"
		return
	end

	-- Reset submission signals
	self.submissionEvents[p1ID] = false
	self.submissionEvents[p2ID] = false

	-- Bot submits immediately (with slight delay for feel)
	if self.isPlayer2Bot then
		task.delay(1, function()
			local botPlays = self.botModule.decidePlays(gs, p2ID)
			print(string.format("[Match] BOT submits %d plays", #botPlays))
			self.turnSubmissions[p2ID] = botPlays
			self.submissionEvents[p2ID] = true
		end)
	end

	-- Wait for both submissions or timer
	local timerStart = tick()
	local timeout = GameConfig.TURN_TIMER_SECONDS

	while self.matchActive do
		local p1Done = self.turnSubmissions[p1ID] ~= nil
		local p2Done = self.turnSubmissions[p2ID] ~= nil

		if p1Done and p2Done then
			break
		end

		local elapsed = tick() - timerStart
		if elapsed >= timeout then
			print(string.format("[Match] Timer expired (%.1fs)", elapsed))
			if not p1Done then
				print(string.format("[Match] %s auto-passed (timer)", p1ID))
				self.turnSubmissions[p1ID] = {}
			end
			if not p2Done then
				print(string.format("[Match] %s auto-passed (timer)", p2ID))
				self.turnSubmissions[p2ID] = {}
			end
			break
		end

		task.wait(0.1)
	end

	gs.phase = "RESOLVING"
end

-- ============================================================
-- Validation
-- ============================================================

function MatchManager:validateSubmission(playerID, submission)
	local gs = self.gameState
	local player = gs.players[playerID]
	local validPlays = {}
	local energyRemaining = player.energy
	local handCopy = {}
	for _, cardID in ipairs(player.hand) do
		table.insert(handCopy, cardID)
	end

	for i, play in ipairs(submission) do
		local cardID = play.cardID or play[1]
		local locIdx = play.locIdx or play[2]
		local col = play.col or play[3]
		local row = play.row or play[4]

		local def = CardDatabase[cardID]
		if not def then
			print(string.format("[Match] REJECTED: %s play %d — unknown card %s", playerID, i, tostring(cardID)))
			self:sendInvalidPlay(playerID, "Unknown card: " .. tostring(cardID))
			continue
		end

		-- Check energy
		if def.cost > energyRemaining then
			print(string.format("[Match] REJECTED: %s play %d — %s costs %d, only %d energy left",
				playerID, i, cardID, def.cost, energyRemaining))
			self:sendInvalidPlay(playerID, cardID .. " costs too much energy")
			continue
		end

		-- Check card is in hand
		local handIdx = nil
		for j, hCardID in ipairs(handCopy) do
			if hCardID == cardID then
				handIdx = j
				break
			end
		end
		if not handIdx then
			print(string.format("[Match] REJECTED: %s play %d — %s not in hand", playerID, i, cardID))
			self:sendInvalidPlay(playerID, cardID .. " not in hand")
			continue
		end

		-- Check valid slot
		if not SlotGrid.isValidSlot(col, row) then
			print(string.format("[Match] REJECTED: %s play %d — invalid slot (%d,%d)", playerID, i, col, row))
			self:sendInvalidPlay(playerID, "Invalid slot position")
			continue
		end

		-- Check location index
		if locIdx < 1 or locIdx > GameConfig.LOCATIONS_PER_GAME then
			print(string.format("[Match] REJECTED: %s play %d — invalid location %d", playerID, i, locIdx))
			self:sendInvalidPlay(playerID, "Invalid location")
			continue
		end

		-- Check location restrictions
		local location = gs.locations[locIdx]
		local canPlay, reason = LocationRestrictions.canPlayAt(location, def, row)
		if not canPlay then
			print(string.format("[Match] REJECTED: %s play %d — %s", playerID, i, reason))
			self:sendInvalidPlay(playerID, reason)
			continue
		end

		-- Valid play
		table.insert(validPlays, {
			cardID = cardID,
			locIdx = locIdx,
			col = col,
			row = row,
			playOrder = #validPlays + 1,
		})
		energyRemaining = energyRemaining - def.cost
		table.remove(handCopy, handIdx)

		print(string.format("[Match] VALID: %s plays %s at loc %d (%d,%d) — %d energy left",
			playerID, cardID, locIdx, col, row, energyRemaining))
	end

	return validPlays
end

-- ============================================================
-- Card Placement
-- ============================================================

function MatchManager:placeCards(playerID, validPlays)
	local gs = self.gameState
	local player = gs.players[playerID]

	for _, play in ipairs(validPlays) do
		local cardID = play.cardID
		local locIdx = play.locIdx
		local col = play.col
		local row = play.row
		local def = CardDatabase[cardID]

		-- Check for overwrite (own card already in slot)
		local existingCard = GSU.getCard(gs, playerID, locIdx, col, row)
		if existingCard then
			print(string.format("[Match] OVERWRITE: %s destroys their %s at loc %d (%d,%d)",
				playerID, existingCard.cardID, locIdx, col, row))
			GSU.destroyCard(gs, playerID, locIdx, col, row)
		end

		-- Remove card from hand
		for i, hCardID in ipairs(player.hand) do
			if hCardID == cardID then
				table.remove(player.hand, i)
				break
			end
		end

		-- Deduct energy
		player.energy = player.energy - def.cost

		-- Create card state and place on board
		local cardState = makeCardState(cardID, gs.turn, play.playOrder)

		-- Apply location on-play effects via registry
		local location = gs.locations[locIdx]
		LocationEffectRegistry.applyOnPlay(location, cardState, playerID, gs)

		-- Place the card
		GSU.setCard(gs, playerID, locIdx, col, row, cardState)
		GSU.recalculatePower(cardState)

		print(string.format("[Match] PLACED: %s's %s at loc %d (%d,%d) — Power %d",
			playerID, cardID, locIdx, col, row, cardState.currentPower))
	end
end

-- ============================================================
-- On Reveal Resolution
-- ============================================================

function MatchManager:resolveOnReveals()
	local gs = self.gameState
	local p1ID = self.playerIDs[1]
	local p2ID = self.playerIDs[2]

	print("[Match] --- Resolving On Reveal abilities ---")

	for _, locIdx in ipairs(gs.locationPriority) do
		local location = gs.locations[locIdx]
		print(string.format("[Match] Resolving at %s (loc %d)", location.name, locIdx))

		-- Determine player resolution order for this turn
		local resolveOrder
		local p1Score = gs.players[p1ID].score
		local p2Score = gs.players[p2ID].score

		if p1Score > p2Score then
			resolveOrder = { p1ID, p2ID }
		elseif p2Score > p1Score then
			resolveOrder = { p2ID, p1ID }
		else
			resolveOrder = gs.playerPriority
		end

		for _, pid in ipairs(resolveOrder) do
			local plays = gs.turnPlays[pid] or {}
			local newCards = {}
			for _, play in ipairs(plays) do
				if play.locIdx == locIdx then
					local card = GSU.getCard(gs, pid, locIdx, play.col, play.row)
					if card then
						table.insert(newCards, {
							card = card,
							col = play.col,
							row = play.row,
							playOrder = play.playOrder,
						})
					end
				end
			end

			table.sort(newCards, function(a, b) return a.playOrder < b.playOrder end)

			for _, entry in ipairs(newCards) do
				local def = CardDatabase[entry.card.cardID]
				if def and def.ability and AbilityRegistry.isOnReveal(def.ability) then
					print(string.format("[Match] Resolving OnReveal: %s's %s at loc %d (%d,%d)",
						pid, entry.card.cardID, locIdx, entry.col, entry.row))
					AbilityRegistry.resolveOnReveal(gs, entry.card, pid, locIdx, entry.col, entry.row)
				end
			end
		end
	end
end

-- ============================================================
-- Ongoing Recalculation
-- ============================================================

function MatchManager:recalculateOngoing()
	local gs = self.gameState

	print("[Match] --- Recalculating Ongoing effects ---")

	-- Clear all Ongoing modifiers
	AbilityRegistry.clearOngoingModifiers(gs)

	-- Apply all Ongoing effects
	for pid, player in pairs(gs.players) do
		for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
			for row = 1, GameConfig.GRID_ROWS do
				for col = 1, GameConfig.GRID_COLUMNS do
					local card = player.boards[locIdx][row][col]
					if card then
						local def = CardDatabase[card.cardID]
						if def and def.ability and AbilityRegistry.isOngoing(def.ability) then
							AbilityRegistry.applyOngoing(gs, card, pid, locIdx, col, row)
						end
					end
				end
			end
		end
	end

	-- Recalculate all power
	for _, player in pairs(gs.players) do
		for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
			for row = 1, GameConfig.GRID_ROWS do
				for col = 1, GameConfig.GRID_COLUMNS do
					local card = player.boards[locIdx][row][col]
					if card then
						GSU.recalculatePower(card)
					end
				end
			end
		end
	end
end

-- ============================================================
-- End-of-Turn Resolution
-- ============================================================

function MatchManager:resolveEndOfTurn()
	local gs = self.gameState

	print("[Match] --- Resolving End-of-Turn abilities ---")

	-- Card EndOfTurn abilities
	for pid, player in pairs(gs.players) do
		for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
			for row = 1, GameConfig.GRID_ROWS do
				for col = 1, GameConfig.GRID_COLUMNS do
					local card = player.boards[locIdx][row][col]
					if card then
						local def = CardDatabase[card.cardID]
						if def and def.ability and AbilityRegistry.isEndOfTurn(def.ability) then
							AbilityRegistry.resolveEndOfTurn(gs, card, pid, locIdx, col, row)
						end
					end
				end
			end
		end
	end

	-- Location EndOfTurn effects
	for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
		local location = gs.locations[locIdx]
		LocationEffectRegistry.applyEndOfTurn(location, locIdx, gs)
	end

	-- Recalculate power after EndOfTurn modifications
	for _, player in pairs(gs.players) do
		for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
			for row = 1, GameConfig.GRID_ROWS do
				for col = 1, GameConfig.GRID_COLUMNS do
					local card = player.boards[locIdx][row][col]
					if card then
						GSU.recalculatePower(card)
					end
				end
			end
		end
	end
end

-- ============================================================
-- Scoring
-- ============================================================

function MatchManager:scoreLocations()
	local gs = self.gameState
	local p1ID = self.playerIDs[1]
	local p2ID = self.playerIDs[2]

	print("[Match] --- Scoring ---")

	for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
		local location = gs.locations[locIdx]
		local p1Power = GSU.sumPowerAtLocation(gs, p1ID, locIdx)
		local p2Power = GSU.sumPowerAtLocation(gs, p2ID, locIdx)

		local p1Points = 0
		local p2Points = 0

		if p1Power > p2Power then
			p1Points = location.pointValue
		elseif p2Power > p1Power then
			p2Points = location.pointValue
		else
			p1Points = 1
			p2Points = 1
		end

		gs.players[p1ID].score = gs.players[p1ID].score + p1Points
		gs.players[p2ID].score = gs.players[p2ID].score + p2Points

		print(string.format("[Match] %s: %s Power %d vs %s Power %d -> %s +%d, %s +%d",
			location.name,
			p1ID, p1Power, p2ID, p2Power,
			p1ID, p1Points, p2ID, p2Points))
	end

	print(string.format("[Match] Scores: %s = %d, %s = %d",
		p1ID, gs.players[p1ID].score, p2ID, gs.players[p2ID].score))
end

-- ============================================================
-- Win Condition
-- ============================================================

function MatchManager:checkWinCondition()
	local gs = self.gameState
	local p1ID = self.playerIDs[1]
	local p2ID = self.playerIDs[2]

	local p1Score = gs.players[p1ID].score
	local p2Score = gs.players[p2ID].score
	local threshold = GameConfig.POINTS_TO_WIN

	if p1Score >= threshold or p2Score >= threshold then
		if gs.tiebreaker then
			local winner
			if p1Score > p2Score then
				winner = p1ID
			elseif p2Score > p1Score then
				winner = p2ID
			else
				winner = "DRAW"
			end
			self:endGame(winner)
			return
		end

		if p1Score > p2Score then
			self:endGame(p1ID)
		elseif p2Score > p1Score then
			self:endGame(p2ID)
		else
			print("[Match] TIEBREAKER: both players at " .. p1Score .. " — playing one more turn")
			gs.tiebreaker = true
		end
	end
end

function MatchManager:endGame(winnerID)
	local gs = self.gameState
	gs.phase = "GAME_OVER"
	self.matchActive = false

	local p1ID = self.playerIDs[1]
	local p2ID = self.playerIDs[2]

	if winnerID == "DRAW" then
		print(string.format("[Match] GAME OVER — DRAW! Final: %s=%d, %s=%d (Turn %d)",
			p1ID, gs.players[p1ID].score, p2ID, gs.players[p2ID].score, gs.turn))
	else
		local loserID = (winnerID == p1ID) and p2ID or p1ID
		print(string.format("[Match] GAME OVER — %s WINS! Final: %s=%d, %s=%d (Turn %d)",
			winnerID, winnerID, gs.players[winnerID].score,
			loserID, gs.players[loserID].score, gs.turn))
	end

	self:sendGameOver(winnerID)
end

-- ============================================================
-- Test-only API (for Phase 2 tests)
-- ============================================================

-- Run a bot-vs-bot match to completion without RemoteEvents.
-- Reuses the real runTurn() logic to prevent test/prod drift.
function MatchManager.runTestMatch()
	print("\n[TestMatch] Starting bot-vs-bot test match...")

	local match = MatchManager.new("BOT_A", "BOT_B", false)
	match.testMode = true
	match.matchActive = true
	match:initGameState()

	print("[TestMatch] === MATCH STARTED ===")

	local maxTurns = 30
	while match.matchActive and match.gameState.phase ~= "GAME_OVER" and match.gameState.turn < maxTurns do
		match:runTurn()
	end

	if match.gameState.turn >= maxTurns and match.gameState.phase ~= "GAME_OVER" then
		print("[TestMatch] Hit turn limit — forcing game end")
		local gs = match.gameState
		local p1S = gs.players["BOT_A"].score
		local p2S = gs.players["BOT_B"].score
		if p1S > p2S then
			match:endGame("BOT_A")
		elseif p2S > p1S then
			match:endGame("BOT_B")
		else
			match:endGame("DRAW")
		end
	end

	return match.gameState
end

return MatchManager
