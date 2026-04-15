local GameConfig = {
	DECK_SIZE = 20,
	MAX_COPIES_PER_CARD = 1,
	LOCATIONS_PER_GAME = 2,
	SLOTS_PER_LOCATION = 3,
	GRID_COLUMNS = 3,
	GRID_ROWS = 1,
	STARTING_HAND_SIZE = 3,
	STARTING_MAX_ENERGY = 0,
	ENERGY_PER_TURN = 1,
	CARDS_DRAWN_PER_TURN = 1,
	MAX_HAND_SIZE = 6,
	TURN_TIMER_SECONDS = 30,
	POINTS_TO_WIN = 20,

	-- Starter deck (20 cards, used for new players and the bot)
	-- Balanced across all 4 factions and all trigger types
	-- Curve: 4x1-cost, 4x2-cost, 4x3-cost, 4x4-cost, 2x5-cost, 2x6-cost
	STARTER_DECK = {
		-- 1-cost (Iron, Arcane, Wild, Shadow)
		"SPARK", "SCOUT", "SPROUT", "PHANTOM",
		-- 2-cost (Iron, Iron, Wild, Shadow)
		"IRON_GUARD", "LOOKOUT", "BLOOM_FAIRY", "DARK_WHISPERER",
		-- 3-cost (Iron, Wild, Shadow, Arcane)
		"STONE_GOLEM", "HEALER", "SABOTEUR", "RIFT_SCHOLAR",
		-- 4-cost (Iron, Iron, Wild, Iron)
		"WAR_BEAST", "COMMANDER", "THORNGUARD", "SHIELD_WALL",
		-- 5-cost (Iron, Iron)
		"DRAGON", "SIEGE_ENGINE",
		-- 6-cost (Iron, Arcane)
		"TITAN", "GRAND_ARCHIVIST",
	},
}

return GameConfig
