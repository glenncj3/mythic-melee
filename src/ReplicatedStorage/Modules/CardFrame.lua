--[[
	CardFrame — shared card rendering component.

	Creates GUI Frame elements for cards at three display sizes:
		"board"  — small, shows art/power/cost only
		"hand"   — medium, shows art/name/cost/power/ability (truncated)
		"detail" — large overlay, shows everything

	Prototype art: colored rectangles with card name text.
	Rarity border colors: Common=white, Uncommon=green, Rare=blue, Legendary=gold.
]]

local CardDatabase = require(script.Parent.CardDatabase)

local CardFrame = {}

-- Rarity → border color mapping
local RARITY_COLORS = {
	Common    = Color3.fromRGB(200, 200, 200),
	Uncommon  = Color3.fromRGB(80, 200, 80),
	Rare      = Color3.fromRGB(60, 120, 255),
	Legendary = Color3.fromRGB(255, 200, 40),
}

-- Size presets { width, height }
local SIZE_PRESETS = {
	board  = UDim2.new(0, 60, 0, 80),
	hand   = UDim2.new(0, 90, 0, 120),
	detail = UDim2.new(0, 240, 0, 340),
}

-- Font sizes per display size
local FONT_SIZES = {
	board  = { cost = 10, power = 14, name = 0,  ability = 0 },
	hand   = { cost = 12, power = 16, name = 12, ability = 10 },
	detail = { cost = 18, power = 24, name = 20, ability = 14 },
}

-- Create a card frame for a given card ID, display size, and optional power override
function CardFrame.create(cardID, displaySize, overridePower)
	local def = CardDatabase[cardID]
	if not def then
		warn("CardFrame: unknown card ID: " .. tostring(cardID))
		return nil
	end

	displaySize = displaySize or "board"
	local size = SIZE_PRESETS[displaySize] or SIZE_PRESETS.board
	local fonts = FONT_SIZES[displaySize] or FONT_SIZES.board
	local rarityColor = RARITY_COLORS[def.rarity] or RARITY_COLORS.Common
	local artColor = def.artColor or Color3.fromRGB(128, 128, 128)
	local power = overridePower or def.power

	-- Main frame
	local frame = Instance.new("Frame")
	frame.Name = "Card_" .. cardID
	frame.Size = size
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	frame.BorderSizePixel = 0

	-- Rarity border (UIStroke)
	local stroke = Instance.new("UIStroke")
	stroke.Color = rarityColor
	stroke.Thickness = 2
	stroke.Parent = frame

	-- Rounded corners
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	-- Art area (colored rectangle)
	local artFrame = Instance.new("Frame")
	artFrame.Name = "Art"
	artFrame.BackgroundColor3 = artColor
	artFrame.BorderSizePixel = 0
	artFrame.Parent = frame

	local artCorner = Instance.new("UICorner")
	artCorner.CornerRadius = UDim.new(0, 4)
	artCorner.Parent = artFrame

	if displaySize == "board" then
		artFrame.Position = UDim2.new(0.05, 0, 0.05, 0)
		artFrame.Size = UDim2.new(0.9, 0, 0.55, 0)
	elseif displaySize == "hand" then
		artFrame.Position = UDim2.new(0.05, 0, 0.05, 0)
		artFrame.Size = UDim2.new(0.9, 0, 0.45, 0)
	else -- detail
		artFrame.Position = UDim2.new(0.05, 0, 0.05, 0)
		artFrame.Size = UDim2.new(0.9, 0, 0.4, 0)
	end

	-- Card name on art (for board: large centered text; for hand/detail: separate label)
	if displaySize == "board" then
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "ArtName"
		nameLabel.Size = UDim2.new(1, 0, 1, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = def.name
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.TextSize = 10
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextWrapped = true
		nameLabel.Parent = artFrame
	end

	-- Cost badge (top-left)
	if fonts.cost > 0 then
		local costBadge = Instance.new("Frame")
		costBadge.Name = "CostBadge"
		costBadge.Size = UDim2.new(0, fonts.cost + 10, 0, fonts.cost + 10)
		costBadge.Position = UDim2.new(0, 4, 0, 4)
		costBadge.BackgroundColor3 = Color3.fromRGB(50, 100, 200)
		costBadge.BorderSizePixel = 0
		costBadge.ZIndex = 2
		costBadge.Parent = frame

		local costCorner = Instance.new("UICorner")
		costCorner.CornerRadius = UDim.new(1, 0)
		costCorner.Parent = costBadge

		local costLabel = Instance.new("TextLabel")
		costLabel.Name = "CostText"
		costLabel.Size = UDim2.new(1, 0, 1, 0)
		costLabel.BackgroundTransparency = 1
		costLabel.Text = tostring(def.cost)
		costLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		costLabel.TextSize = fonts.cost
		costLabel.Font = Enum.Font.GothamBold
		costLabel.ZIndex = 3
		costLabel.Parent = costBadge
	end

	-- Power badge (bottom-right)
	if fonts.power > 0 then
		local powerBadge = Instance.new("Frame")
		powerBadge.Name = "PowerBadge"
		powerBadge.Size = UDim2.new(0, fonts.power + 8, 0, fonts.power + 8)
		powerBadge.AnchorPoint = Vector2.new(1, 1)
		powerBadge.Position = UDim2.new(1, -4, 1, -4)
		powerBadge.BackgroundColor3 = Color3.fromRGB(200, 160, 40)
		powerBadge.BorderSizePixel = 0
		powerBadge.ZIndex = 2
		powerBadge.Parent = frame

		local powerCorner = Instance.new("UICorner")
		powerCorner.CornerRadius = UDim.new(1, 0)
		powerCorner.Parent = powerBadge

		local powerLabel = Instance.new("TextLabel")
		powerLabel.Name = "PowerText"
		powerLabel.Size = UDim2.new(1, 0, 1, 0)
		powerLabel.BackgroundTransparency = 1
		powerLabel.Text = tostring(power)
		powerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		powerLabel.TextSize = fonts.power
		powerLabel.Font = Enum.Font.GothamBold
		powerLabel.ZIndex = 3
		powerLabel.Parent = powerBadge
	end

	-- Name label (hand and detail only)
	if fonts.name > 0 then
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.TextSize = fonts.name
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.Text = def.name
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = frame

		if displaySize == "hand" then
			nameLabel.Position = UDim2.new(0.08, 0, 0.52, 0)
			nameLabel.Size = UDim2.new(0.84, 0, 0.12, 0)
		else -- detail
			nameLabel.Position = UDim2.new(0.08, 0, 0.47, 0)
			nameLabel.Size = UDim2.new(0.84, 0, 0.08, 0)
		end
	end

	-- Ability text (hand: truncated single line; detail: full multi-line)
	if fonts.ability > 0 and def.abilityText then
		local abilityLabel = Instance.new("TextLabel")
		abilityLabel.Name = "AbilityLabel"
		abilityLabel.BackgroundTransparency = 1
		abilityLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		abilityLabel.TextSize = fonts.ability
		abilityLabel.Font = Enum.Font.Gotham
		abilityLabel.Text = def.abilityText
		abilityLabel.TextWrapped = true
		abilityLabel.TextXAlignment = Enum.TextXAlignment.Left
		abilityLabel.TextYAlignment = Enum.TextYAlignment.Top
		abilityLabel.Parent = frame

		if displaySize == "hand" then
			abilityLabel.Position = UDim2.new(0.08, 0, 0.65, 0)
			abilityLabel.Size = UDim2.new(0.84, 0, 0.2, 0)
			abilityLabel.TextTruncate = Enum.TextTruncate.AtEnd
		else -- detail
			abilityLabel.Position = UDim2.new(0.08, 0, 0.57, 0)
			abilityLabel.Size = UDim2.new(0.84, 0, 0.3, 0)
		end
	end

	-- For detail view: show cost/power as text labels too
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
		statsLabel.Parent = frame
	end

	return frame
end

-- Update the power display on an existing card frame
function CardFrame.updatePower(frame, newPower, basePower)
	local powerLabel = frame:FindFirstChild("PowerBadge")
	if powerLabel then
		local text = powerLabel:FindFirstChild("PowerText")
		if text then
			text.Text = tostring(newPower)
			-- Color code: green if above base, red if below, white if equal
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

-- Create an empty slot frame (dotted border placeholder)
function CardFrame.createEmptySlot(displaySize)
	displaySize = displaySize or "board"
	local size = SIZE_PRESETS[displaySize] or SIZE_PRESETS.board

	local frame = Instance.new("Frame")
	frame.Name = "EmptySlot"
	frame.Size = size
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
