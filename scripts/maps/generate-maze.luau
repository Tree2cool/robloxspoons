--!strict
-- Generates the adversarial maze stress fixture and its reachability oracle (plan 03-07, D-08, D-09).
--
--   lune run scripts/maps/generate-maze.luau [outputPath] [--footprint N] [--corridor N]
--       [--wall N] [--levels N] [--braid F] [--sealed N] [--thin N] [--seed N]
--
-- Default outputPath is build/maze.rbxm. An oracle sidecar is written beside it at <outputPath>.oracle.json.
--
-- D-08: Gate G2's stress fixture. An ORACLE FIRST, a stressor second.
--
-- Bake cost is O(sum over boxes of covered columns) + O(columns x spans); flood cost is
-- O(reached cells) and path length does not affect a queue. So a maze is NOT a time stressor for
-- BFS. What it adds is correctness pressure: long single-width paths (a recursive flood exhausts
-- Luau's call depth here), dead ends, many thin walls, a deliberately sealed region, and a set of
-- cell centres whose reachability is KNOWN IN ADVANCE.
--
-- Measured at the defaults: see .planning/phases/03-placement-rules-map-pipeline-and-validator/
-- 03-07-SUMMARY.md. tests/placement/maze.spec.luau holds the bake to a 2.0 s cap.
--
-- Pitfall 4, and the reason this script REFUSES a narrow corridor: at corridor 3 with capsule
-- radius 1.5 and grid 1, erosion leaves ZERO reached cells, while widths 4, 5 and 6 reach all N^2
-- maze-cell centres. A fixture asserting only "the sealed region was not reached" is trivially true
-- at width 3 and reads green while testing nothing: a gate that passes vacuously is worse than none.
--
-- LATTICE ALIGNMENT (load-bearing for that claim). The walkable grid's cell centres sit at
-- half-integers (its origin is the floor of Bounds.min, an integer, at GRID_SIZE 1). "Corridor width 3
-- erodes to nothing" holds only when the wall faces sit ON lattice centre lines, i.e. at half-integers.
-- So the maze starts at coordinate 0.5, and every wall face is a half-integer for any integer
-- corridor and wall. Move MAZE_ORIGIN off a half-integer and the corridor-3 control stops demonstrating
-- what the plan claims.
--
-- Determinism: an integer LCG, not math.random, so the emitted bytes are stable across Lune
-- versions. It is deliberately local rather than a require of src/server/engine/Rng.luau: that is
-- shipped code and tuning it must not change this fixture's bytes.
--
-- Level 0 is the only level linked to the spawn. Upper levels are copies of the same maze 24 studs
-- apart, intentionally unreachable; their cells still count toward bake cost, which is what makes this
-- a bake stress rather than a flood stress.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local rbx = roblox :: any

type Inst = roblox.Instance

-- Contract constants. Duplicated as literals on purpose: this script must stay runnable even if the
-- contract module moves. tests/placement/config_lock.spec.luau is where the shipped values are locked.
local TAG_DEFAULT_SPOT = "SpoonDefaultSpot"
local TAG_SEEKER_SPAWN = "SeekerSpawn"
local MIN_DEFAULT_SPOTS = 16
local CAPSULE_RADIUS = 1.5
local GRID_SIZE = 1.0

local WALL_HEIGHT = 20
local LEVEL_SPACING = 24
local THIN_THICKNESS = 0.3
-- The maze's outer-left face coordinate: a half-integer, see LATTICE ALIGNMENT above.
local MAZE_ORIGIN = 0.5

local function fail(message: string): never
	print(message)
	process.exit(1)
	error(message)
end

local USAGE =
	"usage: lune run scripts/maps/generate-maze.luau [outputPath] [--footprint N] [--corridor N] [--wall N] [--levels N] [--braid F] [--sealed N] [--thin N] [--seed N]"

local dials: { [string]: number } = {
	footprint = 248,
	corridor = 6,
	wall = 1,
	levels = 4,
	braid = 0,
	sealed = 1,
	thin = 1,
	seed = 20261104,
}

local outputPath = "build/maze.rbxm"
do
	local args: { string } = {}
	for _, a in process.args do
		-- Lune 0.11.1 passes a literal "--" separator through; tolerate it.
		if a ~= "--" then
			table.insert(args, a)
		end
	end
	local i = 1
	if args[1] ~= nil and string.sub(args[1], 1, 2) ~= "--" then
		outputPath = args[1]
		i = 2
	end
	while i <= #args do
		local flag = args[i]
		local key = string.match(flag, "^%-%-(%a+)$")
		if key == nil or dials[key] == nil then
			fail(`generate-maze: unknown argument {flag}\n{USAGE}`)
		end
		local value = tonumber(args[i + 1])
		if value == nil then
			fail(`generate-maze: --{key} needs a number\n{USAGE}`)
		end
		-- `fail` is typed `never`, but Luau does not narrow `key`/`value` through the call, so
		-- restate the invariant the two checks above have already enforced. Caught by the
		-- repo-wide standard-platform typecheck after merge: a worktree agent cannot run it,
		-- because the `--ignore "**/fixtures/**"` glob is refused there.
		dials[key :: string] = value :: number
		i += 2
	end
end

local footprint = dials.footprint
local corridor = dials.corridor
local wall = dials.wall
local levels = math.floor(dials.levels)
local braid = dials.braid
local sealed = math.floor(dials.sealed)
local thin = math.floor(dials.thin)
local seed = dials.seed

-- The refusal. Pitfall 4 prevented at the source rather than only detected downstream.
local minimum = 2 * CAPSULE_RADIUS + GRID_SIZE
if corridor < minimum then
	fail(
		`generate-maze: corridor {corridor} is below the minimum {minimum} (2 * capsuleRadius {CAPSULE_RADIUS} + gridSize {string.format(
			"%.1f",
			GRID_SIZE
		)});\n  erosion would leave zero walkable cells and every reachability assertion would pass vacuously`
	)
end
if wall <= 0 or levels < 1 or footprint <= 0 then
	fail(`generate-maze: --wall and --footprint must be positive and --levels at least 1\n{USAGE}`)
end

-- LCG: state = (state * 1103515245 + 12345) mod 2^31, the classic ANSI C constants. The product is
-- computed in two 16-bit halves so every intermediate stays below 2^53 and the arithmetic is exact.
local MODULUS = 2147483648
local MULT_LO, MULT_HI = 1103515245 % 65536, 1103515245 // 65536
local state = math.floor(seed) % MODULUS
local function nextInt(bound: number): number
	local product = (state * MULT_LO + ((state * MULT_HI) % MODULUS) * 65536) % MODULUS
	state = (product + 12345) % MODULUS
	return (state // 65536) % bound
end

local pitch = corridor + wall
local n = footprint // pitch
if n < 3 then
	fail(`generate-maze: footprint {footprint} with corridor {corridor} and wall {wall} gives only {n} cells per side`)
end
local total = n * pitch + wall -- outer extent of the walled maze along each axis

-- Edge state: 0 = wall, 1 = open passage, 2 = open slot holding a thin wall (link verification).
-- exState[j * n + i + 1] joins cell (i, j) to (i + 1, j); ezState joins (i, j) to (i, j + 1).
local exState: { number } = {}
local ezState: { number } = {}
for k = 1, n * n do
	exState[k] = 0
	ezState[k] = 0
end

local function cellId(i: number, j: number): number
	return j * n + i + 1
end

-- Iterative depth-first carve with an explicit stack.
do
	local visited: { boolean } = {}
	local stack: { number } = { cellId(0, 0) }
	visited[cellId(0, 0)] = true
	while #stack > 0 do
		local id = stack[#stack]
		local i, j = (id - 1) % n, (id - 1) // n
		local options: { { number } } = {}
		if i + 1 < n and not visited[cellId(i + 1, j)] then
			table.insert(options, { i + 1, j, 1 })
		end
		if i > 0 and not visited[cellId(i - 1, j)] then
			table.insert(options, { i - 1, j, 2 })
		end
		if j + 1 < n and not visited[cellId(i, j + 1)] then
			table.insert(options, { i, j + 1, 3 })
		end
		if j > 0 and not visited[cellId(i, j - 1)] then
			table.insert(options, { i, j - 1, 4 })
		end
		if #options == 0 then
			table.remove(stack)
		else
			local pick = options[nextInt(#options) + 1]
			local ni, nj, dir = pick[1], pick[2], pick[3]
			if dir == 1 then
				exState[cellId(i, j)] = 1
			elseif dir == 2 then
				exState[cellId(ni, nj)] = 1
			elseif dir == 3 then
				ezState[cellId(i, j)] = 1
			else
				ezState[cellId(ni, nj)] = 1
			end
			visited[cellId(ni, nj)] = true
			table.insert(stack, cellId(ni, nj))
		end
	end
end

-- Braid: knock out a fraction of the remaining interior walls.
if braid > 0 then
	for j = 0, n - 1 do
		for i = 0, n - 1 do
			if i + 1 < n and exState[cellId(i, j)] == 0 and nextInt(1000) < braid * 1000 then
				exState[cellId(i, j)] = 1
			end
			if j + 1 < n and ezState[cellId(i, j)] == 0 and nextInt(1000) < braid * 1000 then
				ezState[cellId(i, j)] = 1
			end
		end
	end
end

local function neighbours(id: number, out: { number })
	local i, j = (id - 1) % n, (id - 1) // n
	local count = 0
	if i + 1 < n and exState[id] == 1 then
		count += 1
		out[count] = cellId(i + 1, j)
	end
	if i > 0 and exState[cellId(i - 1, j)] == 1 then
		count += 1
		out[count] = cellId(i - 1, j)
	end
	if j + 1 < n and ezState[id] == 1 then
		count += 1
		out[count] = cellId(i, j + 1)
	end
	if j > 0 and ezState[cellId(i, j - 1)] == 1 then
		count += 1
		out[count] = cellId(i, j - 1)
	end
	for k = count + 1, #out do
		out[k] = nil
	end
end

-- Breadth-first reachability over the generator's own graph, from the spawn cell (0, 0).
local SPAWN_CELL = cellId(0, 0)
local function reachable(): ({ boolean }, number)
	local seen: { boolean } = { [SPAWN_CELL] = true }
	local queue: { number } = { SPAWN_CELL }
	local head = 1
	local scratch: { number } = {}
	while head <= #queue do
		local id = queue[head]
		head += 1
		neighbours(id, scratch)
		for _, other in scratch do
			if not seen[other] then
				seen[other] = true
				table.insert(queue, other)
			end
		end
	end
	return seen, #queue
end

local function degree(id: number): number
	local scratch: { number } = {}
	neighbours(id, scratch)
	return #scratch
end

local function wallOff(id: number)
	local i, j = (id - 1) % n, (id - 1) // n
	if i + 1 < n then
		exState[id] = 0
	end
	if i > 0 then
		exState[cellId(i - 1, j)] = 0
	end
	if j + 1 < n then
		ezState[id] = 0
	end
	if j > 0 then
		ezState[cellId(i, j - 1)] = 0
	end
end

-- Sealed pockets: prefer dead ends far from the spawn, so re-walling the single opening cuts off only the
-- pocket. Where no dead end remains, any cell far from the spawn is walled off entirely and the BFS below
-- still gives the exact answer, because the oracle is computed from the final graph rather than assumed.
local sealedPockets: { number } = {}
do
	local candidates: { number } = {}
	local fallback: { number } = {}
	for id = 1, n * n do
		local i, j = (id - 1) % n, (id - 1) // n
		if i + j >= n then
			if degree(id) == 1 then
				table.insert(candidates, id)
			elseif degree(id) > 1 then
				table.insert(fallback, id)
			end
		end
	end
	for _ = 1, sealed do
		local pool = if #candidates > 0 then candidates else fallback
		if #pool == 0 then
			break
		end
		local at = nextInt(#pool) + 1
		local id = pool[at]
		table.remove(pool, at)
		wallOff(id)
		table.insert(sealedPockets, id)
	end
end

-- Thin walls: a 0.3-thick wall across one carved passage, so the slot looks open on the lattice but a
-- link test between its two sides must be blocked. Choose a passage whose removal cuts off at most a
-- tenth of what is still open, so the positive half of the oracle stays meaningful.
local thinSlots: { { number } } = {} -- { axis (1 = x slot, 2 = z slot), i, j }
do
	for _ = 1, thin do
		local _, openCount = reachable()
		local placed = false
		for _ = 1, 400 do
			local i, j = nextInt(n), nextInt(n)
			local axis = nextInt(2) + 1
			local edges = if axis == 1 then exState else ezState
			local valid = if axis == 1 then i + 1 < n else j + 1 < n
			if valid and edges[cellId(i, j)] == 1 then
				edges[cellId(i, j)] = 2
				local _, after = reachable()
				if after < openCount and after * 10 >= openCount * 9 then
					table.insert(thinSlots, { axis, i, j })
					placed = true
					break
				end
				edges[cellId(i, j)] = 1
			end
		end
		if not placed then
			print("generate-maze: warning: no suitable passage found for a thin wall")
		end
	end
end

-- The oracle, from the final graph.
local seen, _ = reachable()

local function cellCentre(i: number, j: number): (number, number)
	return MAZE_ORIGIN + wall + i * pitch + corridor / 2, MAZE_ORIGIN + wall + j * pitch + corridor / 2
end

local openCells: { { [string]: number } } = {}
local sealedCells: { { [string]: number } } = {}
for j = 0, n - 1 do
	for i = 0, n - 1 do
		local cx, cz = cellCentre(i, j)
		local entry = { x = cx, y = 0.5, z = cz }
		if seen[cellId(i, j)] then
			table.insert(openCells, entry)
		else
			table.insert(sealedCells, entry)
		end
	end
end
assert(#openCells > 0 and #sealedCells > 0, "generate-maze: the oracle needs both open and sealed cells")
assert(#openCells + #sealedCells == n * n, "generate-maze: the oracle must cover every level-0 cell")
do
	-- A generator whose own oracle is wrong is worse than no oracle.
	local keys: { [string]: boolean } = {}
	for _, e in openCells do
		keys[`{e.x}:{e.z}`] = true
	end
	for _, e in sealedCells do
		assert(not keys[`{e.x}:{e.z}`], "generate-maze: a cell is both open and sealed")
	end
end

local function vec3(x: number, y: number, z: number): any
	return rbx.Vector3.new(x, y, z)
end

local function cframeAt(x: number, y: number, z: number): any
	return rbx.CFrame.new(x, y, z)
end

local function setProps(inst: Inst, props: { [string]: any })
	local untyped = inst :: any
	for key, value in props do
		untyped[key] = value
	end
end

local function make(className: string, name: string, parent: Inst?): Inst
	local inst = roblox.Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

local boxCount = 0
local function block(
	parent: Inst,
	name: string,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number
): Inst
	local part = make("Part", name, parent)
	setProps(part, { Size = vec3(sx, sy, sz), CFrame = cframeAt(x, y, z), Anchored = true, CanCollide = true })
	boxCount += 1
	return part
end

local function anchor(parent: Inst, name: string, cframe: any, tag: string?): Inst
	local part = make("Part", name, parent)
	setProps(part, {
		Size = vec3(1, 1, 1),
		CFrame = cframe,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
	})
	if tag ~= nil then
		part:AddTag(tag)
	end
	return part
end

local function anchorAt(parent: Inst, name: string, x: number, y: number, z: number, tag: string?): Inst
	return anchor(parent, name, cframeAt(x, y, z), tag)
end

local function buildLevel(geometry: Inst, level: number)
	local folder = make("Folder", `Level{level}`, geometry)
	local baseY = level * LEVEL_SPACING
	local middle = MAZE_ORIGIN + total / 2
	block(folder, "Floor", middle, baseY - 0.5, middle, total, 1, total)
	local midY = baseY + WALL_HEIGHT / 2
	local span = corridor + 2 * wall
	-- Wall lines across x (the walls between columns). A segment extends by `wall` at both ends so it also
	-- fills the intersection squares: any wall touching an intersection fills it completely.
	for k = 0, n do
		for j = 0, n - 1 do
			if k == 0 or k == n or exState[cellId(k - 1, j)] == 0 then
				local _, cz = cellCentre(0, j)
				block(folder, `WallX{k}_{j}`, MAZE_ORIGIN + k * pitch + wall / 2, midY, cz, wall, WALL_HEIGHT, span)
			end
		end
	end
	for k = 0, n do
		for i = 0, n - 1 do
			if k == 0 or k == n or ezState[cellId(i, k - 1)] == 0 then
				local cx, _ = cellCentre(i, 0)
				block(folder, `WallZ{k}_{i}`, cx, midY, MAZE_ORIGIN + k * pitch + wall / 2, span, WALL_HEIGHT, wall)
			end
		end
	end
	if level == 0 then
		for index, slot in thinSlots do
			local axis, i, j = slot[1], slot[2], slot[3]
			local cx, cz = cellCentre(i, j)
			if axis == 1 then
				block(
					folder,
					`ThinWall{index}`,
					MAZE_ORIGIN + (i + 1) * pitch + wall / 2,
					midY,
					cz,
					THIN_THICKNESS,
					WALL_HEIGHT,
					corridor
				)
			else
				block(
					folder,
					`ThinWall{index}`,
					cx,
					midY,
					MAZE_ORIGIN + (j + 1) * pitch + wall / 2,
					corridor,
					WALL_HEIGHT,
					THIN_THICKNESS
				)
			end
		end
	end
end

local function buildData(data: Inst): { string }
	local lowX = math.floor(MAZE_ORIGIN - 2)
	local highX = math.ceil(MAZE_ORIGIN + total + 2)
	local lowY = -2
	local highY = (levels - 1) * LEVEL_SPACING + WALL_HEIGHT + 4
	local bounds = anchorAt(data, "Bounds", (lowX + highX) / 2, (lowY + highY) / 2, (lowX + highX) / 2, nil)
	setProps(bounds, { Size = vec3(highX - lowX, highY - lowY, highX - lowX) })

	local sx, sz = cellCentre(0, 0)
	anchorAt(data, "HiderSpawn", sx, 3, sz, nil)
	local seekerSpawns = make("Folder", "SeekerSpawns", data)
	anchorAt(seekerSpawns, "Spawn1", sx, 3, sz, TAG_SEEKER_SPAWN)

	local defaultSpots = make("Folder", "DefaultSpots", data)
	local names: { string } = {}
	local spotNumber = 0
	local used: { [number]: boolean } = { [SPAWN_CELL] = true }
	-- Spots in open cells: MIN_DEFAULT_SPOTS + 2, chosen by the LCG from cells the oracle says are open.
	local openIds: { number } = {}
	for id = 1, n * n do
		if seen[id] and not used[id] then
			table.insert(openIds, id)
		end
	end
	for _ = 1, math.min(MIN_DEFAULT_SPOTS + 2, #openIds) do
		local at = nextInt(#openIds) + 1
		local id = openIds[at]
		openIds[at] = openIds[#openIds]
		openIds[#openIds] = nil
		spotNumber += 1
		local cx, cz = cellCentre((id - 1) % n, (id - 1) // n)
		anchorAt(defaultSpots, string.format("Spot%02d", spotNumber), cx, 0.5, cz, TAG_DEFAULT_SPOT)
	end
	-- One spot per sealed pocket: a deliberately unfindable default spot.
	for _, id in sealedPockets do
		spotNumber += 1
		local name = string.format("Spot%02d", spotNumber)
		local cx, cz = cellCentre((id - 1) % n, (id - 1) // n)
		anchorAt(defaultSpots, name, cx, 0.5, cz, TAG_DEFAULT_SPOT)
		table.insert(names, name)
	end

	make("Folder", "DecoyAnchors", data)

	-- Card table at the middle of the maze; seats on a radius-6 ring at 40-degree spacing, as the graybox does.
	local cardTable = make("Folder", "CardTable", data)
	local tableX, tableY, tableZ = MAZE_ORIGIN + total / 2, 3, MAZE_ORIGIN + total / 2
	anchorAt(cardTable, "TableAnchor", tableX, tableY, tableZ, nil)
	local seats = make("Folder", "Seats", cardTable)
	for i = 1, 9 do
		local a = math.rad((i - 1) * 40)
		local px = tableX + 6 * math.sin(a)
		local pz = tableZ - 6 * math.cos(a)
		local facing = rbx.CFrame.lookAt(vec3(px, tableY, pz), vec3(tableX, tableY, tableZ))
		anchor(seats, `Seat{i}`, facing, nil)
	end
	return names
end

local root = make("Model", "Maze", nil)
root:SetAttribute("ContractVersion", 2)
root:SetAttribute("DisplayName", "Maze Stress Fixture")
root:SetAttribute("MinPlayers", 3)
root:SetAttribute("MaxPlayers", 10)
root:SetAttribute("SizeClass", "Large")
local geometry = make("Folder", "Geometry", root)
for level = 0, levels - 1 do
	buildLevel(geometry, level)
end
local spotsInSealed = buildData(make("Folder", "Data", root))

local contents = roblox.serializeModel({ root })
local slash = string.match(outputPath, "^(.*)/[^/]*$")
if slash ~= nil and slash ~= "" then
	fs.writeDir(slash)
end
fs.writeFile(outputPath, contents)

local oracle = {
	seed = seed,
	footprint = footprint,
	corridor = corridor,
	wall = wall,
	levels = levels,
	gridSize = GRID_SIZE,
	capsuleRadius = CAPSULE_RADIUS,
	open = openCells,
	sealed = sealedCells,
	spotsInSealed = spotsInSealed,
}
fs.writeFile(`{outputPath}.oracle.json`, serde.encode("json", oracle))

print(
	`generate-maze: wrote {outputPath} ({#contents} bytes, {boxCount} boxes, {#openCells} open cells, {#sealedCells} sealed cells) and {outputPath}.oracle.json`
)
