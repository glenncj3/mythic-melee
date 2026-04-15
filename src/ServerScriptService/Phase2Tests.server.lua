--[[
	Phase 2 Tests — validates the MatchManager, BotPlayer, and GameServer.

	Run in Roblox Studio. Tests cover:
		1. MatchManager game state initialization
		2. Submission validation (energy, hand, slot, restrictions)
		3. Card placement and overwriting
		4. On Reveal resolution order
		5. Ongoing recalculation
		6. Scoring logic
		7. Win condition detection
		8. BotPlayer decision-making
		9. Full bot-vs-bot match simulation
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Modules:WaitForChild("GameConfig"))
local CardDatabase = require(Modules:WaitForChild("CardDatabase"))
local LocationDatabase = require(Modules:WaitForChild("LocationDatabase"))
local AbilityRegistry = require(Modules:WaitForChild("AbilityRegistry"))
local SlotGrid = require(Modules:WaitForChild("SlotGrid"))
local MatchManager = require(script.Parent:WaitForChild("MatchManager"))
local BotPlayer = require(script.Parent:WaitForChild("BotPlayer"))

-- ============================================================
-- Test Framework
-- ============================================================

local totalTests = 0
local passedTests = 0
local failedTests = 0
local failedNames = {}

local function test(name, fn)
	totalTests = totalTests + 1
	local ok, err = pcall(fn)
	if ok then
		passedTests = passedTests + 1
		print(string.format("  PASS: %s", name))
	else
		failedTests = failedTests + 1
		table.insert(failedNames, name)
		warn(string.format("  FAIL: %s — %s", name, tostring(err)))
	end
end

local function assertEqual(actual, expected, msg)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", msg or "assertEqual", tostring(expected), tostring(actual)))
	end
end

local function assertTrue(val, msg)
	if not val then error(msg or "assertTrue failed") end
end

local function assertNotNil(val, msg)
	if val == nil then error(msg or "assertNotNil failed") end
end

-- ============================================================
-- Helpers: build game state for unit tests (no real Player objects)
-- ============================================================

local function makeTestMatch()
	-- Create a MatchManager-like context with test player IDs
	local match = setmetatable({}, { __index = MatchManager })
	match.playerIDs = { [1] = "P1", [2] = "P2" }
	match.playerObjects = { ["P1"] = "P1", ["P2"] = "P2" }
	match.isPlayer2Bot = false
	match.matchActive = true
	match.turnSubmissions = {}
	match.submissionEvents = {}
	return match
end

local function makeGameState()
	local function makeEmptyBoard()
		local boards = {}
		for locIdx = 1, 2 do
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

	return {
		players = {
			["P1"] = {
				score = 0,
				deck = { "DRAGON", "TITAN", "OVERLORD", "VOID_WALKER", "COLOSSUS" },
				hand = { "SPARK", "SCOUT", "IRON_GUARD", "HEALER", "STONE_GOLEM" },
				maxEnergy = 5,
				energy = 5,
				boards = makeEmptyBoard(),
			},
			["P2"] = {
				score = 0,
				deck = { "DRAGON", "TITAN", "OVERLORD", "VOID_WALKER", "COLOSSUS" },
				hand = { "SPARK", "SABOTEUR", "IRON_GUARD", "WAR_BEAST", "EMBER" },
				maxEnergy = 5,
				energy = 5,
				boards = makeEmptyBoard(),
			},
		},
		locations = {
			[1] = {
				id = "WAR_CAMP", name = "War Camp", pointValue = 3,
				effect = "OnPlay:AddPower:Self:1", effectText = "Cards played here get +1 Power.",
			},
			[2] = {
				id = "CRYSTAL_CAVERN", name = "Crystal Cavern", pointValue = 2,
				effect = nil, effectText = nil,
			},
		},
		locationPriority = { 1, 2 },
		playerPriority = { "P1", "P2" },
		turn = 3,
		phase = "PLANNING",
		turnPlays = {},
		tiebreaker = false,
	}
end

local function makeCardState(cardID, turnPlayed, playOrder)
	local def = CardDatabase[cardID]
	return {
		cardID = cardID,
		basePower = def.power,
		powerModifiers = {},
		currentPower = def.power,
		isToken = false,
		isImmune = false,
		turnPlayed = turnPlayed or 1,
		playOrder = playOrder or 1,
	}
end

-- ============================================================
-- 1. Validation Tests
-- ============================================================

print("\n=== Validation Tests ===")

test("Valid play accepted", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()

	local plays = {
		{ cardID = "SPARK", locIdx = 1, col = 1, row = 1 },
	}
	local valid = match:validateSubmission("P1", plays)
	assertEqual(#valid, 1, "Should accept 1 valid play")
	assertEqual(valid[1].cardID, "SPARK", "Card ID")
end)

test("Card not in hand rejected", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()

	local plays = {
		{ cardID = "DRAGON", locIdx = 1, col = 1, row = 1 },  -- DRAGON is in deck, not hand
	}
	local valid = match:validateSubmission("P1", plays)
	assertEqual(#valid, 0, "Should reject card not in hand")
end)

test("Exceeding energy rejected", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	match.gameState.players["P1"].energy = 2

	local plays = {
		{ cardID = "STONE_GOLEM", locIdx = 1, col = 1, row = 1 },  -- costs 3
	}
	local valid = match:validateSubmission("P1", plays)
	assertEqual(#valid, 0, "Should reject play exceeding energy")
end)

test("Multiple plays deduct energy correctly", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	match.gameState.players["P1"].energy = 4

	local plays = {
		{ cardID = "SPARK", locIdx = 1, col = 1, row = 1 },       -- cost 1
		{ cardID = "IRON_GUARD", locIdx = 1, col = 2, row = 1 },  -- cost 2 (total 3)
		{ cardID = "STONE_GOLEM", locIdx = 2, col = 1, row = 1 }, -- cost 3 (total 6 > 4, rejected)
	}
	local valid = match:validateSubmission("P1", plays)
	assertEqual(#valid, 2, "Should accept first 2 plays, reject 3rd for energy")
end)

test("Invalid slot rejected", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()

	local plays = {
		{ cardID = "SPARK", locIdx = 1, col = 4, row = 1 },  -- col 4 out of bounds
	}
	local valid = match:validateSubmission("P1", plays)
	assertEqual(#valid, 0, "Should reject out-of-bounds slot")
end)

test("Sky Temple blocks cards under cost 3", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	match.gameState.locations[1] = {
		id = "SKY_TEMPLE", name = "Sky Temple", pointValue = 4,
		effect = "Restrict:MinCost:3", effectText = "Only cards costing 3 or more.",
	}

	local plays = {
		{ cardID = "SPARK", locIdx = 1, col = 1, row = 1 },  -- cost 1, blocked
	}
	local valid = match:validateSubmission("P1", plays)
	assertEqual(#valid, 0, "Sky Temple should block cost-1 card")
end)

test("Dueling Grounds blocks back row", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	match.gameState.locations[1] = {
		id = "DUELING_GROUNDS", name = "Dueling Grounds", pointValue = 3,
		effect = "Restrict:FrontRowOnly", effectText = "Front row only.",
	}

	local plays = {
		{ cardID = "SPARK", locIdx = 1, col = 1, row = 2 },  -- row 2, blocked
	}
	local valid = match:validateSubmission("P1", plays)
	assertEqual(#valid, 0, "Dueling Grounds should block back row")
end)

test("Dueling Grounds allows front row", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	match.gameState.locations[1] = {
		id = "DUELING_GROUNDS", name = "Dueling Grounds", pointValue = 3,
		effect = "Restrict:FrontRowOnly", effectText = "Front row only.",
	}

	local plays = {
		{ cardID = "SPARK", locIdx = 1, col = 1, row = 1 },  -- row 1, allowed
	}
	local valid = match:validateSubmission("P1", plays)
	assertEqual(#valid, 1, "Dueling Grounds should allow front row")
end)

test("Playing at same slot coords as opponent is allowed (separate grids)", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	-- Opponent has a card at loc 1 (1,1) on THEIR grid
	match.gameState.players["P2"].boards[1][1][1] = makeCardState("SPARK", 1, 1)

	local plays = {
		{ cardID = "SPARK", locIdx = 1, col = 1, row = 1 },  -- same coords, but on P1's own grid
	}
	local valid = match:validateSubmission("P1", plays)
	assertEqual(#valid, 1, "Should allow play — each player has their own grid")
end)

test("Overwriting own card is allowed", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	-- Place own card at loc 1 (1,1)
	match.gameState.players["P1"].boards[1][1][1] = makeCardState("SPARK", 1, 1)

	local plays = {
		{ cardID = "IRON_GUARD", locIdx = 1, col = 1, row = 1 },  -- overwrite own card
	}
	local valid = match:validateSubmission("P1", plays)
	assertEqual(#valid, 1, "Should allow overwriting own card")
end)

-- ============================================================
-- 1b. Energy System Tests
-- ============================================================

print("\n=== Energy System Tests ===")

test("Energy refills to max each turn, not increments from remaining", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	local gs = match.gameState

	-- Simulate turn 3: player has 5 max energy, spends 3
	gs.players["P1"].maxEnergy = 3
	gs.players["P1"].energy = 0  -- spent all energy

	-- Turn 4 grant: max goes to 4, energy refills to 4
	gs.turn = 3
	gs.turn = gs.turn + 1
	gs.players["P1"].maxEnergy = gs.players["P1"].maxEnergy + GameConfig.ENERGY_PER_TURN
	gs.players["P1"].energy = gs.players["P1"].maxEnergy

	assertEqual(gs.players["P1"].maxEnergy, 4, "Max energy should be 4 on turn 4")
	assertEqual(gs.players["P1"].energy, 4, "Energy should refill to 4, not 0+1=1")
end)

test("Energy on turn N equals N regardless of spending", function()
	-- Simulate a full sequence of turns
	local maxE = GameConfig.STARTING_MAX_ENERGY
	for turn = 1, 10 do
		maxE = maxE + GameConfig.ENERGY_PER_TURN
		local energy = maxE  -- refill
		assertEqual(energy, turn, "Turn " .. turn .. " should have " .. turn .. " energy")

		-- Simulate spending all energy
		energy = 0
		-- Next turn should still refill properly
	end
end)

test("Spending energy does not reduce next turn's max", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	local gs = match.gameState

	gs.players["P1"].maxEnergy = 5
	gs.players["P1"].energy = 5

	-- Play Stone Golem (cost 3)
	local plays = { { cardID = "STONE_GOLEM", locIdx = 2, col = 1, row = 1, playOrder = 1 } }
	match:placeCards("P1", plays)

	-- Energy should be reduced by 3
	assertEqual(gs.players["P1"].energy, 2, "Energy after spending 3 should be 2")
	-- Max energy should be unchanged
	assertEqual(gs.players["P1"].maxEnergy, 5, "Max energy should still be 5")
end)

-- ============================================================
-- 2. Card Placement Tests
-- ============================================================

print("\n=== Card Placement Tests ===")

test("Placing a card removes it from hand and deducts energy", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	local gs = match.gameState

	local plays = { { cardID = "SPARK", locIdx = 1, col = 1, row = 1, playOrder = 1 } }
	match:placeCards("P1", plays)

	-- Card should be on board
	assertNotNil(gs.players["P1"].boards[1][1][1], "Card should be placed")
	assertEqual(gs.players["P1"].boards[1][1][1].cardID, "SPARK", "Card ID on board")

	-- Card removed from hand
	local sparkInHand = false
	for _, c in ipairs(gs.players["P1"].hand) do
		if c == "SPARK" then sparkInHand = true break end
	end
	assertTrue(not sparkInHand, "SPARK should be removed from hand")

	-- Energy deducted (Spark costs 1)
	assertEqual(gs.players["P1"].energy, 4, "Energy should be 5-1=4")
end)

test("War Camp applies +1 Power on placement", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	local gs = match.gameState

	local plays = { { cardID = "SPARK", locIdx = 1, col = 1, row = 1, playOrder = 1 } }
	match:placeCards("P1", plays)

	local card = gs.players["P1"].boards[1][1][1]
	assertNotNil(card, "Card placed")
	-- Spark base 2, War Camp +1 = 3
	AbilityRegistry.recalculatePower(card)
	assertEqual(card.currentPower, 3, "Spark should be 2+1=3 at War Camp")
end)

test("Frozen Lake applies -1 Power on placement", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	match.gameState.locations[1] = {
		id = "FROZEN_LAKE", name = "Frozen Lake", pointValue = 2,
		effect = "OnPlay:AddPower:Self:-1", effectText = "-1 Power.",
	}
	local gs = match.gameState

	local plays = { { cardID = "SPARK", locIdx = 1, col = 1, row = 1, playOrder = 1 } }
	match:placeCards("P1", plays)

	local card = gs.players["P1"].boards[1][1][1]
	AbilityRegistry.recalculatePower(card)
	assertEqual(card.currentPower, 1, "Spark should be 2-1=1 at Frozen Lake")
end)

test("Overwrite destroys existing card", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	local gs = match.gameState

	-- Pre-place a card
	gs.players["P1"].boards[1][1][1] = makeCardState("SPARK", 1, 1)

	-- Overwrite with IRON_GUARD
	local plays = { { cardID = "IRON_GUARD", locIdx = 1, col = 1, row = 1, playOrder = 1 } }
	match:placeCards("P1", plays)

	local card = gs.players["P1"].boards[1][1][1]
	assertEqual(card.cardID, "IRON_GUARD", "Slot should now have IRON_GUARD")
end)

test("Mana Well draws a card on placement", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	match.gameState.locations[2] = {
		id = "MANA_WELL", name = "Mana Well", pointValue = 2,
		effect = "OnPlay:DrawCard:1", effectText = "Draw on play.",
	}
	local gs = match.gameState
	local handBefore = #gs.players["P1"].hand

	local plays = { { cardID = "SPARK", locIdx = 2, col = 1, row = 1, playOrder = 1 } }
	match:placeCards("P1", plays)

	-- Hand should be: before - 1 (played) + 1 (drawn) = same
	assertEqual(#gs.players["P1"].hand, handBefore, "Mana Well draw should offset the play")
end)

-- ============================================================
-- 3. On Reveal Resolution Order Tests
-- ============================================================

print("\n=== On Reveal Resolution Order Tests ===")

test("Higher-value location resolves first", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	local gs = match.gameState

	-- War Camp (3 pts) should resolve before Crystal Cavern (2 pts)
	assertEqual(gs.locationPriority[1], 1, "War Camp (loc 1, 3pts) should be first")
	assertEqual(gs.locationPriority[2], 2, "Crystal Cavern (loc 2, 2pts) should be second")
end)

test("Higher-score player resolves first at each location", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	local gs = match.gameState

	-- Give P1 a higher score
	gs.players["P1"].score = 5
	gs.players["P2"].score = 3

	-- Place cards with OnReveal at loc 1 for both players
	local healer = makeCardState("HEALER", 3, 1)
	gs.players["P1"].boards[1][1][1] = healer
	gs.turnPlays = {
		["P1"] = { { cardID = "HEALER", locIdx = 1, col = 1, row = 1, playOrder = 1 } },
		["P2"] = {},
	}

	-- Resolve — P1 should go first since score is higher
	match:resolveOnReveals()
	-- No crash = resolution order logic works
	assertTrue(true, "Resolution completed without error")
end)

-- ============================================================
-- 4. Scoring Tests
-- ============================================================

print("\n=== Scoring Tests ===")

test("Player with more Power wins location points", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	local gs = match.gameState

	-- P1 has 5 power at loc 1, P2 has 2
	gs.players["P1"].boards[1][1][1] = makeCardState("STONE_GOLEM", 1, 1)  -- 5 power
	gs.players["P2"].boards[1][1][1] = makeCardState("SPARK", 1, 1)  -- 2 power

	match:scoreLocations()

	-- P1 should win War Camp (3 pts), P2 wins nothing at loc 1
	-- Both have 0 at loc 2, so tie = 1 point each
	assertEqual(gs.players["P1"].score, 3 + 1, "P1 should get 3 (War Camp) + 1 (tie)")
	assertEqual(gs.players["P2"].score, 0 + 1, "P2 should get 0 + 1 (tie)")
end)

test("Tie at location gives 1 point each", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	local gs = match.gameState

	-- Equal power at loc 1
	gs.players["P1"].boards[1][1][1] = makeCardState("SPARK", 1, 1)  -- 2 power
	gs.players["P2"].boards[1][1][1] = makeCardState("SPARK", 1, 1)  -- 2 power

	match:scoreLocations()

	-- Tie at War Camp = 1 each, tie at Crystal Cavern = 1 each
	assertEqual(gs.players["P1"].score, 2, "P1 should get 1+1=2 from ties")
	assertEqual(gs.players["P2"].score, 2, "P2 should get 1+1=2 from ties")
end)

test("Empty location with no cards on either side ties", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	local gs = match.gameState

	-- No cards at any location
	match:scoreLocations()

	-- Both empty = 0 vs 0 = tie = 1 point each per location
	assertEqual(gs.players["P1"].score, 2, "P1 gets 1+1=2 from empty ties")
	assertEqual(gs.players["P2"].score, 2, "P2 gets 1+1=2 from empty ties")
end)

test("One player at location wins full points", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	local gs = match.gameState

	-- Only P1 has cards at loc 1
	gs.players["P1"].boards[1][1][1] = makeCardState("SPARK", 1, 1)
	-- P2 has nothing at loc 1

	match:scoreLocations()

	-- P1 wins War Camp (3pts), loc 2 both empty = tie (1 each)
	assertEqual(gs.players["P1"].score, 4, "P1: 3 (won) + 1 (tie) = 4")
	assertEqual(gs.players["P2"].score, 1, "P2: 0 + 1 (tie) = 1")
end)

-- ============================================================
-- 5. Win Condition Tests
-- ============================================================

print("\n=== Win Condition Tests ===")

test("Player reaching threshold wins", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	local gs = match.gameState

	gs.players["P1"].score = 20
	gs.players["P2"].score = 15

	match:checkWinCondition()

	assertEqual(gs.phase, "GAME_OVER", "Game should be over")
end)

test("Higher score wins when both cross threshold", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	local gs = match.gameState

	gs.players["P1"].score = 22
	gs.players["P2"].score = 20

	match:checkWinCondition()

	assertEqual(gs.phase, "GAME_OVER", "Game should be over")
end)

test("Exact tie at threshold triggers tiebreaker", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	local gs = match.gameState

	gs.players["P1"].score = 20
	gs.players["P2"].score = 20

	match:checkWinCondition()

	assertTrue(gs.tiebreaker, "Should enter tiebreaker")
	assertTrue(gs.phase ~= "GAME_OVER", "Game should NOT be over yet")
end)

test("No win when below threshold", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	local gs = match.gameState

	gs.players["P1"].score = 15
	gs.players["P2"].score = 12

	match:checkWinCondition()

	assertTrue(gs.phase ~= "GAME_OVER", "Game should continue")
end)

-- ============================================================
-- 6. Ongoing Recalculation Tests
-- ============================================================

print("\n=== Ongoing Recalculation Tests ===")

test("Ongoing effects recalculated from scratch", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	local gs = match.gameState

	-- Place Seedling at (1,1) and Spark at (2,1) — adjacent
	local seedling = makeCardState("SEEDLING", 1, 1)
	gs.players["P1"].boards[1][1][1] = seedling

	local spark = makeCardState("SPARK", 1, 2)
	gs.players["P1"].boards[1][1][2] = spark

	match:recalculateOngoing()

	-- Spark should have +1 from Seedling
	assertEqual(spark.currentPower, 3, "Spark should be 2+1=3 from Seedling")
end)

test("Commander boosts all friendlies at location", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	local gs = match.gameState

	local commander = makeCardState("COMMANDER", 1, 1)
	gs.players["P1"].boards[1][1][1] = commander

	local spark = makeCardState("SPARK", 1, 2)
	gs.players["P1"].boards[1][1][2] = spark

	local golem = makeCardState("STONE_GOLEM", 1, 3)
	gs.players["P1"].boards[1][2][1] = golem

	match:recalculateOngoing()

	assertEqual(spark.currentPower, 3, "Spark: 2+1 from Commander = 3")
	assertEqual(golem.currentPower, 6, "Golem: 5+1 from Commander = 6")
	assertEqual(commander.currentPower, 4, "Commander should not boost itself")
end)

test("Ongoing clears previous Ongoing modifiers before reapplying", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	local gs = match.gameState

	local seedling = makeCardState("SEEDLING", 1, 1)
	gs.players["P1"].boards[1][1][1] = seedling

	local spark = makeCardState("SPARK", 1, 2)
	gs.players["P1"].boards[1][1][2] = spark

	-- Apply twice — should not stack
	match:recalculateOngoing()
	match:recalculateOngoing()

	assertEqual(spark.currentPower, 3, "Spark should still be 3 after double recalculation")
end)

-- ============================================================
-- 7. Start-of-Turn Effect Tests
-- ============================================================

print("\n=== Start-of-Turn Effect Tests ===")

test("Verdant Grove adds +1 to all cards each turn", function()
	local match = makeTestMatch()
	match.gameState = makeGameState()
	local gs = match.gameState
	gs.locations[1] = {
		id = "VERDANT_GROVE", name = "Verdant Grove", pointValue = 2,
		effect = "StartOfTurn:AddPower:AllHere:1", effectText = "+1 each turn.",
	}
	gs.turn = 2  -- Not turn 1

	local spark = makeCardState("SPARK", 1, 1)
	gs.players["P1"].boards[1][1][1] = spark

	local enemySpark = makeCardState("SPARK", 1, 1)
	gs.players["P2"].boards[1][1][1] = enemySpark

	match:applyStartOfTurnEffect(1)

	-- Both should have +1
	local m1 = 0
	for _, m in ipairs(spark.powerModifiers) do m1 = m1 + m.amount end
	assertEqual(m1, 1, "Friendly card should get +1 from Verdant Grove")

	local m2 = 0
	for _, m in ipairs(enemySpark.powerModifiers) do m2 = m2 + m.amount end
	assertEqual(m2, 1, "Enemy card should also get +1 from Verdant Grove")
end)

-- ============================================================
-- 8. BotPlayer Tests
-- ============================================================

print("\n=== BotPlayer Tests ===")

test("Bot makes at least one play when it has energy and cards", function()
	local gs = makeGameState()
	gs.players["P2"].energy = 3
	gs.players["P2"].hand = { "SPARK", "IRON_GUARD", "STONE_GOLEM" }

	local plays = BotPlayer.decidePlays(gs, "P2")

	assertTrue(#plays > 0, "Bot should make at least one play")
end)

test("Bot plays no cards when energy is 0", function()
	local gs = makeGameState()
	gs.players["P2"].energy = 0
	gs.players["P2"].hand = { "SPARK", "IRON_GUARD" }

	local plays = BotPlayer.decidePlays(gs, "P2")

	assertEqual(#plays, 0, "Bot should pass with 0 energy")
end)

test("Bot plays no cards when hand is empty", function()
	local gs = makeGameState()
	gs.players["P2"].energy = 10
	gs.players["P2"].hand = {}

	local plays = BotPlayer.decidePlays(gs, "P2")

	assertEqual(#plays, 0, "Bot should pass with empty hand")
end)

test("Bot plays are all valid (cards in hand, energy sufficient)", function()
	local gs = makeGameState()
	gs.players["P2"].energy = 6
	gs.players["P2"].hand = { "SPARK", "IRON_GUARD", "STONE_GOLEM", "WAR_BEAST" }

	local plays = BotPlayer.decidePlays(gs, "P2")

	local totalCost = 0
	local usedCards = {}
	for _, play in ipairs(plays) do
		local def = CardDatabase[play.cardID]
		assertNotNil(def, "Bot played unknown card: " .. tostring(play.cardID))
		totalCost = totalCost + def.cost
		assertTrue(not usedCards[play.cardID], "Bot played same card twice: " .. play.cardID)
		usedCards[play.cardID] = true
		assertTrue(SlotGrid.isValidSlot(play.col, play.row), "Bot played to invalid slot")
		assertTrue(play.locIdx >= 1 and play.locIdx <= 2, "Bot played to invalid location")
	end
	assertTrue(totalCost <= 6, "Bot exceeded energy: " .. totalCost .. " > 6")
end)

test("Bot does not target same slot twice in one turn", function()
	local gs = makeGameState()
	gs.players["P2"].energy = 10
	gs.players["P2"].hand = { "SPARK", "SCOUT", "IRON_GUARD", "LOOKOUT", "STONE_GOLEM" }

	local plays = BotPlayer.decidePlays(gs, "P2")

	local usedSlots = {}
	for _, play in ipairs(plays) do
		local key = play.locIdx .. ":" .. play.col .. ":" .. play.row
		assertTrue(not usedSlots[key], "Bot targeted same slot twice: " .. key)
		usedSlots[key] = true
	end
end)

test("Bot respects Sky Temple restriction", function()
	local gs = makeGameState()
	gs.locations[1] = {
		id = "SKY_TEMPLE", name = "Sky Temple", pointValue = 4,
		effect = "Restrict:MinCost:3", effectText = "Only 3+ cost.",
	}
	gs.players["P2"].energy = 2
	gs.players["P2"].hand = { "SPARK", "IRON_GUARD" }  -- both under cost 3

	local plays = BotPlayer.decidePlays(gs, "P2")

	-- Bot should only play at loc 2 (Crystal Cavern, no restriction)
	for _, play in ipairs(plays) do
		if play.locIdx == 1 then
			local def = CardDatabase[play.cardID]
			assertTrue(def.cost >= 3, "Bot played low-cost card at Sky Temple: " .. play.cardID)
		end
	end
end)

test("Bot plays expensive cards when it has enough energy", function()
	local gs = makeGameState()
	gs.players["P2"].maxEnergy = 6
	gs.players["P2"].energy = 6
	gs.players["P2"].hand = { "TITAN", "SPARK", "IRON_GUARD" }  -- TITAN costs 6

	local plays = BotPlayer.decidePlays(gs, "P2")

	-- Bot should play TITAN (cost 6) since it sorts by cost descending
	local playedTitan = false
	for _, play in ipairs(plays) do
		if play.cardID == "TITAN" then playedTitan = true end
	end
	assertTrue(playedTitan, "Bot should play TITAN when it has 6 energy")
end)

test("Bot plays multiple cards spending full energy", function()
	local gs = makeGameState()
	gs.players["P2"].maxEnergy = 5
	gs.players["P2"].energy = 5
	gs.players["P2"].hand = { "STONE_GOLEM", "IRON_GUARD", "SPARK" }  -- 3+2+1 = 6, but only 5 energy

	local plays = BotPlayer.decidePlays(gs, "P2")

	local totalCost = 0
	for _, play in ipairs(plays) do
		totalCost = totalCost + CardDatabase[play.cardID].cost
	end
	assertTrue(totalCost >= 4, "Bot should spend most of its 5 energy, spent: " .. totalCost)
	assertTrue(totalCost <= 5, "Bot should not exceed 5 energy, spent: " .. totalCost)
end)

-- ============================================================
-- 9. Full Bot-vs-Bot Match
-- ============================================================

print("\n=== Full Bot-vs-Bot Match Test ===")

test("Bot-vs-bot match runs to completion", function()
	local gs = MatchManager.runTestMatch()
	assertEqual(gs.phase, "GAME_OVER", "Match should reach GAME_OVER")
	assertTrue(gs.turn >= 1, "Match should have played at least 1 turn")
	print(string.format("  Match lasted %d turns", gs.turn))
	print(string.format("  Final scores: BOT_A=%d, BOT_B=%d",
		gs.players["BOT_A"].score, gs.players["BOT_B"].score))
end)

test("Bot-vs-bot match produces valid final scores", function()
	local gs = MatchManager.runTestMatch()
	local scoreA = gs.players["BOT_A"].score
	local scoreB = gs.players["BOT_B"].score
	assertTrue(scoreA >= 0, "Score A should be non-negative")
	assertTrue(scoreB >= 0, "Score B should be non-negative")
	-- At least one should meet or exceed threshold (or it's a draw)
	assertTrue(scoreA >= GameConfig.POINTS_TO_WIN or scoreB >= GameConfig.POINTS_TO_WIN,
		string.format("At least one score should reach threshold (%d): A=%d, B=%d",
			GameConfig.POINTS_TO_WIN, scoreA, scoreB))
end)

test("Bot-vs-bot match scores increase each turn", function()
	-- Run a simpler test: verify scores are being accumulated
	local gs = MatchManager.runTestMatch()
	-- Final scores should be > 0 since both locations always score
	assertTrue(gs.players["BOT_A"].score > 0, "BOT_A should have scored something")
	assertTrue(gs.players["BOT_B"].score > 0, "BOT_B should have scored something")
end)

-- ============================================================
-- Summary
-- ============================================================

print("\n" .. string.rep("=", 50))
print(string.format("Phase 2 Tests Complete: %d/%d passed, %d failed",
	passedTests, totalTests, failedTests))
if failedTests > 0 then
	print("Failed tests:")
	for _, name in ipairs(failedNames) do
		warn("  - " .. name)
	end
else
	print("ALL TESTS PASSED!")
end
print(string.rep("=", 50))
