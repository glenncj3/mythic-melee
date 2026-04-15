--[[
	MatchClient — handles the full match UI on the client side.

	Responsibilities:
		- Builds match GUI (two locations, grids, hand, scores, energy, timer)
		- Planning phase: tap-to-select card, tap-to-place, pending management
		- Sends SubmitTurn to server on confirm or timer expiry
		- Receives RevealResult, ScoreUpdate, GameOver from server
		- Animates reveals, score changes, game-over screen
		- Pre-match: shows "Play vs Bot" button
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Events = ReplicatedStorage:WaitForChild("Events")

local GameConfig = require(Modules:WaitForChild("GameConfig"))
local CardDatabase = require(Modules:WaitForChild("CardDatabase"))
local CardFrame = require(Modules:WaitForChild("CardFrame"))
local SlotGrid = require(Modules:WaitForChild("SlotGrid"))

-- Remote Events
local TurnStartEvent = Events:WaitForChild("TurnStart")
local SubmitTurnEvent = Events:WaitForChild("SubmitTurn")
local RevealResultEvent = Events:WaitForChild("RevealResult")
local ScoreUpdateEvent = Events:WaitForChild("ScoreUpdate")
local GameOverEvent = Events:WaitForChild("GameOver")
local InvalidPlayEvent = Events:WaitForChild("InvalidPlay")
local RequestBotMatchEvent = Events:WaitForChild("RequestBotMatch")

-- ============================================================
-- State
-- ============================================================

local matchActive = false
local currentTurn = 0
local myEnergy = 0
local energySpent = 0
local myHand = {}         -- { cardID, ... }
local myScore = 0
local oppScore = 0
local locations = {}
local selectedCardID = nil
local selectedCardIndex = nil  -- index in myHand
local pendingPlays = {}   -- { { cardID, locIdx, col, row }, ... }
local timerRunning = false
local timerSeconds = 0

-- UI references
local matchGui = nil
local lobbyGui = nil
local boardFrame = nil
local handFrame = nil
local scoreBar = nil
local energyLabel = nil
local timerLabel = nil
local confirmButton = nil
local waitingLabel = nil
local detailOverlay = nil
local gameOverOverlay = nil
local locationFrames = {}    -- [locIdx] = { frame, myGrid, oppGrid, nameLabel, powerLabel }
local handCardFrames = {}    -- { frame, ... }

-- ============================================================
-- Color Constants
-- ============================================================

local COLORS = {
	bg = Color3.fromRGB(20, 20, 25),
	panel = Color3.fromRGB(30, 30, 38),
	slotEmpty = Color3.fromRGB(40, 40, 50),
	slotHighlight = Color3.fromRGB(60, 160, 80),
	slotOverwrite = Color3.fromRGB(200, 130, 40),
	pending = Color3.fromRGB(100, 200, 120),
	scoreText = Color3.fromRGB(255, 255, 255),
	energyFull = Color3.fromRGB(80, 140, 255),
	energySpentColor = Color3.fromRGB(60, 60, 80),
	timerNormal = Color3.fromRGB(200, 200, 200),
	timerWarning = Color3.fromRGB(255, 80, 80),
	confirm = Color3.fromRGB(60, 160, 80),
	confirmDisabled = Color3.fromRGB(60, 60, 70),
	textWhite = Color3.fromRGB(255, 255, 255),
	textGray = Color3.fromRGB(160, 160, 160),
	textGreen = Color3.fromRGB(100, 255, 100),
	textRed = Color3.fromRGB(255, 100, 100),
	victory = Color3.fromRGB(255, 215, 0),
	defeat = Color3.fromRGB(180, 50, 50),
}

-- ============================================================
-- UI Building
-- ============================================================

local function createLobbyUI()
	lobbyGui = Instance.new("ScreenGui")
	lobbyGui.Name = "LobbyGui"
	lobbyGui.ResetOnSpawn = false
	lobbyGui.IgnoreGuiInset = true
	lobbyGui.Parent = playerGui

	local bgFrame = Instance.new("Frame")
	bgFrame.Name = "LobbyBG"
	bgFrame.Size = UDim2.new(1, 0, 1, 0)
	bgFrame.BackgroundColor3 = COLORS.bg
	bgFrame.BorderSizePixel = 0
	bgFrame.Parent = lobbyGui

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(0.8, 0, 0.1, 0)
	title.Position = UDim2.new(0.1, 0, 0.2, 0)
	title.BackgroundTransparency = 1
	title.Text = "MYTHIC MASH"
	title.TextColor3 = COLORS.victory
	title.TextSize = 48
	title.Font = Enum.Font.GothamBold
	title.Parent = bgFrame

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(0.8, 0, 0.05, 0)
	subtitle.Position = UDim2.new(0.1, 0, 0.32, 0)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "A Positional Card Game"
	subtitle.TextColor3 = COLORS.textGray
	subtitle.TextSize = 20
	subtitle.Font = Enum.Font.Gotham
	subtitle.Parent = bgFrame

	local botButton = Instance.new("TextButton")
	botButton.Name = "PlayBotButton"
	botButton.Size = UDim2.new(0.3, 0, 0.08, 0)
	botButton.Position = UDim2.new(0.35, 0, 0.5, 0)
	botButton.BackgroundColor3 = COLORS.confirm
	botButton.BorderSizePixel = 0
	botButton.Text = "Play vs Bot"
	botButton.TextColor3 = COLORS.textWhite
	botButton.TextSize = 24
	botButton.Font = Enum.Font.GothamBold
	botButton.Parent = bgFrame

	local botCorner = Instance.new("UICorner")
	botCorner.CornerRadius = UDim.new(0, 8)
	botCorner.Parent = botButton

	botButton.MouseButton1Click:Connect(function()
		if matchActive then return end
		botButton.Text = "Searching..."
		botButton.BackgroundColor3 = COLORS.confirmDisabled
		RequestBotMatchEvent:FireServer()
	end)

	return lobbyGui
end

local function createMatchUI()
	-- Use the MatchGui from StarterGui
	matchGui = playerGui:WaitForChild("MatchGui")

	-- Clear any existing children
	for _, child in ipairs(matchGui:GetChildren()) do
		child:Destroy()
	end

	-- Main background
	local bg = Instance.new("Frame")
	bg.Name = "MatchBG"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = COLORS.bg
	bg.BorderSizePixel = 0
	bg.Parent = matchGui

	-- === SCORE BAR (top) ===
	scoreBar = Instance.new("Frame")
	scoreBar.Name = "ScoreBar"
	scoreBar.Size = UDim2.new(1, 0, 0.06, 0)
	scoreBar.Position = UDim2.new(0, 0, 0, 0)
	scoreBar.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	scoreBar.BorderSizePixel = 0
	scoreBar.Parent = bg

	local oppScoreLabel = Instance.new("TextLabel")
	oppScoreLabel.Name = "OppScore"
	oppScoreLabel.Size = UDim2.new(0.3, 0, 1, 0)
	oppScoreLabel.Position = UDim2.new(0.02, 0, 0, 0)
	oppScoreLabel.BackgroundTransparency = 1
	oppScoreLabel.Text = "Opponent: 0"
	oppScoreLabel.TextColor3 = COLORS.textRed
	oppScoreLabel.TextSize = 20
	oppScoreLabel.Font = Enum.Font.GothamBold
	oppScoreLabel.TextXAlignment = Enum.TextXAlignment.Left
	oppScoreLabel.Parent = scoreBar

	local turnLabel = Instance.new("TextLabel")
	turnLabel.Name = "TurnLabel"
	turnLabel.Size = UDim2.new(0.2, 0, 1, 0)
	turnLabel.Position = UDim2.new(0.4, 0, 0, 0)
	turnLabel.BackgroundTransparency = 1
	turnLabel.Text = "Turn 1"
	turnLabel.TextColor3 = COLORS.textWhite
	turnLabel.TextSize = 20
	turnLabel.Font = Enum.Font.GothamBold
	turnLabel.Parent = scoreBar

	local myScoreLabel = Instance.new("TextLabel")
	myScoreLabel.Name = "MyScore"
	myScoreLabel.Size = UDim2.new(0.3, 0, 1, 0)
	myScoreLabel.Position = UDim2.new(0.68, 0, 0, 0)
	myScoreLabel.BackgroundTransparency = 1
	myScoreLabel.Text = "You: 0"
	myScoreLabel.TextColor3 = COLORS.textGreen
	myScoreLabel.TextSize = 20
	myScoreLabel.Font = Enum.Font.GothamBold
	myScoreLabel.TextXAlignment = Enum.TextXAlignment.Right
	myScoreLabel.Parent = scoreBar

	-- === BOARD AREA (locations) ===
	boardFrame = Instance.new("Frame")
	boardFrame.Name = "BoardArea"
	boardFrame.Size = UDim2.new(1, 0, 0.62, 0)
	boardFrame.Position = UDim2.new(0, 0, 0.06, 0)
	boardFrame.BackgroundTransparency = 1
	boardFrame.Parent = bg

	local boardLayout = Instance.new("UIListLayout")
	boardLayout.FillDirection = Enum.FillDirection.Horizontal
	boardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	boardLayout.Padding = UDim.new(0.02, 0)
	boardLayout.Parent = boardFrame

	-- Create location panels
	locationFrames = {}
	for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
		locationFrames[locIdx] = createLocationPanel(locIdx, boardFrame)
	end

	-- === BOTTOM AREA ===
	local bottomFrame = Instance.new("Frame")
	bottomFrame.Name = "BottomArea"
	bottomFrame.Size = UDim2.new(1, 0, 0.32, 0)
	bottomFrame.Position = UDim2.new(0, 0, 0.68, 0)
	bottomFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
	bottomFrame.BorderSizePixel = 0
	bottomFrame.Parent = bg

	-- Energy + Confirm row
	local controlRow = Instance.new("Frame")
	controlRow.Name = "ControlRow"
	controlRow.Size = UDim2.new(1, 0, 0.3, 0)
	controlRow.Position = UDim2.new(0, 0, 0, 0)
	controlRow.BackgroundTransparency = 1
	controlRow.Parent = bottomFrame

	energyLabel = Instance.new("TextLabel")
	energyLabel.Name = "EnergyLabel"
	energyLabel.Size = UDim2.new(0.3, 0, 1, 0)
	energyLabel.Position = UDim2.new(0.05, 0, 0, 0)
	energyLabel.BackgroundTransparency = 1
	energyLabel.Text = "Energy: 0"
	energyLabel.TextColor3 = COLORS.energyFull
	energyLabel.TextSize = 18
	energyLabel.Font = Enum.Font.GothamBold
	energyLabel.TextXAlignment = Enum.TextXAlignment.Left
	energyLabel.Parent = controlRow

	timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.Size = UDim2.new(0.2, 0, 1, 0)
	timerLabel.Position = UDim2.new(0.38, 0, 0, 0)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text = ""
	timerLabel.TextColor3 = COLORS.timerNormal
	timerLabel.TextSize = 18
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.Parent = controlRow

	confirmButton = Instance.new("TextButton")
	confirmButton.Name = "ConfirmButton"
	confirmButton.Size = UDim2.new(0.25, 0, 0.8, 0)
	confirmButton.Position = UDim2.new(0.7, 0, 0.1, 0)
	confirmButton.BackgroundColor3 = COLORS.confirm
	confirmButton.BorderSizePixel = 0
	confirmButton.Text = "Confirm"
	confirmButton.TextColor3 = COLORS.textWhite
	confirmButton.TextSize = 18
	confirmButton.Font = Enum.Font.GothamBold
	confirmButton.Parent = controlRow

	local confirmCorner = Instance.new("UICorner")
	confirmCorner.CornerRadius = UDim.new(0, 6)
	confirmCorner.Parent = confirmButton

	confirmButton.MouseButton1Click:Connect(onConfirmClicked)

	waitingLabel = Instance.new("TextLabel")
	waitingLabel.Name = "WaitingLabel"
	waitingLabel.Size = UDim2.new(0.25, 0, 0.8, 0)
	waitingLabel.Position = UDim2.new(0.7, 0, 0.1, 0)
	waitingLabel.BackgroundColor3 = COLORS.confirmDisabled
	waitingLabel.BorderSizePixel = 0
	waitingLabel.Text = "Waiting..."
	waitingLabel.TextColor3 = COLORS.textGray
	waitingLabel.TextSize = 18
	waitingLabel.Font = Enum.Font.GothamBold
	waitingLabel.Visible = false
	waitingLabel.Parent = controlRow

	local waitCorner = Instance.new("UICorner")
	waitCorner.CornerRadius = UDim.new(0, 6)
	waitCorner.Parent = waitingLabel

	-- Hand area
	handFrame = Instance.new("ScrollingFrame")
	handFrame.Name = "HandArea"
	handFrame.Size = UDim2.new(0.9, 0, 0.65, 0)
	handFrame.Position = UDim2.new(0.05, 0, 0.32, 0)
	handFrame.BackgroundTransparency = 1
	handFrame.BorderSizePixel = 0
	handFrame.ScrollBarThickness = 4
	handFrame.ScrollingDirection = Enum.ScrollingDirection.X
	handFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	handFrame.AutomaticCanvasSize = Enum.AutomaticSize.X
	handFrame.Parent = bottomFrame

	local handLayout = Instance.new("UIListLayout")
	handLayout.FillDirection = Enum.FillDirection.Horizontal
	handLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	handLayout.Padding = UDim.new(0, 8)
	handLayout.SortOrder = Enum.SortOrder.LayoutOrder
	handLayout.Parent = handFrame

	local handPadding = Instance.new("UIPadding")
	handPadding.PaddingLeft = UDim.new(0, 8)
	handPadding.PaddingRight = UDim.new(0, 8)
	handPadding.Parent = handFrame

	-- Detail overlay (hidden by default)
	createDetailOverlay(bg)

	-- Game over overlay (hidden by default)
	createGameOverOverlay(bg)
end

function createLocationPanel(locIdx, parent)
	local panel = Instance.new("Frame")
	panel.Name = "Location" .. locIdx
	panel.Size = UDim2.new(0.47, 0, 1, 0)
	panel.BackgroundColor3 = COLORS.panel
	panel.BorderSizePixel = 0
	panel.Parent = parent

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 8)
	panelCorner.Parent = panel

	-- Location name + points
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "LocationName"
	nameLabel.Size = UDim2.new(1, 0, 0.08, 0)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = "Location " .. locIdx
	nameLabel.TextColor3 = COLORS.textWhite
	nameLabel.TextSize = 14
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = panel

	-- Location effect text
	local effectLabel = Instance.new("TextLabel")
	effectLabel.Name = "EffectText"
	effectLabel.Size = UDim2.new(0.9, 0, 0.05, 0)
	effectLabel.Position = UDim2.new(0.05, 0, 0.08, 0)
	effectLabel.BackgroundTransparency = 1
	effectLabel.Text = ""
	effectLabel.TextColor3 = COLORS.textGray
	effectLabel.TextSize = 10
	effectLabel.Font = Enum.Font.Gotham
	effectLabel.TextWrapped = true
	effectLabel.Parent = panel

	-- Opponent grid (top half)
	local oppGrid = Instance.new("Frame")
	oppGrid.Name = "OppGrid"
	oppGrid.Size = UDim2.new(0.9, 0, 0.35, 0)
	oppGrid.Position = UDim2.new(0.05, 0, 0.14, 0)
	oppGrid.BackgroundTransparency = 1
	oppGrid.Parent = panel

	createSlotGrid(oppGrid, locIdx, false)

	-- Divider
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(0.9, 0, 0, 2)
	divider.Position = UDim2.new(0.05, 0, 0.50, 0)
	divider.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	divider.BorderSizePixel = 0
	divider.Parent = panel

	-- My grid (bottom half)
	local myGrid = Instance.new("Frame")
	myGrid.Name = "MyGrid"
	myGrid.Size = UDim2.new(0.9, 0, 0.35, 0)
	myGrid.Position = UDim2.new(0.05, 0, 0.52, 0)
	myGrid.BackgroundTransparency = 1
	myGrid.Parent = panel

	createSlotGrid(myGrid, locIdx, true)

	-- Power totals
	local powerLabel = Instance.new("TextLabel")
	powerLabel.Name = "PowerLabel"
	powerLabel.Size = UDim2.new(0.9, 0, 0.08, 0)
	powerLabel.Position = UDim2.new(0.05, 0, 0.89, 0)
	powerLabel.BackgroundTransparency = 1
	powerLabel.Text = "You: 0 / Opp: 0"
	powerLabel.TextColor3 = COLORS.textGray
	powerLabel.TextSize = 14
	powerLabel.Font = Enum.Font.GothamBold
	powerLabel.Parent = panel

	return {
		frame = panel,
		myGrid = myGrid,
		oppGrid = oppGrid,
		nameLabel = nameLabel,
		effectLabel = effectLabel,
		powerLabel = powerLabel,
	}
end

function createSlotGrid(parent, locIdx, isMine)
	for row = 1, GameConfig.GRID_ROWS do
		for col = 1, GameConfig.GRID_COLUMNS do
			local slotFrame = Instance.new("TextButton")
			slotFrame.Name = string.format("Slot_%d_%d", col, row)
			slotFrame.Size = UDim2.new(1/GameConfig.GRID_COLUMNS - 0.02, 0, 1/GameConfig.GRID_ROWS - 0.04, 0)
			slotFrame.Position = UDim2.new((col-1)/GameConfig.GRID_COLUMNS + 0.01, 0, (row-1)/GameConfig.GRID_ROWS + 0.02, 0)
			slotFrame.BackgroundColor3 = COLORS.slotEmpty
			slotFrame.BackgroundTransparency = 0.5
			slotFrame.BorderSizePixel = 0
			slotFrame.Text = ""
			slotFrame.AutoButtonColor = false
			slotFrame.Parent = parent

			local slotCorner = Instance.new("UICorner")
			slotCorner.CornerRadius = UDim.new(0, 4)
			slotCorner.Parent = slotFrame

			local slotStroke = Instance.new("UIStroke")
			slotStroke.Name = "SlotStroke"
			slotStroke.Color = Color3.fromRGB(60, 60, 70)
			slotStroke.Thickness = 1
			slotStroke.Parent = slotFrame

			if isMine then
				slotFrame.MouseButton1Click:Connect(function()
					onSlotClicked(locIdx, col, row)
				end)
			else
				-- Opponent slots: show detail on click
				slotFrame.MouseButton1Click:Connect(function()
					onOppSlotClicked(locIdx, col, row)
				end)
			end
		end
	end
end

function createDetailOverlay(parent)
	detailOverlay = Instance.new("Frame")
	detailOverlay.Name = "DetailOverlay"
	detailOverlay.Size = UDim2.new(1, 0, 1, 0)
	detailOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	detailOverlay.BackgroundTransparency = 0.5
	detailOverlay.BorderSizePixel = 0
	detailOverlay.Visible = false
	detailOverlay.ZIndex = 10
	detailOverlay.Parent = parent

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseArea"
	closeButton.Size = UDim2.new(1, 0, 1, 0)
	closeButton.BackgroundTransparency = 1
	closeButton.Text = ""
	closeButton.ZIndex = 10
	closeButton.Parent = detailOverlay

	closeButton.MouseButton1Click:Connect(function()
		detailOverlay.Visible = false
		-- Clear detail card
		local existing = detailOverlay:FindFirstChild("DetailCard")
		if existing then existing:Destroy() end
	end)

	-- Container for the card
	local cardContainer = Instance.new("Frame")
	cardContainer.Name = "CardContainer"
	cardContainer.Size = UDim2.new(0, 260, 0, 360)
	cardContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	cardContainer.Position = UDim2.new(0.5, 0, 0.45, 0)
	cardContainer.BackgroundTransparency = 1
	cardContainer.ZIndex = 11
	cardContainer.Parent = detailOverlay
end

function createGameOverOverlay(parent)
	gameOverOverlay = Instance.new("Frame")
	gameOverOverlay.Name = "GameOverOverlay"
	gameOverOverlay.Size = UDim2.new(1, 0, 1, 0)
	gameOverOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	gameOverOverlay.BackgroundTransparency = 0.3
	gameOverOverlay.BorderSizePixel = 0
	gameOverOverlay.Visible = false
	gameOverOverlay.ZIndex = 20
	gameOverOverlay.Parent = parent

	local resultLabel = Instance.new("TextLabel")
	resultLabel.Name = "ResultLabel"
	resultLabel.Size = UDim2.new(0.6, 0, 0.15, 0)
	resultLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	resultLabel.Position = UDim2.new(0.5, 0, 0.35, 0)
	resultLabel.BackgroundTransparency = 1
	resultLabel.Text = "VICTORY!"
	resultLabel.TextColor3 = COLORS.victory
	resultLabel.TextSize = 48
	resultLabel.Font = Enum.Font.GothamBold
	resultLabel.ZIndex = 21
	resultLabel.Parent = gameOverOverlay

	local finalScoreLabel = Instance.new("TextLabel")
	finalScoreLabel.Name = "FinalScore"
	finalScoreLabel.Size = UDim2.new(0.5, 0, 0.08, 0)
	finalScoreLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	finalScoreLabel.Position = UDim2.new(0.5, 0, 0.48, 0)
	finalScoreLabel.BackgroundTransparency = 1
	finalScoreLabel.Text = "Final Score: 0 - 0"
	finalScoreLabel.TextColor3 = COLORS.textWhite
	finalScoreLabel.TextSize = 24
	finalScoreLabel.Font = Enum.Font.Gotham
	finalScoreLabel.ZIndex = 21
	finalScoreLabel.Parent = gameOverOverlay

	local returnButton = Instance.new("TextButton")
	returnButton.Name = "ReturnButton"
	returnButton.Size = UDim2.new(0.3, 0, 0.07, 0)
	returnButton.AnchorPoint = Vector2.new(0.5, 0.5)
	returnButton.Position = UDim2.new(0.5, 0, 0.62, 0)
	returnButton.BackgroundColor3 = COLORS.confirm
	returnButton.BorderSizePixel = 0
	returnButton.Text = "Return to Lobby"
	returnButton.TextColor3 = COLORS.textWhite
	returnButton.TextSize = 20
	returnButton.Font = Enum.Font.GothamBold
	returnButton.ZIndex = 21
	returnButton.Parent = gameOverOverlay

	local returnCorner = Instance.new("UICorner")
	returnCorner.CornerRadius = UDim.new(0, 8)
	returnCorner.Parent = returnButton

	returnButton.MouseButton1Click:Connect(function()
		returnToLobby()
	end)
end

-- ============================================================
-- UI Update Functions
-- ============================================================

local function updateScoreDisplay()
	if not scoreBar then return end
	local oppLabel = scoreBar:FindFirstChild("OppScore")
	local myLabel = scoreBar:FindFirstChild("MyScore")
	local turnLbl = scoreBar:FindFirstChild("TurnLabel")
	if oppLabel then oppLabel.Text = "Opponent: " .. oppScore end
	if myLabel then myLabel.Text = "You: " .. myScore end
	if turnLbl then turnLbl.Text = "Turn " .. currentTurn end
end

local function updateEnergyDisplay()
	if not energyLabel then return end
	local available = myEnergy - energySpent
	energyLabel.Text = string.format("Energy: %d / %d", available, myEnergy)
end

local function updateLocationInfo()
	for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
		local lf = locationFrames[locIdx]
		if lf and locations[locIdx] then
			local loc = locations[locIdx]
			lf.nameLabel.Text = string.format("%s (%d pts)", loc.name or ("Loc " .. locIdx), loc.pointValue or 0)
			lf.effectLabel.Text = loc.effectText or ""
		end
	end
end

local function clearSlotContents(gridFrame)
	for _, slotFrame in ipairs(gridFrame:GetChildren()) do
		if slotFrame:IsA("GuiButton") then
			-- Remove any card display inside
			for _, child in ipairs(slotFrame:GetChildren()) do
				if child:IsA("Frame") and child.Name ~= "SlotStroke" then
					child:Destroy()
				end
			end
			-- Reset slot appearance
			slotFrame.BackgroundColor3 = COLORS.slotEmpty
			slotFrame.BackgroundTransparency = 0.5
			local stroke = slotFrame:FindFirstChild("SlotStroke")
			if stroke then
				stroke.Color = Color3.fromRGB(60, 60, 70)
				stroke.Thickness = 1
			end
		end
	end
end

local function renderCardInSlot(slotFrame, cardID, power, basePower, isPending)
	-- Clear existing
	for _, child in ipairs(slotFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local cardF = CardFrame.create(cardID, "board", power)
	if cardF then
		cardF.Size = UDim2.new(1, -4, 1, -4)
		cardF.Position = UDim2.new(0, 2, 0, 2)
		cardF.ZIndex = 2
		cardF.Parent = slotFrame

		-- Update power color
		if power and basePower then
			CardFrame.updatePower(cardF, power, basePower)
		end

		if isPending then
			cardF.BackgroundTransparency = 0.4
		end
	end

	slotFrame.BackgroundTransparency = 0
	slotFrame.BackgroundColor3 = isPending and COLORS.pending or Color3.fromRGB(30, 30, 35)
end

local function renderMyBoard(myBoards)
	if not myBoards then return end
	for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
		local lf = locationFrames[locIdx]
		if not lf then continue end

		local myGrid = lf.myGrid
		clearSlotContents(myGrid)

		local board = myBoards[locIdx]
		if not board then continue end

		for row = 1, GameConfig.GRID_ROWS do
			for col = 1, GameConfig.GRID_COLUMNS do
				local slotName = string.format("Slot_%d_%d", col, row)
				local slotFrame = myGrid:FindFirstChild(slotName)
				if not slotFrame then continue end

				local cardState = board[row] and board[row][col]
				if cardState then
					local cardID = cardState.cardID or cardState
					local power, basePower
					if type(cardState) == "table" then
						power = cardState.currentPower
						basePower = cardState.basePower
					else
						local def = CardDatabase[cardID]
						power = def and def.power
						basePower = power
					end
					renderCardInSlot(slotFrame, cardID, power, basePower, false)
				end
			end
		end
	end
end

local function renderOppBoard(oppBoards)
	if not oppBoards then return end
	for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
		local lf = locationFrames[locIdx]
		if not lf then continue end

		local oppGrid = lf.oppGrid
		clearSlotContents(oppGrid)

		local board = oppBoards[locIdx]
		if not board then continue end

		for row = 1, GameConfig.GRID_ROWS do
			for col = 1, GameConfig.GRID_COLUMNS do
				local slotName = string.format("Slot_%d_%d", col, row)
				local slotFrame = oppGrid:FindFirstChild(slotName)
				if not slotFrame then continue end

				local cardState = board[row] and board[row][col]
				if cardState then
					local cardID = type(cardState) == "table" and cardState.cardID or cardState
					local power, basePower
					if type(cardState) == "table" then
						power = cardState.currentPower
						basePower = cardState.basePower
					end
					renderCardInSlot(slotFrame, cardID, power, basePower, false)
				end
			end
		end
	end
end

local function renderHand()
	-- Clear existing hand cards
	for _, frame in ipairs(handCardFrames) do
		if frame and frame.Parent then frame:Destroy() end
	end
	handCardFrames = {}

	if not handFrame then return end

	for i, cardID in ipairs(myHand) do
		-- Check if this card is in pending plays (skip display)
		local isPending = false
		for _, play in ipairs(pendingPlays) do
			if play.cardID == cardID and play.handIndex == i then
				isPending = true
				break
			end
		end
		if isPending then continue end

		local def = CardDatabase[cardID]
		if not def then continue end

		local cardF = CardFrame.create(cardID, "hand")
		if cardF then
			cardF.LayoutOrder = i
			cardF.Parent = handFrame

			-- Make it a button for selection
			local clickArea = Instance.new("TextButton")
			clickArea.Name = "ClickArea"
			clickArea.Size = UDim2.new(1, 0, 1, 0)
			clickArea.BackgroundTransparency = 1
			clickArea.Text = ""
			clickArea.ZIndex = 5
			clickArea.Parent = cardF

			local cardIndex = i
			local cID = cardID
			clickArea.MouseButton1Click:Connect(function()
				onHandCardClicked(cID, cardIndex)
			end)

			-- Highlight if selected
			if selectedCardID == cardID and selectedCardIndex == i then
				local selStroke = cardF:FindFirstChildWhichIsA("UIStroke")
				if selStroke then
					selStroke.Color = COLORS.slotHighlight
					selStroke.Thickness = 3
				end
			end

			table.insert(handCardFrames, cardF)
		end
	end
end

local function renderPendingPlays()
	-- Show pending cards on the board
	for _, play in ipairs(pendingPlays) do
		local lf = locationFrames[play.locIdx]
		if not lf then continue end

		local slotName = string.format("Slot_%d_%d", play.col, play.row)
		local slotFrame = lf.myGrid:FindFirstChild(slotName)
		if not slotFrame then continue end

		local def = CardDatabase[play.cardID]
		if def then
			renderCardInSlot(slotFrame, play.cardID, def.power, def.power, true)
		end
	end
end

local function highlightValidSlots()
	if not selectedCardID then
		-- Remove all highlights
		for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
			local lf = locationFrames[locIdx]
			if not lf then continue end
			for _, slotFrame in ipairs(lf.myGrid:GetChildren()) do
				if slotFrame:IsA("GuiButton") then
					local stroke = slotFrame:FindFirstChild("SlotStroke")
					if stroke then
						stroke.Color = Color3.fromRGB(60, 60, 70)
						stroke.Thickness = 1
					end
				end
			end
		end
		return
	end

	local def = CardDatabase[selectedCardID]
	if not def then return end

	for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
		local lf = locationFrames[locIdx]
		if not lf then continue end
		local loc = locations[locIdx]

		for row = 1, GameConfig.GRID_ROWS do
			for col = 1, GameConfig.GRID_COLUMNS do
				local slotName = string.format("Slot_%d_%d", col, row)
				local slotFrame = lf.myGrid:FindFirstChild(slotName)
				if not slotFrame then continue end

				local stroke = slotFrame:FindFirstChild("SlotStroke")
				if not stroke then continue end

				local isValid = true

				-- Check location restrictions
				if loc and loc.effect then
					if loc.effect == "Restrict:MinCost:3" and def.cost < 3 then
						isValid = false
					end
					if loc.effect == "Restrict:FrontRowOnly" and row ~= 1 then
						isValid = false
					end
				end

				-- Check if already has a pending play
				local hasPending = false
				for _, play in ipairs(pendingPlays) do
					if play.locIdx == locIdx and play.col == col and play.row == row then
						hasPending = true
						break
					end
				end

				if isValid and not hasPending then
					-- Check if slot has own card (overwrite target)
					local hasOwnCard = false
					-- We track this from the server state
					if slotFrame.BackgroundTransparency == 0 and not hasPending then
						hasOwnCard = true
					end

					stroke.Color = hasOwnCard and COLORS.slotOverwrite or COLORS.slotHighlight
					stroke.Thickness = 2
				else
					stroke.Color = Color3.fromRGB(60, 60, 70)
					stroke.Thickness = 1
				end
			end
		end
	end
end

local function updatePowerTotals(myBoards, oppBoards)
	for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
		local lf = locationFrames[locIdx]
		if not lf then continue end

		local myPower = 0
		local oppPower = 0

		if myBoards and myBoards[locIdx] then
			for row = 1, GameConfig.GRID_ROWS do
				for col = 1, GameConfig.GRID_COLUMNS do
					local card = myBoards[locIdx][row] and myBoards[locIdx][row][col]
					if card then
						if type(card) == "table" then
							myPower = myPower + (card.currentPower or card.basePower or 0)
						end
					end
				end
			end
		end

		if oppBoards and oppBoards[locIdx] then
			for row = 1, GameConfig.GRID_ROWS do
				for col = 1, GameConfig.GRID_COLUMNS do
					local card = oppBoards[locIdx][row] and oppBoards[locIdx][row][col]
					if card then
						if type(card) == "table" then
							oppPower = oppPower + (card.currentPower or card.basePower or 0)
						end
					end
				end
			end
		end

		-- Add pending play power
		for _, play in ipairs(pendingPlays) do
			if play.locIdx == locIdx then
				local def = CardDatabase[play.cardID]
				if def then myPower = myPower + def.power end
			end
		end

		lf.powerLabel.Text = string.format("You: %d / Opp: %d", myPower, oppPower)
	end
end

-- ============================================================
-- Interaction Handlers
-- ============================================================

function onHandCardClicked(cardID, cardIndex)
	if not matchActive then return end

	local def = CardDatabase[cardID]
	if not def then return end

	-- Check if we can afford it
	local available = myEnergy - energySpent
	if def.cost > available then
		print("[Client] Can't afford " .. cardID .. " (cost " .. def.cost .. ", have " .. available .. ")")
		return
	end

	if selectedCardID == cardID and selectedCardIndex == cardIndex then
		-- Deselect
		selectedCardID = nil
		selectedCardIndex = nil
	else
		-- Select this card
		selectedCardID = cardID
		selectedCardIndex = cardIndex
	end

	renderHand()
	highlightValidSlots()
end

function onSlotClicked(locIdx, col, row)
	if not matchActive then return end

	-- Check if there's a pending play here — if so, undo it
	for i, play in ipairs(pendingPlays) do
		if play.locIdx == locIdx and play.col == col and play.row == row then
			-- Undo this pending play
			local def = CardDatabase[play.cardID]
			if def then
				energySpent = energySpent - def.cost
			end
			table.remove(pendingPlays, i)
			print("[Client] Undid pending play: " .. play.cardID)

			selectedCardID = nil
			selectedCardIndex = nil

			renderHand()
			renderPendingPlays()
			highlightValidSlots()
			updateEnergyDisplay()
			return
		end
	end

	-- If no card selected, do nothing
	if not selectedCardID then return end

	local def = CardDatabase[selectedCardID]
	if not def then return end

	-- Check location restrictions
	local loc = locations[locIdx]
	if loc and loc.effect then
		if loc.effect == "Restrict:MinCost:3" and def.cost < 3 then
			print("[Client] Card blocked by Sky Temple")
			return
		end
		if loc.effect == "Restrict:FrontRowOnly" and row ~= 1 then
			print("[Client] Back row blocked by Dueling Grounds")
			return
		end
	end

	-- Place the pending play
	table.insert(pendingPlays, {
		cardID = selectedCardID,
		locIdx = locIdx,
		col = col,
		row = row,
		handIndex = selectedCardIndex,
	})
	energySpent = energySpent + def.cost

	print(string.format("[Client] Pending: %s at loc %d (%d,%d)", selectedCardID, locIdx, col, row))

	selectedCardID = nil
	selectedCardIndex = nil

	renderHand()
	renderPendingPlays()
	highlightValidSlots()
	updateEnergyDisplay()
end

function onOppSlotClicked(locIdx, col, row)
	-- Show detail of opponent's card if one exists
	-- (detail viewing works during any phase)
end

function onConfirmClicked()
	if not matchActive then return end

	submitPlays()
end

local function submitPlays()
	-- Build the play list in order
	local plays = {}
	for _, play in ipairs(pendingPlays) do
		table.insert(plays, {
			cardID = play.cardID,
			locIdx = play.locIdx,
			col = play.col,
			row = play.row,
		})
	end

	print(string.format("[Client] Submitting %d plays", #plays))
	SubmitTurnEvent:FireServer(plays)

	-- Switch to waiting state
	timerRunning = false
	if confirmButton then confirmButton.Visible = false end
	if waitingLabel then waitingLabel.Visible = true end
end

local function showDetailCard(cardID, power)
	if not detailOverlay then return end

	-- Clear previous
	local container = detailOverlay:FindFirstChild("CardContainer")
	if container then
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Frame") then child:Destroy() end
		end

		local cardF = CardFrame.create(cardID, "detail", power)
		if cardF then
			cardF.Size = UDim2.new(1, 0, 1, 0)
			cardF.Position = UDim2.new(0, 0, 0, 0)
			cardF.ZIndex = 12
			cardF.Parent = container
		end
	end

	detailOverlay.Visible = true
end

function returnToLobby()
	matchActive = false
	currentTurn = 0
	myEnergy = 0
	energySpent = 0
	myHand = {}
	myScore = 0
	oppScore = 0
	locations = {}
	selectedCardID = nil
	selectedCardIndex = nil
	pendingPlays = {}

	if matchGui then
		matchGui.Enabled = false
	end
	if gameOverOverlay then
		gameOverOverlay.Visible = false
	end
	if lobbyGui then
		lobbyGui.Enabled = true
		local btn = lobbyGui:FindFirstChild("LobbyBG")
		if btn then
			local botBtn = btn:FindFirstChild("PlayBotButton")
			if botBtn then
				botBtn.Text = "Play vs Bot"
				botBtn.BackgroundColor3 = COLORS.confirm
			end
		end
	end
end

-- ============================================================
-- Timer
-- ============================================================

local function startTimer(seconds)
	timerSeconds = seconds
	timerRunning = true

	task.spawn(function()
		while timerRunning and timerSeconds > 0 do
			timerSeconds = timerSeconds - 1
			if timerLabel then
				timerLabel.Text = "Timer: " .. timerSeconds
				if timerSeconds <= 5 then
					timerLabel.TextColor3 = COLORS.timerWarning
				else
					timerLabel.TextColor3 = COLORS.timerNormal
				end
			end
			task.wait(1)
		end

		if timerRunning then
			-- Timer expired — auto-submit whatever is placed
			print("[Client] Timer expired — auto-submitting")
			submitPlays()
		end
	end)
end

-- ============================================================
-- Server Event Handlers
-- ============================================================

local lastMyBoards = nil
local lastOppBoards = nil

TurnStartEvent.OnClientEvent:Connect(function(state)
	if not matchActive then
		-- First turn — set up the match UI
		matchActive = true
		if lobbyGui then lobbyGui.Enabled = false end
		createMatchUI()
		matchGui.Enabled = true
	end

	print(string.format("[Client] Turn %d started — Energy: %d, Hand: %d cards",
		state.turn, state.energy, #state.hand))

	currentTurn = state.turn
	myEnergy = state.energy
	energySpent = 0
	myHand = state.hand
	myScore = state.myScore
	oppScore = state.oppScore
	locations = state.locations
	selectedCardID = nil
	selectedCardIndex = nil
	pendingPlays = {}
	lastMyBoards = state.myBoards
	lastOppBoards = state.oppBoards

	-- Update displays
	updateScoreDisplay()
	updateEnergyDisplay()
	updateLocationInfo()
	renderMyBoard(state.myBoards)
	renderOppBoard(state.oppBoards)
	renderHand()
	highlightValidSlots()
	updatePowerTotals(state.myBoards, state.oppBoards)

	-- Show confirm button, hide waiting
	if confirmButton then confirmButton.Visible = true end
	if waitingLabel then waitingLabel.Visible = false end

	-- Start timer
	startTimer(GameConfig.TURN_TIMER_SECONDS)
end)

RevealResultEvent.OnClientEvent:Connect(function(resultData)
	print(string.format("[Client] Reveal results for turn %d", resultData.turn))

	timerRunning = false

	-- Update boards with results
	lastMyBoards = resultData.myBoards
	lastOppBoards = resultData.oppBoards
	renderMyBoard(resultData.myBoards)
	renderOppBoard(resultData.oppBoards)
	updatePowerTotals(resultData.myBoards, resultData.oppBoards)

	-- Clear pending state
	pendingPlays = {}
	selectedCardID = nil
	selectedCardIndex = nil
end)

ScoreUpdateEvent.OnClientEvent:Connect(function(scoreData)
	local myID = tostring(player.UserId)
	for pid, score in pairs(scoreData.scores) do
		if pid == myID then
			myScore = score
		else
			oppScore = score
		end
	end
	updateScoreDisplay()

	-- Animate score change
	if scoreBar then
		local myLabel = scoreBar:FindFirstChild("MyScore")
		if myLabel then
			local origSize = myLabel.TextSize
			myLabel.TextSize = origSize + 6
			task.delay(0.3, function()
				myLabel.TextSize = origSize
			end)
		end
	end
end)

GameOverEvent.OnClientEvent:Connect(function(resultData)
	print("[Client] Game Over!")
	matchActive = false
	timerRunning = false

	if not gameOverOverlay then return end

	local myID = tostring(player.UserId)
	local resultLabel = gameOverOverlay:FindFirstChild("ResultLabel")
	local finalScoreLabel = gameOverOverlay:FindFirstChild("FinalScore")

	if resultData.winner == myID then
		if resultLabel then
			resultLabel.Text = "VICTORY!"
			resultLabel.TextColor3 = COLORS.victory
		end
	elseif resultData.winner == "DRAW" then
		if resultLabel then
			resultLabel.Text = "DRAW"
			resultLabel.TextColor3 = COLORS.textWhite
		end
	else
		if resultLabel then
			resultLabel.Text = "DEFEAT"
			resultLabel.TextColor3 = COLORS.defeat
		end
	end

	if finalScoreLabel then
		local myFinalScore = resultData.finalScores[myID] or 0
		local oppFinalScore = 0
		for pid, s in pairs(resultData.finalScores) do
			if pid ~= myID then oppFinalScore = s end
		end
		finalScoreLabel.Text = string.format("Final Score: %d - %d  |  Turns: %d",
			myFinalScore, oppFinalScore, resultData.totalTurns or 0)
	end

	gameOverOverlay.Visible = true
end)

InvalidPlayEvent.OnClientEvent:Connect(function(data)
	print("[Client] Invalid play: " .. (data.reason or "unknown"))
end)

-- ============================================================
-- Initialize
-- ============================================================

print("[MatchClient] Initialized — waiting for match")
createLobbyUI()
