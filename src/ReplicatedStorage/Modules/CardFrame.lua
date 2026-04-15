--[[
	CardFrame — shared card rendering component.

	Creates GUI Frame elements for cards at three display sizes:
		"board"  — dynamic size, shows art/power/cost only (no name at small sizes)
		"hand"   — medium (110x147), shows art/name/cost/power/ability (truncated)
		"detail" — large overlay (240x340), shows everything

	Prototype art: colored rectangles with gradient.
	Rarity border colors with glow progression:
		Common=white, Uncommon=green glow, Rare=blue glow, Legendary=gold glow+shimmer.
	Ability type indicator pips: OnReveal=orange, Ongoing=teal.
]]

local CardDatabase = require(script.Parent.CardDatabase)
local TweenService = game:GetService("TweenService")

local CardFrame = {}

-- Rarity -> border color mapping
local RARITY_COLORS = {
	Common    = Color3.fromRGB(200, 200, 200),
	Uncommon  = Color3.fromRGB(80, 200, 80),
	Rare      = Color3.fromRGB(60, 120, 255),
	Legendary = Color3.fromRGB(255, 200, 40),
}

-- Rarity -> glow config { thickness, transparency }
local RARITY_GLOW = {
	Common    = nil,
	Uncommon  = { thickness = 4, transparency = 0.7, color = Color3.fromRGB(80, 200, 80) },
	Rare      = { thickness = 5, transparency = 0.6, color = Color3.fromRGB(60, 120, 255) },
	Legendary = { thickness = 5, transparency = 0.5, color = Color3.fromRGB(255, 200, 40) },
}

-- Rarity -> border thickness
local RARITY_THICKNESS = {
	Common    = 2,
	Uncommon  = 2,
	Rare      = 3,
	Legendary = 3,
}

-- Ability type indicator colors
local ABILITY_PIP_COLORS = {
	OnReveal = Color3.fromRGB(255, 160, 40),
	Ongoing  = Color3.fromRGB(40, 200, 180),
}

-- Size presets { width, height }
-- Board cards use scale sizing (fill slot) — the slot has its own aspect ratio constraint
-- Hand and detail cards use fixed pixel size at 3:4 portrait ratio
local SIZE_PRESETS = {
	hand   = UDim2.new(0, 130, 0, 173),
	detail = UDim2.new(0, 240, 0, 340),
}

-- Font sizes per display size
local FONT_SIZES = {
	board  = { cost = 10, power = 14, name = 0,  ability = 0 },
	hand   = { cost = 14, power = 18, name = 13, ability = 11 },
	detail = { cost = 18, power = 24, name = 20, ability = 14 },
}

-- Ability pip sizes per display size
local PIP_SIZES = {
	board  = 10,
	hand   = 14,
	detail = 18,
}

-- Darken a color by a factor (0-1, where 0.25 = 25% darker)
local function darkenColor(color, factor)
	return Color3.new(
		math.max(0, color.R * (1 - factor)),
		math.max(0, color.G * (1 - factor)),
		math.max(0, color.B * (1 - factor))
	)
end

-- Lighten a color by a factor
local function lightenColor(color, factor)
	return Color3.new(
		math.min(1, color.R + (1 - color.R) * factor),
		math.min(1, color.G + (1 - color.G) * factor),
		math.min(1, color.B + (1 - color.B) * factor)
	)
end

-- Create a card frame for a given card ID, display size, and optional power override
function CardFrame.create(cardID, displaySize, overridePower)
	local def = CardDatabase[cardID]
	if not def then
		warn("CardFrame: unknown card ID: " .. tostring(cardID))
		return nil
	end

	displaySize = displaySize or "board"
	local size = SIZE_PRESETS[displaySize]
	local fonts = FONT_SIZES[displaySize] or FONT_SIZES.board
	local rarityColor = RARITY_COLORS[def.rarity] or RARITY_COLORS.Common
	local artColor = def.artColor or Color3.fromRGB(128, 128, 128)
	local power = overridePower or def.power

	-- Main frame
	local frame = Instance.new("Frame")
	frame.Name = "Card_" .. cardID
	if size then
		frame.Size = size
	else
		-- Board cards: fill slot dimensions (slot has its own aspect constraint)
		frame.Size = UDim2.new(1, 0, 1, 0)
	end
	frame.BackgroundColor3 = Color3.fromRGB(50, 55, 75)
	frame.BorderSizePixel = 0
	frame.ClipDescendants = true

	-- Rarity border (UIStroke) — thick enough to always see
	local stroke = Instance.new("UIStroke")
	stroke.Name = "RarityStroke"
	stroke.Color = rarityColor
	stroke.Thickness = math.max(RARITY_THICKNESS[def.rarity] or 2, 3)
	stroke.Parent = frame

	-- Rounded corners
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	-- Art area — flat color, explicit ZIndex to ensure visibility
	local artFrame = Instance.new("Frame")
	artFrame.Name = "Art"
	artFrame.BackgroundColor3 = artColor
	artFrame.BackgroundTransparency = 0
	artFrame.BorderSizePixel = 0
	artFrame.ZIndex = 1
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

	-- Card name on art (board: only if not too small to read)
	if displaySize == "board" then
		-- Board cards: no name text (unreadable at small sizes per plan 4A)
		-- Art color + cost/power badges identify the card
	end

	-- Cost badge (top-left) — sized as 26% of card width
	if fonts.cost > 0 then
		local costBadge = Instance.new("Frame")
		costBadge.Name = "CostBadge"
		costBadge.Size = UDim2.new(0.26, 0, 0.26, 0)
		costBadge.SizeConstraint = Enum.SizeConstraint.RelativeXX
		costBadge.Position = UDim2.new(0, 4, 0, 4)
		costBadge.BackgroundColor3 = Color3.fromRGB(50, 100, 200)
		costBadge.BorderSizePixel = 0
		costBadge.ZIndex = 2
		costBadge.Parent = frame

		local costCorner = Instance.new("UICorner")
		costCorner.CornerRadius = UDim.new(1, 0)
		costCorner.Parent = costBadge

		-- Dark outline on badge
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
		costLabel.ZIndex = 3
		costLabel.Parent = costBadge
	end

	-- Power badge (top-right) — sized as 26% of card width
	if fonts.power > 0 then
		local powerBadge = Instance.new("Frame")
		powerBadge.Name = "PowerBadge"
		powerBadge.Size = UDim2.new(0.26, 0, 0.26, 0)
		powerBadge.SizeConstraint = Enum.SizeConstraint.RelativeXX
		powerBadge.AnchorPoint = Vector2.new(1, 0)
		powerBadge.Position = UDim2.new(1, -4, 0, 4)
		powerBadge.BackgroundColor3 = Color3.fromRGB(200, 160, 40)
		powerBadge.BorderSizePixel = 0
		powerBadge.ZIndex = 2
		powerBadge.Parent = frame

		local powerCorner = Instance.new("UICorner")
		powerCorner.CornerRadius = UDim.new(1, 0)
		powerCorner.Parent = powerBadge

		-- Dark outline on badge
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
		powerLabel.ZIndex = 3
		powerLabel.Parent = powerBadge
	end

	-- Ability type indicator pip (below art, right side)
	if def.ability then
		local parsed = string.split(def.ability, ":")
		local trigger = parsed[1]
		local pipColor = ABILITY_PIP_COLORS[trigger]
		if pipColor then
			local pipSize = PIP_SIZES[displaySize] or PIP_SIZES.board
			local pip = Instance.new("Frame")
			pip.Name = "AbilityPip"
			pip.Size = UDim2.new(0, pipSize, 0, pipSize)
			pip.AnchorPoint = Vector2.new(1, 0)
			-- Position just below the art area, right-aligned
			local artBottom = displaySize == "board" and 0.62 or (displaySize == "hand" and 0.52 or 0.47)
			pip.Position = UDim2.new(0.92, 0, artBottom, 2)
			pip.BackgroundColor3 = pipColor
			pip.BorderSizePixel = 0
			pip.ZIndex = 4
			pip.Parent = frame

			local pipCorner = Instance.new("UICorner")
			pipCorner.CornerRadius = UDim.new(1, 0)
			pipCorner.Parent = pip

			-- Dark outline so it reads against any art color
			local pipStroke = Instance.new("UIStroke")
			pipStroke.Color = Color3.fromRGB(15, 15, 20)
			pipStroke.Thickness = 1
			pipStroke.Parent = pip
		end
	end

	-- Rarity outer glow (second UIStroke on a wrapper, or direct approach)
	local glowConfig = RARITY_GLOW[def.rarity]
	if glowConfig then
		-- We add a second UIStroke by wrapping in an outer frame concept
		-- Roblox only allows one UIStroke per instance, so we use the main stroke
		-- and add a glow effect via a slightly larger background frame
		local glowFrame = Instance.new("Frame")
		glowFrame.Name = "RarityGlow"
		glowFrame.Size = UDim2.new(1, glowConfig.thickness * 2, 1, glowConfig.thickness * 2)
		glowFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		glowFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
		glowFrame.BackgroundTransparency = 1
		glowFrame.BorderSizePixel = 0
		glowFrame.ZIndex = -1
		glowFrame.Parent = frame

		local glowCorner = Instance.new("UICorner")
		glowCorner.CornerRadius = UDim.new(0, 8)
		glowCorner.Parent = glowFrame

		local glowStroke = Instance.new("UIStroke")
		glowStroke.Color = glowConfig.color
		glowStroke.Thickness = glowConfig.thickness
		glowStroke.Transparency = glowConfig.transparency
		glowStroke.Parent = glowFrame

		-- Legendary shimmer animation (UIGradient rotation tween)
		if def.rarity == "Legendary" then
			local shimmerGradient = Instance.new("UIGradient")
			shimmerGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 40)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 200)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 40)),
			})
			shimmerGradient.Rotation = 0
			shimmerGradient.Parent = glowFrame

			-- Animate shimmer rotation
			task.spawn(function()
				while glowFrame and glowFrame.Parent do
					local tween = TweenService:Create(shimmerGradient,
						TweenInfo.new(3, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
						{ Rotation = 360 }
					)
					tween:Play()
					tween.Completed:Wait()
				end
			end)
		end
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

-- Update the power display on an existing card frame (with flash animation)
function CardFrame.updatePower(frame, newPower, basePower)
	local powerBadge = frame:FindFirstChild("PowerBadge")
	if powerBadge then
		local text = powerBadge:FindFirstChild("PowerText")
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

		-- Power change flash animation
		local tween = TweenService:Create(powerBadge,
			TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.new(0.34, 0, 0.34, 0) }
		)
		tween:Play()
		tween.Completed:Connect(function()
			local tweenBack = TweenService:Create(powerBadge,
				TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Size = UDim2.new(0.26, 0, 0.26, 0) }
			)
			tweenBack:Play()
		end)
	end
end

-- Create an empty slot frame (dotted border placeholder)
function CardFrame.createEmptySlot(displaySize)
	displaySize = displaySize or "board"
	local size = SIZE_PRESETS[displaySize]

	local frame = Instance.new("Frame")
	frame.Name = "EmptySlot"
	if size then
		frame.Size = size
	else
		frame.Size = UDim2.new(1, 0, 1, 0)
	end
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
