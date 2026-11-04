--!strict
-- MAP-01 contract. PURE ZONE: no Roblox API. The validator consumes a plain-data snapshot so the same code
-- runs in CI (Lune, from a .rbxm) and at runtime (server, from a live object tree).
--
-- Layout every map must obey (single top-level Model per .rbxm, mounted at ServerStorage.Maps.<MapId>):
--   <MapId>              Model   attributes: ContractVersion, DisplayName, MinPlayers, MaxPlayers, SizeClass
--     Geometry/          Folder  the ONLY thing ever cloned into Workspace; no code of any kind
--     Data/              Folder  server-only, never cloned (CLAUDE.md rule 3: hidden data is never replicated)
--       Bounds           Part    one axis-aligned box centred on its position (D-19)
--       HiderSpawn       Part
--       SeekerSpawns/    Folder  >= 1 Part tagged TAG_SEEKER_SPAWN
--       DefaultSpots/    Folder  >= MIN_DEFAULT_SPOTS Parts tagged TAG_DEFAULT_SPOT
--       DecoyAnchors/    Folder  0..n Parts tagged TAG_DECOY_ANCHOR (the folder is required even when empty)
--       CardTable/       Folder
--         TableAnchor    Part
--         Seats/         Folder  exactly Seat1..Seat9 (9 = 10 players minus the hider, D-11)
--
-- Contract version 2 decisions, recorded so a later reader does not re-open them:
--   * `shape` is in scope for v2 (research Pitfall 9, assumption A4). Part.Shape reads under Lune 0.11.1, but a
--     Ball or Cylinder Part has className "Part", so without `shape` a sphere would be modelled as a box. The
--     geometry layer is reject-biased: only className == "Part" with shape == "Block" is a standable, blocking
--     box; every other collidable BasePart contributes its bounding box as blocking-only and never standable. A
--     mesh floor therefore yields no footing and the map author fixes it by modelling floors as Parts.
--   * A ContractVersion 1 map is rejected outright, not migrated. The version check is exact equality against
--     CONTRACT_VERSION, so this is free; the graybox is the only v1 map and it is regenerated in this phase.
export type Vec3 = { x: number, y: number, z: number }
export type Pose = { position: Vec3, look: Vec3 }
export type SizeClass = "Small" | "Medium" | "Large"
export type MapMetadata = {
	contractVersion: number,
	id: string,
	displayName: string,
	minPlayers: number,
	maxPlayers: number,
	sizeClass: SizeClass,
}
export type Aabb = { min: Vec3, max: Vec3 }
export type MapSpec = {
	metadata: MapMetadata,
	bounds: Aabb,
	hiderSpawn: Pose,
	seekerSpawns: { Pose },
	defaultSpots: { Pose },
	decoyAnchors: { Pose },
	cardTable: { anchor: Pose, seats: { Pose } },
}
-- The plain-data snapshot the validator consumes. Both snapshotters (the Lune CLI and the runtime
-- loader) MUST emit exactly this shape, field for field. position/size/look/up/anchored/canCollide
-- are present for BaseParts and absent for Models and Folders. `shape` is present only when
-- className == "Part" (Shape is a Part property; a MeshPart or WedgePart has no Shape).
--
-- CONTRACT VERSION 2 (D-02, D-03). `up` is the part's CFrame.UpVector: without it a roll about the
-- look axis is invisible and the graybox Ramp snapshots as a flat floating slab, which culls the
-- four ledge spots and fails MIN_DEFAULT_SPOTS. The third basis vector is `look x up` (verified
-- against the committed Ramp: look = (0,0,-1), up = (0.42111206, 0.90701294, 0), and
-- look x up = (0.90701294, -0.42111206, 0) = the part's RightVector).
export type Node = {
	name: string,
	className: string,
	attributes: { [string]: string | number | boolean },
	tags: { string },
	position: Vec3?,
	size: Vec3?,
	look: Vec3?,
	up: Vec3?,
	anchored: boolean?,
	canCollide: boolean?,
	shape: string?,
	children: { Node },
}
export type Issue = { code: string, path: string, message: string }

local MapContract = {
	CONTRACT_VERSION = 2,
	MIN_DEFAULT_SPOTS = 16,
	SEAT_COUNT = 9, -- max seekers = 10 players - 1 hider (D-11)
	MAX_DISPLAY_NAME = 48,
	MIN_PLAYERS_FLOOR = 3,
	MAX_PLAYERS_CEILING = 10,
	TAG_DEFAULT_SPOT = "SpoonDefaultSpot",
	TAG_SEEKER_SPAWN = "SeekerSpawn",
	TAG_DECOY_ANCHOR = "DecoyAnchor",
	-- Every stable issue code the validator can emit. Tests assert by code and check this list is fully covered.
	ISSUE_CODES = {
		"MAP_BOUNDS_INVALID",
		"MAP_META_INVALID",
		"MAP_MISSING_FOLDER",
		"MAP_MISSING_PART",
		"MAP_NODE_BASIS_INVALID",
		"MAP_OUT_OF_BOUNDS",
		"MAP_ROOT_INVALID",
		"MAP_SCRIPT_FORBIDDEN",
		"MAP_SEAT_COUNT",
		"MAP_SEAT_NAME",
		"MAP_SPAWN_COUNT",
		"MAP_SPOT_COUNT",
		"MAP_TAG_OUTSIDE_FOLDER",
	} :: { string },
}

return MapContract
