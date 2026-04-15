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
