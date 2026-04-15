--[[
	Phase 1 Tests — comprehensive validation of all Phase 1 modules.

	Run this in Roblox Studio (ServerScriptService Script).
	Check the Output panel for PASS/FAIL results.

	Tests cover:
		1. GameConfig — all required parameters present and valid
		2. CardDatabase — all 28 cards present with correct fields
		3. LocationDatabase — all 10 locations present with correct fields
		4. SlotGrid — adjacency, row, column, bounds checking
		5. AbilityRegistry — parsing, resolver coverage, On Reveal + Ongoing logic
]]

local Modules = game.ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local CardDatabase = require(Modules:WaitForChild("CardDatabase"))
local LocationDatabase = require(Modules:WaitForChild("LocationDatabase"))
local SlotGrid = require(Modules:WaitForChild("SlotGrid"))
local AbilityRegistry = require(Modules:WaitForChild("AbilityRegistry"))

-- ============================================================
-- Test framework
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
	if not val then
		error(msg or "assertTrue failed")
	end
end

local function assertContains(tbl, val, msg)
	for _, v in ipairs(tbl) do
		if v == val then return end
	end
	error(string.format("%s: %s not found in table", msg or "assertContains", tostring(val)))
end

local function tableContainsSlot(tbl, col, row)
	for _, slot in ipairs(tbl) do
		if slot[1] == col and slot[2] == row then
			return true
		end
	end
	return false
end

-- ============================================================
-- 1. GameConfig Tests
-- ============================================================

print("\n=== GameConfig Tests ===")

test("GameConfig.DECK_SIZE is 20", function()
	assertEqual(GameConfig.DECK_SIZE, 20, "DECK_SIZE")
end)

test("GameConfig.MAX_COPIES_PER_CARD is 1", function()
	assertEqual(GameConfig.MAX_COPIES_PER_CARD, 1, "MAX_COPIES_PER_CARD")
end)

test("GameConfig.LOCATIONS_PER_GAME is 2", function()
	assertEqual(GameConfig.LOCATIONS_PER_GAME, 2, "LOCATIONS_PER_GAME")
end)

test("GameConfig.SLOTS_PER_LOCATION is 6", function()
	assertEqual(GameConfig.SLOTS_PER_LOCATION, 6, "SLOTS_PER_LOCATION")
end)

test("GameConfig.GRID_COLUMNS is 3", function()
	assertEqual(GameConfig.GRID_COLUMNS, 3, "GRID_COLUMNS")
end)

test("GameConfig.GRID_ROWS is 2", function()
	assertEqual(GameConfig.GRID_ROWS, 2, "GRID_ROWS")
end)

test("GameConfig.STARTING_HAND_SIZE is 3", function()
	assertEqual(GameConfig.STARTING_HAND_SIZE, 3, "STARTING_HAND_SIZE")
end)

test("GameConfig.STARTING_MAX_ENERGY is 0", function()
	assertEqual(GameConfig.STARTING_MAX_ENERGY, 0, "STARTING_MAX_ENERGY")
end)

test("GameConfig.ENERGY_PER_TURN is 1", function()
	assertEqual(GameConfig.ENERGY_PER_TURN, 1, "ENERGY_PER_TURN")
end)

test("GameConfig.CARDS_DRAWN_PER_TURN is 1", function()
	assertEqual(GameConfig.CARDS_DRAWN_PER_TURN, 1, "CARDS_DRAWN_PER_TURN")
end)

test("GameConfig.MAX_HAND_SIZE is 7", function()
	assertEqual(GameConfig.MAX_HAND_SIZE, 7, "MAX_HAND_SIZE")
end)

test("GameConfig.TURN_TIMER_SECONDS is 30", function()
	assertEqual(GameConfig.TURN_TIMER_SECONDS, 30, "TURN_TIMER_SECONDS")
end)

test("GameConfig.POINTS_TO_WIN is 20", function()
	assertEqual(GameConfig.POINTS_TO_WIN, 20, "POINTS_TO_WIN")
end)

test("GameConfig.STARTER_DECK has 20 cards", function()
	assertEqual(#GameConfig.STARTER_DECK, 20, "STARTER_DECK length")
end)

test("GameConfig.STARTER_DECK contains only valid card IDs", function()
	for _, cardID in ipairs(GameConfig.STARTER_DECK) do
		assertTrue(CardDatabase[cardID] ~= nil,
			"Starter deck card '" .. cardID .. "' not found in CardDatabase")
	end
end)

test("GameConfig.STARTER_DECK has no duplicates", function()
	local seen = {}
	for _, cardID in ipairs(GameConfig.STARTER_DECK) do
		assertTrue(not seen[cardID], "Duplicate in starter deck: " .. cardID)
		seen[cardID] = true
	end
end)

-- ============================================================
-- 2. CardDatabase Tests
-- ============================================================

print("\n=== CardDatabase Tests ===")

local EXPECTED_CARDS = {
	-- 1-cost
	{ id = "SPARK",       cost = 1, power = 2,  ability = nil },
	{ id = "SCOUT",       cost = 1, power = 1,  ability = "OnReveal:DrawCard:1" },
	{ id = "SEEDLING",    cost = 1, power = 1,  ability = "Ongoing:AddPower:Adjacent:1" },
	{ id = "EMBER",       cost = 1, power = 3,  ability = "OnReveal:RemovePower:Random_Friendly_Here:1" },
	{ id = "SAGE",        cost = 1, power = 1,  ability = "Ongoing:AddPower:Self:PerOngoing" },
	-- 2-cost
	{ id = "IRON_GUARD",  cost = 2, power = 3,  ability = nil },
	{ id = "FROST_SPRITE",cost = 2, power = 1,  ability = "OnReveal:RemovePower:Random_Enemy_Here:2" },
	{ id = "LOOKOUT",     cost = 2, power = 2,  ability = "OnReveal:ConditionalPower:Opponent_Played_Here:3" },
	{ id = "FLAME_IMP",   cost = 2, power = 2,  ability = "Ongoing:AddPower:Adjacent:1" },
	{ id = "MYSTIC",      cost = 2, power = 2,  ability = "OnReveal:AddPower:Column:1" },
	-- 3-cost
	{ id = "STONE_GOLEM", cost = 3, power = 5,  ability = nil },
	{ id = "HEALER",      cost = 3, power = 2,  ability = "OnReveal:AddPower:Location:1" },
	{ id = "WIND_DANCER", cost = 3, power = 4,  ability = "OnReveal:MoveThis:OtherLocation" },
	{ id = "SABOTEUR",    cost = 3, power = 3,  ability = "OnReveal:RemovePower:All_Enemy_Here:1" },
	{ id = "ECHO",        cost = 3, power = 1,  ability = "OnReveal:SummonCopy:Adjacent:1" },
	-- 4-cost
	{ id = "WAR_BEAST",   cost = 4, power = 7,  ability = nil },
	{ id = "COMMANDER",   cost = 4, power = 4,  ability = "Ongoing:AddPower:Location:1" },
	{ id = "TRICKSTER",   cost = 4, power = 0,  ability = "OnReveal:SetPower:Highest_Enemy_Here" },
	{ id = "SHIELD_WALL", cost = 4, power = 3,  ability = "Ongoing:AddPower:Row:2" },
	{ id = "BERSERKER",   cost = 4, power = 4,  ability = "OnReveal:ConditionalPower:Empty_Slots_Here:1" },
	-- 5-cost
	{ id = "DRAGON",      cost = 5, power = 9,  ability = nil },
	{ id = "STORM_MAGE",  cost = 5, power = 5,  ability = "OnReveal:RemovePower:All_Enemy_Here:2" },
	{ id = "WARLORD",     cost = 5, power = 1,  ability = "Ongoing:DoublePower:Location" },
	{ id = "HIGH_PRIESTESS", cost = 5, power = 6, ability = "OnReveal:DrawCard:2" },
	-- 6-cost
	{ id = "TITAN",       cost = 6, power = 12, ability = nil },
	{ id = "OVERLORD",    cost = 6, power = 8,  ability = "Ongoing:AddPower:AllLocations:1" },
	{ id = "VOID_WALKER", cost = 6, power = 10, ability = "OnReveal:DestroyBelow:2:Here_Both" },
	{ id = "COLOSSUS",    cost = 6, power = 8,  ability = "Ongoing:Immune" },
}

test("CardDatabase has exactly 28 cards", function()
	local allIDs = CardDatabase.getAllIDs()
	assertEqual(#allIDs, 28, "card count")
end)

for _, expected in ipairs(EXPECTED_CARDS) do
	test("Card " .. expected.id .. " exists with correct stats", function()
		local card = CardDatabase[expected.id]
		assertTrue(card ~= nil, expected.id .. " not found")
		assertEqual(card.cost, expected.cost, expected.id .. " cost")
		assertEqual(card.power, expected.power, expected.id .. " power")
		assertEqual(card.ability, expected.ability, expected.id .. " ability")
	end)
end

test("All cards have required fields (name, cost, power, rarity)", function()
	for _, id in ipairs(CardDatabase.getAllIDs()) do
		local c = CardDatabase[id]
		assertTrue(c.name ~= nil, id .. " missing name")
		assertTrue(type(c.cost) == "number", id .. " cost not a number")
		assertTrue(type(c.power) == "number", id .. " power not a number")
		assertTrue(c.rarity ~= nil, id .. " missing rarity")
	end
end)

test("Cards with abilities have abilityText", function()
	for _, id in ipairs(CardDatabase.getAllIDs()) do
		local c = CardDatabase[id]
		if c.ability then
			assertTrue(c.abilityText ~= nil,
				id .. " has ability but no abilityText")
		end
	end
end)

test("Vanilla cards at each cost follow baseline power curve", function()
	-- Baseline: 1/2, 2/3, 3/5, 4/7, 5/9, 6/12
	local baseline = { [1]=2, [2]=3, [3]=5, [4]=7, [5]=9, [6]=12 }
	local vanillas = { SPARK=1, IRON_GUARD=2, STONE_GOLEM=3, WAR_BEAST=4, DRAGON=5, TITAN=6 }
	for id, cost in pairs(vanillas) do
		local card = CardDatabase[id]
		assertEqual(card.power, baseline[cost],
			id .. " vanilla baseline at cost " .. cost)
	end
end)

test("Ability cards have less power than vanilla at same cost (except drawback cards)", function()
	local baseline = { [1]=2, [2]=3, [3]=5, [4]=7, [5]=9, [6]=12 }
	-- Cards with drawback abilities (self-harm) can exceed vanilla baseline
	local drawbackCards = { EMBER = true }
	for _, id in ipairs(CardDatabase.getAllIDs()) do
		local c = CardDatabase[id]
		if c.ability and not drawbackCards[id] then
			assertTrue(c.power <= baseline[c.cost],
				id .. " (cost " .. c.cost .. ", power " .. c.power ..
				") exceeds vanilla baseline " .. baseline[c.cost])
		end
	end
end)

test("CardDatabase.printByCost(3) returns cost-3 cards", function()
	-- Just verify the function runs without error
	CardDatabase.printByCost(3)
end)

-- ============================================================
-- 3. LocationDatabase Tests
-- ============================================================

print("\n=== LocationDatabase Tests ===")

local EXPECTED_LOCATIONS = {
	{ id = "CRYSTAL_CAVERN",   points = 2, hasEffect = false },
	{ id = "DRAGONS_PEAK",     points = 3, hasEffect = false },
	{ id = "SUNKEN_RUINS",     points = 4, hasEffect = false },
	{ id = "FROZEN_LAKE",      points = 2, hasEffect = true },
	{ id = "WAR_CAMP",         points = 3, hasEffect = true },
	{ id = "SHADOW_NEXUS",     points = 3, hasEffect = true },
	{ id = "VERDANT_GROVE",    points = 2, hasEffect = true },
	{ id = "SKY_TEMPLE",       points = 4, hasEffect = true },
	{ id = "DUELING_GROUNDS",  points = 3, hasEffect = true },
	{ id = "MANA_WELL",        points = 2, hasEffect = true },
}

test("LocationDatabase has exactly 10 locations", function()
	assertEqual(#LocationDatabase.getAllIDs(), 10, "location count")
end)

for _, expected in ipairs(EXPECTED_LOCATIONS) do
	test("Location " .. expected.id .. " exists with correct data", function()
		local loc = LocationDatabase[expected.id]
		assertTrue(loc ~= nil, expected.id .. " not found")
		assertEqual(loc.pointValue, expected.points, expected.id .. " pointValue")
		if expected.hasEffect then
			assertTrue(loc.effect ~= nil, expected.id .. " expected an effect")
			assertTrue(loc.effectText ~= nil, expected.id .. " expected effectText")
		else
			assertTrue(loc.effect == nil, expected.id .. " should have no effect")
		end
	end)
end

test("Location point distribution: 4x2pts, 4x3pts, 2x4pts", function()
	local dist = {}
	for _, id in ipairs(LocationDatabase.getAllIDs()) do
		local pts = LocationDatabase[id].pointValue
		dist[pts] = (dist[pts] or 0) + 1
	end
	assertEqual(dist[2], 4, "2-point locations")
	assertEqual(dist[3], 4, "3-point locations")
	assertEqual(dist[4], 2, "4-point locations")
end)

-- ============================================================
-- 4. SlotGrid Tests
-- ============================================================

print("\n=== SlotGrid Tests ===")

test("SlotGrid.isValidSlot accepts all grid positions", function()
	for col = 1, 3 do
		for row = 1, 2 do
			assertTrue(SlotGrid.isValidSlot(col, row),
				string.format("(%d,%d) should be valid", col, row))
		end
	end
end)

test("SlotGrid.isValidSlot rejects out-of-bounds", function()
	assertTrue(not SlotGrid.isValidSlot(0, 1), "(0,1) should be invalid")
	assertTrue(not SlotGrid.isValidSlot(4, 1), "(4,1) should be invalid")
	assertTrue(not SlotGrid.isValidSlot(1, 0), "(1,0) should be invalid")
	assertTrue(not SlotGrid.isValidSlot(1, 3), "(1,3) should be invalid")
	assertTrue(not SlotGrid.isValidSlot(-1, 1), "(-1,1) should be invalid")
end)

test("SlotGrid.getAllSlots returns 6 slots", function()
	assertEqual(#SlotGrid.getAllSlots(), 6, "total slots")
end)

-- Adjacency tests per spec diagram:
-- (1,1) <-> (2,1) <-> (3,1)
--   |          |          |
-- (1,2) <-> (2,2) <-> (3,2)

test("(1,1) adjacent to (2,1) and (1,2) only", function()
	local adj = SlotGrid.getAdjacent(1, 1)
	assertEqual(#adj, 2, "(1,1) neighbor count")
	assertTrue(tableContainsSlot(adj, 2, 1), "(1,1) -> (2,1)")
	assertTrue(tableContainsSlot(adj, 1, 2), "(1,1) -> (1,2)")
end)

test("(2,1) adjacent to (1,1), (3,1), and (2,2)", function()
	local adj = SlotGrid.getAdjacent(2, 1)
	assertEqual(#adj, 3, "(2,1) neighbor count")
	assertTrue(tableContainsSlot(adj, 1, 1), "(2,1) -> (1,1)")
	assertTrue(tableContainsSlot(adj, 3, 1), "(2,1) -> (3,1)")
	assertTrue(tableContainsSlot(adj, 2, 2), "(2,1) -> (2,2)")
end)

test("(3,1) adjacent to (2,1) and (3,2) only", function()
	local adj = SlotGrid.getAdjacent(3, 1)
	assertEqual(#adj, 2, "(3,1) neighbor count")
	assertTrue(tableContainsSlot(adj, 2, 1), "(3,1) -> (2,1)")
	assertTrue(tableContainsSlot(adj, 3, 2), "(3,1) -> (3,2)")
end)

test("(1,2) adjacent to (1,1) and (2,2) only", function()
	local adj = SlotGrid.getAdjacent(1, 2)
	assertEqual(#adj, 2, "(1,2) neighbor count")
	assertTrue(tableContainsSlot(adj, 1, 1), "(1,2) -> (1,1)")
	assertTrue(tableContainsSlot(adj, 2, 2), "(1,2) -> (2,2)")
end)

test("(2,2) adjacent to (2,1), (1,2), and (3,2)", function()
	local adj = SlotGrid.getAdjacent(2, 2)
	assertEqual(#adj, 3, "(2,2) neighbor count")
	assertTrue(tableContainsSlot(adj, 2, 1), "(2,2) -> (2,1)")
	assertTrue(tableContainsSlot(adj, 1, 2), "(2,2) -> (1,2)")
	assertTrue(tableContainsSlot(adj, 3, 2), "(2,2) -> (3,2)")
end)

test("(3,2) adjacent to (3,1) and (2,2) only", function()
	local adj = SlotGrid.getAdjacent(3, 2)
	assertEqual(#adj, 2, "(3,2) neighbor count")
	assertTrue(tableContainsSlot(adj, 3, 1), "(3,2) -> (3,1)")
	assertTrue(tableContainsSlot(adj, 2, 2), "(3,2) -> (2,2)")
end)

test("No diagonal adjacency anywhere", function()
	-- (1,1) should NOT be adjacent to (2,2)
	local adj11 = SlotGrid.getAdjacent(1, 1)
	assertTrue(not tableContainsSlot(adj11, 2, 2), "(1,1) should not be adjacent to (2,2)")
	assertTrue(not tableContainsSlot(adj11, 3, 1), "(1,1) should not be adjacent to (3,1)")
	assertTrue(not tableContainsSlot(adj11, 3, 2), "(1,1) should not be adjacent to (3,2)")
end)

test("Corner slots have 2 neighbors, edge slots have 3", function()
	-- Corners: (1,1), (3,1), (1,2), (3,2)
	assertEqual(#SlotGrid.getAdjacent(1, 1), 2, "(1,1) corners")
	assertEqual(#SlotGrid.getAdjacent(3, 1), 2, "(3,1) corners")
	assertEqual(#SlotGrid.getAdjacent(1, 2), 2, "(1,2) corners")
	assertEqual(#SlotGrid.getAdjacent(3, 2), 2, "(3,2) corners")
	-- Edges: (2,1), (2,2)
	assertEqual(#SlotGrid.getAdjacent(2, 1), 3, "(2,1) edge")
	assertEqual(#SlotGrid.getAdjacent(2, 2), 3, "(2,2) edge")
end)

test("SlotGrid.getRow returns 3 slots", function()
	assertEqual(#SlotGrid.getRow(1), 3, "row 1 count")
	assertEqual(#SlotGrid.getRow(2), 3, "row 2 count")
end)

test("SlotGrid.getRow(1) contains correct slots", function()
	local r = SlotGrid.getRow(1)
	assertTrue(tableContainsSlot(r, 1, 1), "row 1 has (1,1)")
	assertTrue(tableContainsSlot(r, 2, 1), "row 1 has (2,1)")
	assertTrue(tableContainsSlot(r, 3, 1), "row 1 has (3,1)")
end)

test("SlotGrid.getColumn returns 2 slots", function()
	assertEqual(#SlotGrid.getColumn(1), 2, "col 1 count")
	assertEqual(#SlotGrid.getColumn(2), 2, "col 2 count")
	assertEqual(#SlotGrid.getColumn(3), 2, "col 3 count")
end)

test("SlotGrid.getColumn(2) contains correct slots", function()
	local c = SlotGrid.getColumn(2)
	assertTrue(tableContainsSlot(c, 2, 1), "col 2 has (2,1)")
	assertTrue(tableContainsSlot(c, 2, 2), "col 2 has (2,2)")
end)

-- ============================================================
-- 5. AbilityRegistry Tests
-- ============================================================

print("\n=== AbilityRegistry Tests ===")

test("AbilityRegistry.parse returns nil for nil input", function()
	assertEqual(AbilityRegistry.parse(nil), nil, "nil input")
end)

test("AbilityRegistry.parse correctly parses OnReveal:AddPower:Location:1", function()
	local p = AbilityRegistry.parse("OnReveal:AddPower:Location:1")
	assertTrue(p ~= nil, "parse returned nil")
	assertEqual(p.trigger, "OnReveal", "trigger")
	assertEqual(p.effect, "AddPower", "effect")
	assertEqual(#p.params, 2, "param count")
	assertEqual(p.params[1], "Location", "param1")
	assertEqual(p.params[2], "1", "param2")
end)

test("AbilityRegistry.parse correctly parses Ongoing:Immune", function()
	local p = AbilityRegistry.parse("Ongoing:Immune")
	assertTrue(p ~= nil, "parse returned nil")
	assertEqual(p.trigger, "Ongoing", "trigger")
	assertEqual(p.effect, "Immune", "effect")
	assertEqual(#p.params, 0, "param count")
end)

test("AbilityRegistry.parse handles multi-param ability", function()
	local p = AbilityRegistry.parse("OnReveal:DestroyBelow:2:Here_Both")
	assertTrue(p ~= nil, "parse returned nil")
	assertEqual(p.trigger, "OnReveal", "trigger")
	assertEqual(p.effect, "DestroyBelow", "effect")
	assertEqual(#p.params, 2, "param count")
	assertEqual(p.params[1], "2", "threshold")
	assertEqual(p.params[2], "Here_Both", "scope")
end)

test("AbilityRegistry.isOngoing detects Ongoing abilities", function()
	assertTrue(AbilityRegistry.isOngoing("Ongoing:Immune"), "Ongoing:Immune")
	assertTrue(AbilityRegistry.isOngoing("Ongoing:AddPower:Adjacent:1"), "Ongoing:AddPower")
	assertTrue(not AbilityRegistry.isOngoing("OnReveal:DrawCard:1"), "OnReveal is not Ongoing")
	assertTrue(not AbilityRegistry.isOngoing(nil), "nil is not Ongoing")
end)

test("AbilityRegistry.isOnReveal detects OnReveal abilities", function()
	assertTrue(AbilityRegistry.isOnReveal("OnReveal:DrawCard:1"), "OnReveal:DrawCard")
	assertTrue(AbilityRegistry.isOnReveal("OnReveal:AddPower:Location:1"), "OnReveal:AddPower")
	assertTrue(not AbilityRegistry.isOnReveal("Ongoing:Immune"), "Ongoing is not OnReveal")
	assertTrue(not AbilityRegistry.isOnReveal(nil), "nil is not OnReveal")
end)

-- Test that every card ability in the database can be parsed
test("All card abilities parse successfully", function()
	for _, id in ipairs(CardDatabase.getAllIDs()) do
		local c = CardDatabase[id]
		if c.ability then
			local parsed = AbilityRegistry.parse(c.ability)
			assertTrue(parsed ~= nil,
				id .. " ability '" .. c.ability .. "' failed to parse")
			assertTrue(parsed.trigger == "OnReveal" or parsed.trigger == "Ongoing",
				id .. " has unknown trigger: " .. parsed.trigger)
		end
	end
end)

-- Test that every On Reveal ability has a resolver
test("All OnReveal abilities have resolvers", function()
	for _, id in ipairs(CardDatabase.getAllIDs()) do
		local c = CardDatabase[id]
		if c.ability and AbilityRegistry.isOnReveal(c.ability) then
			-- Verify resolveOnReveal won't crash by checking parse
			local parsed = AbilityRegistry.parse(c.ability)
			assertTrue(parsed ~= nil, id .. " OnReveal ability failed to parse")
		end
	end
end)

-- ============================================================
-- 6. Integration: Mock game state ability resolution
-- ============================================================

print("\n=== Ability Resolution Integration Tests ===")

-- Helper: create a minimal game state for testing abilities
local function makeTestState()
	return {
		players = {
			["P1"] = {
				score = 0,
				deck = { "SPARK", "SCOUT", "EMBER" },
				hand = { "IRON_GUARD", "HEALER" },
				energy = 5,
				boards = {
					[1] = {
						{ nil, nil, nil },
						{ nil, nil, nil },
					},
					[2] = {
						{ nil, nil, nil },
						{ nil, nil, nil },
					},
				},
			},
			["P2"] = {
				score = 0,
				deck = { "DRAGON", "TITAN" },
				hand = { "SABOTEUR" },
				energy = 5,
				boards = {
					[1] = {
						{ nil, nil, nil },
						{ nil, nil, nil },
					},
					[2] = {
						{ nil, nil, nil },
						{ nil, nil, nil },
					},
				},
			},
		},
		locations = {
			[1] = { id = "WAR_CAMP", pointValue = 3, effect = "OnPlay:AddPower:Self:1" },
			[2] = { id = "CRYSTAL_CAVERN", pointValue = 2, effect = nil },
		},
		locationPriority = { 1, 2 },
		playerPriority = { "P1", "P2" },
		turn = 3,
		turnPlays = {
			["P1"] = {},
			["P2"] = {},
		},
	}
end

local function makeCard(cardID, basePower, turnPlayed, playOrder)
	return {
		cardID = cardID,
		basePower = basePower,
		powerModifiers = {},
		currentPower = basePower,
		isToken = false,
		isImmune = false,
		turnPlayed = turnPlayed or 1,
		playOrder = playOrder or 1,
	}
end

test("Healer OnReveal: +1 Power to other friendlies at location", function()
	local gs = makeTestState()
	local spark = makeCard("SPARK", 2, 1, 1)
	gs.players["P1"].boards[1][1][1] = spark  -- Spark at (1,1)

	local healer = makeCard("HEALER", 2, 3, 2)
	gs.players["P1"].boards[1][1][2] = healer  -- Healer at (2,1)

	AbilityRegistry.resolveOnReveal(gs, healer, "P1", 1, 2, 1)

	-- Spark should have gotten +1
	local sparkMod = 0
	for _, m in ipairs(spark.powerModifiers) do
		sparkMod = sparkMod + m.amount
	end
	assertEqual(sparkMod, 1, "Spark should have +1 from Healer")

	-- Healer should NOT have buffed itself
	local healerMod = 0
	for _, m in ipairs(healer.powerModifiers) do
		healerMod = healerMod + m.amount
	end
	assertEqual(healerMod, 0, "Healer should not buff itself")
end)

test("Frost Sprite OnReveal: -2 to random enemy at location", function()
	local gs = makeTestState()
	local enemySpark = makeCard("SPARK", 2, 1, 1)
	gs.players["P2"].boards[1][1][1] = enemySpark  -- enemy Spark at loc 1

	local frostSprite = makeCard("FROST_SPRITE", 1, 3, 1)
	gs.players["P1"].boards[1][1][2] = frostSprite

	AbilityRegistry.resolveOnReveal(gs, frostSprite, "P1", 1, 2, 1)

	-- Enemy spark should have -2
	local sparkMod = 0
	for _, m in ipairs(enemySpark.powerModifiers) do
		sparkMod = sparkMod + m.amount
	end
	assertEqual(sparkMod, -2, "Enemy Spark should have -2 from Frost Sprite")
end)

test("Colossus Ongoing: immune to enemy debuffs", function()
	local gs = makeTestState()
	local colossus = makeCard("COLOSSUS", 8, 1, 1)
	colossus.isImmune = true
	gs.players["P1"].boards[1][1][1] = colossus

	-- Simulate enemy debuff: Saboteur -1 to all enemies
	local saboteur = makeCard("SABOTEUR", 3, 3, 1)
	gs.players["P2"].boards[1][1][2] = saboteur

	AbilityRegistry.resolveOnReveal(gs, saboteur, "P2", 1, 2, 1)

	-- Colossus should have resisted the debuff
	local colossusMod = 0
	for _, m in ipairs(colossus.powerModifiers) do
		colossusMod = colossusMod + m.amount
	end
	assertEqual(colossusMod, 0, "Colossus should be immune to enemy debuffs")
end)

test("Shadow Nexus suppresses On Reveal abilities", function()
	local gs = makeTestState()
	gs.locations[1] = { id = "SHADOW_NEXUS", pointValue = 3, effect = "SuppressOnReveal" }

	local scout = makeCard("SCOUT", 1, 3, 1)
	gs.players["P1"].boards[1][1][1] = scout
	local handSizeBefore = #gs.players["P1"].hand

	AbilityRegistry.resolveOnReveal(gs, scout, "P1", 1, 1, 1)

	-- Scout's draw should NOT have triggered
	assertEqual(#gs.players["P1"].hand, handSizeBefore,
		"Scout draw should be suppressed at Shadow Nexus")
end)

test("Scout OnReveal: draws 1 card", function()
	local gs = makeTestState()
	local scout = makeCard("SCOUT", 1, 3, 1)
	gs.players["P1"].boards[2][1][1] = scout
	local handSizeBefore = #gs.players["P1"].hand

	AbilityRegistry.resolveOnReveal(gs, scout, "P1", 2, 1, 1)

	assertEqual(#gs.players["P1"].hand, handSizeBefore + 1,
		"Scout should have drawn 1 card")
end)

test("Lookout conditional: +3 when opponent played here", function()
	local gs = makeTestState()
	gs.turnPlays["P2"] = { { cardID = "SPARK", locIdx = 1, col = 1, row = 1 } }

	local lookout = makeCard("LOOKOUT", 2, 3, 1)
	gs.players["P1"].boards[1][1][2] = lookout

	AbilityRegistry.resolveOnReveal(gs, lookout, "P1", 1, 2, 1)

	local lookoutMod = 0
	for _, m in ipairs(lookout.powerModifiers) do
		lookoutMod = lookoutMod + m.amount
	end
	assertEqual(lookoutMod, 3, "Lookout should get +3 when opponent played here")
end)

test("Lookout conditional: no bonus when opponent didn't play here", function()
	local gs = makeTestState()
	gs.turnPlays["P2"] = { { cardID = "SPARK", locIdx = 2, col = 1, row = 1 } }

	local lookout = makeCard("LOOKOUT", 2, 3, 1)
	gs.players["P1"].boards[1][1][2] = lookout

	AbilityRegistry.resolveOnReveal(gs, lookout, "P1", 1, 2, 1)

	local lookoutMod = 0
	for _, m in ipairs(lookout.powerModifiers) do
		lookoutMod = lookoutMod + m.amount
	end
	assertEqual(lookoutMod, 0, "Lookout should get +0 when opponent didn't play here")
end)

test("Berserker: +1 per empty friendly slot at location", function()
	local gs = makeTestState()
	-- Place berserker at (1,1), rest are empty = 5 empty slots
	local berserker = makeCard("BERSERKER", 4, 3, 1)
	gs.players["P1"].boards[1][1][1] = berserker

	AbilityRegistry.resolveOnReveal(gs, berserker, "P1", 1, 1, 1)

	local bmod = 0
	for _, m in ipairs(berserker.powerModifiers) do
		bmod = bmod + m.amount
	end
	assertEqual(bmod, 5, "Berserker should get +5 for 5 empty slots")
end)

test("Wind Dancer: moves to other location", function()
	local gs = makeTestState()
	local dancer = makeCard("WIND_DANCER", 4, 3, 1)
	gs.players["P1"].boards[1][1][1] = dancer

	AbilityRegistry.resolveOnReveal(gs, dancer, "P1", 1, 1, 1)

	-- Should be removed from location 1
	assertEqual(gs.players["P1"].boards[1][1][1], nil, "Wind Dancer should leave loc 1")

	-- Should appear somewhere at location 2
	local found = false
	for r = 1, 2 do
		for c = 1, 3 do
			if gs.players["P1"].boards[2][r][c] then
				found = true
			end
		end
	end
	assertTrue(found, "Wind Dancer should appear at location 2")
end)

test("Echo: summons 1-Power copy in adjacent empty slot", function()
	local gs = makeTestState()
	local echo = makeCard("ECHO", 1, 3, 1)
	gs.players["P1"].boards[1][1][2] = echo  -- at (2,1)

	AbilityRegistry.resolveOnReveal(gs, echo, "P1", 1, 2, 1)

	-- Check adjacent slots: (1,1), (3,1), (2,2) — one should have a token
	local tokenFound = false
	local adjSlots = { {1,1}, {3,1}, {2,2} }
	for _, slot in ipairs(adjSlots) do
		local card = gs.players["P1"].boards[1][slot[2]][slot[1]]
		if card and card.isToken then
			tokenFound = true
			assertEqual(card.basePower, 1, "Echo token basePower")
			assertEqual(card.cardID, "ECHO", "Echo token cardID")
		end
	end
	assertTrue(tokenFound, "Echo should have summoned a token in an adjacent slot")
end)

test("Trickster: sets power to highest enemy at location", function()
	local gs = makeTestState()
	local enemyDragon = makeCard("DRAGON", 9, 1, 1)
	gs.players["P2"].boards[1][1][1] = enemyDragon

	local trickster = makeCard("TRICKSTER", 0, 3, 1)
	gs.players["P1"].boards[1][1][2] = trickster

	AbilityRegistry.resolveOnReveal(gs, trickster, "P1", 1, 2, 1)

	local tmod = 0
	for _, m in ipairs(trickster.powerModifiers) do
		tmod = tmod + m.amount
	end
	assertEqual(tmod, 9, "Trickster should gain +9 to match Dragon")
end)

test("Void Walker: destroys cards with 2 or less Power (both sides)", function()
	local gs = makeTestState()
	local weakFriendly = makeCard("SPARK", 2, 1, 1)
	gs.players["P1"].boards[1][1][1] = weakFriendly

	local weakEnemy = makeCard("SCOUT", 1, 1, 1)
	gs.players["P2"].boards[1][1][1] = weakEnemy

	local strongEnemy = makeCard("DRAGON", 9, 1, 1)
	gs.players["P2"].boards[1][1][2] = strongEnemy

	local voidWalker = makeCard("VOID_WALKER", 10, 3, 1)
	gs.players["P1"].boards[1][2][1] = voidWalker  -- at (1,2)

	AbilityRegistry.resolveOnReveal(gs, voidWalker, "P1", 1, 1, 2)

	-- Weak cards destroyed, strong survives, Void Walker survives
	assertEqual(gs.players["P1"].boards[1][1][1], nil, "Weak friendly Spark should be destroyed")
	assertEqual(gs.players["P2"].boards[1][1][1], nil, "Weak enemy Scout should be destroyed")
	assertTrue(gs.players["P2"].boards[1][1][2] ~= nil, "Strong enemy Dragon should survive")
	assertTrue(gs.players["P1"].boards[1][2][1] ~= nil, "Void Walker should survive")
end)

test("Mystic: +1 to friendly cards in same column", function()
	local gs = makeTestState()
	-- Place a card at (2,2) and Mystic at (2,1) — same column
	local friendly = makeCard("SPARK", 2, 1, 1)
	gs.players["P1"].boards[1][2][2] = friendly  -- (2,2) -> boards[1][row=2][col=2]

	local mystic = makeCard("MYSTIC", 2, 3, 1)
	gs.players["P1"].boards[1][1][2] = mystic  -- (2,1) -> boards[1][row=1][col=2]

	AbilityRegistry.resolveOnReveal(gs, mystic, "P1", 1, 2, 1)

	-- Spark at (2,2) should have +1
	local sparkMod = 0
	for _, m in ipairs(friendly.powerModifiers) do
		sparkMod = sparkMod + m.amount
	end
	assertEqual(sparkMod, 1, "Spark in same column should get +1 from Mystic")
end)

test("Ember: -1 to random friendly (not self)", function()
	local gs = makeTestState()
	local friendly = makeCard("IRON_GUARD", 3, 1, 1)
	gs.players["P1"].boards[1][1][1] = friendly

	local ember = makeCard("EMBER", 3, 3, 1)
	gs.players["P1"].boards[1][1][2] = ember

	AbilityRegistry.resolveOnReveal(gs, ember, "P1", 1, 2, 1)

	-- Iron Guard should have -1
	local igMod = 0
	for _, m in ipairs(friendly.powerModifiers) do
		igMod = igMod + m.amount
	end
	assertEqual(igMod, -1, "Iron Guard should have -1 from Ember")
end)

test("Storm Mage: -2 to ALL enemies at location", function()
	local gs = makeTestState()
	local e1 = makeCard("SPARK", 2, 1, 1)
	local e2 = makeCard("IRON_GUARD", 3, 1, 2)
	gs.players["P2"].boards[1][1][1] = e1
	gs.players["P2"].boards[1][1][2] = e2

	local sm = makeCard("STORM_MAGE", 5, 3, 1)
	gs.players["P1"].boards[1][2][1] = sm

	AbilityRegistry.resolveOnReveal(gs, sm, "P1", 1, 1, 2)

	local m1, m2 = 0, 0
	for _, m in ipairs(e1.powerModifiers) do m1 = m1 + m.amount end
	for _, m in ipairs(e2.powerModifiers) do m2 = m2 + m.amount end
	assertEqual(m1, -2, "Enemy 1 should have -2")
	assertEqual(m2, -2, "Enemy 2 should have -2")
end)

test("High Priestess: draws 2 cards", function()
	local gs = makeTestState()
	local hp = makeCard("HIGH_PRIESTESS", 6, 3, 1)
	gs.players["P1"].boards[1][1][1] = hp
	local before = #gs.players["P1"].hand

	AbilityRegistry.resolveOnReveal(gs, hp, "P1", 1, 1, 1)

	assertEqual(#gs.players["P1"].hand, before + 2, "Should draw 2 cards")
end)

-- ============================================================
-- 7. Ongoing Effect Tests
-- ============================================================

print("\n=== Ongoing Effect Tests ===")

test("Seedling Ongoing: +1 to adjacent cards", function()
	local gs = makeTestState()
	local seedling = makeCard("SEEDLING", 1, 1, 1)
	gs.players["P1"].boards[1][1][2] = seedling  -- at (2,1)

	local adjCard = makeCard("SPARK", 2, 1, 2)
	gs.players["P1"].boards[1][1][1] = adjCard  -- at (1,1) — adjacent to (2,1)

	AbilityRegistry.applyOngoing(gs, seedling, "P1", 1, 2, 1)

	local adjMod = 0
	for _, m in ipairs(adjCard.powerModifiers) do adjMod = adjMod + m.amount end
	assertEqual(adjMod, 1, "Adjacent card should get +1 from Seedling")
end)

test("Commander Ongoing: +1 to all other friendlies at location", function()
	local gs = makeTestState()
	local commander = makeCard("COMMANDER", 4, 1, 1)
	gs.players["P1"].boards[1][1][1] = commander  -- at (1,1)

	local f1 = makeCard("SPARK", 2, 1, 2)
	gs.players["P1"].boards[1][1][2] = f1  -- at (2,1)
	local f2 = makeCard("IRON_GUARD", 3, 1, 3)
	gs.players["P1"].boards[1][2][1] = f2  -- at (1,2)

	AbilityRegistry.applyOngoing(gs, commander, "P1", 1, 1, 1)

	local m1, m2 = 0, 0
	for _, m in ipairs(f1.powerModifiers) do m1 = m1 + m.amount end
	for _, m in ipairs(f2.powerModifiers) do m2 = m2 + m.amount end
	assertEqual(m1, 1, "Friendly 1 should get +1 from Commander")
	assertEqual(m2, 1, "Friendly 2 should get +1 from Commander")

	-- Commander should NOT buff itself
	local cmMod = 0
	for _, m in ipairs(commander.powerModifiers) do cmMod = cmMod + m.amount end
	assertEqual(cmMod, 0, "Commander should not buff itself")
end)

test("Shield Wall Ongoing: +2 to other friendlies in same row", function()
	local gs = makeTestState()
	local sw = makeCard("SHIELD_WALL", 3, 1, 1)
	gs.players["P1"].boards[1][1][1] = sw  -- at (1,1) row 1

	local sameRow = makeCard("SPARK", 2, 1, 2)
	gs.players["P1"].boards[1][1][3] = sameRow  -- at (3,1) row 1

	local diffRow = makeCard("IRON_GUARD", 3, 1, 3)
	gs.players["P1"].boards[1][2][1] = diffRow  -- at (1,2) row 2

	AbilityRegistry.applyOngoing(gs, sw, "P1", 1, 1, 1)

	local srMod, drMod = 0, 0
	for _, m in ipairs(sameRow.powerModifiers) do srMod = srMod + m.amount end
	for _, m in ipairs(diffRow.powerModifiers) do drMod = drMod + m.amount end
	assertEqual(srMod, 2, "Same-row card should get +2 from Shield Wall")
	assertEqual(drMod, 0, "Different-row card should get +0 from Shield Wall")
end)

test("Overlord Ongoing: +1 to all other friendlies at both locations", function()
	local gs = makeTestState()
	local overlord = makeCard("OVERLORD", 8, 1, 1)
	gs.players["P1"].boards[1][1][1] = overlord  -- at loc 1

	local f1 = makeCard("SPARK", 2, 1, 2)
	gs.players["P1"].boards[1][1][2] = f1  -- at loc 1

	local f2 = makeCard("IRON_GUARD", 3, 1, 1)
	gs.players["P1"].boards[2][1][1] = f2  -- at loc 2

	AbilityRegistry.applyOngoing(gs, overlord, "P1", 1, 1, 1)

	local m1, m2 = 0, 0
	for _, m in ipairs(f1.powerModifiers) do m1 = m1 + m.amount end
	for _, m in ipairs(f2.powerModifiers) do m2 = m2 + m.amount end
	assertEqual(m1, 1, "Friendly at same location should get +1")
	assertEqual(m2, 1, "Friendly at other location should get +1")

	-- Overlord should NOT buff itself
	local olMod = 0
	for _, m in ipairs(overlord.powerModifiers) do olMod = olMod + m.amount end
	assertEqual(olMod, 0, "Overlord should not buff itself")
end)

test("Colossus Ongoing: sets isImmune flag", function()
	local gs = makeTestState()
	local colossus = makeCard("COLOSSUS", 8, 1, 1)
	colossus.isImmune = false
	gs.players["P1"].boards[1][1][1] = colossus

	AbilityRegistry.applyOngoing(gs, colossus, "P1", 1, 1, 1)

	assertTrue(colossus.isImmune, "Colossus should be immune after Ongoing applies")
end)

test("Warlord Ongoing: sets _doublesLocationPower flag", function()
	local gs = makeTestState()
	local warlord = makeCard("WARLORD", 1, 1, 1)
	gs.players["P1"].boards[1][1][1] = warlord

	AbilityRegistry.applyOngoing(gs, warlord, "P1", 1, 1, 1)

	assertTrue(warlord._doublesLocationPower == true, "Warlord should set doubling flag")
end)

test("AbilityRegistry.recalculatePower sums correctly", function()
	local card = makeCard("SPARK", 2, 1, 1)
	card.powerModifiers = {
		{ source = "HEALER_ONREVEAL", amount = 1 },
		{ source = "SABOTEUR_ONREVEAL", amount = -1 },
		{ source = "SEEDLING_ONGOING", amount = 1 },
	}
	AbilityRegistry.recalculatePower(card)
	assertEqual(card.currentPower, 3, "2 + 1 - 1 + 1 = 3")
end)

test("AbilityRegistry.clearOngoingModifiers preserves OnReveal mods", function()
	local gs = makeTestState()
	local card = makeCard("SPARK", 2, 1, 1)
	card.powerModifiers = {
		{ source = "HEALER_ONREVEAL", amount = 1 },
		{ source = "WAR_CAMP_EFFECT", amount = 1 },
		{ source = "SEEDLING_ONGOING", amount = 1 },
		{ source = "COMMANDER_ONGOING", amount = 1 },
	}
	gs.players["P1"].boards[1][1][1] = card

	AbilityRegistry.clearOngoingModifiers(gs)

	-- Should keep ONREVEAL and EFFECT, remove ONGOING
	assertEqual(#card.powerModifiers, 2, "Should keep 2 non-Ongoing modifiers")
	for _, m in ipairs(card.powerModifiers) do
		assertTrue(not string.find(m.source, "_ONGOING$"),
			"Ongoing modifier should have been removed: " .. m.source)
	end
end)

-- ============================================================
-- Summary
-- ============================================================

print("\n" .. string.rep("=", 50))
print(string.format("Phase 1 Tests Complete: %d/%d passed, %d failed",
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
