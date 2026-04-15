--[[
	GameServer — the entry point script that listens for match requests
	and creates MatchManager instances.

	Handles:
		- RequestBotMatch: human player vs bot
		- RequestMatch: PvP matchmaking queue (basic FIFO)

	Runs in ServerScriptService as a Script.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Events = ReplicatedStorage:WaitForChild("Events")
local MatchManager = require(script.Parent:WaitForChild("MatchManager"))

-- ============================================================
-- State
-- ============================================================

local activeMatches = {}      -- { [matchID] = MatchManager instance }
local playerInMatch = {}      -- { [playerID] = matchID }
local pvpQueue = {}           -- { Player, Player, ... }
local nextMatchID = 1

-- ============================================================
-- Match Creation
-- ============================================================

local function createBotMatch(player)
	local playerID = tostring(player.UserId)

	-- Check if already in a match
	if playerInMatch[playerID] then
		warn("[GameServer] " .. player.Name .. " is already in match " .. playerInMatch[playerID])
		return
	end

	local matchID = "match_" .. nextMatchID
	nextMatchID = nextMatchID + 1

	print(string.format("[GameServer] Creating bot match %s for %s", matchID, player.Name))

	local match = MatchManager.new(player, "BOT", true)
	activeMatches[matchID] = match
	playerInMatch[playerID] = matchID

	-- Run the match in a new thread
	task.spawn(function()
		local ok, err = pcall(function()
			match:start()
		end)

		if not ok then
			warn("[GameServer] Match " .. matchID .. " error: " .. tostring(err))
		end

		-- Cleanup
		print(string.format("[GameServer] Match %s ended, cleaning up", matchID))
		activeMatches[matchID] = nil
		playerInMatch[playerID] = nil
	end)
end

local function createPvPMatch(player1, player2)
	local p1ID = tostring(player1.UserId)
	local p2ID = tostring(player2.UserId)

	if playerInMatch[p1ID] or playerInMatch[p2ID] then
		warn("[GameServer] One or both players already in a match")
		return
	end

	local matchID = "match_" .. nextMatchID
	nextMatchID = nextMatchID + 1

	print(string.format("[GameServer] Creating PvP match %s: %s vs %s",
		matchID, player1.Name, player2.Name))

	local match = MatchManager.new(player1, player2, false)
	activeMatches[matchID] = match
	playerInMatch[p1ID] = matchID
	playerInMatch[p2ID] = matchID

	task.spawn(function()
		local ok, err = pcall(function()
			match:start()
		end)

		if not ok then
			warn("[GameServer] Match " .. matchID .. " error: " .. tostring(err))
		end

		print(string.format("[GameServer] Match %s ended, cleaning up", matchID))
		activeMatches[matchID] = nil
		playerInMatch[p1ID] = nil
		playerInMatch[p2ID] = nil
	end)
end

-- ============================================================
-- Event Listeners
-- ============================================================

-- Bot match requests
local requestBotEvent = Events:WaitForChild("RequestBotMatch")
requestBotEvent.OnServerEvent:Connect(function(player)
	print(string.format("[GameServer] %s requested a bot match", player.Name))
	createBotMatch(player)
end)

-- PvP match requests (basic queue)
local requestMatchEvent = Events:WaitForChild("RequestMatch")
requestMatchEvent.OnServerEvent:Connect(function(player)
	local playerID = tostring(player.UserId)

	-- Don't allow if already in match or already in queue
	if playerInMatch[playerID] then
		warn("[GameServer] " .. player.Name .. " already in a match")
		return
	end

	for _, queuedPlayer in ipairs(pvpQueue) do
		if queuedPlayer == player then
			print("[GameServer] " .. player.Name .. " already in queue")
			return
		end
	end

	table.insert(pvpQueue, player)
	print(string.format("[GameServer] %s joined PvP queue (size: %d)", player.Name, #pvpQueue))

	-- Check if we can make a match
	if #pvpQueue >= 2 then
		local p1 = table.remove(pvpQueue, 1)
		local p2 = table.remove(pvpQueue, 1)

		-- Verify both players are still in the game
		if p1.Parent and p2.Parent then
			createPvPMatch(p1, p2)
		else
			-- One left, put the other back
			if p1.Parent then table.insert(pvpQueue, 1, p1) end
			if p2.Parent then table.insert(pvpQueue, 1, p2) end
		end
	end
end)

-- Remove players from queue when they leave the game
Players.PlayerRemoving:Connect(function(player)
	local playerID = tostring(player.UserId)

	-- Remove from queue
	for i, queuedPlayer in ipairs(pvpQueue) do
		if queuedPlayer == player then
			table.remove(pvpQueue, i)
			print(string.format("[GameServer] %s left queue", player.Name))
			break
		end
	end

	-- Mark match as needing cleanup (the match will handle player disconnection)
	if playerInMatch[playerID] then
		print(string.format("[GameServer] %s left during match %s", player.Name, playerInMatch[playerID]))
		-- The match loop's pcall will handle the error when trying to FireClient
	end
end)

print("[GameServer] Ready — listening for match requests")
