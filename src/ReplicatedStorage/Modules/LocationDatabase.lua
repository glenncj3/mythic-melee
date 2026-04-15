local LocationDatabase = {
	CRYSTAL_CAVERN = {
		name = "Crystal Cavern",
		pointValue = 2,
		effect = nil,
		effectText = nil,
	},
	DRAGONS_PEAK = {
		name = "Dragon's Peak",
		pointValue = 3,
		effect = nil,
		effectText = nil,
	},
	SUNKEN_RUINS = {
		name = "Sunken Ruins",
		pointValue = 4,
		effect = nil,
		effectText = nil,
	},
	FROZEN_LAKE = {
		name = "Frozen Lake",
		pointValue = 2,
		effect = "OnPlay:AddPower:Self:-1",
		effectText = "Cards played here get -1 Power.",
	},
	WAR_CAMP = {
		name = "War Camp",
		pointValue = 3,
		effect = "OnPlay:AddPower:Self:1",
		effectText = "Cards played here get +1 Power.",
	},
	SHADOW_NEXUS = {
		name = "Shadow Nexus",
		pointValue = 3,
		effect = "SuppressOnReveal",
		effectText = "On Reveal abilities do not trigger here.",
	},
	VERDANT_GROVE = {
		name = "Verdant Grove",
		pointValue = 2,
		effect = "StartOfTurn:AddPower:AllHere:1",
		effectText = "At the start of each turn, +1 Power to all cards here (both players).",
	},
	SKY_TEMPLE = {
		name = "Sky Temple",
		pointValue = 4,
		effect = "Restrict:MinCost:3",
		effectText = "Only cards costing 3 or more can be played here.",
	},
	DUELING_GROUNDS = {
		name = "Dueling Grounds",
		pointValue = 3,
		effect = "Restrict:FrontRowOnly",
		effectText = "Each player can only use the front row (3 slots) here.",
	},
	MANA_WELL = {
		name = "Mana Well",
		pointValue = 2,
		effect = "OnPlay:DrawCard:1",
		effectText = "Whenever you play a card here, draw a card.",
	},

	-- ============================================================
	-- Vanilla Locations (no effect)
	-- ============================================================
	ANCIENT_ARENA = {
		name = "Ancient Arena",
		pointValue = 3,
		effect = nil,
		effectText = nil,
	},
	THRONE_ROOM = {
		name = "Throne Room",
		pointValue = 4,
		effect = nil,
		effectText = nil,
	},

	-- ============================================================
	-- Power Modifier Locations
	-- ============================================================
	ENCHANTED_SPRING = {
		name = "Enchanted Spring",
		pointValue = 2,
		effect = "OnPlay:AddPower:Self:2",
		effectText = "Cards played here get +2 Power.",
	},
	CURSED_BOG = {
		name = "Cursed Bog",
		pointValue = 3,
		effect = "OnPlay:AddPower:Self:-2",
		effectText = "Cards played here get -2 Power.",
	},
	MIRROR_LAKE = {
		name = "Mirror Lake",
		pointValue = 3,
		effect = "OnPlay:AddPower:Self:PerTurn",
		effectText = "Cards played here get +1 Power per current turn number.",
	},

	-- ============================================================
	-- Card Draw Locations
	-- ============================================================
	SCHOLARS_TOWER = {
		name = "Scholar's Tower",
		pointValue = 2,
		effect = "OnPlay:DrawCard:2",
		effectText = "Whenever you play a card here, draw 2 cards.",
	},
	LIBRARY = {
		name = "Library",
		pointValue = 2,
		effect = "StartOfTurn:DrawCard:BothPlayers:1",
		effectText = "At the start of each turn, both players draw 1 extra card.",
	},

	-- ============================================================
	-- Restriction Locations
	-- ============================================================
	PROVING_GROUNDS = {
		name = "Proving Grounds",
		pointValue = 3,
		effect = "Restrict:MaxCost:3",
		effectText = "Only cards costing 3 or less can be played here.",
	},
	SACRED_GROVE = {
		name = "Sacred Grove",
		pointValue = 3,
		effect = "Restrict:NoAbility",
		effectText = "Only vanilla cards (no abilities) can be played here.",
	},
	SILENCE_CHAMBER = {
		name = "Silence Chamber",
		pointValue = 2,
		effect = "Restrict:NoOngoing",
		effectText = "Ongoing cards cannot be played here.",
	},
	TITANS_GATE = {
		name = "Titan's Gate",
		pointValue = 4,
		effect = "Restrict:MinCost:5",
		effectText = "Only cards costing 5 or more can be played here.",
	},

	-- ============================================================
	-- Destruction Locations
	-- ============================================================
	DEATH_HOLLOW = {
		name = "Death Hollow",
		pointValue = 3,
		effect = "EndOfTurn:DestroyWeakest:Here",
		effectText = "At end of turn, the weakest card here is destroyed (either side).",
	},
	VOLCANIC_RIFT = {
		name = "Volcanic Rift",
		pointValue = 3,
		effect = "EndOfTurn:DamageAll:Here:1",
		effectText = "At end of turn, -1 Power to all cards here (both sides).",
	},

	-- ============================================================
	-- Growth Locations
	-- ============================================================
	GROWING_MEADOW = {
		name = "Growing Meadow",
		pointValue = 2,
		effect = "StartOfTurn:AddPower:AllHere:2",
		effectText = "At the start of each turn, +2 Power to all cards here (both players).",
	},
	BLOOD_PIT = {
		name = "Blood Pit",
		pointValue = 4,
		effect = "OnPlay:AddPower:Self:-1|StartOfTurn:AddPower:AllHere:1",
		effectText = "Cards played here get -1 Power, but all cards here gain +1 Power each turn.",
	},

	-- ============================================================
	-- Unique Locations
	-- ============================================================
	WASTELAND = {
		name = "Wasteland",
		pointValue = 4,
		effect = "SuppressOnReveal",
		effectText = "On Reveal abilities do not trigger here.",
	},
	HAUNTED_RUINS = {
		name = "Haunted Ruins",
		pointValue = 3,
		effect = "OnPlay:SummonToken:Opponent:1",
		effectText = "When you play a card here, your opponent gets a 1-Power token.",
	},
	HEALING_SHRINE = {
		name = "Healing Shrine",
		pointValue = 2,
		effect = "StartOfTurn:AddPower:AllHere:1",
		effectText = "At the start of each turn, +1 Power to all cards here (both players).",
	},
}

-- Utility: get list of all location IDs
function LocationDatabase.getAllIDs()
	local ids = {}
	for id, _ in pairs(LocationDatabase) do
		if type(LocationDatabase[id]) == "table" then
			table.insert(ids, id)
		end
	end
	return ids
end

-- Debug: print all locations
function LocationDatabase.printAll()
	print("=== Location Database ===")
	for _, id in ipairs(LocationDatabase.getAllIDs()) do
		local loc = LocationDatabase[id]
		local effectStr = loc.effectText or "No effect"
		print(string.format("  [%s] %s — %d pts — %s", id, loc.name, loc.pointValue, effectStr))
	end
end

return LocationDatabase
