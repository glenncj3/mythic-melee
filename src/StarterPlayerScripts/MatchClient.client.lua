--[[
	MatchClient — handles the full match UI on the client side.

	Responsibilities:
		- Builds match GUI (two locations, 1x3 grids, hand, scores, energy, timer)
		- Planning phase: drag-to-play cards, click-to-inspect
		- Sends SubmitTurn to server on confirm or timer expiry
		- Receives RevealResult, ScoreUpdate, GameOver from server
		- Animates reveals, score changes, game-over screen
		- Pre-match: shows "Play vs Bot" button with lobby animations
]]

print("[MatchClient] v2 loaded — drag-and-drop + click-to-inspect")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Events = ReplicatedStorage:WaitForChild("Events")

local GameConfig = require(Modules:WaitForChild("GameConfig"))
local CardDatabase = require(Modules:WaitForChild("CardDatabase"))
local CardFrame = require(Modules:WaitForChild("CardFrame"))
local SlotGrid = require(Modules:WaitForChild("SlotGrid"))
local LocationRestrictions = require(Modules:WaitForChild("LocationRestrictions"))

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
local myHand = {}
local myScore = 0
local oppScore = 0
local locations = {}
local selectedCardID = nil
local selectedCardIndex = nil
local pendingPlays = {}
-- Drag-and-drop state
local draggingCardID = nil
local draggingCardIndex = nil
local dragGhost = nil
local dragConnections = {}
local isDragging = false
local lastHoveredSlot = nil
local timerRunning = false
local timerSeconds = 0
local submitted = false

-- UI references
local matchGui = nil
local lobbyGui = nil
local boardFrame = nil
local handFrame = nil
local scoreBar = nil
local energyFrame = nil
local energyNumberLabel = nil
local energyMaxLabel = nil
local energyPreviewLabel = nil
local timerLabel = nil
local confirmButton = nil
local waitingLabel = nil
local detailOverlay = nil
local gameOverOverlay = nil
local locationFrames = {}
local handCardFrames = {}
local lastMyBoards = nil
local lastOppBoards = nil
local progressBarPlayer = nil
local progressBarOpp = nil
local toastLabel = nil
local vignetteFrame = nil

-- Active tweens tracking (for cancellation)
local activeTweens = {}

-- ============================================================
-- Color Constants (Phase 2 palette)
-- ============================================================

local COLORS = {
	bg = Color3.fromRGB(10, 10, 18),
	boardSurface = Color3.fromRGB(20, 22, 32),
	panel = Color3.fromRGB(32, 36, 52),
	panelBorder = Color3.fromRGB(70, 80, 110),
	panelGlow = Color3.fromRGB(60, 80, 160),
	centerBand = Color3.fromRGB(25, 28, 42),
	oppRow = Color3.fromRGB(50, 25, 30),
	myRow = Color3.fromRGB(25, 35, 55),
	slotEmpty = Color3.fromRGB(42, 46, 62),
	slotEmptyOpp = Color3.fromRGB(58, 32, 36),
	slotBorder = Color3.fromRGB(70, 75, 90),
	slotHighlight = Color3.fromRGB(50, 200, 90),
	slotOverwrite = Color3.fromRGB(220, 150, 40),
	pending = Color3.fromRGB(40, 80, 50),
	divider = Color3.fromRGB(90, 95, 110),
	scoreBarBg = Color3.fromRGB(14, 14, 22),
	bottomBg = Color3.fromRGB(18, 20, 30),
	energyColor = Color3.fromRGB(70, 140, 255),
	timerNormal = Color3.fromRGB(220, 220, 220),
	timerWarning = Color3.fromRGB(255, 60, 60),
	timerAmber = Color3.fromRGB(255, 180, 40),
	confirm = Color3.fromRGB(40, 170, 80),
	confirmHover = Color3.fromRGB(55, 200, 100),
	confirmDisabled = Color3.fromRGB(50, 50, 60),
	textWhite = Color3.fromRGB(240, 240, 240),
	textGray = Color3.fromRGB(140, 145, 160),
	textEffect = Color3.fromRGB(220, 195, 100),
	textGreen = Color3.fromRGB(80, 230, 80),
	textRed = Color3.fromRGB(255, 90, 90),
	textBlue = Color3.fromRGB(100, 170, 255),
	victory = Color3.fromRGB(255, 210, 40),
	defeat = Color3.fromRGB(200, 50, 50),
	toastBg = Color3.fromRGB(180, 40, 40),
	winGlow = Color3.fromRGB(50, 200, 90),
	loseGlow = Color3.fromRGB(200, 50, 50),
}

-- ============================================================
-- Tween Helpers
-- ============================================================

local function cancelTween(key)
	if activeTweens[key] then
		activeTweens[key]:Cancel()
		activeTweens[key] = nil
	end
end

local function playTween(key, instance, tweenInfo, properties)
	cancelTween(key)
	local tween = TweenService:Create(instance, tweenInfo, properties)
	activeTweens[key] = tween
	tween:Play()
	return tween
end

-- Pulse a single property between two values in a loop.
-- Runs in a spawned thread; stops when the instance loses its Parent
-- or the optional guardFn returns false.
local function pulseProperty(instance, property, lowVal, highVal, duration, guardFn)
	task.spawn(function()
		while instance and instance.Parent do
			if guardFn and not guardFn() then break end
			local tweenA = TweenService:Create(instance,
				TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ [property] = highVal }
			)
			tweenA:Play()
			tweenA.Completed:Wait()
			if not instance or not instance.Parent then break end
			if guardFn and not guardFn() then break end
			local tweenB = TweenService:Create(instance,
				TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ [property] = lowVal }
			)
			tweenB:Play()
			tweenB.Completed:Wait()
		end
	end)
end

-- ============================================================
-- Screen Transition Utility
-- ============================================================

local transitionFrame = nil

local function screenTransition(callback)
	if not transitionFrame then
		transitionFrame = Instance.new("Frame")
		transitionFrame.Name = "TransitionOverlay"
		transitionFrame.Size = UDim2.new(1, 0, 1, 0)
		transitionFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		transitionFrame.BackgroundTransparency = 1
		transitionFrame.BorderSizePixel = 0
		transitionFrame.ZIndex = 100
	end
	transitionFrame.Parent = playerGui:FindFirstChild("LobbyGui") or playerGui:FindFirstChild("MatchGui") or playerGui

	-- Fade to black
	local fadeIn = TweenService:Create(transitionFrame,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0 }
	)
	fadeIn:Play()
	fadeIn.Completed:Wait()

	task.wait(0.1)
	if callback then callback() end

	-- Reparent to new GUI if needed
	transitionFrame.Parent = playerGui:FindFirstChild("LobbyGui") or playerGui:FindFirstChild("MatchGui") or playerGui

	-- Fade from black
	local fadeOut = TweenService:Create(transitionFrame,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	)
	fadeOut:Play()
	fadeOut.Completed:Wait()
end

-- ============================================================
-- Toast Notification System (Phase 3D)
-- ============================================================

local function showToast(message)
	if not toastLabel then return end
	toastLabel.Text = message
	toastLabel.Visible = true
	toastLabel.Position = UDim2.new(0.5, 0, -0.05, 0)
	toastLabel.BackgroundTransparency = 0

	-- Slide down
	local slideIn = TweenService:Create(toastLabel,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0.03, 0) }
	)
	slideIn:Play()

	-- Hold, then slide back up
	task.delay(1.5, function()
		if toastLabel and toastLabel.Parent then
			local slideOut = TweenService:Create(toastLabel,
				TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = UDim2.new(0.5, 0, -0.05, 0), BackgroundTransparency = 1 }
			)
			slideOut:Play()
			slideOut.Completed:Connect(function()
				if toastLabel then toastLabel.Visible = false end
			end)
		end
	end)
end

-- ============================================================
-- Responsive Sizing Helpers (Phase 7)
-- ============================================================

local function getViewportSize()
	return camera.ViewportSize
end

local function isPortrait()
	local vp = getViewportSize()
	return vp.X < vp.Y
end

local function isMobile()
	return UserInputService.TouchEnabled
end

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

	-- Title with entrance animation
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(0.8, 0, 0.1, 0)
	title.Position = UDim2.new(0.1, 0, 0.25, 0)
	title.BackgroundTransparency = 1
	title.Text = "MYTHIC MASH"
	title.TextColor3 = COLORS.victory
	title.TextSize = 52
	title.Font = Enum.Font.GothamBold
	title.TextTransparency = 1
	title.Parent = bgFrame

	-- Entrance: scale + fade
	title.Size = UDim2.new(0.64, 0, 0.08, 0)
	title.Position = UDim2.new(0.18, 0, 0.27, 0)
	local titleFade = TweenService:Create(title,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 0, Size = UDim2.new(0.8, 0, 0.1, 0), Position = UDim2.new(0.1, 0, 0.25, 0) }
	)
	titleFade:Play()

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(0.8, 0, 0.05, 0)
	subtitle.Position = UDim2.new(0.1, 0, 0.37, 0)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "A Positional Card Game"
	subtitle.TextColor3 = COLORS.textGray
	subtitle.TextSize = 20
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextTransparency = 1
	subtitle.Parent = bgFrame

	task.delay(0.3, function()
		local subFade = TweenService:Create(subtitle,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ TextTransparency = 0 }
		)
		subFade:Play()
	end)

	local botButton = Instance.new("TextButton")
	botButton.Name = "PlayBotButton"
	botButton.Size = UDim2.new(0.3, 0, 0.08, 0)
	botButton.Position = UDim2.new(0.35, 0, 0.52, 0)
	botButton.BackgroundColor3 = COLORS.confirm
	botButton.BorderSizePixel = 0
	botButton.Text = "Play vs Bot"
	botButton.TextColor3 = COLORS.textWhite
	botButton.TextSize = 24
	botButton.Font = Enum.Font.GothamBold
	botButton.TextTransparency = 1
	botButton.BackgroundTransparency = 1
	botButton.Parent = bgFrame

	local botCorner = Instance.new("UICorner")
	botCorner.CornerRadius = UDim.new(0, 10)
	botCorner.Parent = botButton

	-- Green glow on play button
	local botGlow = Instance.new("UIStroke")
	botGlow.Color = COLORS.confirm
	botGlow.Thickness = 2
	botGlow.Transparency = 0.5
	botGlow.Parent = botButton

	-- Entrance animation (delayed)
	task.delay(0.6, function()
		local btnFade = TweenService:Create(botButton,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ TextTransparency = 0, BackgroundTransparency = 0, Position = UDim2.new(0.35, 0, 0.52, 0) }
		)
		botButton.Position = UDim2.new(0.35, 0, 0.56, 0)
		btnFade:Play()
	end)

	-- Searching dots animation
	local searchingDots = 0
	local searchingConnection = nil

	botButton.MouseButton1Click:Connect(function()
		if matchActive then return end
		botButton.Text = "Searching"
		botButton.BackgroundColor3 = COLORS.confirmDisabled
		RequestBotMatchEvent:FireServer()

		-- Dots animation
		searchingConnection = task.spawn(function()
			while botButton and botButton.Parent and botButton.Text:find("Searching") do
				searchingDots = (searchingDots % 3) + 1
				botButton.Text = "Searching" .. string.rep(".", searchingDots)
				task.wait(0.4)
			end
		end)
	end)

	return lobbyGui
end

local function createMatchUI()
	matchGui = playerGui:WaitForChild("MatchGui")

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

	-- Board surface background with radial gradient feel
	local boardBg = Instance.new("Frame")
	boardBg.Name = "BoardSurface"
	boardBg.Size = UDim2.new(1, 0, 1, 0)
	boardBg.BackgroundColor3 = COLORS.boardSurface
	boardBg.BorderSizePixel = 0
	boardBg.Parent = bg

	local boardBgGradient = Instance.new("UIGradient")
	boardBgGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 28, 40)),
		ColorSequenceKeypoint.new(0.5, COLORS.boardSurface),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(25, 28, 40)),
	})
	boardBgGradient.Parent = boardBg

	-- Toast notification label
	toastLabel = Instance.new("TextLabel")
	toastLabel.Name = "Toast"
	toastLabel.Size = UDim2.new(0.4, 0, 0.04, 0)
	toastLabel.AnchorPoint = Vector2.new(0.5, 0)
	toastLabel.Position = UDim2.new(0.5, 0, -0.05, 0)
	toastLabel.BackgroundColor3 = COLORS.toastBg
	toastLabel.BackgroundTransparency = 0
	toastLabel.BorderSizePixel = 0
	toastLabel.Text = ""
	toastLabel.TextColor3 = COLORS.textWhite
	toastLabel.TextSize = 14
	toastLabel.Font = Enum.Font.GothamBold
	toastLabel.Visible = false
	toastLabel.ZIndex = 30
	toastLabel.Parent = bg

	local toastCorner = Instance.new("UICorner")
	toastCorner.CornerRadius = UDim.new(0, 8)
	toastCorner.Parent = toastLabel

	-- === SCORE BAR (top, proportional height) ===
	scoreBar = Instance.new("Frame")
	scoreBar.Name = "ScoreBar"
	scoreBar.Size = UDim2.new(1, 0, 0.045, 0)
	scoreBar.Position = UDim2.new(0, 0, 0, 0)
	scoreBar.BackgroundColor3 = COLORS.scoreBarBg
	scoreBar.BorderSizePixel = 0
	scoreBar.ZIndex = 2
	scoreBar.Parent = bg

	-- Top padding for Roblox UI
	local scoreBarPadding = Instance.new("UIPadding")
	scoreBarPadding.PaddingTop = UDim.new(0, 4)
	scoreBarPadding.Parent = scoreBar

	-- Opponent score (left of center) — red pip + number
	local oppScoreLabel = Instance.new("TextLabel")
	oppScoreLabel.Name = "OppScore"
	oppScoreLabel.Size = UDim2.new(0.2, 0, 1, 0)
	oppScoreLabel.Position = UDim2.new(0.22, 0, 0, 0)
	oppScoreLabel.BackgroundTransparency = 1
	oppScoreLabel.Text = "0"
	oppScoreLabel.TextColor3 = COLORS.textRed
	oppScoreLabel.TextSize = 20
	oppScoreLabel.Font = Enum.Font.GothamBold
	oppScoreLabel.TextXAlignment = Enum.TextXAlignment.Right
	oppScoreLabel.ZIndex = 3
	oppScoreLabel.Parent = scoreBar

	-- Turn counter (centered, prominent)
	local turnLabel = Instance.new("TextLabel")
	turnLabel.Name = "TurnLabel"
	turnLabel.Size = UDim2.new(0.16, 0, 1, 0)
	turnLabel.Position = UDim2.new(0.42, 0, 0, 0)
	turnLabel.BackgroundTransparency = 1
	turnLabel.Text = "TURN 1"
	turnLabel.TextColor3 = COLORS.textWhite
	turnLabel.TextSize = 22
	turnLabel.Font = Enum.Font.GothamBold
	turnLabel.ZIndex = 3
	turnLabel.Parent = scoreBar

	-- Player score (right of center) — green number
	local myScoreLabel = Instance.new("TextLabel")
	myScoreLabel.Name = "MyScore"
	myScoreLabel.Size = UDim2.new(0.2, 0, 1, 0)
	myScoreLabel.Position = UDim2.new(0.58, 0, 0, 0)
	myScoreLabel.BackgroundTransparency = 1
	myScoreLabel.Text = "0"
	myScoreLabel.TextColor3 = COLORS.textGreen
	myScoreLabel.TextSize = 20
	myScoreLabel.Font = Enum.Font.GothamBold
	myScoreLabel.TextXAlignment = Enum.TextXAlignment.Left
	myScoreLabel.ZIndex = 3
	myScoreLabel.Parent = scoreBar

	-- Score progress bar (Phase 5D)
	local progressContainer = Instance.new("Frame")
	progressContainer.Name = "ProgressBar"
	progressContainer.Size = UDim2.new(0.5, 0, 0, 4)
	progressContainer.AnchorPoint = Vector2.new(0.5, 0)
	progressContainer.Position = UDim2.new(0.5, 0, 1, 0)
	progressContainer.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	progressContainer.BorderSizePixel = 0
	progressContainer.ZIndex = 3
	progressContainer.Parent = scoreBar

	local progCorner = Instance.new("UICorner")
	progCorner.CornerRadius = UDim.new(0, 2)
	progCorner.Parent = progressContainer

	-- Player progress (green, from right)
	progressBarPlayer = Instance.new("Frame")
	progressBarPlayer.Name = "PlayerProgress"
	progressBarPlayer.Size = UDim2.new(0, 0, 1, 0)
	progressBarPlayer.AnchorPoint = Vector2.new(1, 0)
	progressBarPlayer.Position = UDim2.new(1, 0, 0, 0)
	progressBarPlayer.BackgroundColor3 = COLORS.textGreen
	progressBarPlayer.BorderSizePixel = 0
	progressBarPlayer.ZIndex = 4
	progressBarPlayer.Parent = progressContainer

	local progPlayerCorner = Instance.new("UICorner")
	progPlayerCorner.CornerRadius = UDim.new(0, 2)
	progPlayerCorner.Parent = progressBarPlayer

	-- Opponent progress (red, from left)
	progressBarOpp = Instance.new("Frame")
	progressBarOpp.Name = "OppProgress"
	progressBarOpp.Size = UDim2.new(0, 0, 1, 0)
	progressBarOpp.Position = UDim2.new(0, 0, 0, 0)
	progressBarOpp.BackgroundColor3 = COLORS.textRed
	progressBarOpp.BorderSizePixel = 0
	progressBarOpp.ZIndex = 4
	progressBarOpp.Parent = progressContainer

	local progOppCorner = Instance.new("UICorner")
	progOppCorner.CornerRadius = UDim.new(0, 2)
	progOppCorner.Parent = progressBarOpp

	-- Center tick mark
	local centerTick = Instance.new("Frame")
	centerTick.Size = UDim2.new(0, 2, 1, 2)
	centerTick.AnchorPoint = Vector2.new(0.5, 0.5)
	centerTick.Position = UDim2.new(0.5, 0, 0.5, 0)
	centerTick.BackgroundColor3 = COLORS.textWhite
	centerTick.BorderSizePixel = 0
	centerTick.ZIndex = 5
	centerTick.Parent = progressContainer

	-- === BOARD AREA (locations, left 65%) ===
	boardFrame = Instance.new("Frame")
	boardFrame.Name = "BoardArea"
	boardFrame.Size = UDim2.new(0.65, -8, 0.95, -8)
	boardFrame.Position = UDim2.new(0, 8, 0.05, 0)
	boardFrame.BackgroundTransparency = 1
	boardFrame.ZIndex = 2
	boardFrame.Parent = bg

	local boardLayout = Instance.new("UIListLayout")
	boardLayout.FillDirection = Enum.FillDirection.Horizontal
	boardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	boardLayout.Padding = UDim.new(0, 8)
	boardLayout.Parent = boardFrame

	locationFrames = {}
	for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
		locationFrames[locIdx] = createLocationPanel(locIdx, boardFrame)
	end

	-- === SIDEBAR (right 35% — energy, timer, hand, confirm) ===
	local sidebar = Instance.new("Frame")
	sidebar.Name = "Sidebar"
	sidebar.Size = UDim2.new(0.35, -12, 0.95, -8)
	sidebar.Position = UDim2.new(0.65, 4, 0.05, 0)
	sidebar.BackgroundColor3 = COLORS.bottomBg
	sidebar.BorderSizePixel = 0
	sidebar.ZIndex = 2
	sidebar.Parent = bg

	local sidebarCorner = Instance.new("UICorner")
	sidebarCorner.CornerRadius = UDim.new(0, 8)
	sidebarCorner.Parent = sidebar

	local sidebarStroke = Instance.new("UIStroke")
	sidebarStroke.Color = COLORS.panelBorder
	sidebarStroke.Thickness = 1
	sidebarStroke.Parent = sidebar

	-- Top row: Energy + Timer
	local topRow = Instance.new("Frame")
	topRow.Name = "TopRow"
	topRow.Size = UDim2.new(1, 0, 0, 50)
	topRow.Position = UDim2.new(0, 0, 0, 6)
	topRow.BackgroundTransparency = 1
	topRow.ZIndex = 3
	topRow.Parent = sidebar

	-- Energy indicator (circular)
	energyFrame = Instance.new("Frame")
	energyFrame.Name = "EnergyIndicator"
	energyFrame.Size = UDim2.new(0, 44, 0, 44)
	energyFrame.Position = UDim2.new(0, 10, 0, 3)
	energyFrame.BackgroundColor3 = Color3.fromRGB(30, 35, 50)
	energyFrame.BorderSizePixel = 0
	energyFrame.ZIndex = 4
	energyFrame.Parent = topRow

	local energyCorner = Instance.new("UICorner")
	energyCorner.CornerRadius = UDim.new(1, 0)
	energyCorner.Parent = energyFrame

	local energyRing = Instance.new("UIStroke")
	energyRing.Name = "EnergyRing"
	energyRing.Color = COLORS.energyColor
	energyRing.Thickness = 3
	energyRing.Parent = energyFrame

	energyNumberLabel = Instance.new("TextLabel")
	energyNumberLabel.Name = "EnergyNumber"
	energyNumberLabel.Size = UDim2.new(1, 0, 0.65, 0)
	energyNumberLabel.Position = UDim2.new(0, 0, 0.05, 0)
	energyNumberLabel.BackgroundTransparency = 1
	energyNumberLabel.Text = "0"
	energyNumberLabel.TextColor3 = COLORS.energyColor
	energyNumberLabel.TextSize = 24
	energyNumberLabel.Font = Enum.Font.GothamBold
	energyNumberLabel.ZIndex = 5
	energyNumberLabel.Parent = energyFrame

	energyMaxLabel = Instance.new("TextLabel")
	energyMaxLabel.Name = "EnergyMax"
	energyMaxLabel.Size = UDim2.new(1, 0, 0.3, 0)
	energyMaxLabel.Position = UDim2.new(0, 0, 0.65, 0)
	energyMaxLabel.BackgroundTransparency = 1
	energyMaxLabel.Text = "/ 0"
	energyMaxLabel.TextColor3 = COLORS.textGray
	energyMaxLabel.TextSize = 11
	energyMaxLabel.Font = Enum.Font.Gotham
	energyMaxLabel.ZIndex = 5
	energyMaxLabel.Parent = energyFrame

	energyPreviewLabel = Instance.new("TextLabel")
	energyPreviewLabel.Name = "EnergyPreview"
	energyPreviewLabel.Size = UDim2.new(0, 40, 0, 16)
	energyPreviewLabel.Position = UDim2.new(0, 58, 0, 30)
	energyPreviewLabel.BackgroundTransparency = 1
	energyPreviewLabel.Text = ""
	energyPreviewLabel.TextColor3 = Color3.fromRGB(255, 180, 40)
	energyPreviewLabel.TextSize = 12
	energyPreviewLabel.Font = Enum.Font.GothamBold
	energyPreviewLabel.TextXAlignment = Enum.TextXAlignment.Left
	energyPreviewLabel.Visible = false
	energyPreviewLabel.ZIndex = 5
	energyPreviewLabel.Parent = topRow

	timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.Size = UDim2.new(0.4, 0, 1, 0)
	timerLabel.AnchorPoint = Vector2.new(1, 0)
	timerLabel.Position = UDim2.new(1, -6, 0, 0)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text = ""
	timerLabel.TextColor3 = COLORS.timerNormal
	timerLabel.TextSize = 22
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.TextXAlignment = Enum.TextXAlignment.Right
	timerLabel.ZIndex = 4
	timerLabel.Parent = topRow

	-- Hand area (2 columns x 3 rows, manually positioned, max 6 cards)
	handFrame = Instance.new("Frame")
	handFrame.Name = "HandArea"
	handFrame.Size = UDim2.new(1, -12, 1, -112)
	handFrame.Position = UDim2.new(0, 6, 0, 58)
	handFrame.BackgroundTransparency = 1
	handFrame.BorderSizePixel = 0
	handFrame.ZIndex = 3
	handFrame.Parent = sidebar

	-- Confirm button (bottom of sidebar)
	confirmButton = Instance.new("TextButton")
	confirmButton.Name = "ConfirmButton"
	confirmButton.Size = UDim2.new(1, -16, 0, 44)
	confirmButton.AnchorPoint = Vector2.new(0, 1)
	confirmButton.Position = UDim2.new(0, 8, 1, -6)
	confirmButton.BackgroundColor3 = COLORS.confirm
	confirmButton.BorderSizePixel = 0
	confirmButton.Text = "Confirm"
	confirmButton.TextColor3 = COLORS.textWhite
	confirmButton.TextSize = 18
	confirmButton.Font = Enum.Font.GothamBold
	confirmButton.ZIndex = 4
	confirmButton.Parent = sidebar

	local confirmCorner = Instance.new("UICorner")
	confirmCorner.CornerRadius = UDim.new(0, 8)
	confirmCorner.Parent = confirmButton

	confirmButton.MouseEnter:Connect(function()
		if submitted then return end
		playTween("confirmHover", confirmButton,
			TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundColor3 = COLORS.confirmHover }
		)
	end)

	confirmButton.MouseLeave:Connect(function()
		if submitted then return end
		playTween("confirmLeave", confirmButton,
			TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundColor3 = COLORS.confirm }
		)
	end)

	confirmButton.MouseButton1Click:Connect(function()
		onConfirmClicked()
	end)

	waitingLabel = Instance.new("TextLabel")
	waitingLabel.Name = "WaitingLabel"
	waitingLabel.Size = UDim2.new(1, -16, 0, 44)
	waitingLabel.AnchorPoint = Vector2.new(0, 1)
	waitingLabel.Position = UDim2.new(0, 8, 1, -6)
	waitingLabel.BackgroundColor3 = COLORS.confirmDisabled
	waitingLabel.BorderSizePixel = 0
	waitingLabel.Text = "Waiting..."
	waitingLabel.TextColor3 = COLORS.textGray
	waitingLabel.TextSize = 16
	waitingLabel.Font = Enum.Font.GothamBold
	waitingLabel.Visible = false
	waitingLabel.ZIndex = 4
	waitingLabel.Parent = sidebar

	local waitCorner = Instance.new("UICorner")
	waitCorner.CornerRadius = UDim.new(0, 8)
	waitCorner.Parent = waitingLabel

	-- Timer urgency vignette (Phase 3E)
	vignetteFrame = Instance.new("Frame")
	vignetteFrame.Name = "Vignette"
	vignetteFrame.Size = UDim2.new(1, 0, 1, 0)
	vignetteFrame.BackgroundTransparency = 1
	vignetteFrame.BorderSizePixel = 0
	vignetteFrame.Visible = false
	vignetteFrame.ZIndex = 25
	vignetteFrame.Parent = bg

	local vignetteGradient = Instance.new("UIGradient")
	vignetteGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 30, 30)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(0, 0, 0)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(0, 0, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 30, 30)),
	})
	vignetteGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.4, 1),
		NumberSequenceKeypoint.new(0.6, 1),
		NumberSequenceKeypoint.new(1, 0.5),
	})
	vignetteGradient.Parent = vignetteFrame

	createDetailOverlay(bg)
	createGameOverOverlay(bg)
end

function createLocationPanel(locIdx, parent)
	local panel = Instance.new("Frame")
	panel.Name = "Location" .. locIdx
	panel.Size = UDim2.new(0.48, 0, 1, 0)
	panel.BackgroundColor3 = COLORS.panel
	panel.BorderSizePixel = 0
	panel.Parent = parent

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 8)
	panelCorner.Parent = panel

	-- Panel glow stroke (Phase 2B)
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Name = "PanelStroke"
	panelStroke.Color = COLORS.panelGlow
	panelStroke.Thickness = 2
	panelStroke.Transparency = 0.5
	panelStroke.Parent = panel

	-- Panel gradient (lighter center, darker edges — raised surface feel)
	local panelGradient = Instance.new("UIGradient")
	panelGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 31, 45)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(36, 40, 58)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(36, 40, 58)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(28, 31, 45)),
	})
	panelGradient.Rotation = 90
	panelGradient.Parent = panel

	-- Inner bevel stroke
	-- (Using panel's main stroke for glow, the gradient handles the bevel feel)

	-- Opponent grid (top ~35%) with tinted background
	local oppGrid = Instance.new("Frame")
	oppGrid.Name = "OppGrid"
	oppGrid.Size = UDim2.new(0.92, 0, 0.30, 0)
	oppGrid.Position = UDim2.new(0.04, 0, 0.03, 0)
	oppGrid.BackgroundColor3 = COLORS.oppRow
	oppGrid.BackgroundTransparency = 0.3
	oppGrid.Parent = panel

	local oppGridCorner = Instance.new("UICorner")
	oppGridCorner.CornerRadius = UDim.new(0, 4)
	oppGridCorner.Parent = oppGrid

	createSlotGrid(oppGrid, locIdx, false)

	-- === CENTER INFO BAND (location divider, ~18%) ===
	local centerBand = Instance.new("Frame")
	centerBand.Name = "CenterBand"
	centerBand.Size = UDim2.new(0.92, 0, 0.18, 0)
	centerBand.Position = UDim2.new(0.04, 0, 0.35, 0)
	centerBand.BackgroundColor3 = COLORS.centerBand
	centerBand.BackgroundTransparency = 0.3
	centerBand.BorderSizePixel = 0
	centerBand.Parent = panel

	local centerBandCorner = Instance.new("UICorner")
	centerBandCorner.CornerRadius = UDim.new(0, 4)
	centerBandCorner.Parent = centerBand

	-- Point value badge (circular, gold, left of name)
	local pointBadge = Instance.new("Frame")
	pointBadge.Name = "PointBadge"
	pointBadge.Size = UDim2.new(0, 22, 0, 22)
	pointBadge.Position = UDim2.new(0.05, 0, 0.15, 0)
	pointBadge.BackgroundColor3 = Color3.fromRGB(200, 160, 40)
	pointBadge.BorderSizePixel = 0
	pointBadge.ZIndex = 3
	pointBadge.Parent = centerBand

	local pointBadgeCorner = Instance.new("UICorner")
	pointBadgeCorner.CornerRadius = UDim.new(1, 0)
	pointBadgeCorner.Parent = pointBadge

	local pointBadgeText = Instance.new("TextLabel")
	pointBadgeText.Name = "PointText"
	pointBadgeText.Size = UDim2.new(1, 0, 1, 0)
	pointBadgeText.BackgroundTransparency = 1
	pointBadgeText.Text = "0"
	pointBadgeText.TextColor3 = COLORS.textWhite
	pointBadgeText.TextSize = 14
	pointBadgeText.Font = Enum.Font.GothamBold
	pointBadgeText.ZIndex = 4
	pointBadgeText.Parent = pointBadge

	-- Location name (centered, to the right of badge)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "LocationName"
	nameLabel.Size = UDim2.new(0.75, 0, 0.45, 0)
	nameLabel.Position = UDim2.new(0.2, 0, 0.05, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = "Location " .. locIdx
	nameLabel.TextColor3 = COLORS.textWhite
	nameLabel.TextSize = 17
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ZIndex = 3
	nameLabel.Parent = centerBand

	-- Location effect text (gold/amber tint)
	local effectLabel = Instance.new("TextLabel")
	effectLabel.Name = "EffectText"
	effectLabel.Size = UDim2.new(0.9, 0, 0.45, 0)
	effectLabel.Position = UDim2.new(0.05, 0, 0.52, 0)
	effectLabel.BackgroundTransparency = 1
	effectLabel.Text = ""
	effectLabel.TextColor3 = COLORS.textEffect
	effectLabel.TextSize = 12
	effectLabel.Font = Enum.Font.GothamMedium
	effectLabel.TextWrapped = true
	effectLabel.ZIndex = 3
	effectLabel.Parent = centerBand

	-- Player grid (bottom ~35%)
	local myGrid = Instance.new("Frame")
	myGrid.Name = "MyGrid"
	myGrid.Size = UDim2.new(0.92, 0, 0.30, 0)
	myGrid.Position = UDim2.new(0.04, 0, 0.55, 0)
	myGrid.BackgroundColor3 = COLORS.myRow
	myGrid.BackgroundTransparency = 0.3
	myGrid.Parent = panel

	local myGridCorner = Instance.new("UICorner")
	myGridCorner.CornerRadius = UDim.new(0, 4)
	myGridCorner.Parent = myGrid

	createSlotGrid(myGrid, locIdx, true)

	-- Power totals footer (~12%)
	local powerFrame = Instance.new("Frame")
	powerFrame.Name = "PowerFooter"
	powerFrame.Size = UDim2.new(0.92, 0, 0.10, 0)
	powerFrame.Position = UDim2.new(0.04, 0, 0.87, 0)
	powerFrame.BackgroundTransparency = 1
	powerFrame.Parent = panel

	local myPowerLabel = Instance.new("TextLabel")
	myPowerLabel.Name = "MyPower"
	myPowerLabel.Size = UDim2.new(0.45, 0, 0.6, 0)
	myPowerLabel.Position = UDim2.new(0.55, 0, 0, 0)
	myPowerLabel.BackgroundTransparency = 1
	myPowerLabel.Text = "You: 0"
	myPowerLabel.TextColor3 = COLORS.textWhite
	myPowerLabel.TextSize = 14
	myPowerLabel.Font = Enum.Font.GothamBold
	myPowerLabel.TextXAlignment = Enum.TextXAlignment.Right
	myPowerLabel.Parent = powerFrame

	local oppPowerLabel = Instance.new("TextLabel")
	oppPowerLabel.Name = "OppPower"
	oppPowerLabel.Size = UDim2.new(0.45, 0, 0.6, 0)
	oppPowerLabel.Position = UDim2.new(0, 0, 0, 0)
	oppPowerLabel.BackgroundTransparency = 1
	oppPowerLabel.Text = "Opp: 0"
	oppPowerLabel.TextColor3 = COLORS.textWhite
	oppPowerLabel.TextSize = 14
	oppPowerLabel.Font = Enum.Font.GothamBold
	oppPowerLabel.TextXAlignment = Enum.TextXAlignment.Left
	oppPowerLabel.Parent = powerFrame

	-- Win/Loss status badge (Phase 5A)
	local statusBadge = Instance.new("TextLabel")
	statusBadge.Name = "StatusBadge"
	statusBadge.Size = UDim2.new(1, 0, 0.4, 0)
	statusBadge.Position = UDim2.new(0, 0, 0.6, 0)
	statusBadge.BackgroundTransparency = 1
	statusBadge.Text = ""
	statusBadge.TextColor3 = COLORS.textGray
	statusBadge.TextSize = 10
	statusBadge.Font = Enum.Font.GothamBold
	statusBadge.Parent = powerFrame

	return {
		frame = panel,
		myGrid = myGrid,
		oppGrid = oppGrid,
		centerBand = centerBand,
		nameLabel = nameLabel,
		effectLabel = effectLabel,
		pointBadge = pointBadge,
		pointBadgeText = pointBadgeText,
		myPowerLabel = myPowerLabel,
		oppPowerLabel = oppPowerLabel,
		statusBadge = statusBadge,
		panelStroke = panelStroke,
	}
end

function createSlotGrid(parent, locIdx, isMine)
	-- Use UIListLayout to center portrait slots horizontally
	local gridLayout = Instance.new("UIListLayout")
	gridLayout.FillDirection = Enum.FillDirection.Horizontal
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	gridLayout.Padding = UDim.new(0.02, 0)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = parent

	local gridPadding = Instance.new("UIPadding")
	gridPadding.PaddingTop = UDim.new(0.02, 0)
	gridPadding.PaddingBottom = UDim.new(0.02, 0)
	gridPadding.Parent = parent

	for row = 1, GameConfig.GRID_ROWS do
		for col = 1, GameConfig.GRID_COLUMNS do
			local slotFrame = Instance.new("TextButton")
			slotFrame.Name = string.format("Slot_%d_%d", col, row)
			slotFrame.LayoutOrder = (row - 1) * GameConfig.GRID_COLUMNS + col
			-- Height fills the grid, width set by aspect ratio constraint
			slotFrame.Size = UDim2.new(0.3, 0, 0.96, 0)
			slotFrame.BackgroundColor3 = isMine and COLORS.slotEmpty or COLORS.slotEmptyOpp
			slotFrame.BackgroundTransparency = 0.3
			slotFrame.BorderSizePixel = 0
			slotFrame.Text = ""
			slotFrame.AutoButtonColor = false
			slotFrame.Parent = parent

			local slotCorner = Instance.new("UICorner")
			slotCorner.CornerRadius = UDim.new(0, 5)
			slotCorner.Parent = slotFrame

			-- Force portrait 3:4 aspect ratio
			local aspectConstraint = Instance.new("UIAspectRatioConstraint")
			aspectConstraint.AspectRatio = 3 / 4
			aspectConstraint.DominantAxis = Enum.DominantAxis.Height
			aspectConstraint.Parent = slotFrame

			local slotStroke = Instance.new("UIStroke")
			slotStroke.Name = "SlotStroke"
			slotStroke.Color = COLORS.slotBorder
			slotStroke.Thickness = 1
			slotStroke.Parent = slotFrame

			if isMine then
				slotFrame.MouseButton1Click:Connect(function()
					onSlotClicked(locIdx, col, row)
				end)
			else
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
	detailOverlay.BackgroundTransparency = 0.4
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
		local container = detailOverlay:FindFirstChild("CardContainer")
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Frame") then child:Destroy() end
			end
		end
	end)

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
	gameOverOverlay.BackgroundTransparency = 1
	gameOverOverlay.BorderSizePixel = 0
	gameOverOverlay.Visible = false
	gameOverOverlay.ZIndex = 20
	gameOverOverlay.Parent = parent

	local resultLabel = Instance.new("TextLabel")
	resultLabel.Name = "ResultLabel"
	resultLabel.Size = UDim2.new(0.6, 0, 0.12, 0)
	resultLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	resultLabel.Position = UDim2.new(0.5, 0, 0.30, 0)
	resultLabel.BackgroundTransparency = 1
	resultLabel.Text = "VICTORY!"
	resultLabel.TextColor3 = COLORS.victory
	resultLabel.TextSize = 52
	resultLabel.Font = Enum.Font.GothamBold
	resultLabel.TextTransparency = 1
	resultLabel.ZIndex = 21
	resultLabel.Parent = gameOverOverlay

	local finalScoreLabel = Instance.new("TextLabel")
	finalScoreLabel.Name = "FinalScore"
	finalScoreLabel.Size = UDim2.new(0.5, 0, 0.06, 0)
	finalScoreLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	finalScoreLabel.Position = UDim2.new(0.5, 0, 0.42, 0)
	finalScoreLabel.BackgroundTransparency = 1
	finalScoreLabel.Text = "Final Score: 0 - 0"
	finalScoreLabel.TextColor3 = COLORS.textWhite
	finalScoreLabel.TextSize = 22
	finalScoreLabel.Font = Enum.Font.Gotham
	finalScoreLabel.TextTransparency = 1
	finalScoreLabel.ZIndex = 21
	finalScoreLabel.Parent = gameOverOverlay

	-- Location breakdown (Phase 6B)
	local breakdownLabel = Instance.new("TextLabel")
	breakdownLabel.Name = "Breakdown"
	breakdownLabel.Size = UDim2.new(0.6, 0, 0.12, 0)
	breakdownLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	breakdownLabel.Position = UDim2.new(0.5, 0, 0.52, 0)
	breakdownLabel.BackgroundTransparency = 1
	breakdownLabel.Text = ""
	breakdownLabel.TextColor3 = COLORS.textWhite
	breakdownLabel.TextSize = 14
	breakdownLabel.Font = Enum.Font.Gotham
	breakdownLabel.TextWrapped = true
	breakdownLabel.TextTransparency = 1
	breakdownLabel.ZIndex = 21
	breakdownLabel.Parent = gameOverOverlay

	-- Button container
	local buttonContainer = Instance.new("Frame")
	buttonContainer.Name = "ButtonContainer"
	buttonContainer.Size = UDim2.new(0.6, 0, 0.06, 0)
	buttonContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	buttonContainer.Position = UDim2.new(0.5, 0, 0.68, 0)
	buttonContainer.BackgroundTransparency = 1
	buttonContainer.ZIndex = 21
	buttonContainer.Parent = gameOverOverlay

	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	buttonLayout.Padding = UDim.new(0, 12)
	buttonLayout.Parent = buttonContainer

	-- Play Again button
	local playAgainButton = Instance.new("TextButton")
	playAgainButton.Name = "PlayAgainButton"
	playAgainButton.Size = UDim2.new(0, 150, 0, 40)
	playAgainButton.BackgroundColor3 = COLORS.confirm
	playAgainButton.BorderSizePixel = 0
	playAgainButton.Text = "Play Again"
	playAgainButton.TextColor3 = COLORS.textWhite
	playAgainButton.TextSize = 18
	playAgainButton.Font = Enum.Font.GothamBold
	playAgainButton.TextTransparency = 1
	playAgainButton.BackgroundTransparency = 1
	playAgainButton.ZIndex = 22
	playAgainButton.Parent = buttonContainer

	local playAgainCorner = Instance.new("UICorner")
	playAgainCorner.CornerRadius = UDim.new(0, 8)
	playAgainCorner.Parent = playAgainButton

	playAgainButton.MouseButton1Click:Connect(function()
		-- Start new match directly
		gameOverOverlay.Visible = false
		matchActive = false
		submitted = false
		RequestBotMatchEvent:FireServer()
	end)

	-- Return to Lobby button
	local returnButton = Instance.new("TextButton")
	returnButton.Name = "ReturnButton"
	returnButton.Size = UDim2.new(0, 150, 0, 40)
	returnButton.BackgroundColor3 = COLORS.confirmDisabled
	returnButton.BorderSizePixel = 0
	returnButton.Text = "Return to Lobby"
	returnButton.TextColor3 = COLORS.textWhite
	returnButton.TextSize = 18
	returnButton.Font = Enum.Font.GothamBold
	returnButton.TextTransparency = 1
	returnButton.BackgroundTransparency = 1
	returnButton.ZIndex = 22
	returnButton.Parent = buttonContainer

	local returnCorner = Instance.new("UICorner")
	returnCorner.CornerRadius = UDim.new(0, 8)
	returnCorner.Parent = returnButton

	returnButton.MouseButton1Click:Connect(function()
		returnToLobby()
	end)
end

-- ============================================================
-- Game Over Reveal Animation (Phase 3G)
-- ============================================================

local function playGameOverReveal(resultData)
	if not gameOverOverlay then return end

	gameOverOverlay.Visible = true
	gameOverOverlay.BackgroundTransparency = 1

	local resultLabel = gameOverOverlay:FindFirstChild("ResultLabel")
	local finalScoreLabel = gameOverOverlay:FindFirstChild("FinalScore")
	local breakdownLabel = gameOverOverlay:FindFirstChild("Breakdown")
	local buttonContainer = gameOverOverlay:FindFirstChild("ButtonContainer")

	-- Step 1: Dim overlay fades in (0.4s)
	TweenService:Create(gameOverOverlay,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.25 }
	):Play()

	-- Step 2: Result text scales in with bounce (delayed 0.3s)
	task.delay(0.3, function()
		if resultLabel then
			resultLabel.TextTransparency = 0
			resultLabel.Size = UDim2.new(0.3, 0, 0.06, 0)
			TweenService:Create(resultLabel,
				TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = UDim2.new(0.6, 0, 0.12, 0) }
			):Play()
		end
	end)

	-- Step 3: Final score + breakdown fades in (delayed 0.7s)
	task.delay(0.7, function()
		if finalScoreLabel then
			TweenService:Create(finalScoreLabel,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ TextTransparency = 0 }
			):Play()
		end
		if breakdownLabel then
			TweenService:Create(breakdownLabel,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ TextTransparency = 0 }
			):Play()
		end
	end)

	-- Step 4: Buttons slide up + fade in (delayed 1.0s)
	task.delay(1.0, function()
		if buttonContainer then
			for _, btn in ipairs(buttonContainer:GetChildren()) do
				if btn:IsA("TextButton") then
					btn.BackgroundTransparency = 0
					TweenService:Create(btn,
						TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ TextTransparency = 0 }
					):Play()
				end
			end
		end
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
	if oppLabel then oppLabel.Text = tostring(oppScore) end
	if myLabel then myLabel.Text = tostring(myScore) end
	if turnLbl then turnLbl.Text = "TURN " .. currentTurn end

	-- Update progress bar (Phase 5D)
	if progressBarPlayer then
		local playerProg = math.clamp(myScore / GameConfig.POINTS_TO_WIN, 0, 1)
		playTween("progressPlayer", progressBarPlayer,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.new(playerProg, 0, 1, 0) }
		)
	end
	if progressBarOpp then
		local oppProg = math.clamp(oppScore / GameConfig.POINTS_TO_WIN, 0, 1)
		playTween("progressOpp", progressBarOpp,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.new(oppProg, 0, 1, 0) }
		)
	end
end

local function updateEnergyDisplay()
	if not energyNumberLabel then return end
	local available = myEnergy - energySpent
	energyNumberLabel.Text = tostring(available)
	if energyMaxLabel then
		energyMaxLabel.Text = "/ " .. myEnergy
	end

	-- Update ring color
	local ring = energyFrame and energyFrame:FindFirstChild("EnergyRing")
	if ring then
		if available == 0 then
			ring.Color = COLORS.textGray
			energyNumberLabel.TextColor3 = COLORS.textGray
		else
			ring.Color = COLORS.energyColor
			energyNumberLabel.TextColor3 = COLORS.energyColor
		end
	end

	-- Energy cost preview (Phase 5C)
	if energyPreviewLabel then
		local previewCardID = selectedCardID or draggingCardID
		if previewCardID then
			local def = CardDatabase[previewCardID]
			if def then
				energyPreviewLabel.Text = "(-" .. def.cost .. ")"
				energyPreviewLabel.Visible = true
			end
		else
			energyPreviewLabel.Visible = false
		end
	end
end

local function updateLocationInfo()
	for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
		local lf = locationFrames[locIdx]
		if lf and locations[locIdx] then
			local loc = locations[locIdx]
			lf.nameLabel.Text = loc.name or ("Loc " .. locIdx)
			lf.effectLabel.Text = loc.effectText or ""
			-- Update point badge
			if lf.pointBadgeText then
				lf.pointBadgeText.Text = tostring(loc.pointValue or 0)
			end
		end
	end
end

local function clearSlotContents(gridFrame)
	for _, slotFrame in ipairs(gridFrame:GetChildren()) do
		if slotFrame:IsA("GuiButton") then
			for _, child in ipairs(slotFrame:GetChildren()) do
				if child:IsA("Frame") then
					child:Destroy()
				end
			end
			local stroke = slotFrame:FindFirstChild("SlotStroke")
			if stroke then
				stroke.Color = COLORS.slotBorder
				stroke.Thickness = 1
			end
		end
	end
end

local function renderCardInSlot(slotFrame, cardID, power, basePower, isPending)
	for _, child in ipairs(slotFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local cardF = CardFrame.create(cardID, "board", power)
	if cardF then
		cardF.Size = UDim2.new(1, -8, 1, -8)
		cardF.Position = UDim2.new(0, 4, 0, 4)
		cardF.ZIndex = 2
		cardF.Parent = slotFrame

		if power and basePower then
			CardFrame.updatePower(cardF, power, basePower)
		end

		if isPending then
			cardF.BackgroundTransparency = 0.35
			local stroke = slotFrame:FindFirstChild("SlotStroke")
			if stroke then
				stroke.Color = COLORS.slotHighlight
				stroke.Thickness = 2
			end

			-- Pending card pulsing transparency (Phase 3B)
			pulseProperty(cardF, "BackgroundTransparency", 0.3, 0.45, 0.75)
		end
	end

	slotFrame.BackgroundTransparency = 0
	if isPending then
		slotFrame.BackgroundColor3 = COLORS.pending
	else
		slotFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
	end
end

local function renderBoard(boards, gridKey)
	if not boards then return end
	for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
		local lf = locationFrames[locIdx]
		if not lf then continue end

		local grid = lf[gridKey]
		clearSlotContents(grid)

		local board = boards[locIdx]
		if not board then continue end

		for row = 1, GameConfig.GRID_ROWS do
			for col = 1, GameConfig.GRID_COLUMNS do
				local slotName = string.format("Slot_%d_%d", col, row)
				local slotFrame = grid:FindFirstChild(slotName)
				if not slotFrame then continue end

				local cardState = board[row] and board[row][col]
				if cardState then
					local cardID = type(cardState) == "table" and cardState.cardID or cardState
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

local function renderMyBoard(myBoards)
	renderBoard(myBoards, "myGrid")
end

local function renderOppBoard(oppBoards)
	renderBoard(oppBoards, "oppGrid")
end

local function renderHand()
	for _, frame in ipairs(handCardFrames) do
		if frame and frame.Parent then frame:Destroy() end
	end
	handCardFrames = {}

	if not handFrame then return end

	-- Calculate card positions for 2x3 grid manually
	local cols = 2
	local rows = 3
	local padX = 6
	local padY = 6
	local handW = handFrame.AbsoluteSize.X
	local handH = handFrame.AbsoluteSize.Y
	-- Fallback if AbsoluteSize not ready
	if handW < 10 then handW = 300 end
	if handH < 10 then handH = 700 end

	local cardW = math.floor((handW - padX * (cols + 1)) / cols)
	local cardH = math.floor(cardW * 4 / 3)  -- 3:4 portrait
	-- If cards are too tall for 3 rows, shrink based on height
	local maxCardH = math.floor((handH - padY * (rows + 1)) / rows)
	if cardH > maxCardH then
		cardH = maxCardH
		cardW = math.floor(cardH * 3 / 4)
	end

	local slotIndex = 0
	for i, cardID in ipairs(myHand) do
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

		local available = myEnergy - energySpent
		local canAfford = def.cost <= available

		-- Position in 2-column grid
		local col = slotIndex % cols
		local row = math.floor(slotIndex / cols)
		slotIndex = slotIndex + 1
		if row >= rows then break end  -- max 6 visible cards

		local xPos = padX + col * (cardW + padX)
		local yPos = padY + row * (cardH + padY)

		local cardF = CardFrame.create(cardID, "hand")
		if cardF then
			cardF.Size = UDim2.new(0, cardW, 0, cardH)
			cardF.Position = UDim2.new(0, xPos, 0, yPos)

			-- Unaffordable: dim
			if not canAfford then
				cardF.BackgroundTransparency = 0.4
			end

			-- Dim if being dragged
			if draggingCardID == cardID and draggingCardIndex == i then
				cardF.BackgroundTransparency = 0.6
			end

			cardF.Parent = handFrame

			-- Click area (transparent button on top of card)
			local clickArea = Instance.new("TextButton")
			clickArea.Name = "ClickArea"
			clickArea.Size = UDim2.new(1, 0, 1, 0)
			clickArea.BackgroundTransparency = 1
			clickArea.Text = ""
			clickArea.ZIndex = 6
			clickArea.Parent = cardF

			local cardIndex = i
			local cID = cardID
			local thisCardFrame = cardF
			clickArea.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch then
					startDrag(cID, cardIndex, thisCardFrame, input)
				end
			end)

			table.insert(handCardFrames, cardF)
		end
	end
end

local function renderPendingPlays()
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
	-- Reset all slot highlights first
	for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
		local lf = locationFrames[locIdx]
		if not lf then continue end
		for _, slotFrame in ipairs(lf.myGrid:GetChildren()) do
			if slotFrame:IsA("GuiButton") then
				local stroke = slotFrame:FindFirstChild("SlotStroke")
				if stroke then
					local hasCard = false
					for _, child in ipairs(slotFrame:GetChildren()) do
						if child:IsA("Frame") then hasCard = true break end
					end
					if not hasCard then
						stroke.Color = COLORS.slotBorder
						stroke.Thickness = 1
					end
				end
				-- Cancel any pulsing tween on this slot
				cancelTween("slotPulse_" .. locIdx .. "_" .. slotFrame.Name)
			end
		end
	end

	local highlightCardID = selectedCardID or draggingCardID
	if not highlightCardID then return end

	local def = CardDatabase[highlightCardID]
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

				local isValid = LocationRestrictions.canPlayAt(loc, def, row)

				local hasPending = false
				for _, play in ipairs(pendingPlays) do
					if play.locIdx == locIdx and play.col == col and play.row == row then
						hasPending = true
						break
					end
				end

				if isValid and not hasPending then
					local hasCard = false
					for _, child in ipairs(slotFrame:GetChildren()) do
						if child:IsA("Frame") then hasCard = true break end
					end

					local highlightColor = hasCard and COLORS.slotOverwrite or COLORS.slotHighlight
					stroke.Color = highlightColor
					stroke.Thickness = 2

					-- Pulsing border animation (Phase 3C)
					pulseProperty(stroke, "Transparency", 0, 0.6, 0.5, function()
						return selectedCardID ~= nil or draggingCardID ~= nil
					end)
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
					if card and type(card) == "table" then
						myPower = myPower + (card.currentPower or card.basePower or 0)
					end
				end
			end
		end

		if oppBoards and oppBoards[locIdx] then
			for row = 1, GameConfig.GRID_ROWS do
				for col = 1, GameConfig.GRID_COLUMNS do
					local card = oppBoards[locIdx][row] and oppBoards[locIdx][row][col]
					if card and type(card) == "table" then
						oppPower = oppPower + (card.currentPower or card.basePower or 0)
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

		lf.myPowerLabel.Text = "You: " .. myPower
		lf.oppPowerLabel.Text = "Opp: " .. oppPower

		-- Color the power text + panel glow based on who's winning (Phase 5A)
		if myPower > oppPower then
			lf.myPowerLabel.TextColor3 = COLORS.textGreen
			lf.oppPowerLabel.TextColor3 = COLORS.textRed
			lf.statusBadge.Text = "WINNING"
			lf.statusBadge.TextColor3 = COLORS.textGreen
			playTween("panelGlow" .. locIdx, lf.panelStroke,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Color = COLORS.winGlow, Transparency = 0.3 }
			)
		elseif oppPower > myPower then
			lf.myPowerLabel.TextColor3 = COLORS.textRed
			lf.oppPowerLabel.TextColor3 = COLORS.textGreen
			lf.statusBadge.Text = "LOSING"
			lf.statusBadge.TextColor3 = COLORS.textRed
			playTween("panelGlow" .. locIdx, lf.panelStroke,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Color = COLORS.loseGlow, Transparency = 0.3 }
			)
		else
			lf.myPowerLabel.TextColor3 = COLORS.textWhite
			lf.oppPowerLabel.TextColor3 = COLORS.textWhite
			lf.statusBadge.Text = "TIED"
			lf.statusBadge.TextColor3 = COLORS.textGray
			playTween("panelGlow" .. locIdx, lf.panelStroke,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Color = COLORS.panelGlow, Transparency = 0.5 }
			)
		end
	end
end

-- ============================================================
-- Submission
-- ============================================================

local function submitPlays()
	if submitted then return end
	submitted = true

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

	timerRunning = false
	if confirmButton then confirmButton.Visible = false end
	if waitingLabel then
		waitingLabel.Visible = true
		-- Waiting pulsing text (Phase 3H)
		pulseProperty(waitingLabel, "TextTransparency", 0, 0.5, 0.75, function()
			return waitingLabel and waitingLabel.Visible
		end)
	end
end

-- ============================================================
-- Card Inspect & Drag-and-Drop
-- ============================================================

function showCardInspect(cardID, overridePower, pendingPlay)
	print("[MatchClient] showCardInspect:", cardID, "pending:", pendingPlay ~= nil)
	if not detailOverlay then return end
	local container = detailOverlay:FindFirstChild("CardContainer")
	if not container then return end

	-- Clear existing content
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextButton") then child:Destroy() end
	end

	local detailCard = CardFrame.create(cardID, "detail", overridePower)
	if detailCard then
		detailCard.ZIndex = 12
		detailCard.Parent = container
	end

	-- Show undo button for pending plays
	if pendingPlay then
		local undoBtn = Instance.new("TextButton")
		undoBtn.Name = "UndoButton"
		undoBtn.Size = UDim2.new(0, 140, 0, 36)
		undoBtn.Position = UDim2.new(0.5, 0, 1, 10)
		undoBtn.AnchorPoint = Vector2.new(0.5, 0)
		undoBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
		undoBtn.BorderSizePixel = 0
		undoBtn.Text = "Undo Play"
		undoBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		undoBtn.TextSize = 16
		undoBtn.Font = Enum.Font.GothamBold
		undoBtn.ZIndex = 12
		undoBtn.Parent = container

		local undoCorner = Instance.new("UICorner")
		undoCorner.CornerRadius = UDim.new(0, 6)
		undoCorner.Parent = undoBtn

		undoBtn.MouseButton1Click:Connect(function()
			for i, play in ipairs(pendingPlays) do
				if play == pendingPlay then
					local pDef = CardDatabase[play.cardID]
					if pDef then energySpent = energySpent - pDef.cost end
					table.remove(pendingPlays, i)
					break
				end
			end
			detailOverlay.Visible = false
			renderMyBoard(lastMyBoards)
			renderPendingPlays()
			renderHand()
			highlightValidSlots()
			updateEnergyDisplay()
			updatePowerTotals(lastMyBoards, lastOppBoards)
		end)
	end

	detailOverlay.Visible = true
end

function cleanupDrag()
	for _, conn in ipairs(dragConnections) do
		conn:Disconnect()
	end
	dragConnections = {}

	if dragGhost then
		dragGhost:Destroy()
		dragGhost = nil
	end

	-- Reset hovered slot highlight
	if lastHoveredSlot then
		local stroke = lastHoveredSlot:FindFirstChild("SlotStroke")
		if stroke then
			stroke.Color = COLORS.slotBorder
			stroke.Thickness = 1
		end
		lastHoveredSlot = nil
	end

	draggingCardID = nil
	draggingCardIndex = nil
	isDragging = false
end

function findSlotUnderPosition(absX, absY)
	for locIdx = 1, GameConfig.LOCATIONS_PER_GAME do
		local lf = locationFrames[locIdx]
		if not lf then continue end

		for col = 1, GameConfig.GRID_COLUMNS do
			local slotName = string.format("Slot_%d_%d", col, 1)
			local slotFrame = lf.myGrid:FindFirstChild(slotName)
			if not slotFrame then continue end

			local slotPos = slotFrame.AbsolutePosition
			local slotSize = slotFrame.AbsoluteSize

			-- Match based on horizontal column alignment
			if absX >= slotPos.X and absX <= slotPos.X + slotSize.X then
				return locIdx, col, 1, slotFrame
			end
		end
	end
	return nil, nil, nil, nil
end

function startDrag(cardID, cardIndex, cardFrame, input)
	print("[MatchClient] startDrag called:", cardID, "input:", input.UserInputType.Name)
	if draggingCardID then return end
	if not matchActive or submitted then return end

	local def = CardDatabase[cardID]
	if not def then return end

	draggingCardID = cardID
	draggingCardIndex = cardIndex
	isDragging = false
	local startPos = Vector2.new(input.Position.X, input.Position.Y)
	local canAfford = def.cost <= (myEnergy - energySpent)

	local moveConn = UserInputService.InputChanged:Connect(function(changedInput)
		if changedInput.UserInputType ~= Enum.UserInputType.MouseMovement
			and changedInput.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local mousePos = Vector2.new(changedInput.Position.X, changedInput.Position.Y)

		if not isDragging then
			local delta = (mousePos - startPos).Magnitude
			if delta < 5 then return end

			-- Threshold exceeded — try to start drag
			if not canAfford then
				showToast("Not enough energy")
				if energyFrame then
					local ring = energyFrame:FindFirstChild("EnergyRing")
					if ring then
						local origColor = ring.Color
						ring.Color = COLORS.textRed
						task.delay(0.3, function()
							if ring and ring.Parent then ring.Color = origColor end
						end)
					end
				end
				cleanupDrag()
				return
			end

			isDragging = true

			-- Create drag ghost
			dragGhost = CardFrame.create(cardID, "hand")
			if dragGhost then
				local cardSize = cardFrame.AbsoluteSize
				dragGhost.Size = UDim2.new(0, cardSize.X, 0, cardSize.Y)
				dragGhost.AnchorPoint = Vector2.new(0.5, 0.5)
				dragGhost.BackgroundTransparency = 0.3
				dragGhost.ZIndex = 15
				for _, desc in ipairs(dragGhost:GetDescendants()) do
					if desc:IsA("GuiObject") then
						desc.ZIndex = desc.ZIndex + 12
					end
				end
				dragGhost.Parent = matchGui
			end

			-- Dim original card in hand
			cardFrame.BackgroundTransparency = 0.6

			-- Highlight valid drop slots
			highlightValidSlots()
			updateEnergyDisplay()
		end

		-- Update ghost position
		if dragGhost then
			dragGhost.Position = UDim2.new(0, mousePos.X, 0, mousePos.Y)

			-- Update hover highlight on closest slot
			local hLocIdx, hCol, hRow, hSlotFrame = findSlotUnderPosition(mousePos.X, mousePos.Y)
			if lastHoveredSlot and lastHoveredSlot ~= hSlotFrame then
				local hStroke = lastHoveredSlot:FindFirstChild("SlotStroke")
				if hStroke then hStroke.Thickness = 2 end
			end
			if hSlotFrame then
				local hStroke = hSlotFrame:FindFirstChild("SlotStroke")
				if hStroke then
					hStroke.Color = COLORS.slotHighlight
					hStroke.Thickness = 3
				end
				lastHoveredSlot = hSlotFrame
			else
				lastHoveredSlot = nil
			end
		end
	end)

	local endConn = UserInputService.InputEnded:Connect(function(endedInput)
		if endedInput.UserInputType ~= Enum.UserInputType.MouseButton1
			and endedInput.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		if isDragging then
			local mousePos = Vector2.new(endedInput.Position.X, endedInput.Position.Y)
			local locIdx, col, row, slotFrame = findSlotUnderPosition(mousePos.X, mousePos.Y)

			if locIdx then
				local loc = locations[locIdx]
				local canPlay, restrictReason = LocationRestrictions.canPlayAt(loc, def, row)

				local hasPending = false
				for _, play in ipairs(pendingPlays) do
					if play.locIdx == locIdx and play.col == col and play.row == row then
						hasPending = true
						break
					end
				end

				if canPlay and not hasPending then
					table.insert(pendingPlays, {
						cardID = cardID,
						locIdx = locIdx,
						col = col,
						row = row,
						handIndex = cardIndex,
					})
					energySpent = energySpent + def.cost

					print(string.format("[Client] Pending: %s at loc %d (%d,%d)", cardID, locIdx, col, row))

					cleanupDrag()
					renderMyBoard(lastMyBoards)
					renderPendingPlays()
					renderHand()
					highlightValidSlots()
					updateEnergyDisplay()
					updatePowerTotals(lastMyBoards, lastOppBoards)
					return
				elseif not canPlay then
					showToast(restrictReason)
				elseif hasPending then
					showToast("Slot already has a pending play")
				end
			end

			-- Drop failed or missed — cancel drag
			cleanupDrag()
			renderHand()
			highlightValidSlots()
			updateEnergyDisplay()
		else
			-- Was just a click (no drag) — inspect the card
			local cID = draggingCardID
			cleanupDrag()
			if cID then
				showCardInspect(cID)
			end
		end
	end)

	table.insert(dragConnections, moveConn)
	table.insert(dragConnections, endConn)
end

-- ============================================================
-- Interaction Handlers
-- ============================================================

function onHandCardClicked(cardID, cardIndex)
	if not matchActive or submitted then return end
	showCardInspect(cardID)
end

function onSlotClicked(locIdx, col, row)
	if not matchActive or submitted then return end
	if draggingCardID then return end

	-- Check if there's a pending play here — inspect with undo option
	for _, play in ipairs(pendingPlays) do
		if play.locIdx == locIdx and play.col == col and play.row == row then
			showCardInspect(play.cardID, nil, play)
			return
		end
	end

	-- Check if there's a committed card here — inspect it
	if lastMyBoards then
		local board = lastMyBoards[locIdx]
		if board then
			local cardState = board[1] and board[1][col]
			if cardState then
				local cardID = type(cardState) == "table" and cardState.cardID or cardState
				local power = type(cardState) == "table" and cardState.currentPower or nil
				showCardInspect(cardID, power)
				return
			end
		end
	end
end

function onOppSlotClicked(locIdx, col, row)
	if draggingCardID then return end
	-- Show detail overlay for opponent's card (Phase 5E)
	if not lastOppBoards then return end
	local board = lastOppBoards[locIdx]
	if not board then return end

	local cardState = board[1] and board[1][col]  -- row is always 1 with 1x3 grid
	if not cardState then return end

	local cardID = type(cardState) == "table" and cardState.cardID or cardState
	if not cardID then return end

	-- Show detail overlay
	if detailOverlay then
		local container = detailOverlay:FindFirstChild("CardContainer")
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Frame") then child:Destroy() end
			end

			local power = type(cardState) == "table" and cardState.currentPower or nil
			local detailCard = CardFrame.create(cardID, "detail", power)
			if detailCard then
				detailCard.ZIndex = 12
				detailCard.Parent = container

				-- Red-tinted border for opponent's card
				local rarityStroke = detailCard:FindFirstChildWhichIsA("UIStroke")
				if rarityStroke then
					rarityStroke.Color = Color3.fromRGB(200, 80, 80)
				end
			end

			detailOverlay.Visible = true
		end
	end
end

function onConfirmClicked()
	if not matchActive or submitted then return end
	submitPlays()
end

function returnToLobby()
	matchActive = false
	submitted = false
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

	screenTransition(function()
		if matchGui then
			matchGui.Enabled = false
		end
		if gameOverOverlay then
			gameOverOverlay.Visible = false
		end
		if lobbyGui then
			lobbyGui.Enabled = true
			local bg = lobbyGui:FindFirstChild("LobbyBG")
			if bg then
				local botBtn = bg:FindFirstChild("PlayBotButton")
				if botBtn then
					botBtn.Text = "Play vs Bot"
					botBtn.BackgroundColor3 = COLORS.confirm
				end
			end
		end
	end)
end

-- ============================================================
-- Timer (Phase 3E urgency escalation)
-- ============================================================

local function startTimer(seconds)
	timerSeconds = seconds
	timerRunning = true

	task.spawn(function()
		while timerRunning and timerSeconds > 0 do
			timerSeconds = timerSeconds - 1
			if timerLabel then
				timerLabel.Text = tostring(timerSeconds)

				if timerSeconds <= 3 then
					-- Critical: red, fast pulse, vignette intensifies
					timerLabel.TextColor3 = COLORS.timerWarning
					timerLabel.TextSize = 24
					if vignetteFrame then
						vignetteFrame.Visible = true
						vignetteFrame.BackgroundTransparency = 0.6
					end
				elseif timerSeconds <= 5 then
					-- Urgent: red, faster pulse, vignette starts
					timerLabel.TextColor3 = COLORS.timerWarning
					timerLabel.TextSize = 23
					if vignetteFrame then
						vignetteFrame.Visible = true
						vignetteFrame.BackgroundTransparency = 0.8
					end
				elseif timerSeconds <= 10 then
					-- Warning: amber, slow pulse
					timerLabel.TextColor3 = COLORS.timerAmber
					timerLabel.TextSize = 22
				else
					-- Normal
					timerLabel.TextColor3 = COLORS.timerNormal
					timerLabel.TextSize = 20
				end
			end
			task.wait(1)
		end

		-- Hide vignette when timer stops
		if vignetteFrame then
			vignetteFrame.Visible = false
		end

		if timerRunning and not submitted then
			print("[Client] Timer expired — auto-submitting")
			submitPlays()
		end
	end)
end

-- ============================================================
-- Score Animation (Phase 3F)
-- ============================================================

local function animateScoreChange(label, delta)
	if not label or not label.Parent then return end
	if delta == 0 then return end

	-- Floating "+N" or "-N" label
	local floater = Instance.new("TextLabel")
	floater.Size = UDim2.new(0, 50, 0, 25)
	floater.AnchorPoint = Vector2.new(0.5, 1)
	floater.Position = UDim2.new(0.5, 0, 0, 0)
	floater.BackgroundTransparency = 1
	floater.Text = (delta > 0 and "+" or "") .. tostring(delta)
	floater.TextColor3 = delta > 0 and COLORS.textGreen or COLORS.textRed
	floater.TextSize = 16
	floater.Font = Enum.Font.GothamBold
	floater.ZIndex = label.ZIndex + 1
	floater.Parent = label.Parent

	-- Float up and fade
	local floatTween = TweenService:Create(floater,
		TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, -0.5, 0), TextTransparency = 1 }
	)
	floatTween:Play()
	floatTween.Completed:Connect(function()
		floater:Destroy()
	end)

	-- Score number scale pulse
	local origSize = label.TextSize
	label.TextSize = origSize + 6
	task.delay(0.15, function()
		if label and label.Parent then
			TweenService:Create(label,
				TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ TextSize = origSize }
			):Play()
		end
	end)
end

-- ============================================================
-- Server Event Handlers
-- ============================================================

TurnStartEvent.OnClientEvent:Connect(function(state)
	if not matchActive then
		matchActive = true
		screenTransition(function()
			if lobbyGui then lobbyGui.Enabled = false end
			createMatchUI()
			matchGui.Enabled = true
		end)
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
	submitted = false
	lastMyBoards = state.myBoards
	lastOppBoards = state.oppBoards

	updateScoreDisplay()
	updateEnergyDisplay()
	updateLocationInfo()
	renderMyBoard(state.myBoards)
	renderOppBoard(state.oppBoards)
	renderHand()
	highlightValidSlots()
	updatePowerTotals(state.myBoards, state.oppBoards)

	if confirmButton then confirmButton.Visible = true end
	if waitingLabel then waitingLabel.Visible = false end

	startTimer(GameConfig.TURN_TIMER_SECONDS)
end)

RevealResultEvent.OnClientEvent:Connect(function(resultData)
	print(string.format("[Client] Reveal results for turn %d", resultData.turn))

	timerRunning = false
	if vignetteFrame then vignetteFrame.Visible = false end

	lastMyBoards = resultData.myBoards
	lastOppBoards = resultData.oppBoards
	renderMyBoard(resultData.myBoards)
	renderOppBoard(resultData.oppBoards)
	updatePowerTotals(resultData.myBoards, resultData.oppBoards)

	pendingPlays = {}
	selectedCardID = nil
	selectedCardIndex = nil
end)

ScoreUpdateEvent.OnClientEvent:Connect(function(scoreData)
	local oldMyScore = myScore
	local oldOppScore = oppScore
	myScore = scoreData.myScore
	oppScore = scoreData.oppScore
	updateScoreDisplay()

	-- Animated score changes (Phase 3F)
	if scoreBar then
		local myLabel = scoreBar:FindFirstChild("MyScore")
		local oppLabel = scoreBar:FindFirstChild("OppScore")
		animateScoreChange(myLabel, myScore - oldMyScore)
		animateScoreChange(oppLabel, oppScore - oldOppScore)
	end
end)

GameOverEvent.OnClientEvent:Connect(function(resultData)
	print("[Client] Game Over!")
	matchActive = false
	timerRunning = false
	if vignetteFrame then vignetteFrame.Visible = false end

	if not gameOverOverlay then return end

	local resultLabel = gameOverOverlay:FindFirstChild("ResultLabel")
	local finalScoreLabel = gameOverOverlay:FindFirstChild("FinalScore")
	local breakdownLabel = gameOverOverlay:FindFirstChild("Breakdown")

	if resultData.won then
		if resultLabel then
			resultLabel.Text = "VICTORY!"
			resultLabel.TextColor3 = COLORS.victory
		end
	elseif resultData.draw then
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
		local myFinalScore = resultData.myFinalScore or 0
		local oppFinalScore = resultData.oppFinalScore or 0
		finalScoreLabel.Text = string.format("Final Score: %d - %d  |  Turns: %d",
			myFinalScore, oppFinalScore, resultData.totalTurns or 0)
	end

	-- Location breakdown (Phase 6B)
	if breakdownLabel and resultData.locationResults then
		local lines = {}
		for _, locResult in ipairs(resultData.locationResults) do
			local statusText = "TIED"
			if locResult.myPower > locResult.oppPower then
				statusText = "WON"
			elseif locResult.oppPower > locResult.myPower then
				statusText = "LOST"
			end
			table.insert(lines, string.format("%s (%d pts): You %d | Opp %d — %s",
				locResult.name or "Location",
				locResult.pointValue or 0,
				locResult.myPower or 0,
				locResult.oppPower or 0,
				statusText
			))
		end
		breakdownLabel.Text = table.concat(lines, "\n")
	end

	playGameOverReveal(resultData)
end)

InvalidPlayEvent.OnClientEvent:Connect(function(data)
	local reason = data.reason or "Invalid placement"
	print("[Client] Invalid play: " .. reason)
	showToast(reason)
end)

-- ============================================================
-- Initialize
-- ============================================================

print("[MatchClient] Initialized — waiting for match")
createLobbyUI()
