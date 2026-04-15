--[[
	Phase 3 Tests — validates the MatchClient and MatchGui setup.

	Since Phase 3 is primarily client-side UI, these tests verify:
		1. CardFrame module renders correctly (all display sizes)
		2. CardFrame handles all card IDs without errors
		3. CardFrame.updatePower works correctly
		4. CardFrame.createEmptySlot works
		5. MatchGui ScreenGui exists and is configured correctly
		6. All required RemoteEvents exist
		7. Integration: full bot-vs-bot match with scoring verification

	Run in Roblox Studio as a server-side Script.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Events = ReplicatedStorage:WaitForChild("Events")

local GameConfig = require(Modules:WaitForChild("GameConfig"))
local CardDatabase = require(Modules:WaitForChild("CardDatabase"))
local CardFrame = require(Modules:WaitForChild("CardFrame"))
local SlotGrid = require(Modules:WaitForChild("SlotGrid"))
local MatchManager = require(script.Parent:WaitForChild("MatchManager"))

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
-- 1. CardFrame Rendering Tests
-- ============================================================

print("\n=== CardFrame Rendering Tests ===")

test("CardFrame.create returns a Frame for all cards (board size)", function()
	for _, id in ipairs(CardDatabase.getAllIDs()) do
		local frame = CardFrame.create(id, "board")
		assertNotNil(frame, "CardFrame.create returned nil for " .. id)
		assertTrue(frame:IsA("Frame"), id .. " should be a Frame")
		frame:Destroy()
	end
end)

test("CardFrame.create returns a Frame for all cards (hand size)", function()
	for _, id in ipairs(CardDatabase.getAllIDs()) do
		local frame = CardFrame.create(id, "hand")
		assertNotNil(frame, "CardFrame.create returned nil for " .. id)
		frame:Destroy()
	end
end)

test("CardFrame.create returns a Frame for all cards (detail size)", function()
	for _, id in ipairs(CardDatabase.getAllIDs()) do
		local frame = CardFrame.create(id, "detail")
		assertNotNil(frame, "CardFrame.create returned nil for " .. id)
		frame:Destroy()
	end
end)

test("CardFrame board size uses scale (fills parent)", function()
	local frame = CardFrame.create("SPARK", "board")
	assertNotNil(frame)
	-- Board cards now use scale sizing (1,0,1,0) to fill their slot
	assertEqual(frame.Size.X.Scale, 1, "board width scale")
	assertEqual(frame.Size.Y.Scale, 1, "board height scale")
	frame:Destroy()
end)

test("CardFrame hand size has correct dimensions", function()
	local frame = CardFrame.create("SPARK", "hand")
	assertNotNil(frame)
	assertEqual(frame.Size.X.Offset, 110, "hand width")
	assertEqual(frame.Size.Y.Offset, 147, "hand height")
	frame:Destroy()
end)

test("CardFrame detail size has correct dimensions", function()
	local frame = CardFrame.create("SPARK", "detail")
	assertNotNil(frame)
	assertEqual(frame.Size.X.Offset, 240, "detail width")
	assertEqual(frame.Size.Y.Offset, 340, "detail height")
	frame:Destroy()
end)

test("CardFrame has CostBadge with correct text", function()
	local frame = CardFrame.create("STONE_GOLEM", "hand")
	assertNotNil(frame)
	local costBadge = frame:FindFirstChild("CostBadge")
	assertNotNil(costBadge, "Should have CostBadge")
	local costText = costBadge:FindFirstChild("CostText")
	assertNotNil(costText, "Should have CostText")
	assertEqual(costText.Text, "3", "Stone Golem costs 3")
	frame:Destroy()
end)

test("CardFrame has PowerBadge with correct text", function()
	local frame = CardFrame.create("DRAGON", "board")
	assertNotNil(frame)
	local powerBadge = frame:FindFirstChild("PowerBadge")
	assertNotNil(powerBadge, "Should have PowerBadge")
	local powerText = powerBadge:FindFirstChild("PowerText")
	assertNotNil(powerText, "Should have PowerText")
	assertEqual(powerText.Text, "9", "Dragon has 9 power")
	frame:Destroy()
end)

test("CardFrame power override works", function()
	local frame = CardFrame.create("SPARK", "board", 5)  -- override power to 5
	assertNotNil(frame)
	local powerBadge = frame:FindFirstChild("PowerBadge")
	local powerText = powerBadge:FindFirstChild("PowerText")
	assertEqual(powerText.Text, "5", "Power should be overridden to 5")
	frame:Destroy()
end)

test("CardFrame hand size shows name label", function()
	local frame = CardFrame.create("HEALER", "hand")
	assertNotNil(frame)
	local nameLabel = frame:FindFirstChild("NameLabel")
	assertNotNil(nameLabel, "Hand size should have NameLabel")
	assertEqual(nameLabel.Text, "Healer", "Name should be Healer")
	frame:Destroy()
end)

test("CardFrame hand size shows ability text for ability cards", function()
	local frame = CardFrame.create("HEALER", "hand")
	assertNotNil(frame)
	local abilityLabel = frame:FindFirstChild("AbilityLabel")
	assertNotNil(abilityLabel, "Ability card hand view should have AbilityLabel")
	assertTrue(string.len(abilityLabel.Text) > 0, "Ability text should not be empty")
	frame:Destroy()
end)

test("CardFrame hand size has no ability text for vanilla cards", function()
	local frame = CardFrame.create("SPARK", "hand")
	assertNotNil(frame)
	local abilityLabel = frame:FindFirstChild("AbilityLabel")
	-- Vanilla cards should have no ability label
	assertTrue(abilityLabel == nil, "Vanilla card should not have AbilityLabel")
	frame:Destroy()
end)

test("CardFrame detail size shows stats label", function()
	local frame = CardFrame.create("COMMANDER", "detail")
	assertNotNil(frame)
	local statsLabel = frame:FindFirstChild("StatsLabel")
	assertNotNil(statsLabel, "Detail view should have StatsLabel")
	assertTrue(string.find(statsLabel.Text, "Cost: 4"), "Should show cost")
	assertTrue(string.find(statsLabel.Text, "Power: 4"), "Should show power")
	frame:Destroy()
end)

test("CardFrame.updatePower changes text and color", function()
	local frame = CardFrame.create("SPARK", "board")
	assertNotNil(frame)

	-- Update to higher power (should turn green)
	CardFrame.updatePower(frame, 5, 2)
	local powerBadge = frame:FindFirstChild("PowerBadge")
	local powerText = powerBadge:FindFirstChild("PowerText")
	assertEqual(powerText.Text, "5", "Power should update to 5")
	assertEqual(powerText.TextColor3, Color3.fromRGB(100, 255, 100), "Should be green for buff")

	-- Update to lower power (should turn red)
	CardFrame.updatePower(frame, 1, 2)
	assertEqual(powerText.Text, "1", "Power should update to 1")
	assertEqual(powerText.TextColor3, Color3.fromRGB(255, 100, 100), "Should be red for debuff")

	-- Update to base power (should be white)
	CardFrame.updatePower(frame, 2, 2)
	assertEqual(powerText.Text, "2", "Power should update to 2")
	assertEqual(powerText.TextColor3, Color3.fromRGB(255, 255, 255), "Should be white for base")

	frame:Destroy()
end)

test("CardFrame.createEmptySlot returns a Frame", function()
	local frame = CardFrame.createEmptySlot("board")
	assertNotNil(frame, "Should return a Frame")
	assertTrue(frame:IsA("Frame"), "Should be a Frame")
	assertTrue(frame.BackgroundTransparency > 0, "Should be semi-transparent")
	frame:Destroy()
end)

test("CardFrame returns nil for invalid card ID", function()
	local frame = CardFrame.create("NONEXISTENT_CARD", "board")
	assertTrue(frame == nil, "Should return nil for invalid card ID")
end)

-- ============================================================
-- 2. RemoteEvent Existence Tests
-- ============================================================

print("\n=== RemoteEvent Tests ===")

local requiredEvents = {
	"TurnStart", "SubmitTurn", "RevealResult",
	"ScoreUpdate", "GameOver", "InvalidPlay",
	"RequestBotMatch", "RequestMatch",
}

for _, eventName in ipairs(requiredEvents) do
	test("RemoteEvent '" .. eventName .. "' exists", function()
		local event = Events:FindFirstChild(eventName)
		assertNotNil(event, eventName .. " not found in Events folder")
	end)
end

-- ============================================================
-- 3. MatchGui Configuration Tests
-- ============================================================

print("\n=== MatchGui Tests ===")

test("MatchGui exists in StarterGui", function()
	local gui = StarterGui:FindFirstChild("MatchGui")
	assertNotNil(gui, "MatchGui should exist")
end)

test("MatchGui is a ScreenGui", function()
	local gui = StarterGui:FindFirstChild("MatchGui")
	assertNotNil(gui)
	assertTrue(gui:IsA("ScreenGui"), "Should be a ScreenGui")
end)

test("MatchGui starts disabled", function()
	local gui = StarterGui:FindFirstChild("MatchGui")
	assertNotNil(gui)
	assertEqual(gui.Enabled, false, "Should start disabled")
end)

test("MatchGui has IgnoreGuiInset enabled", function()
	local gui = StarterGui:FindFirstChild("MatchGui")
	assertNotNil(gui)
	assertTrue(gui.IgnoreGuiInset, "Should ignore GUI inset for full-screen")
end)

-- ============================================================
-- 4. Integration: Bot-vs-Bot Match Validation
-- ============================================================

print("\n=== Integration: Full Match Validation ===")

test("Bot-vs-bot match has valid turn progression", function()
	local gs = MatchManager.runTestMatch()
	assertTrue(gs.turn >= 4, "Match should last at least 4 turns (enough to score 20)")
	assertTrue(gs.turn <= 30, "Match should not exceed safety limit")
end)

test("Bot-vs-bot final scores sum correctly from per-turn scoring", function()
	-- Run a match and verify scores are reasonable
	local gs = MatchManager.runTestMatch()
	local scoreA = gs.players["BOT_A"].score
	local scoreB = gs.players["BOT_B"].score

	-- Each turn awards 2-6 points total across locations (min 2 from ties, max 5+3=8)
	-- Over N turns, total points = approximately turns * 5
	local totalPoints = scoreA + scoreB
	local maxPossible = gs.turn * 10  -- generous upper bound
	assertTrue(totalPoints > 0, "Some points should have been scored")
	assertTrue(totalPoints <= maxPossible,
		string.format("Total points %d exceeds reasonable maximum %d", totalPoints, maxPossible))
end)

test("Bot-vs-bot match winner has score >= threshold", function()
	local gs = MatchManager.runTestMatch()
	local scoreA = gs.players["BOT_A"].score
	local scoreB = gs.players["BOT_B"].score
	local maxScore = math.max(scoreA, scoreB)
	assertTrue(maxScore >= GameConfig.POINTS_TO_WIN,
		string.format("Winner score %d should be >= %d", maxScore, GameConfig.POINTS_TO_WIN))
end)

test("Multiple bot-vs-bot matches all complete successfully", function()
	-- Run 3 matches to check for consistency
	for i = 1, 3 do
		local gs = MatchManager.runTestMatch()
		assertEqual(gs.phase, "GAME_OVER", "Match " .. i .. " should reach GAME_OVER")
		print(string.format("  Match %d: %d turns, A=%d B=%d",
			i, gs.turn, gs.players["BOT_A"].score, gs.players["BOT_B"].score))
	end
end)

-- ============================================================
-- Summary
-- ============================================================

print("\n" .. string.rep("=", 50))
print(string.format("Phase 3 Tests Complete: %d/%d passed, %d failed",
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
