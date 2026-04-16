--[[
	CardFrame — shared card rendering component.

	Creates GUI Frame elements for cards at three display sizes:
		"board"  — fills parent slot, extended art + badges + name
		"hand"   — fills parent slot, extended art + badges + name
		"detail" — fixed 240x340 pixels, shows everything + stats + ability

	Board/hand: extended art fills card edge-to-edge (masked by rarity border),
	dark gradient at bottom for name readability, no ability text or pip.
	Detail (inspect): inset art, full ability text, ability pip, stats line.
	Rarity borders: Common=white, Uncommon=green+glow, Rare=blue+glow, Legendary=gold+glow.
	Badges: Cost (blue, top-left), Power (gold, top-right).

	IMPORTANT: All elements use ZIndex >= 3 because parent containers
	may have ZIndex=2 and Roblox ZIndex is global within a ScreenGui.
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
	detail = UDim2.new(0, 240, 0, 340),
}

-- Darken a color by a factor (0-1)
local function darkenColor(color, factor)
	return Color3.new(
		math.max(0, color.R * (1 - factor)),
		math.max(0, color.G * (1 - factor)),
		math.max(0, color.B * (1 - factor))
	)
end

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
	frame.BackgroundColor3 = Color3.fromRGB(35, 38, 52)
	frame.BorderSizePixel = 0
	frame.ZIndex = 3

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	-- Rarity border
	local stroke = Instance.new("UIStroke")
	stroke.Name = "RarityStroke"
	stroke.Color = rarityColor
	stroke.Thickness = RARITY_THICKNESS[def.rarity] or 2
	stroke.Parent = frame

	-- === ART AREA ===
	local artFrame = Instance.new("Frame")
	artFrame.Name = "Art"
	-- White background so UIGradient colors render accurately
	artFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	artFrame.BorderSizePixel = 0
	artFrame.ZIndex = 3
	artFrame.Parent = frame

	local artCorner = Instance.new("UICorner")
	artCorner.CornerRadius = UDim.new(0, 4)
	artCorner.Parent = artFrame

	-- Gradient from artColor to slightly darker — gives dimensionality
	local artGradient = Instance.new("UIGradient")
	artGradient.Color = ColorSequence.new(artColor, darkenColor(artColor, 0.2))
	artGradient.Rotation = 135
	artGradient.Parent = artFrame

	if displaySize == "detail" then
		artFrame.Position = UDim2.new(0.05, 0, 0.05, 0)
		artFrame.Size = UDim2.new(0.9, 0, 0.4, 0)
	else
		-- Extended art: fills entire card up to the rarity border
		artFrame.Position = UDim2.new(0, 0, 0, 0)
		artFrame.Size = UDim2.new(1, 0, 1, 0)
		artCorner.CornerRadius = UDim.new(0, 6)

		-- Dark gradient at bottom for name readability over art
		local nameBg = Instance.new("Frame")
		nameBg.Name = "NameBg"
		nameBg.Size = UDim2.new(1, 0, 0.35, 0)
		nameBg.Position = UDim2.new(0, 0, 0.65, 0)
		nameBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		nameBg.BorderSizePixel = 0
		nameBg.ZIndex = 3
		nameBg.Parent = frame

		local nameBgCorner = Instance.new("UICorner")
		nameBgCorner.CornerRadius = UDim.new(0, 6)
		nameBgCorner.Parent = nameBg

		local nameBgGradient = Instance.new("UIGradient")
		nameBgGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.3),
			NumberSequenceKeypoint.new(1, 0.1),
		})
		nameBgGradient.Rotation = 90
		nameBgGradient.Parent = nameBg
	end

	-- === COST BADGE (blue circle, top-left) ===
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

	Instance.new("UICorner", costBadge).CornerRadius = UDim.new(1, 0)

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

	-- === POWER BADGE (gold circle, top-right) ===
	local powerBadge = Instance.new("Frame")
	powerBadge.Name = "PowerBadge"
	powerBadge.Size = UDim2.new(0, badgeSize, 0, badgeSize)
	powerBadge.AnchorPoint = Vector2.new(1, 0)
	powerBadge.Position = UDim2.new(1, -3, 0, 3)
	powerBadge.BackgroundColor3 = Color3.fromRGB(200, 160, 40)
	powerBadge.BorderSizePixel = 0
	powerBadge.ZIndex = 4
	powerBadge.Parent = frame

	Instance.new("UICorner", powerBadge).CornerRadius = UDim.new(1, 0)

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

	-- === ABILITY PIP (detail only — small colored dot below art) ===
	if def.ability and displaySize == "detail" then
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

			Instance.new("UICorner", pip).CornerRadius = UDim.new(1, 0)

			local pipStroke = Instance.new("UIStroke")
			pipStroke.Color = Color3.fromRGB(15, 15, 20)
			pipStroke.Thickness = 1
			pipStroke.Parent = pip
		end
	end

	-- === NAME LABEL (all sizes) ===
	do
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.Text = def.name
		nameLabel.ZIndex = 4
		nameLabel.Parent = frame

		if displaySize == "detail" then
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextSize = 20
			nameLabel.Position = UDim2.new(0.08, 0, 0.47, 0)
			nameLabel.Size = UDim2.new(0.84, 0, 0.08, 0)
		else
			-- Board and hand: centered at bottom over dark gradient
			nameLabel.TextXAlignment = Enum.TextXAlignment.Center
			nameLabel.TextScaled = true
			nameLabel.Position = UDim2.new(0.06, 0, 0.80, 0)
			nameLabel.Size = UDim2.new(0.88, 0, 0.16, 0)
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		end
	end

	-- === ABILITY TEXT (detail only) ===
	if displaySize == "detail" and def.abilityText then
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

		abilityLabel.TextSize = 14
		abilityLabel.Position = UDim2.new(0.08, 0, 0.57, 0)
		abilityLabel.Size = UDim2.new(0.84, 0, 0.3, 0)
	end

	-- === STATS LINE (detail only) ===
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

-- Update the power display on an existing card frame
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

-- Create an empty slot placeholder
function CardFrame.createEmptySlot(displaySize)
	displaySize = displaySize or "board"
	local size = SIZE_PRESETS[displaySize]

	local frame = Instance.new("Frame")
	frame.Name = "EmptySlot"
	frame.Size = size or UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	frame.BackgroundTransparency = 0.5
	frame.BorderSizePixel = 0
	frame.ZIndex = 3

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
