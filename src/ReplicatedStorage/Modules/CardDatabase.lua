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
		faction = "Iron",
		artColor = Color3.fromRGB(255, 200, 60),
	},
	SCOUT = {
		name = "Scout",
		cost = 1,
		power = 1,
		ability = "OnReveal:DrawCard:1",
		abilityText = "On Reveal: Draw a card.",
		rarity = "Common",
		faction = "Arcane",
		artColor = Color3.fromRGB(100, 200, 100),
	},
	SEEDLING = {
		name = "Seedling",
		cost = 1,
		power = 1,
		ability = "Ongoing:AddPower:Adjacent:1",
		abilityText = "Ongoing: +1 Power to adjacent cards.",
		rarity = "Common",
		faction = "Wild",
		artColor = Color3.fromRGB(80, 180, 80),
	},
	EMBER = {
		name = "Ember",
		cost = 1,
		power = 3,
		ability = "OnReveal:RemovePower:Random_Friendly_Here:1",
		abilityText = "On Reveal: -1 Power to a random friendly card at this location.",
		rarity = "Common",
		faction = "Shadow",
		artColor = Color3.fromRGB(255, 100, 50),
	},
	SAGE = {
		name = "Sage",
		cost = 1,
		power = 1,
		ability = "Ongoing:AddPower:Self:PerOngoing",
		abilityText = "Ongoing: +1 Power for each other Ongoing card you control (at any location).",
		rarity = "Uncommon",
		faction = "Arcane",
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
		faction = "Iron",
		artColor = Color3.fromRGB(150, 150, 160),
	},
	FROST_SPRITE = {
		name = "Frost Sprite",
		cost = 2,
		power = 1,
		ability = "OnReveal:RemovePower:Random_Enemy_Here:2",
		abilityText = "On Reveal: -2 Power to a random enemy card at this location.",
		rarity = "Common",
		faction = "Shadow",
		artColor = Color3.fromRGB(130, 200, 255),
	},
	LOOKOUT = {
		name = "Lookout",
		cost = 2,
		power = 2,
		ability = "OnReveal:ConditionalPower:Opponent_Played_Here:3",
		abilityText = "On Reveal: If your opponent played a card at this location this turn, +3 Power to this card.",
		rarity = "Common",
		faction = "Iron",
		artColor = Color3.fromRGB(200, 180, 100),
	},
	FLAME_IMP = {
		name = "Flame Imp",
		cost = 2,
		power = 2,
		ability = "Ongoing:AddPower:Adjacent:1",
		abilityText = "Ongoing: +1 Power to adjacent cards.",
		rarity = "Common",
		faction = "Iron",
		artColor = Color3.fromRGB(255, 80, 30),
	},
	MYSTIC = {
		name = "Mystic",
		cost = 2,
		power = 2,
		ability = "OnReveal:AddPower:Column:1",
		abilityText = "On Reveal: +1 Power to all friendly cards in the same column at this location.",
		rarity = "Common",
		faction = "Arcane",
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
		faction = "Iron",
		artColor = Color3.fromRGB(140, 130, 120),
	},
	HEALER = {
		name = "Healer",
		cost = 3,
		power = 2,
		ability = "OnReveal:AddPower:Location:1",
		abilityText = "On Reveal: +1 Power to all other friendly cards at this location.",
		rarity = "Common",
		faction = "Wild",
		artColor = Color3.fromRGB(255, 255, 200),
	},
	WIND_DANCER = {
		name = "Wind Dancer",
		cost = 3,
		power = 4,
		ability = "OnReveal:MoveThis:OtherLocation",
		abilityText = "On Reveal: Move this card to a random empty slot at the other location.",
		rarity = "Uncommon",
		faction = "Arcane",
		artColor = Color3.fromRGB(180, 230, 255),
	},
	SABOTEUR = {
		name = "Saboteur",
		cost = 3,
		power = 3,
		ability = "OnReveal:RemovePower:All_Enemy_Here:1",
		abilityText = "On Reveal: -1 Power to all enemy cards at this location.",
		rarity = "Common",
		faction = "Shadow",
		artColor = Color3.fromRGB(100, 60, 100),
	},
	ECHO = {
		name = "Echo",
		cost = 3,
		power = 1,
		ability = "OnReveal:SummonCopy:Adjacent:1",
		abilityText = "On Reveal: Summon a 1-Power copy of this card in a random empty adjacent slot.",
		rarity = "Uncommon",
		faction = "Wild",
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
		faction = "Iron",
		artColor = Color3.fromRGB(180, 60, 60),
	},
	COMMANDER = {
		name = "Commander",
		cost = 4,
		power = 4,
		ability = "Ongoing:AddPower:Location:1",
		abilityText = "Ongoing: +1 Power to all other friendly cards at this location.",
		rarity = "Uncommon",
		faction = "Iron",
		artColor = Color3.fromRGB(220, 180, 60),
	},
	TRICKSTER = {
		name = "Trickster",
		cost = 4,
		power = 0,
		ability = "OnReveal:SetPower:Highest_Enemy_Here",
		abilityText = "On Reveal: Set this card's Power equal to the highest-Power enemy card at this location.",
		rarity = "Rare",
		faction = "Shadow",
		artColor = Color3.fromRGB(100, 200, 180),
	},
	SHIELD_WALL = {
		name = "Shield Wall",
		cost = 4,
		power = 3,
		ability = "Ongoing:AddPower:Row:2",
		abilityText = "Ongoing: +2 Power to all other friendly cards in the same row as this card.",
		rarity = "Uncommon",
		faction = "Iron",
		artColor = Color3.fromRGB(80, 120, 200),
	},
	BERSERKER = {
		name = "Berserker",
		cost = 4,
		power = 4,
		ability = "OnReveal:ConditionalPower:Empty_Slots_Here:1",
		abilityText = "On Reveal: +1 Power for each empty slot on your side of this location.",
		rarity = "Common",
		faction = "Iron",
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
		faction = "Iron",
		artColor = Color3.fromRGB(200, 30, 30),
	},
	STORM_MAGE = {
		name = "Storm Mage",
		cost = 5,
		power = 5,
		ability = "OnReveal:RemovePower:All_Enemy_Here:2",
		abilityText = "On Reveal: -2 Power to all enemy cards at this location.",
		rarity = "Rare",
		faction = "Shadow",
		artColor = Color3.fromRGB(60, 60, 180),
	},
	WARLORD = {
		name = "Warlord",
		cost = 5,
		power = 1,
		ability = "Ongoing:DoublePower:Location",
		abilityText = "Ongoing: Double your total Power at this location (applied after all other modifiers).",
		rarity = "Legendary",
		faction = "Iron",
		artColor = Color3.fromRGB(180, 0, 0),
	},
	HIGH_PRIESTESS = {
		name = "High Priestess",
		cost = 5,
		power = 6,
		ability = "OnReveal:DrawCard:2",
		abilityText = "On Reveal: Draw 2 cards.",
		rarity = "Rare",
		faction = "Arcane",
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
		faction = "Iron",
		artColor = Color3.fromRGB(100, 100, 100),
	},
	OVERLORD = {
		name = "Overlord",
		cost = 6,
		power = 8,
		ability = "Ongoing:AddPower:AllLocations:1",
		abilityText = "Ongoing: +1 Power to all your other cards at both locations.",
		rarity = "Legendary",
		faction = "Arcane",
		artColor = Color3.fromRGB(60, 0, 60),
	},
	VOID_WALKER = {
		name = "Void Walker",
		cost = 6,
		power = 10,
		ability = "OnReveal:DestroyBelow:2:Here_Both",
		abilityText = "On Reveal: Destroy all cards with 2 or less Power at this location (both sides).",
		rarity = "Legendary",
		faction = "Shadow",
		artColor = Color3.fromRGB(30, 0, 50),
	},
	COLOSSUS = {
		name = "Colossus",
		cost = 6,
		power = 8,
		ability = "Ongoing:Immune",
		abilityText = "Ongoing: This card's Power cannot be reduced by enemy abilities.",
		rarity = "Rare",
		faction = "Iron",
		artColor = Color3.fromRGB(180, 160, 140),
	},

	-- ============================================================
	-- Arcane Faction — New Cards
	-- ============================================================
	ARCANIST = {
		name = "Arcanist",
		cost = 2,
		power = 1,
		ability = "OnReveal:DrawCard:1|Ongoing:AddPower:Self:PerOngoing",
		abilityText = "On Reveal: Draw 1 card. Ongoing: +1 Power for each other Ongoing card you control.",
		rarity = "Uncommon",
		faction = "Arcane",
		artColor = Color3.fromRGB(120, 80, 220),
	},
	RIFT_SCHOLAR = {
		name = "Rift Scholar",
		cost = 3,
		power = 3,
		ability = "OnReveal:AddPower:PerFaction_Arcane:1",
		abilityText = "On Reveal: +1 Power for each other Arcane card you control.",
		rarity = "Uncommon",
		faction = "Arcane",
		artColor = Color3.fromRGB(140, 100, 240),
	},
	SPELL_WEAVER = {
		name = "Spell Weaver",
		cost = 4,
		power = 5,
		ability = "OnReveal:Bounce:Weakest_Friendly_Here",
		abilityText = "On Reveal: Return your weakest card here to your hand.",
		rarity = "Rare",
		faction = "Arcane",
		artColor = Color3.fromRGB(180, 140, 255),
	},
	CHRONO_MAGE = {
		name = "Chrono Mage",
		cost = 4,
		power = 4,
		ability = "OnReveal:DrawCard:1|OnReveal:AddPower:Self:2",
		abilityText = "On Reveal: Draw 1 card. +2 Power to this card.",
		rarity = "Rare",
		faction = "Arcane",
		artColor = Color3.fromRGB(100, 150, 255),
	},
	ARCANE_SOVEREIGN = {
		name = "Arcane Sovereign",
		cost = 5,
		power = 5,
		ability = "Ongoing:AddPower:Faction_Arcane:1",
		abilityText = "Ongoing: +1 Power to all your other Arcane cards at all locations.",
		rarity = "Legendary",
		faction = "Arcane",
		artColor = Color3.fromRGB(160, 80, 255),
	},
	GRAND_ARCHIVIST = {
		name = "Grand Archivist",
		cost = 6,
		power = 7,
		ability = "OnReveal:AddPowerAll:1",
		abilityText = "On Reveal: +1 Power to ALL your other cards at ALL locations.",
		rarity = "Legendary",
		faction = "Arcane",
		artColor = Color3.fromRGB(200, 180, 255),
	},

	-- ============================================================
	-- Iron Faction — New Cards
	-- ============================================================
	SHIELD_BEARER = {
		name = "Shield Bearer",
		cost = 1,
		power = 1,
		ability = "Ongoing:NoPowerReduction:Location",
		abilityText = "Ongoing: Friendly cards at this location cannot lose Power from enemy effects.",
		rarity = "Uncommon",
		faction = "Iron",
		artColor = Color3.fromRGB(180, 180, 200),
	},
	BANNER_KNIGHT = {
		name = "Banner Knight",
		cost = 2,
		power = 2,
		ability = "OnReveal:AddPower:Faction_Iron:1",
		abilityText = "On Reveal: +1 Power to all Iron cards at this location.",
		rarity = "Common",
		faction = "Iron",
		artColor = Color3.fromRGB(200, 160, 80),
	},
	FORTRESS = {
		name = "Fortress",
		cost = 3,
		power = 4,
		ability = "Ongoing:AddPower:Adjacent:2",
		abilityText = "Ongoing: +2 Power to adjacent cards.",
		rarity = "Uncommon",
		faction = "Iron",
		artColor = Color3.fromRGB(160, 140, 120),
	},
	IRON_MARSHAL = {
		name = "Iron Marshal",
		cost = 4,
		power = 5,
		ability = "Ongoing:AddPower:Location:1|Ongoing:Immune",
		abilityText = "Ongoing: +1 Power to all other friendly cards here. Immune to enemy debuffs.",
		rarity = "Rare",
		faction = "Iron",
		artColor = Color3.fromRGB(170, 150, 130),
	},
	SIEGE_ENGINE = {
		name = "Siege Engine",
		cost = 5,
		power = 7,
		ability = "EndOfTurn:AddPower:Self:1",
		abilityText = "End of Turn: +1 Power each turn.",
		rarity = "Rare",
		faction = "Iron",
		artColor = Color3.fromRGB(120, 100, 80),
	},
	WAR_TITAN = {
		name = "War Titan",
		cost = 6,
		power = 11,
		ability = "OnReveal:RemovePower:All_Enemy_Here:1",
		abilityText = "On Reveal: -1 Power to all enemy cards at this location.",
		rarity = "Rare",
		faction = "Iron",
		artColor = Color3.fromRGB(140, 40, 40),
	},

	-- ============================================================
	-- Wild Faction — New Cards
	-- ============================================================
	SPROUT = {
		name = "Sprout",
		cost = 1,
		power = 0,
		ability = "EndOfTurn:AddPower:Self:1",
		abilityText = "End of Turn: +1 Power each turn.",
		rarity = "Common",
		faction = "Wild",
		artColor = Color3.fromRGB(120, 200, 80),
	},
	BLOOM_FAIRY = {
		name = "Bloom Fairy",
		cost = 2,
		power = 2,
		ability = "OnReveal:SummonCopy:Adjacent:1",
		abilityText = "On Reveal: Summon a 1-Power copy in a random empty adjacent slot.",
		rarity = "Common",
		faction = "Wild",
		artColor = Color3.fromRGB(255, 180, 220),
	},
	GROVE_TENDER = {
		name = "Grove Tender",
		cost = 2,
		power = 1,
		ability = "EndOfTurn:AddPower:AllFriendlyHere:1",
		abilityText = "End of Turn: +1 Power to all friendly cards at this location.",
		rarity = "Uncommon",
		faction = "Wild",
		artColor = Color3.fromRGB(60, 160, 60),
	},
	VINE_MOTHER = {
		name = "Vine Mother",
		cost = 3,
		power = 2,
		ability = "EndOfTurn:SummonToken:1",
		abilityText = "End of Turn: Summon a 1-Power token in a random empty slot here.",
		rarity = "Uncommon",
		faction = "Wild",
		artColor = Color3.fromRGB(40, 140, 40),
	},
	THORNGUARD = {
		name = "Thornguard",
		cost = 4,
		power = 5,
		ability = "OnDestroy:AddPower:AllFriendlyHere:3",
		abilityText = "On Destroy: +3 Power to all your other cards at this location.",
		rarity = "Rare",
		faction = "Wild",
		artColor = Color3.fromRGB(80, 120, 40),
	},
	ANCIENT_OAK = {
		name = "Ancient Oak",
		cost = 5,
		power = 4,
		ability = "EndOfTurn:AddPower:Self:2|Ongoing:AddPower:Adjacent:1",
		abilityText = "End of Turn: +2 Power to self. Ongoing: +1 Power to adjacent cards.",
		rarity = "Legendary",
		faction = "Wild",
		artColor = Color3.fromRGB(100, 80, 40),
	},
	WORLD_TREE = {
		name = "World Tree",
		cost = 6,
		power = 6,
		ability = "OnReveal:FillLocation:1|EndOfTurn:AddPower:AllFriendlyHere:2",
		abilityText = "On Reveal: Fill empty slots with 1-Power tokens. End of Turn: +2 Power to all friendlies here.",
		rarity = "Legendary",
		faction = "Wild",
		artColor = Color3.fromRGB(60, 100, 30),
	},

	-- ============================================================
	-- Shadow Faction — New Cards
	-- ============================================================
	PHANTOM = {
		name = "Phantom",
		cost = 1,
		power = 2,
		ability = "OnDestroy:Bounce:Self",
		abilityText = "On Destroy: Return this card to your hand instead.",
		rarity = "Uncommon",
		faction = "Shadow",
		artColor = Color3.fromRGB(140, 100, 160),
	},
	DARK_WHISPERER = {
		name = "Dark Whisperer",
		cost = 2,
		power = 1,
		ability = "OnReveal:RemovePower:All_Enemy_Here:1",
		abilityText = "On Reveal: -1 Power to all enemy cards at this location.",
		rarity = "Common",
		faction = "Shadow",
		artColor = Color3.fromRGB(80, 40, 100),
	},
	SOUL_THIEF = {
		name = "Soul Thief",
		cost = 3,
		power = 2,
		ability = "OnReveal:SwapPower:Random_Enemy_Here",
		abilityText = "On Reveal: Swap this card's Power with a random enemy card here.",
		rarity = "Rare",
		faction = "Shadow",
		artColor = Color3.fromRGB(100, 60, 140),
	},
	PLAGUE_RAT = {
		name = "Plague Rat",
		cost = 3,
		power = 4,
		ability = "EndOfTurn:DamageAll:1",
		abilityText = "End of Turn: -1 Power to all enemy cards at this location.",
		rarity = "Uncommon",
		faction = "Shadow",
		artColor = Color3.fromRGB(120, 100, 60),
	},
	DOOM_HERALD = {
		name = "Doom Herald",
		cost = 4,
		power = 3,
		ability = "OnReveal:RemovePower:Random_Enemy_Here:3|OnDestroy:SummonToken:5",
		abilityText = "On Reveal: -3 Power to a random enemy here. On Destroy: Summon a 5-Power token.",
		rarity = "Rare",
		faction = "Shadow",
		artColor = Color3.fromRGB(60, 20, 80),
	},
	SHADOW_LORD = {
		name = "Shadow Lord",
		cost = 5,
		power = 6,
		ability = "OnReveal:DestroyBelow:3:Here_Enemy|OnReveal:AddPower:Self:2",
		abilityText = "On Reveal: Destroy all enemies with 3 or less Power here. +2 Power to self.",
		rarity = "Legendary",
		faction = "Shadow",
		artColor = Color3.fromRGB(40, 0, 60),
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

-- Validate all card entries: checks required fields, ability parsing, and resolver existence
function CardDatabase.validate()
	local AbilityRegistry = require(script.Parent.AbilityRegistry)
	local errors = {}

	for _, id in ipairs(CardDatabase.getAllIDs()) do
		local card = CardDatabase[id]

		-- Check required fields
		if not card.name then table.insert(errors, id .. ": missing name") end
		if not card.cost or card.cost < 0 or card.cost > 10 then
			table.insert(errors, id .. ": invalid cost " .. tostring(card.cost))
		end
		if card.power == nil then
			table.insert(errors, id .. ": missing power")
		end
		if not card.rarity then table.insert(errors, id .. ": missing rarity") end
		if not card.faction then table.insert(errors, id .. ": missing faction") end
		if not card.artColor then table.insert(errors, id .. ": missing artColor") end

		-- Check ability resolves
		if card.ability then
			local subs = string.split(card.ability, "|")
			for _, sub in ipairs(subs) do
				local parsed = AbilityRegistry.parse(sub)
				if not parsed then
					table.insert(errors, id .. ": ability parse failed: " .. sub)
				elseif not AbilityRegistry.hasResolver(parsed.trigger, parsed.effect) then
					table.insert(errors, id .. ": no resolver for " .. parsed.trigger .. ":" .. parsed.effect)
				end
			end
		end

		-- Ability text should exist if ability exists
		if card.ability and not card.abilityText then
			table.insert(errors, id .. ": has ability but no abilityText")
		end
	end

	if #errors > 0 then
		print("=== CardDatabase Validation FAILED (" .. #errors .. " errors) ===")
		for _, err in ipairs(errors) do
			print("  ERROR: " .. err)
		end
	else
		print("=== CardDatabase Validation PASSED (" .. #CardDatabase.getAllIDs() .. " cards) ===")
	end

	return #errors == 0, errors
end

return CardDatabase
