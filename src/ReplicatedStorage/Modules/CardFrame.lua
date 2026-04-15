--[[
	CardFrame — shared card rendering component.

	Creates GUI Frame elements for cards at three display sizes:
		"board"  — fills parent slot (scale-based)
		"hand"   — fixed 130x173 pixels
		"detail" — fixed 240x340 pixels

	Art: bright colored rectangle (top half of card).
	Rarity borders: Common=white, Uncommon=green, Rare=blue, Legendary=gold.
	Badges: Cost (blue, top-left), Power (gold, top-right).
]]

local CardDatabase = require(script.Parent.CardDatabase)
local TweenService = game:GetService("TweenService")

local CardFrame = {}

local RARITY_COLORS = {
	Common    = Color3.fromRGB(200, 200, 200),
	Uncommon  = Color3.fromRGB(80, 200, 80),
	Rare      = Color3.fromRGB(60, 120, 255),
	Legendary = Color3.fromRGB(255, 200, 40),
}

local RARITY_THICKNESS = {
	Common    = 2,
	Uncommon  = 3,
	Rare      = 3,
	Legendary = 4,
}

local ABILITY_PIP_COLORS = {
	OnReveal = Color3.fromRGB(255, 160, 40),
	Ongoing  = Color3.fromRGB(40, 200, 180),
}

local SIZE_PRESETS = {
	hand   = UDim2.new(0, 130, 0, 173),
	detail = UDim2.new(0, 240, 0, 340),
}

function CardFrame.create(cardID, displaySize, overridePower)
	local def = CardDatabase[cardID]
	if not def then
		warn("CardFrame: unknown card ID: " .. tostring(cardID))
		return nil
	end

	displaySize = displaySize or "board"
	local rarityColor = RARITY_COLORS[def.rarity] or RARITY_COLORS.Common
	local artColor = def.artColor or Color3.fromRGB(128, 128, 128)
	local power = overridePower or def.power
	local size = SIZE_PRESETS[displaySize]

	-- === MAIN CARD FRAME ===
	local frame = Instance.new("Frame")
	frame.Name = "Card_" .. cardID
	frame.Size = size or UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(50, 55, 75)
	frame.BorderSizePixel = 0
	frame.ZIndex = 3

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Name = "RarityStroke"
	stroke.Color = rarityColor
	stroke.Thickness = RARITY_THICKNESS[def.rarity] or 2
	stroke.Parent = frame

	-- === ART AREA (top portion — bright colored rectangle) ===
	local artFrame = Instance.new("Frame")
	artFrame.Name = "Art"
	artFrame.BackgroundColor3 = artColor
	artFrame.BorderSizePixel = 0
	artFrame.ZIndex = 3
	artFrame.Parent = frame

	local artCorner = Instance.new("UICorner")
	artCorner.CornerRadius = UDim.new(0, 4)
	artCorner.Parent = artFrame

	if displaySize == "detail" then
		artFrame.Position = UDim2.new(0.05, 0, 0.05, 0)
		artFrame.Size = UDim2.new(0.9, 0, 0.4, 0)
	else
		-- board and hand: same layout
		artFrame.Position = UDim2.new(0.05, 0, 0.05, 0)
		artFrame.Size = UDim2.new(0.9, 0, 0.5, 0)
	end

	-- === COST BADGE (blue circle, top-left, offset positioning) ===
	local badgeSize = 28
	if displaySize == "detail" then badgeSize = 36 end

	local costBadge = Instance.new("Frame")
	costBadge.Name = "CostBadge"
	costBadge.Size = UDim2.new(0, badgeSize, 0, badgeSize)
	costBadge.Position = UDim2.new(0, 3, 0, 3)
	costBadge.BackgroundColor3 = Color3.fromRGB(50, 100, 200)
	costBadge.BorderSizePixel = 0
	costBadge.ZIndex = 4
	costBadge.Parent = frame

	local costCorner = Instance.new("UICorner")
	costCorner.CornerRadius = UDim.new(1, 0)
	costCorner.Parent = costBadge

	local costStroke = Instance.new("UIStroke")
	costStroke.Color = Color3.fromRGB(10, 10, 15)
	costStroke.Thickness = 1
	costStroke.Parent = costBadge

	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "CostText"
	costLabel.Size = UDim2.new(1, 0, 1, 0)
	costLabel.BackgroundTransparency = 1
	costLabel.Text = tostring(def.cost)
	costLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	costLabel.TextScaled = true
	costLabel.Font = Enum.Font.GothamBold
	costLabel.ZIndex = 5
	costLabel.Parent = costBadge

	-- === POWER BADGE (gold circle, top-right, offset positioning) ===
	local powerBadge = Instance.new("Frame")
	powerBadge.Name = "PowerBadge"
	powerBadge.Size = UDim2.new(0, badgeSize, 0, badgeSize)
	powerBadge.AnchorPoint = Vector2.new(1, 0)
	powerBadge.Position = UDim2.new(1, -3, 0, 3)
	powerBadge.BackgroundColor3 = Color3.fromRGB(200, 160, 40)
	powerBadge.BorderSizePixel = 0
	powerBadge.ZIndex = 4
	powerBadge.Parent = frame

	local powerCorner = Instance.new("UICorner")
	powerCorner.CornerRadius = UDim.new(1, 0)
	powerCorner.Parent = powerBadge

	local powerStroke = Instance.new("UIStroke")
	powerStroke.Color = Color3.fromRGB(10, 10, 15)
	powerStroke.Thickness = 1
	powerStroke.Parent = powerBadge

	local powerLabel = Instance.new("TextLabel")
	powerLabel.Name = "PowerText"
	powerLabel.Size = UDim2.new(1, 0, 1, 0)
	powerLabel.BackgroundTransparency = 1
	powerLabel.Text = tostring(power)
	powerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	powerLabel.TextScaled = true
	powerLabel.Font = Enum.Font.GothamBold
	powerLabel.ZIndex = 5
	powerLabel.Parent = powerBadge

	-- === ABILITY PIP (small colored dot below art) ===
	if def.ability then
		local parsed = string.split(def.ability, ":")
		local trigger = parsed[1]
		local pipColor = ABILITY_PIP_COLORS[trigger]
		if pipColor then
			local pipSize = displaySize == "detail" and 18 or 10
			local pip = Instance.new("Frame")
			pip.Name = "AbilityPip"
			pip.Size = UDim2.new(0, pipSize, 0, pipSize)
			pip.AnchorPoint = Vector2.new(1, 0)
			pip.Position = UDim2.new(0.92, 0, 0.58, 0)
			pip.BackgroundColor3 = pipColor
			pip.BorderSizePixel = 0
			pip.ZIndex = 4
			pip.Parent = frame

			local pipCorner = Instance.new("UICorner")
			pipCorner.CornerRadius = UDim.new(1, 0)
			pipCorner.Parent = pip
		end
	end

	-- === NAME LABEL (hand and detail only) ===
	if displaySize == "hand" or displaySize == "detail" then
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.Text = def.name
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.ZIndex = 4
		nameLabel.Parent = frame

		if displaySize == "hand" then
			nameLabel.TextSize = 13
			nameLabel.Position = UDim2.new(0.08, 0, 0.57, 0)
			nameLabel.Size = UDim2.new(0.84, 0, 0.10, 0)
		else
			nameLabel.TextSize = 20
			nameLabel.Position = UDim2.new(0.08, 0, 0.47, 0)
			nameLabel.Size = UDim2.new(0.84, 0, 0.08, 0)
		end
	end

	-- === ABILITY TEXT (hand and detail only) ===
	if (displaySize == "hand" or displaySize == "detail") and def.abilityText then
		local abilityLabel = Instance.new("TextLabel")
		abilityLabel.Name = "AbilityLabel"
		abilityLabel.BackgroundTransparency = 1
		abilityLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		abilityLabel.Font = Enum.Font.Gotham
		abilityLabel.Text = def.abilityText
		abilityLabel.TextWrapped = true
		abilityLabel.TextXAlignment = Enum.TextXAlignment.Left
		abilityLabel.TextYAlignment = Enum.TextYAlignment.Top
		abilityLabel.ZIndex = 4
		abilityLabel.Parent = frame

		if displaySize == "hand" then
			abilityLabel.TextSize = 11
			abilityLabel.Position = UDim2.new(0.08, 0, 0.68, 0)
			abilityLabel.Size = UDim2.new(0.84, 0, 0.18, 0)
			abilityLabel.TextTruncate = Enum.TextTruncate.AtEnd
		else
			abilityLabel.TextSize = 14
			abilityLabel.Position = UDim2.new(0.08, 0, 0.57, 0)
			abilityLabel.Size = UDim2.new(0.84, 0, 0.3, 0)
		end
	end

	-- === STATS (detail only) ===
	if displaySize == "detail" then
		local statsLabel = Instance.new("TextLabel")
		statsLabel.Name = "StatsLabel"
		statsLabel.BackgroundTransparency = 1
		statsLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
		statsLabel.TextSize = 14
		statsLabel.Font = Enum.Font.Gotham
		statsLabel.Text = string.format("Cost: %d  |  Power: %d  |  %s", def.cost, power, def.rarity)
		statsLabel.TextXAlignment = Enum.TextXAlignment.Left
		statsLabel.Position = UDim2.new(0.08, 0, 0.89, 0)
		statsLabel.Size = UDim2.new(0.84, 0, 0.08, 0)
		statsLabel.ZIndex = 4
		statsLabel.Parent = frame
	end

	return frame
end

function CardFrame.updatePower(frame, newPower, basePower)
	local powerBadge = frame:FindFirstChild("PowerBadge")
	if powerBadge then
		local text = powerBadge:FindFirstChild("PowerText")
		if text then
			text.Text = tostring(newPower)
			if newPower > basePower then
				text.TextColor3 = Color3.fromRGB(100, 255, 100)
			elseif newPower < basePower then
				text.TextColor3 = Color3.fromRGB(255, 100, 100)
			else
				text.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		end
	end
end

function CardFrame.createEmptySlot(displaySize)
	displaySize = displaySize or "board"
	local size = SIZE_PRESETS[displaySize]

	local frame = Instance.new("Frame")
	frame.Name = "EmptySlot"
	frame.Size = size or UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	frame.BackgroundTransparency = 0.5
	frame.BorderSizePixel = 0

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 80, 90)
	stroke.Thickness = 1
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	return frame
end

return CardFrame
