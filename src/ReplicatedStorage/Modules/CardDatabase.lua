local CardDatabase = {
	-- ============================================================
	-- 1-Cost Cards
	-- ============================================================
	SPARK = {
		name = "Spark",
		cost = 1,
		power = 2,
		ability = nil,
		abilityText = nil,
		rarity = "Common",
		faction = nil,
		artColor = Color3.fromRGB(255, 200, 60),
	},
	SCOUT = {
		name = "Scout",
		cost = 1,
		power = 1,
		ability = "OnReveal:DrawCard:1",
		abilityText = "On Reveal: Draw a card.",
		rarity = "Common",
		faction = nil,
		artColor = Color3.fromRGB(100, 200, 100),
	},
	SEEDLING = {
		name = "Seedling",
		cost = 1,
		power = 1,
		ability = "Ongoing:AddPower:Adjacent:1",
		abilityText = "Ongoing: +1 Power to adjacent cards.",
		rarity = "Common",
		faction = nil,
		artColor = Color3.fromRGB(80, 180, 80),
	},
	EMBER = {
		name = "Ember",
		cost = 1,
		power = 3,
		ability = "OnReveal:RemovePower:Random_Friendly_Here:1",
		abilityText = "On Reveal: -1 Power to a random friendly card at this location.",
		rarity = "Common",
		faction = nil,
		artColor = Color3.fromRGB(255, 100, 50),
	},
	SAGE = {
		name = "Sage",
		cost = 1,
		power = 1,
		ability = "Ongoing:AddPower:Self:PerOngoing",
		abilityText = "Ongoing: +1 Power for each other Ongoing card you control (at any location).",
		rarity = "Uncommon",
		faction = nil,
		artColor = Color3.fromRGB(160, 120, 220),
	},

	-- ============================================================
	-- 2-Cost Cards
	-- ============================================================
	IRON_GUARD = {
		name = "Iron Guard",
		cost = 2,
		power = 3,
		ability = nil,
		abilityText = nil,
		rarity = "Common",
		faction = nil,
		artColor = Color3.fromRGB(150, 150, 160),
	},
	FROST_SPRITE = {
		name = "Frost Sprite",
		cost = 2,
		power = 1,
		ability = "OnReveal:RemovePower:Random_Enemy_Here:2",
		abilityText = "On Reveal: -2 Power to a random enemy card at this location.",
		rarity = "Common",
		faction = nil,
		artColor = Color3.fromRGB(130, 200, 255),
	},
	LOOKOUT = {
		name = "Lookout",
		cost = 2,
		power = 2,
		ability = "OnReveal:ConditionalPower:Opponent_Played_Here:3",
		abilityText = "On Reveal: If your opponent played a card at this location this turn, +3 Power to this card.",
		rarity = "Common",
		faction = nil,
		artColor = Color3.fromRGB(200, 180, 100),
	},
	FLAME_IMP = {
		name = "Flame Imp",
		cost = 2,
		power = 2,
		ability = "Ongoing:AddPower:Adjacent:1",
		abilityText = "Ongoing: +1 Power to adjacent cards.",
		rarity = "Common",
		faction = nil,
		artColor = Color3.fromRGB(255, 80, 30),
	},
	MYSTIC = {
		name = "Mystic",
		cost = 2,
		power = 2,
		ability = "OnReveal:AddPower:Column:1",
		abilityText = "On Reveal: +1 Power to all friendly cards in the same column at this location.",
		rarity = "Common",
		faction = nil,
		artColor = Color3.fromRGB(100, 80, 200),
	},

	-- ============================================================
	-- 3-Cost Cards
	-- ============================================================
	STONE_GOLEM = {
		name = "Stone Golem",
		cost = 3,
		power = 5,
		ability = nil,
		abilityText = nil,
		rarity = "Common",
		faction = nil,
		artColor = Color3.fromRGB(140, 130, 120),
	},
	HEALER = {
		name = "Healer",
		cost = 3,
		power = 2,
		ability = "OnReveal:AddPower:Location:1",
		abilityText = "On Reveal: +1 Power to all other friendly cards at this location.",
		rarity = "Common",
		faction = nil,
		artColor = Color3.fromRGB(255, 255, 200),
	},
	WIND_DANCER = {
		name = "Wind Dancer",
		cost = 3,
		power = 4,
		ability = "OnReveal:MoveThis:OtherLocation",
		abilityText = "On Reveal: Move this card to a random empty slot at the other location.",
		rarity = "Uncommon",
		faction = nil,
		artColor = Color3.fromRGB(180, 230, 255),
	},
	SABOTEUR = {
		name = "Saboteur",
		cost = 3,
		power = 3,
		ability = "OnReveal:RemovePower:All_Enemy_Here:1",
		abilityText = "On Reveal: -1 Power to all enemy cards at this location.",
		rarity = "Common",
		faction = nil,
		artColor = Color3.fromRGB(100, 60, 100),
	},
	ECHO = {
		name = "Echo",
		cost = 3,
		power = 1,
		ability = "OnReveal:SummonCopy:Adjacent:1",
		abilityText = "On Reveal: Summon a 1-Power copy of this card in a random empty adjacent slot.",
		rarity = "Uncommon",
		faction = nil,
		artColor = Color3.fromRGB(200, 200, 255),
	},

	-- ============================================================
	-- 4-Cost Cards
	-- ============================================================
	WAR_BEAST = {
		name = "War Beast",
		cost = 4,
		power = 7,
		ability = nil,
		abilityText = nil,
		rarity = "Common",
		faction = nil,
		artColor = Color3.fromRGB(180, 60, 60),
	},
	COMMANDER = {
		name = "Commander",
		cost = 4,
		power = 4,
		ability = "Ongoing:AddPower:Location:1",
		abilityText = "Ongoing: +1 Power to all other friendly cards at this location.",
		rarity = "Uncommon",
		faction = nil,
		artColor = Color3.fromRGB(220, 180, 60),
	},
	TRICKSTER = {
		name = "Trickster",
		cost = 4,
		power = 0,
		ability = "OnReveal:SetPower:Highest_Enemy_Here",
		abilityText = "On Reveal: Set this card's Power equal to the highest-Power enemy card at this location.",
		rarity = "Rare",
		faction = nil,
		artColor = Color3.fromRGB(100, 200, 180),
	},
	SHIELD_WALL = {
		name = "Shield Wall",
		cost = 4,
		power = 3,
		ability = "Ongoing:AddPower:Row:2",
		abilityText = "Ongoing: +2 Power to all other friendly cards in the same row as this card.",
		rarity = "Uncommon",
		faction = nil,
		artColor = Color3.fromRGB(80, 120, 200),
	},
	BERSERKER = {
		name = "Berserker",
		cost = 4,
		power = 4,
		ability = "OnReveal:ConditionalPower:Empty_Slots_Here:1",
		abilityText = "On Reveal: +1 Power for each empty slot on your side of this location.",
		rarity = "Common",
		faction = nil,
		artColor = Color3.fromRGB(200, 50, 50),
	},

	-- ============================================================
	-- 5-Cost Cards
	-- ============================================================
	DRAGON = {
		name = "Dragon",
		cost = 5,
		power = 9,
		ability = nil,
		abilityText = nil,
		rarity = "Rare",
		faction = nil,
		artColor = Color3.fromRGB(200, 30, 30),
	},
	STORM_MAGE = {
		name = "Storm Mage",
		cost = 5,
		power = 5,
		ability = "OnReveal:RemovePower:All_Enemy_Here:2",
		abilityText = "On Reveal: -2 Power to all enemy cards at this location.",
		rarity = "Rare",
		faction = nil,
		artColor = Color3.fromRGB(60, 60, 180),
	},
	WARLORD = {
		name = "Warlord",
		cost = 5,
		power = 1,
		ability = "Ongoing:DoublePower:Location",
		abilityText = "Ongoing: Double your total Power at this location (applied after all other modifiers).",
		rarity = "Legendary",
		faction = nil,
		artColor = Color3.fromRGB(180, 0, 0),
	},
	HIGH_PRIESTESS = {
		name = "High Priestess",
		cost = 5,
		power = 6,
		ability = "OnReveal:DrawCard:2",
		abilityText = "On Reveal: Draw 2 cards.",
		rarity = "Rare",
		faction = nil,
		artColor = Color3.fromRGB(255, 220, 255),
	},

	-- ============================================================
	-- 6-Cost Cards
	-- ============================================================
	TITAN = {
		name = "Titan",
		cost = 6,
		power = 12,
		ability = nil,
		abilityText = nil,
		rarity = "Rare",
		faction = nil,
		artColor = Color3.fromRGB(100, 100, 100),
	},
	OVERLORD = {
		name = "Overlord",
		cost = 6,
		power = 8,
		ability = "Ongoing:AddPower:AllLocations:1",
		abilityText = "Ongoing: +1 Power to all your other cards at both locations.",
		rarity = "Legendary",
		faction = nil,
		artColor = Color3.fromRGB(60, 0, 60),
	},
	VOID_WALKER = {
		name = "Void Walker",
		cost = 6,
		power = 10,
		ability = "OnReveal:DestroyBelow:2:Here_Both",
		abilityText = "On Reveal: Destroy all cards with 2 or less Power at this location (both sides).",
		rarity = "Legendary",
		faction = nil,
		artColor = Color3.fromRGB(30, 0, 50),
	},
	COLOSSUS = {
		name = "Colossus",
		cost = 6,
		power = 8,
		ability = "Ongoing:Immune",
		abilityText = "Ongoing: This card's Power cannot be reduced by enemy abilities.",
		rarity = "Rare",
		faction = nil,
		artColor = Color3.fromRGB(180, 160, 140),
	},
}

-- Utility: get list of all card IDs
function CardDatabase.getAllIDs()
	local ids = {}
	for id, val in pairs(CardDatabase) do
		if type(val) == "table" then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
		local ca, cb = CardDatabase[a], CardDatabase[b]
		if ca.cost ~= cb.cost then return ca.cost < cb.cost end
		return a < b
	end)
	return ids
end

-- Debug: print all cards
function CardDatabase.printAll()
	print("=== Card Database (" .. #CardDatabase.getAllIDs() .. " cards) ===")
	for _, id in ipairs(CardDatabase.getAllIDs()) do
		local c = CardDatabase[id]
		local abilStr = c.abilityText or "Vanilla"
		print(string.format("  [%s] %s — %d/%d — %s — %s",
			id, c.name, c.cost, c.power, c.rarity, abilStr))
	end
end

-- Debug: print cards at a given cost
function CardDatabase.printByCost(cost)
	print(string.format("=== Cards at Cost %d ===", cost))
	for _, id in ipairs(CardDatabase.getAllIDs()) do
		local c = CardDatabase[id]
		if c.cost == cost then
			local abilStr = c.abilityText or "Vanilla"
			print(string.format("  [%s] %s — %d/%d — %s", id, c.name, c.cost, c.power, abilStr))
		end
	end
end

return CardDatabase
