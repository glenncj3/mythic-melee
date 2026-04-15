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
		-- Random tiebreak
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
				energy = GameConfig.STARTING_MAX_ENERGY,
				boards = makeEmptyBoard(),
			},
			[p2ID] = {
				score = 0,
				deck = deck2,
				hand = hand2,
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
-- Card State Helpers
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

local function getCard(gameState, playerID, locIdx, col, row)
	local board = gameState.players[playerID].boards[locIdx]
	if board and board[row] and board[row][col] then
		return board[row][col]
	end
	return nil
end

local function sumPowerAtLocation(gameState, playerID, locIdx)
	local total = 0
	local hasDoubler = false
	for row = 1, GameConfig.GRID_ROWS do
		for col = 1, GameConfig.GRID_COLUMNS do
			local card = getCard(gameState, playerID, locIdx, col, row)
			if card then
				AbilityRegistry.recalculatePower(card)
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

local function getOpponentID(gameState, playerID)
	for pid, _ in pairs(gameState.players) do
		if pid ~= playerID then return pid end
	end
	return nil
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

	-- 2. GRANT ENERGY
	for _, pid in ipairs({p1ID, p2ID}) do
		gs.players[pid].energy = gs.players[pid].energy + GameConfig.ENERGY_PER_TURN
		print(string.format("[Match] %s energy: %d", pid, gs.players[pid].energy))
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

	-- 11. BROADCAST REVEAL RESULTS
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
	if not location or not location.effect then return end

	-- Verdant Grove: +1 Power to all cards here (both players)
	if location.effect == "StartOfTurn:AddPower:AllHere:1" then
		if gs.turn > 1 then  -- Don't apply on turn 1 (no cards yet)
			for pid, _ in pairs(gs.players) do
				for row = 1, GameConfig.GRID_ROWS do
					for col = 1, GameConfig.GRID_COLUMNS do
						local card = getCard(gs, pid, locIdx, col, row)
						if card then
							table.insert(card.powerModifiers, {
								source = "VERDANT_GROVE_START",
								amount = 1,
							})
							print(string.format("[Match] Verdant Grove: +1 Power to %s (%s) at loc %d (%d,%d)",
								card.cardID, pid, locIdx, col, row))
						end
					end
				end
			end
		end
	end
end

-- ============================================================
-- Client Communication
-- ============================================================

function MatchManager:sendTurnStart()
	local gs = self.gameState
	local turnStartEvent = Events:FindFirstChild("TurnStart")
	if not turnStartEvent then return end

	for _, pid in ipairs({self.playerIDs[1], self.playerIDs[2]}) do
		if pid ~= "BOT" then
			local player = self.playerObjects[pid]
			if player and typeof(player) == "Instance" then
				local opponentID = getOpponentID(gs, pid)
				local visibleState = {
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
				turnStartEvent:FireClient(player, visibleState)
			end
		end
	end
end

function MatchManager:getVisibleOpponentBoards(opponentID)
	local gs = self.gameState
	local boards = {}
	for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
		boards[locIdx] = {}
		for row = 1, GameConfig.GRID_ROWS do
			boards[locIdx][row] = {}
			for col = 1, GameConfig.GRID_COLUMNS do
				local card = getCard(gs, opponentID, locIdx, col, row)
				if card then
					AbilityRegistry.recalculatePower(card)
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
	local revealEvent = Events:FindFirstChild("RevealResult")
	if not revealEvent then return end

	for _, pid in ipairs({self.playerIDs[1], self.playerIDs[2]}) do
		if pid ~= "BOT" then
			local player = self.playerObjects[pid]
			if player and typeof(player) == "Instance" then
				local opponentID = getOpponentID(gs, pid)
				local resultData = {
					turn = gs.turn,
					myBoards = gs.players[pid].boards,
					oppBoards = self:getVisibleOpponentBoards(opponentID),
					myPlays = gs.turnPlays[pid] or {},
					oppPlays = gs.turnPlays[opponentID] or {},
					locations = gs.locations,
				}
				revealEvent:FireClient(player, resultData)
			end
		end
	end
end

function MatchManager:sendScoreUpdate()
	local gs = self.gameState
	local scoreEvent = Events:FindFirstChild("ScoreUpdate")
	if not scoreEvent then return end

	local p1ID = self.playerIDs[1]
	local p2ID = self.playerIDs[2]

	local scoreData = {
		turn = gs.turn,
		scores = {
			[p1ID] = gs.players[p1ID].score,
			[p2ID] = gs.players[p2ID].score,
		},
		locationPower = {},
	}

	for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
		scoreData.locationPower[locIdx] = {
			[p1ID] = sumPowerAtLocation(gs, p1ID, locIdx),
			[p2ID] = sumPowerAtLocation(gs, p2ID, locIdx),
		}
	end

	for _, pid in ipairs({p1ID, p2ID}) do
		if pid ~= "BOT" then
			local player = self.playerObjects[pid]
			if player and typeof(player) == "Instance" then
				scoreEvent:FireClient(player, scoreData)
			end
		end
	end
end

function MatchManager:sendGameOver(winnerID)
	local gs = self.gameState
	local gameOverEvent = Events:FindFirstChild("GameOver")
	if not gameOverEvent then return end

	local p1ID = self.playerIDs[1]
	local p2ID = self.playerIDs[2]

	local resultData = {
		winner = winnerID,
		finalScores = {
			[p1ID] = gs.players[p1ID].score,
			[p2ID] = gs.players[p2ID].score,
		},
		totalTurns = gs.turn,
	}

	for _, pid in ipairs({p1ID, p2ID}) do
		if pid ~= "BOT" then
			local player = self.playerObjects[pid]
			if player and typeof(player) == "Instance" then
				gameOverEvent:FireClient(player, resultData)
			end
		end
	end
end

function MatchManager:sendInvalidPlay(playerID, reason)
	local invalidEvent = Events:FindFirstChild("InvalidPlay")
	if not invalidEvent then return end

	if playerID ~= "BOT" then
		local player = self.playerObjects[playerID]
		if player and typeof(player) == "Instance" then
			invalidEvent:FireClient(player, { reason = reason })
		end
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
			-- Empty submission = pass for any player who didn't submit
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

		-- Check if opponent card is in that slot (can't overwrite opponent)
		local opponentID = getOpponentID(gs, playerID)
		local oppCard = getCard(gs, opponentID, locIdx, col, row)
		if oppCard then
			print(string.format("[Match] REJECTED: %s play %d — slot occupied by opponent", playerID, i))
			self:sendInvalidPlay(playerID, "Cannot overwrite opponent's card")
			continue
		end

		-- Check location restrictions
		local location = gs.locations[locIdx]
		if location.effect then
			-- Sky Temple: only cards costing 3+
			if location.effect == "Restrict:MinCost:3" and def.cost < 3 then
				print(string.format("[Match] REJECTED: %s play %d — %s (cost %d) blocked by Sky Temple",
					playerID, i, cardID, def.cost))
				self:sendInvalidPlay(playerID, cardID .. " blocked by " .. location.name)
				continue
			end

			-- Dueling Grounds: front row only (row 1)
			if location.effect == "Restrict:FrontRowOnly" and row ~= 1 then
				print(string.format("[Match] REJECTED: %s play %d — back row blocked by Dueling Grounds",
					playerID, i))
				self:sendInvalidPlay(playerID, "Only front row allowed at " .. location.name)
				continue
			end
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
		local existingCard = getCard(gs, playerID, locIdx, col, row)
		if existingCard then
			print(string.format("[Match] OVERWRITE: %s destroys their %s at loc %d (%d,%d)",
				playerID, existingCard.cardID, locIdx, col, row))
			gs.players[playerID].boards[locIdx][row][col] = nil
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

		-- Apply location on-play effects
		local location = gs.locations[locIdx]
		if location.effect then
			-- War Camp: +1 Power on play
			if location.effect == "OnPlay:AddPower:Self:1" then
				table.insert(cardState.powerModifiers, {
					source = location.id .. "_EFFECT",
					amount = 1,
				})
				print(string.format("[Match] %s effect: +1 Power to %s", location.name, cardID))
			end

			-- Frozen Lake: -1 Power on play
			if location.effect == "OnPlay:AddPower:Self:-1" then
				table.insert(cardState.powerModifiers, {
					source = location.id .. "_EFFECT",
					amount = -1,
				})
				print(string.format("[Match] %s effect: -1 Power to %s", location.name, cardID))
			end

			-- Mana Well: draw a card on play
			if location.effect == "OnPlay:DrawCard:1" then
				if #player.hand < GameConfig.MAX_HAND_SIZE and #player.deck > 0 then
					local drawn = table.remove(player.deck, 1)
					table.insert(player.hand, drawn)
					print(string.format("[Match] %s effect: %s drew %s", location.name, playerID, drawn))
				end
			end
		end

		-- Place the card
		gs.players[playerID].boards[locIdx][row][col] = cardState
		AbilityRegistry.recalculatePower(cardState)

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
			-- Get cards this player placed at this location THIS turn, in play order
			local plays = gs.turnPlays[pid] or {}
			local newCards = {}
			for _, play in ipairs(plays) do
				if play.locIdx == locIdx then
					local card = getCard(gs, pid, locIdx, play.col, play.row)
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

			-- Sort by play order
			table.sort(newCards, function(a, b) return a.playOrder < b.playOrder end)

			-- Resolve each On Reveal
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
						AbilityRegistry.recalculatePower(card)
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
		local p1Power = sumPowerAtLocation(gs, p1ID, locIdx)
		local p2Power = sumPowerAtLocation(gs, p2ID, locIdx)

		local p1Points = 0
		local p2Points = 0

		if p1Power > p2Power then
			p1Points = location.pointValue
		elseif p2Power > p1Power then
			p2Points = location.pointValue
		else
			-- Tie: each player gets 1 point
			p1Points = 1
			p2Points = 1
		end

		gs.players[p1ID].score = gs.players[p1ID].score + p1Points
		gs.players[p2ID].score = gs.players[p2ID].score + p2Points

		print(string.format("[Match] %s: %s Power %d vs %s Power %d → %s +%d, %s +%d",
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
			-- Already in tiebreaker — determine winner
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
			-- Exact tie at threshold — play one more tiebreaker turn
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

-- Run a bot-vs-bot match to completion without RemoteEvents
function MatchManager.runTestMatch()
	print("\n[TestMatch] Starting bot-vs-bot test match...")

	local match = setmetatable({}, MatchManager)
	match.playerIDs = { [1] = "BOT_A", [2] = "BOT_B" }
	match.playerObjects = { ["BOT_A"] = "BOT_A", ["BOT_B"] = "BOT_B" }
	match.isPlayer2Bot = true
	match.player1 = "BOT_A"
	match.player2 = "BOT_B"
	match.matchActive = true
	match.turnSubmissions = {}
	match.submissionEvents = {}

	match:initGameState()

	local BotPlayer = require(script.Parent.BotPlayer)
	local gs = match.gameState
	local p1ID = "BOT_A"
	local p2ID = "BOT_B"

	print("[TestMatch] === MATCH STARTED ===")

	local maxTurns = 30  -- Safety limit
	while match.matchActive and gs.phase ~= "GAME_OVER" and gs.turn < maxTurns do
		-- ADVANCE TURN
		gs.turn = gs.turn + 1
		print(string.format("\n[TestMatch] ========== TURN %d ==========", gs.turn))

		-- GRANT ENERGY
		for _, pid in ipairs({p1ID, p2ID}) do
			gs.players[pid].energy = gs.players[pid].energy + GameConfig.ENERGY_PER_TURN
		end

		-- DRAW CARDS
		for _, pid in ipairs({p1ID, p2ID}) do
			local player = gs.players[pid]
			if #player.hand < GameConfig.MAX_HAND_SIZE and #player.deck > 0 then
				local card = table.remove(player.deck, 1)
				table.insert(player.hand, card)
			end
		end

		-- START-OF-TURN EFFECTS
		for _, locIdx in ipairs(gs.locationPriority) do
			match:applyStartOfTurnEffect(locIdx)
		end

		gs.phase = "PLANNING"

		-- BOT SUBMISSIONS
		local bot1Plays = BotPlayer.decidePlays(gs, p1ID)
		local bot2Plays = BotPlayer.decidePlays(gs, p2ID)

		-- VALIDATE AND PLACE
		gs.turnPlays = {}
		gs.turnPlays[p1ID] = match:validateSubmission(p1ID, bot1Plays)
		gs.turnPlays[p2ID] = match:validateSubmission(p2ID, bot2Plays)
		match:placeCards(p1ID, gs.turnPlays[p1ID])
		match:placeCards(p2ID, gs.turnPlays[p2ID])

		gs.phase = "RESOLVING"

		-- RESOLVE ON REVEALS
		match:resolveOnReveals()

		-- RECALCULATE ONGOING
		match:recalculateOngoing()

		-- SCORE
		match:scoreLocations()

		-- WIN CHECK
		match:checkWinCondition()
	end

	if gs.turn >= maxTurns and gs.phase ~= "GAME_OVER" then
		print("[TestMatch] Hit turn limit — forcing game end")
		local p1S = gs.players[p1ID].score
		local p2S = gs.players[p2ID].score
		if p1S > p2S then
			match:endGame(p1ID)
		elseif p2S > p1S then
			match:endGame(p2ID)
		else
			match:endGame("DRAW")
		end
	end

	return gs
end

return MatchManager
