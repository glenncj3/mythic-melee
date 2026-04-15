local GameConfig = require(script.Parent.GameConfig)

local SlotGrid = {}

function SlotGrid.isValidSlot(col, row)
	return col >= 1 and col <= GameConfig.GRID_COLUMNS
		and row >= 1 and row <= GameConfig.GRID_ROWS
end

function SlotGrid.getAdjacent(col, row)
	local neighbors = {}
	local offsets = { {-1, 0}, {1, 0}, {0, -1}, {0, 1} }
	for _, offset in ipairs(offsets) do
		local nc, nr = col + offset[1], row + offset[2]
		if SlotGrid.isValidSlot(nc, nr) then
			table.insert(neighbors, {nc, nr})
		end
	end
	return neighbors
end

function SlotGrid.getRow(row)
	local slots = {}
	for col = 1, GameConfig.GRID_COLUMNS do
		table.insert(slots, {col, row})
	end
	return slots
end

function SlotGrid.getColumn(col)
	local slots = {}
	for row = 1, GameConfig.GRID_ROWS do
		table.insert(slots, {col, row})
	end
	return slots
end

function SlotGrid.getAllSlots()
	local slots = {}
	for row = 1, GameConfig.GRID_ROWS do
		for col = 1, GameConfig.GRID_COLUMNS do
			table.insert(slots, {col, row})
		end
	end
	return slots
end

---------- Debug helpers ----------

function SlotGrid.printAdjacencyMap()
	print("=== SlotGrid Adjacency Map ===")
	for _, slot in ipairs(SlotGrid.getAllSlots()) do
		local col, row = slot[1], slot[2]
		local adj = SlotGrid.getAdjacent(col, row)
		local names = {}
		for _, a in ipairs(adj) do
			table.insert(names, string.format("(%d,%d)", a[1], a[2]))
		end
		print(string.format("  (%d,%d) -> %s", col, row, table.concat(names, ", ")))
	end
end

return SlotGrid
