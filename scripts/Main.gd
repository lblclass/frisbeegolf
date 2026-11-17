extends Node2D

# =============================================================
# Disc Golf — v0.3 Stage 1 (mechanics rewrite)
#
# Changes vs v0.2:
#   • Power tiers: PUTT / MID / HUCK auto-selected from drag length,
#     can be force-overridden with Z / X / C
#   • BH/FH characteristics matrix (per tier) — accuracy ≠ distance
#   • Visible release offset (BH from player's left, FH from right)
#   • Post-landing roll governed by hyzer + surface friction
#   • Surface zones per hole: fairway / short / rough / sand / water
#   • Water = +1 stroke penalty, drop at last in-bounds crossing
#   • Basket spit-out: hot drives have a chance to deflect out
#   • Predicted trajectory ghost line while aiming (Pro Mode toggles off)
#   • Hyzer disc icon visibly tilts; "horizon" gauge above
#
# Stage 2 will add: 9-hole course, camera follow, larger world,
#                   updated tutorial cards.
# =============================================================

const FIELD_WIDTH := 1280            # viewport width (visible area)
const FIELD_HEIGHT := 720            # viewport height
const POWER_FOR_FULL := 300.0  # drag pixels for max-effort
const PX_PER_METER := 8.0      # logical scale: 1m ≈ 8px (field ≈ 160m wide)
const BASKET_RADIUS := 26.0
const BASKET_CATCH_RADIUS := 24.0
const BASKET_CATCH_SPEED := 50.0    # below this AND centered: guaranteed catch
const BASKET_HOT_SPEED := 700.0     # above this = max spit-out chance
const ROLL_STOP_SPEED := 8.0        # final rest

# --- Aerodynamic / physics constants (v0.3 physics rewrite) ---
const GRAVITY := 200.0              # px/s² downward
const LIFT_BASE := 280.0            # lift accel coefficient; lift ≈ LIFT_BASE × speed_ratio
const MAX_BANK := 1.2               # radians (~70°) full-bank cap
const TURN_TORQUE := 0.9            # bank-rate scalar for "turn" rating
const FADE_TORQUE := 1.2            # bank-rate scalar for "fade" rating
const HYZER_RESTORE := 1.4          # rate restoring bank toward release set-point
const LIFT_LATERAL_SCALE := 1.7     # how strongly bank steers the flight

enum State { TITLE, TUTORIAL, PLAYING, HOLE_COMPLETE, LEVEL_INTRO, LEVEL_COMPLETE, LEVEL_SELECT, ROUND_COMPLETE }
enum GameMode { CAMPAIGN, FREE }
const SAVE_PATH := "user://records.json"

# =============================================================
# Throw mode tiers
# =============================================================
enum ThrowMode { PUTT, MID, HUCK }

# Drag fraction thresholds for auto mode selection
const DRAG_PUTT_MAX := 0.30
const DRAG_MID_MAX := 0.70

# Per-tier characteristics (lookup tables)
# Distance fraction is what % of a disc's potential range each tier reaches.
const MODE_DIST_FRAC := {
	ThrowMode.PUTT: 0.40,
	ThrowMode.MID:  0.70,
	ThrowMode.HUCK: 1.00,
}

# Style x mode → jitter degrees. Captures real-world rules:
#   - Putt: BH dominant (wrist control), FH less accurate
#   - Mid:  both equal
#   - Huck: BH max range / more spread, FH tighter
const JITTER_DEG := {
	ThrowMode.PUTT: { 0: 1.0,  1: 2.0 },  # 0=BH, 1=FH
	ThrowMode.MID:  { 0: 2.5,  1: 2.5 },
	ThrowMode.HUCK: { 0: 5.0,  1: 3.0 },
}

# Range multiplier per hand (BH inherently outranges FH at every tier)
const HAND_RANGE_MULT := { 0: 1.00, 1: 0.85 }

const MODE_NAMES := { ThrowMode.PUTT: "PUTT", ThrowMode.MID: "MID", ThrowMode.HUCK: "HUCK" }
const MODE_COLORS := {
	ThrowMode.PUTT: Color(0.4, 1.0, 0.4),
	ThrowMode.MID:  Color(1.0, 0.85, 0.3),
	ThrowMode.HUCK: Color(1.0, 0.4, 0.4),
}

# =============================================================
# Surface system
# =============================================================
enum Surface { FAIRWAY, SHORT_GRASS, ROUGH, SAND, WATER, HARD_GROUND }

# Drag multipliers during roll phase. 1.0 = normal; higher = stops faster.
const SURFACE_ROLL_DRAG := {
	Surface.FAIRWAY:     1.0,
	Surface.SHORT_GRASS: 1.6,
	Surface.ROUGH:       5.0,
	Surface.SAND:        8.0,
	Surface.WATER:       1.0,  # n/a — water triggers penalty
	Surface.HARD_GROUND: 0.35, # slick, rolls FARTHER than fairway
}

const SURFACE_COLORS := {
	Surface.FAIRWAY:     Color(0.48, 0.70, 0.38),
	Surface.SHORT_GRASS: Color(0.42, 0.62, 0.32),
	Surface.ROUGH:       Color(0.28, 0.42, 0.20),
	Surface.SAND:        Color(0.85, 0.75, 0.45),
	Surface.WATER:       Color(0.30, 0.55, 0.85),
	Surface.HARD_GROUND: Color(0.62, 0.62, 0.66),  # concrete/asphalt grey
}

# =============================================================
# Disc types
# =============================================================
class DiscType:
	var name: String
	var speed: float
	var glide: float
	var turn: float
	var fade: float
	var color: Color
	func _init(n: String, s: float, g: float, t: float, f: float, c: Color) -> void:
		name = n; speed = s; glide = g; turn = t; fade = f; color = c

var discs: Array[DiscType] = [
	DiscType.new("Putter", 3.0, 4.0,  0.0, 1.0, Color(0.95, 0.95, 1.0)),
	DiscType.new("Mid",    5.0, 5.0, -1.0, 1.0, Color(1.0, 0.85, 0.3)),
	DiscType.new("Driver", 9.0, 5.0, -2.0, 2.0, Color(1.0, 0.35, 0.3)),
]
var current_disc_idx: int = 1

enum ThrowStyle { BACKHAND, FOREHAND }
var throw_style: int = ThrowStyle.BACKHAND

# Mode override: -1 = auto, otherwise ThrowMode enum value
var mode_override: int = -1

# Pro mode hides the predicted trajectory ghost.
var pro_mode: bool = false

# =============================================================
# Holes (with surface zones)
# =============================================================
class SurfaceZone:
	var type: int
	var polygon: PackedVector2Array
	func _init(t: int, p: PackedVector2Array) -> void:
		type = t; polygon = p

class WindZone:
	var polygon: PackedVector2Array
	var wind: Vector2
	func _init(p: PackedVector2Array, w: Vector2) -> void:
		polygon = p; wind = w

class Mando:
	# Line segment that the disc MUST pass on the `required_side` side.
	# Side is determined by sign((p2-p1) × (disc-p1))  — +1 = left of dir, -1 = right.
	var p1: Vector2
	var p2: Vector2
	var required_side: int    # +1 or -1
	var label: String         # short text (e.g. "MANDO →")
	func _init(a: Vector2, b: Vector2, side: int, lbl: String = "MANDO") -> void:
		p1 = a; p2 = b; required_side = side; label = lbl

class Portal:
	# Circular teleport region. Disc entering this circle (in flight) is
	# instantly relocated to `dest` keeping its velocity (rotated to face dest).
	# `pair_color` lets us draw paired portals consistently.
	var pos: Vector2
	var radius: float
	var dest: Vector2
	var pair_color: Color
	func _init(p: Vector2, r: float, d: Vector2, c: Color) -> void:
		pos = p; radius = r; dest = d; pair_color = c

class Hole:
	var name: String
	var tee: Vector2
	var basket: Vector2
	var par: int
	func _init(n: String, t: Vector2, b: Vector2, p: int) -> void:
		name = n; tee = t; basket = b; par = p

class Level:
	var name: String
	var bounds: Vector2
	var holes: Array[Hole]
	var obstacles: Array
	var zones: Array[SurfaceZone]
	var wind: Vector2
	var wind_zones: Array[WindZone]
	var mandos: Array[Mando]              # optional gates
	var portals: Array[Portal]            # optional teleport pairs
	var allowed_discs: Array[int]          # if non-empty, only these disc indices allowed
	var theme_grass_color: Color           # optional override for base grass tint
	func _init(n: String, bnd: Vector2, hs: Array[Hole], obs: Array,
			zs: Array[SurfaceZone], w: Vector2, wz: Array[WindZone] = [],
			md: Array[Mando] = [], pt: Array[Portal] = [],
			ad: Array[int] = [], tg: Color = Color(0, 0, 0, 0)) -> void:
		name = n; bounds = bnd; holes = hs; obstacles = obs; zones = zs
		wind = w; wind_zones = wz; mandos = md; portals = pt
		allowed_discs = ad; theme_grass_color = tg

var holes: Array[Hole] = []           # currently-active hole list (level swap)
var levels: Array[Level] = []          # the 5 real levels
var round_holes: Array[Hole] = []      # holes of current playing level (cached)
var tutorial_holes: Array[Hole] = []   # 5 practice scenes (each its own pseudo-level)
var current_level: Level               # current Level (round or tutorial wrapper)
var current_level_idx: int = 0         # which round level we're on
var tutorial_titles: Array[String] = []
var tutorial_lines: Array = []          # Array[PackedStringArray]
var tutorial_hints: Array[String] = []
var tutorial_pseudo_levels: Array[Level] = []  # one-hole Levels for each tutorial scene
var is_tutorial: bool = false
var tutorial_done_current: bool = false
var current_hole_idx: int = 0
var stroke_count: int = 0
var hole_scores: Array[int] = []
var level_scores: Array = []           # Array of Array[int] — one row per level

# --- Persistent records + game mode ---
var records: Dictionary = {}          # int level_idx → int best_total
var levels_unlocked: Dictionary = {}  # int level_idx → bool (true = unlocked)
var game_mode: int = GameMode.CAMPAIGN
var menu_idx: int = 0                  # selected item on title menu
var level_select_idx: int = 0          # selected level on level-select screen
var level_select_scroll: int = 0       # scroll offset (top visible row)
const LEVEL_SELECT_ROWS_VISIBLE := 9

# =============================================================
# Disc / flight / roll state
# =============================================================
var disc_pos: Vector2
var disc_vel: Vector2 = Vector2.ZERO
var disc_flying: bool = false
var disc_rolling: bool = false

var flight_time: float = 0.0
var hyzer_at_release: float = 0.0
var disc_at_release: int = 1
var style_at_release: int = ThrowStyle.BACKHAND
var power_at_release: float = 0.0  # 0..1, scales lateral forces

# True 3D-ish state: bank evolves over time; height/vz model lift vs gravity.
var disc_bank: float = 0.0          # radians; +bank = hyzer for RHBH
var disc_height: float = 0.0        # px above ground (>= 0)
var disc_vz: float = 0.0            # vertical velocity px/s, +up
var launch_height: float = 32.0     # release height (px) — set per throw by mode

const LAUNCH_HEIGHT_PUTT := 60.0    # high release: chains down to disc
const LAUNCH_HEIGHT_MID  := 38.0    # mid release
const LAUNCH_HEIGHT_HUCK := 18.0    # low release: disc rises on lift
var trail: Array[Vector2] = []          # flight trail (white)
var roll_trail: Array[Vector2] = []     # roll trail (brown)

# Mando: per-throw tracking. mando_side[i] = side disc was on at start;
# at throw end we compare with where disc ended up to detect crossing.
var mando_pre_side: Array[int] = []
var mando_passed: Array[bool] = []  # which mandos have been satisfied this throw
var mando_violated_msg: bool = false
var portal_cooldown: float = 0.0      # seconds before a teleported disc can re-trigger
var last_trail_pos: Vector2
var flight_duration_est: float = 1.0    # estimated total flight time (for height curve)
var roll_sfx_timer: float = 0.0          # countdown between roll-tick sounds

# Last in-bounds (non-water) position — used for water-penalty drop
var last_safe_pos: Vector2

# =============================================================
# Input
# =============================================================
var aim_dragging: bool = false
var aim_start: Vector2          # screen coords
var aim_current: Vector2        # screen coords
var hyzer_angle: float = 0.0

# Camera: top-left corner of viewport in WORLD coords.
var camera_pos: Vector2 = Vector2.ZERO

# Predicted trajectory cache
var predicted_path: PackedVector2Array = PackedVector2Array()

# =============================================================
# Game state
# =============================================================
var state: int = State.TITLE
var tutorial_page: int = 0
var landing_msg: String = ""
var landing_msg_timer: float = 0.0

# =============================================================
# Audio
# =============================================================
var sfx_throw: AudioStreamWAV
var sfx_chain: AudioStreamWAV
var sfx_rim: AudioStreamWAV
var sfx_land: AudioStreamWAV
var sfx_roll: AudioStreamWAV
var sfx_tree: AudioStreamWAV
var sfx_splash: AudioStreamWAV
var sfx_click: AudioStreamWAV
var audio_player: AudioStreamPlayer
var roll_player: AudioStreamPlayer

# =============================================================
# Lifecycle
# =============================================================
func _ready() -> void:
	_init_holes()
	_init_tutorial_scenes()
	_init_audio()
	_load_records()
	disc_pos = Vector2.ZERO

# --- Persistence ---
func _load_records() -> void:
	records = {}
	levels_unlocked = {}
	# Level 0 always unlocked
	levels_unlocked[0] = true
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var raw_records = parsed.get("records", {})
	var raw_unlocked = parsed.get("unlocked", {})
	if typeof(raw_records) == TYPE_DICTIONARY:
		for k in raw_records.keys():
			records[int(k)] = int(raw_records[k])
	if typeof(raw_unlocked) == TYPE_DICTIONARY:
		for k in raw_unlocked.keys():
			levels_unlocked[int(k)] = bool(raw_unlocked[k])

func _save_records() -> void:
	var rec_str := {}
	for k in records.keys():
		rec_str[str(k)] = int(records[k])
	var unl_str := {}
	for k in levels_unlocked.keys():
		unl_str[str(k)] = bool(levels_unlocked[k])
	var data := { "records": rec_str, "unlocked": unl_str }
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

func _record_level_score(li: int, total: int) -> bool:
	# Returns true if this is a new best.
	var existing: int = 9999
	if records.has(li):
		existing = int(records[li])
	if total < existing:
		records[li] = total
		_save_records()
		return true
	return false

func _unlock_level(li: int) -> void:
	if li < 0 or li >= levels.size():
		return
	levels_unlocked[li] = true
	_save_records()

func _init_holes() -> void:
	levels = []
	levels.append(_build_level_1())
	levels.append(_build_level_2())
	levels.append(_build_level_3())
	levels.append(_build_level_4())
	levels.append(_build_level_5())
	levels.append(_build_level_6_boomerang())
	levels.append(_build_level_7_multi_lane())
	levels.append(_build_level_8_winter())
	levels.append(_build_level_9_mandatory())
	levels.append(_build_level_10_islands())
	levels.append(_build_level_11_wind_tunnel())
	levels.append(_build_level_12_one_disc())
	levels.append(_build_level_13_portals())
	current_level_idx = 0
	current_level = levels[0]
	round_holes = current_level.holes
	holes = round_holes

# Helpers for building level content -------------------------------

func _tree(p: Vector2, r: float) -> Dictionary:
	return { "pos": p, "radius": r }

func _zone(t: int, pts: Array) -> SurfaceZone:
	var pa := PackedVector2Array()
	for v in pts:
		pa.append(v)
	return SurfaceZone.new(t, pa)

func _windz(pts: Array, w: Vector2) -> WindZone:
	var pa := PackedVector2Array()
	for v in pts:
		pa.append(v)
	return WindZone.new(pa, w)

# =============================================================
# LEVEL 1 — Open Meadow (the original 3 holes, kept verbatim feel)
# Map = single viewport, 3 holes chained tee→basket→tee→basket.
# =============================================================
func _build_level_1() -> Level:
	var bounds: Vector2 = Vector2(1280, 720)
	# Holes chain: h1 basket = h2 tee, h2 basket = h3 tee
	var h1: Hole = Hole.new("1-1 Open Meadow", Vector2(150, 600), Vector2(1100, 200), 3)
	var h2: Hole = Hole.new("1-2 Wooded Dogleg", Vector2(1100, 200), Vector2(150, 550), 3)
	var h3: Hole = Hole.new("1-3 Hazards", Vector2(150, 550), Vector2(1130, 360), 4)
	var holes_l1: Array[Hole] = [h1, h2, h3]
	var obstacles: Array = [
		_tree(Vector2(600, 500), 28.0),
		_tree(Vector2(820, 350), 32.0),
		_tree(Vector2(380, 280), 28.0),
		_tree(Vector2(520, 400), 30.0),
		_tree(Vector2(700, 300), 26.0),
		_tree(Vector2(860, 480), 30.0),
	]
	var zones: Array[SurfaceZone] = []
	# A water pond + sand bunker for hole 3 (still on the same map)
	zones.append(_zone(Surface.WATER, [
		Vector2(620, 600), Vector2(820, 600),
		Vector2(820, 700), Vector2(620, 700),
	]))
	zones.append(_zone(Surface.SAND, [
		Vector2(950, 220), Vector2(1080, 220),
		Vector2(1080, 290), Vector2(950, 290),
	]))
	return Level.new("Level 1 — Practice Park", bounds, holes_l1, obstacles, zones,
		Vector2.ZERO, [] as Array[WindZone])

# =============================================================
# LEVEL 2 — Grassland (open, strong + complex wind)
# Wide map, sparse trees. Wind zones pull in different directions.
# =============================================================
func _build_level_2() -> Level:
	var bounds: Vector2 = Vector2(2200, 900)
	var h1: Hole = Hole.new("2-1 Tailwind Boulevard", Vector2(150, 450), Vector2(1100, 450), 3)
	var h2: Hole = Hole.new("2-2 Crosswind Carry", Vector2(1100, 450), Vector2(2050, 220), 4)
	var h3: Hole = Hole.new("2-3 Headwind Finale", Vector2(2050, 220), Vector2(1450, 780), 4)
	var holes_l2: Array[Hole] = [h1, h2, h3]
	var obstacles: Array = [
		_tree(Vector2(700, 380), 26.0),
		_tree(Vector2(1450, 600), 30.0),
		_tree(Vector2(1750, 350), 28.0),
		_tree(Vector2(1300, 250), 26.0),
	]
	# Subtle short-grass strips for visual variety
	var zones: Array[SurfaceZone] = []
	# Base wind: mild southward
	var base_wind: Vector2 = Vector2(0, 18)
	# Wind zones — each polygon overrides base wind inside it
	var wzs: Array[WindZone] = [
		# Hole 1 area: strong tailwind east
		_windz([Vector2(0, 350), Vector2(1200, 350), Vector2(1200, 580), Vector2(0, 580)],
			Vector2(60, 0)),
		# Hole 2 area: brutal crosswind south
		_windz([Vector2(1100, 100), Vector2(2200, 100), Vector2(2200, 480), Vector2(1100, 480)],
			Vector2(-15, 70)),
		# Hole 3 area: stiff headwind blowing back at thrower (north)
		_windz([Vector2(1100, 480), Vector2(2200, 480), Vector2(2200, 900), Vector2(1100, 900)],
			Vector2(0, -55)),
	]
	return Level.new("Level 2 — Grassland", bounds, holes_l2, obstacles, zones,
		base_wind, wzs)

# =============================================================
# LEVEL 3 — Forest (many trees, requires curve shots)
# Tighter, taller map. Lots of trees forming corridors.
# =============================================================
func _build_level_3() -> Level:
	var bounds: Vector2 = Vector2(1700, 1200)
	var h1: Hole = Hole.new("3-1 First Cut", Vector2(150, 1050), Vector2(900, 700), 3)
	var h2: Hole = Hole.new("3-2 Dogleg Right", Vector2(900, 700), Vector2(1550, 350), 4)
	var h3: Hole = Hole.new("3-3 The Wall", Vector2(1550, 350), Vector2(550, 150), 4)
	var holes_l3: Array[Hole] = [h1, h2, h3]
	# Dense forest scattered + corridors
	var obstacles: Array = [
		# Hole 1 area
		_tree(Vector2(330, 900), 30.0),
		_tree(Vector2(500, 800), 28.0),
		_tree(Vector2(420, 1020), 26.0),
		_tree(Vector2(650, 880), 32.0),
		_tree(Vector2(780, 760), 28.0),
		# Hole 2 area
		_tree(Vector2(1050, 620), 30.0),
		_tree(Vector2(1180, 550), 28.0),
		_tree(Vector2(1280, 480), 26.0),
		_tree(Vector2(1380, 400), 30.0),
		_tree(Vector2(1100, 480), 26.0),
		_tree(Vector2(1450, 600), 28.0),
		# Hole 3 area — the wall
		_tree(Vector2(1300, 280), 32.0),
		_tree(Vector2(1100, 230), 28.0),
		_tree(Vector2(900, 220), 30.0),
		_tree(Vector2(720, 240), 26.0),
		_tree(Vector2(900, 350), 28.0),
		_tree(Vector2(1100, 350), 26.0),
	]
	# Some rough patches
	var zones: Array[SurfaceZone] = [
		_zone(Surface.ROUGH, [
			Vector2(0, 1100), Vector2(1700, 1100),
			Vector2(1700, 1200), Vector2(0, 1200),
		]),
		_zone(Surface.ROUGH, [
			Vector2(0, 0), Vector2(1700, 0),
			Vector2(1700, 80), Vector2(0, 80),
		]),
	]
	return Level.new("Level 3 — Forest", bounds, holes_l3, obstacles, zones,
		Vector2(0, 0), [] as Array[WindZone])

# =============================================================
# LEVEL 4 — Lakes (water hazards demand precision)
# Long thin map with water carries.
# =============================================================
func _build_level_4() -> Level:
	var bounds: Vector2 = Vector2(2500, 800)
	var h1: Hole = Hole.new("4-1 Water Carry", Vector2(150, 400), Vector2(950, 400), 3)
	var h2: Hole = Hole.new("4-2 Island Green", Vector2(950, 400), Vector2(1700, 250), 3)
	var h3: Hole = Hole.new("4-3 Long Lake", Vector2(1700, 250), Vector2(2400, 600), 4)
	var holes_l4: Array[Hole] = [h1, h2, h3]
	var obstacles: Array = [
		_tree(Vector2(550, 240), 28.0),
		_tree(Vector2(550, 560), 28.0),
		_tree(Vector2(1300, 200), 26.0),
		_tree(Vector2(2050, 450), 28.0),
	]
	# Multiple water bodies along the fairways
	var zones: Array[SurfaceZone] = [
		# Carry water for hole 1 (between tee and basket)
		_zone(Surface.WATER, [
			Vector2(400, 320), Vector2(800, 320),
			Vector2(800, 480), Vector2(400, 480),
		]),
		# Island green moat for hole 2 (surround basket roughly)
		_zone(Surface.WATER, [
			Vector2(1100, 130), Vector2(1900, 130),
			Vector2(1900, 200), Vector2(1100, 200),
		]),
		_zone(Surface.WATER, [
			Vector2(1100, 300), Vector2(1900, 300),
			Vector2(1900, 370), Vector2(1100, 370),
		]),
		# Long lake along hole 3
		_zone(Surface.WATER, [
			Vector2(1850, 450), Vector2(2300, 450),
			Vector2(2300, 700), Vector2(1850, 700),
		]),
		# Some short-grass fairway strips for visual nav
	]
	return Level.new("Level 4 — Lakes", bounds, holes_l4, obstacles, zones,
		Vector2(0, 12), [] as Array[WindZone])

# =============================================================
# LEVEL 5 — Hard Ground (concrete approaches near baskets)
# Discs land on hard ground and roll WAY further — overshoot risk.
# =============================================================
func _build_level_5() -> Level:
	var bounds: Vector2 = Vector2(2000, 900)
	var h1: Hole = Hole.new("5-1 Concrete Approach", Vector2(150, 500), Vector2(950, 500), 3)
	var h2: Hole = Hole.new("5-2 Slide City", Vector2(950, 500), Vector2(1700, 250), 4)
	var h3: Hole = Hole.new("5-3 The Skating Rink", Vector2(1700, 250), Vector2(1850, 750), 3)
	var holes_l5: Array[Hole] = [h1, h2, h3]
	var obstacles: Array = [
		_tree(Vector2(450, 380), 24.0),
		_tree(Vector2(700, 600), 26.0),
		_tree(Vector2(1300, 380), 28.0),
		_tree(Vector2(1500, 500), 26.0),
	]
	# Hard-ground rings around each basket + a water/rough trap beyond
	var zones: Array[SurfaceZone] = [
		# Hard ground around hole 1 basket — overshoot lands in water
		_zone(Surface.HARD_GROUND, [
			Vector2(820, 420), Vector2(1080, 420),
			Vector2(1080, 580), Vector2(820, 580),
		]),
		_zone(Surface.WATER, [
			Vector2(1080, 430), Vector2(1200, 430),
			Vector2(1200, 570), Vector2(1080, 570),
		]),
		# Hard ground around hole 2 basket — overshoot lands in rough
		_zone(Surface.HARD_GROUND, [
			Vector2(1570, 180), Vector2(1830, 180),
			Vector2(1830, 320), Vector2(1570, 320),
		]),
		_zone(Surface.ROUGH, [
			Vector2(1830, 180), Vector2(1980, 180),
			Vector2(1980, 320), Vector2(1830, 320),
		]),
		# Hole 3: the "skating rink" — big slab of hard ground around basket
		_zone(Surface.HARD_GROUND, [
			Vector2(1650, 600), Vector2(1980, 600),
			Vector2(1980, 880), Vector2(1650, 880),
		]),
		_zone(Surface.WATER, [
			Vector2(1450, 700), Vector2(1640, 700),
			Vector2(1640, 880), Vector2(1450, 880),
		]),
	]
	return Level.new("Level 5 — Hard Ground", bounds, holes_l5, obstacles, zones,
		Vector2.ZERO, [] as Array[WindZone])

# =============================================================
# LEVEL 6 — Boomerang. Three holes loop around a central tree cluster
# back to near the start. Each hole forces a different curve direction.
# =============================================================
func _build_level_6_boomerang() -> Level:
	var bounds: Vector2 = Vector2(1800, 1200)
	# Tee/basket positions chained around a roughly circular path.
	var t1: Vector2 = Vector2(250, 1000)
	var t2: Vector2 = Vector2(1450, 850)   # = h1 basket
	var t3: Vector2 = Vector2(1450, 250)   # = h2 basket
	var t4: Vector2 = Vector2(450, 200)    # = h3 basket (final, close to start)
	var h1: Hole = Hole.new("6-1 First Sweep", t1, t2, 4)
	var h2: Hole = Hole.new("6-2 Round the Bend", t2, t3, 3)
	var h3: Hole = Hole.new("6-3 Home Stretch", t3, t4, 4)
	var holes_l6: Array[Hole] = [h1, h2, h3]
	# Central tree cluster forcing detour
	var obstacles: Array = [
		_tree(Vector2(900, 580), 40.0),
		_tree(Vector2(800, 520), 36.0),
		_tree(Vector2(1000, 520), 36.0),
		_tree(Vector2(900, 460), 36.0),
		_tree(Vector2(820, 640), 32.0),
		_tree(Vector2(980, 640), 32.0),
		# Some scattered trees forcing curve choices on each leg
		_tree(Vector2(550, 900), 28.0),
		_tree(Vector2(1300, 950), 28.0),
		_tree(Vector2(1280, 380), 28.0),
		_tree(Vector2(700, 320), 28.0),
	]
	return Level.new("Level 6 — Boomerang", bounds, holes_l6, obstacles,
		[] as Array[SurfaceZone], Vector2.ZERO, [] as Array[WindZone])

# =============================================================
# LEVEL 7 — Multi-Lane. Each hole has multiple visible routes:
# safe long route around obstacles, risky short route through a gap.
# =============================================================
func _build_level_7_multi_lane() -> Level:
	var bounds: Vector2 = Vector2(2200, 900)
	var h1: Hole = Hole.new("7-1 Choose Your Path", Vector2(180, 450), Vector2(1100, 450), 3)
	var h2: Hole = Hole.new("7-2 Risk vs Safe", Vector2(1100, 450), Vector2(2050, 450), 4)
	var h3: Hole = Hole.new("7-3 The Gambit", Vector2(2050, 450), Vector2(1100, 800), 4)
	var holes_l7: Array[Hole] = [h1, h2, h3]
	var obstacles: Array = [
		# Hole 1: tight gap dead-center, open route around top OR bottom
		_tree(Vector2(560, 420), 32.0),
		_tree(Vector2(560, 480), 32.0),
		_tree(Vector2(680, 420), 30.0),
		_tree(Vector2(680, 480), 30.0),
		# Hole 2: a wall of trees at mid; short gap top, big gap bottom
		_tree(Vector2(1450, 350), 32.0),
		_tree(Vector2(1450, 420), 30.0),
		_tree(Vector2(1450, 490), 30.0),
		_tree(Vector2(1600, 380), 30.0),
		_tree(Vector2(1600, 460), 30.0),
		# Hole 3: dogleg with gap up top and a long way around the bottom
		_tree(Vector2(1700, 700), 36.0),
		_tree(Vector2(1500, 750), 36.0),
		_tree(Vector2(1850, 600), 28.0),
	]
	# Some rough patches reward staying on fairway
	var zones: Array[SurfaceZone] = [
		_zone(Surface.ROUGH, [
			Vector2(0, 0), Vector2(2200, 0),
			Vector2(2200, 130), Vector2(0, 130),
		]),
		_zone(Surface.ROUGH, [
			Vector2(0, 770), Vector2(2200, 770),
			Vector2(2200, 900), Vector2(0, 900),
		]),
	]
	return Level.new("Level 7 — Multi-Lane", bounds, holes_l7, obstacles, zones,
		Vector2.ZERO, [] as Array[WindZone])

# =============================================================
# LEVEL 8 — Winter (Frozen). All ground is hard, so discs slide far.
# Roughs near baskets are "snow" patches that grab discs.
# =============================================================
func _build_level_8_winter() -> Level:
	var bounds: Vector2 = Vector2(2000, 900)
	var h1: Hole = Hole.new("8-1 First Slide", Vector2(180, 450), Vector2(1000, 250), 3)
	var h2: Hole = Hole.new("8-2 Frozen Lake", Vector2(1000, 250), Vector2(1750, 600), 3)
	var h3: Hole = Hole.new("8-3 Avalanche Run", Vector2(1750, 600), Vector2(420, 800), 4)
	var holes_l8: Array[Hole] = [h1, h2, h3]
	var obstacles: Array = [
		_tree(Vector2(550, 350), 28.0),
		_tree(Vector2(800, 580), 26.0),
		_tree(Vector2(1300, 400), 28.0),
		_tree(Vector2(1500, 700), 26.0),
		_tree(Vector2(900, 750), 28.0),
	]
	var ice: Color = Color(0.78, 0.85, 0.92)  # icy bluish base
	# Whole map is hard ground, with snow (rough) patches around each basket.
	var zones: Array[SurfaceZone] = [
		# Hard ground covers everything (drawn first as background)
		_zone(Surface.HARD_GROUND, [
			Vector2(0, 0), Vector2(2000, 0),
			Vector2(2000, 900), Vector2(0, 900),
		]),
		# Snow circles near baskets — render as ROUGH polygons (octagons)
		_octagon_zone(Surface.ROUGH, Vector2(1000, 250), 110),
		_octagon_zone(Surface.ROUGH, Vector2(1750, 600), 110),
		_octagon_zone(Surface.ROUGH, Vector2(420, 800), 110),
	]
	return Level.new("Level 8 — Winter", bounds, holes_l8, obstacles, zones,
		Vector2.ZERO, [] as Array[WindZone],
		[] as Array[Mando], [] as Array[Portal],
		[] as Array[int], ice)

# Octagon polygon helper for rounded zones.
func _octagon_zone(t: int, center: Vector2, r: float) -> SurfaceZone:
	var pts: Array = []
	for i in range(8):
		var a: float = TAU * float(i) / 8.0
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return _zone(t, pts)

# =============================================================
# LEVEL 9 — Mandatory. Each hole has a mando (forced gate side).
# Missing the mando = +1 stroke. Tests planning around constraints.
# =============================================================
func _build_level_9_mandatory() -> Level:
	var bounds: Vector2 = Vector2(2200, 900)
	var t1: Vector2 = Vector2(180, 450)
	var b1: Vector2 = Vector2(1100, 450)
	var b2: Vector2 = Vector2(2050, 250)
	var b3: Vector2 = Vector2(1500, 800)
	var h1: Hole = Hole.new("9-1 Must Go Right", t1, b1, 3)
	var h2: Hole = Hole.new("9-2 Must Go Left", b1, b2, 4)
	var h3: Hole = Hole.new("9-3 Double Mando", b2, b3, 4)
	var holes_l9: Array[Hole] = [h1, h2, h3]
	# Mando "posts" — visualize a tree at each end so mando makes sense visually.
	var obstacles: Array = [
		_tree(Vector2(620, 340), 28.0),
		_tree(Vector2(620, 560), 28.0),
		_tree(Vector2(1500, 340), 28.0),
		_tree(Vector2(1500, 560), 28.0),
		_tree(Vector2(1850, 700), 28.0),
		_tree(Vector2(1850, 460), 28.0),
	]
	# Mando definitions:
	# Hole 1: between trees at x=620, disc must pass on RIGHT side (going +x).
	# For pre-side calculation: tee at (180,450), p1=(620,340), p2=(620,560).
	# (p2-p1) = (0,220); rel = tee - p1 = (-440, 110). Cross = 0*110 - 220*(-440) = +96800 > 0
	# So tee is on +1 side. We want pass on RIGHT of the disc as it flies east =
	# from disc's POV crossing left to right of the gate line, but cross-product
	# convention says: required +1 = tee starts and stays on +1 side, must cross to -1?
	# Simpler: we want disc to pass BETWEEN p1.p2 on the segment, ending up past it.
	# Choose required_side = -1 so the disc must end up on the OTHER side (after the gate).
	var mandos1: Array[Mando] = [Mando.new(Vector2(620, 340), Vector2(620, 560), -1, "MANDO →")]
	var mandos2: Array[Mando] = [Mando.new(Vector2(1500, 340), Vector2(1500, 560), -1, "MANDO →")]
	var mandos3: Array[Mando] = [
		Mando.new(Vector2(1500, 340), Vector2(1500, 560), -1, "MANDO 1"),
		Mando.new(Vector2(1850, 460), Vector2(1850, 700), -1, "MANDO 2"),
	]
	# Combined mandos for the level (active per disc position; applied if mando
	# is ahead of the player's current hole). For simplicity we list ALL mandos
	# for the whole level; each one is checked independently.
	var all_mandos: Array[Mando] = []
	for m in mandos1: all_mandos.append(m)
	for m in mandos3: all_mandos.append(m)
	# (mandos2 is the same gate as mandos3[0] so we don't add it twice.)
	return Level.new("Level 9 — Mandatory", bounds, holes_l9, obstacles,
		[] as Array[SurfaceZone], Vector2.ZERO, [] as Array[WindZone],
		all_mandos)

# =============================================================
# LEVEL 10 — Island Chain. Heavy water with small grass islands.
# =============================================================
func _build_level_10_islands() -> Level:
	var bounds: Vector2 = Vector2(2400, 900)
	var t1: Vector2 = Vector2(200, 450)
	var b1: Vector2 = Vector2(900, 200)
	var b2: Vector2 = Vector2(1600, 700)
	var b3: Vector2 = Vector2(2250, 350)
	var h1: Hole = Hole.new("10-1 First Hop", t1, b1, 3)
	var h2: Hole = Hole.new("10-2 Long Carry", b1, b2, 4)
	var h3: Hole = Hole.new("10-3 The Final Island", b2, b3, 4)
	var holes_l10: Array[Hole] = [h1, h2, h3]
	# Whole field is water, with islands of fairway around each tee/basket.
	var zones: Array[SurfaceZone] = [
		_zone(Surface.WATER, [
			Vector2(0, 0), Vector2(2400, 0),
			Vector2(2400, 900), Vector2(0, 900),
		]),
		# Islands (octagonal fairways)
		_octagon_zone(Surface.FAIRWAY, t1, 180),
		_octagon_zone(Surface.FAIRWAY, b1, 130),
		_octagon_zone(Surface.FAIRWAY, b2, 130),
		_octagon_zone(Surface.FAIRWAY, b3, 150),
		# A couple of mid-flight relief islands
		_octagon_zone(Surface.FAIRWAY, Vector2(550, 320), 80),
		_octagon_zone(Surface.FAIRWAY, Vector2(1250, 450), 90),
		_octagon_zone(Surface.FAIRWAY, Vector2(1950, 550), 80),
	]
	return Level.new("Level 10 — Island Chain", bounds, holes_l10,
		[] as Array, zones, Vector2.ZERO, [] as Array[WindZone])

# =============================================================
# LEVEL 11 — Wind Tunnel. Alternating strong head/tail wind zones.
# =============================================================
func _build_level_11_wind_tunnel() -> Level:
	var bounds: Vector2 = Vector2(2300, 800)
	var h1: Hole = Hole.new("11-1 Boost", Vector2(180, 400), Vector2(1100, 400), 3)
	var h2: Hole = Hole.new("11-2 Push Back", Vector2(1100, 400), Vector2(2150, 400), 4)
	var h3: Hole = Hole.new("11-3 Crosscurrents", Vector2(2150, 400), Vector2(1200, 720), 4)
	var holes_l11: Array[Hole] = [h1, h2, h3]
	var obstacles: Array = [
		_tree(Vector2(700, 320), 26.0),
		_tree(Vector2(700, 480), 26.0),
		_tree(Vector2(1700, 320), 26.0),
		_tree(Vector2(1700, 480), 26.0),
	]
	# Alternating wind columns
	var wzs: Array[WindZone] = [
		# Hole 1 zone: strong tailwind east (helps)
		_windz([Vector2(0, 200), Vector2(1100, 200), Vector2(1100, 600), Vector2(0, 600)],
			Vector2(80, 0)),
		# Hole 2 zone: strong headwind west (fights you)
		_windz([Vector2(1100, 200), Vector2(2300, 200), Vector2(2300, 600), Vector2(1100, 600)],
			Vector2(-80, 0)),
		# Hole 3 zone: crosswind south
		_windz([Vector2(800, 600), Vector2(2300, 600), Vector2(2300, 800), Vector2(800, 800)],
			Vector2(0, 60)),
	]
	return Level.new("Level 11 — Wind Tunnel", bounds, holes_l11, obstacles,
		[] as Array[SurfaceZone], Vector2.ZERO, wzs)

# =============================================================
# LEVEL 12 — One Disc Challenge. Only the Putter (idx 0) is allowed.
# Short, technical holes.
# =============================================================
func _build_level_12_one_disc() -> Level:
	var bounds: Vector2 = Vector2(1400, 800)
	var h1: Hole = Hole.new("12-1 Wrist Check", Vector2(150, 400), Vector2(700, 400), 3)
	var h2: Hole = Hole.new("12-2 Around the Tree", Vector2(700, 400), Vector2(1280, 220), 3)
	var h3: Hole = Hole.new("12-3 Putter Only Finale", Vector2(1280, 220), Vector2(300, 700), 4)
	var holes_l12: Array[Hole] = [h1, h2, h3]
	var obstacles: Array = [
		_tree(Vector2(400, 350), 30.0),
		_tree(Vector2(500, 480), 28.0),
		_tree(Vector2(950, 320), 32.0),
		_tree(Vector2(1100, 380), 28.0),
		_tree(Vector2(800, 600), 30.0),
		_tree(Vector2(600, 700), 28.0),
	]
	return Level.new("Level 12 — Putter Only", bounds, holes_l12, obstacles,
		[] as Array[SurfaceZone], Vector2.ZERO, [] as Array[WindZone],
		[] as Array[Mando], [] as Array[Portal],
		[0] as Array[int])  # only Putter

# =============================================================
# LEVEL 13 — Portals. Some basket-area holes have teleport pairs
# that you can use as shortcuts. Whimsical, non-realistic.
# =============================================================
func _build_level_13_portals() -> Level:
	var bounds: Vector2 = Vector2(2400, 1000)
	var h1: Hole = Hole.new("13-1 Try the Portal", Vector2(200, 800), Vector2(2200, 200), 4)
	var h2: Hole = Hole.new("13-2 Long Loop", Vector2(2200, 200), Vector2(200, 200), 5)
	var h3: Hole = Hole.new("13-3 Final Warp", Vector2(200, 200), Vector2(2150, 850), 4)
	var holes_l13: Array[Hole] = [h1, h2, h3]
	var obstacles: Array = [
		_tree(Vector2(1100, 600), 36.0),
		_tree(Vector2(1300, 400), 36.0),
		_tree(Vector2(900, 350), 32.0),
		_tree(Vector2(1500, 700), 32.0),
	]
	# Portal pairs (entry → dest). Color-coded so player can find pairs.
	var portals: Array[Portal] = [
		# Pair A: (purple) 700,650 ↔ 2000,250 — diagonal shortcut
		Portal.new(Vector2(700, 650), 36.0, Vector2(2000, 250), Color(0.85, 0.55, 1.0)),
		Portal.new(Vector2(2000, 250), 36.0, Vector2(700, 650), Color(0.85, 0.55, 1.0)),
		# Pair B: (cyan) 1700,200 ↔ 400,400
		Portal.new(Vector2(1700, 200), 32.0, Vector2(400, 400), Color(0.5, 0.95, 1.0)),
		Portal.new(Vector2(400, 400), 32.0, Vector2(1700, 200), Color(0.5, 0.95, 1.0)),
		# Pair C: (yellow) 1300, 800 ↔ 2100, 700
		Portal.new(Vector2(1300, 800), 30.0, Vector2(2100, 700), Color(1.0, 0.95, 0.5)),
		Portal.new(Vector2(2100, 700), 30.0, Vector2(1300, 800), Color(1.0, 0.95, 0.5)),
	]
	return Level.new("Level 13 — Portals", bounds, holes_l13, obstacles,
		[] as Array[SurfaceZone], Vector2.ZERO, [] as Array[WindZone],
		[] as Array[Mando], portals)

# Build a fairway corridor polygon between two points with given half-width
func _corridor(a: Vector2, b: Vector2, half_w: float) -> PackedVector2Array:
	var dir: Vector2 = (b - a).normalized()
	var perp: Vector2 = Vector2(-dir.y, dir.x) * half_w
	var ext: Vector2 = dir * 80.0  # extend past endpoints a bit
	return PackedVector2Array([
		a - ext + perp,
		b + ext + perp,
		b + ext - perp,
		a - ext - perp,
	])

# Same but returns a regular Array (for use with _zone helper).
func _corridor_pts(a: Vector2, b: Vector2, half_w: float) -> Array:
	var dir: Vector2 = (b - a).normalized()
	var perp: Vector2 = Vector2(-dir.y, dir.x) * half_w
	var ext: Vector2 = dir * 80.0
	return [
		a - ext + perp,
		b + ext + perp,
		b + ext - perp,
		a - ext - perp,
	]

# =============================================================
# Tutorial scenes (playable practice levels)
# =============================================================
func _init_tutorial_scenes() -> void:
	tutorial_holes = []
	tutorial_titles = []
	tutorial_lines = []
	tutorial_hints = []

	# Tutorial scenes are rendered with the left ~380px occupied by the
	# instruction panel, so all tees stay at x >= 460.
	tutorial_pseudo_levels = []

	# Helper to build a single-hole pseudo-Level for a tutorial scene.
	# Bounds = viewport size (no camera scroll needed in tutorial).

	# --- Scene 0: Throwing basics ---
	var t0: Vector2 = Vector2(480, 400)
	var b0: Vector2 = Vector2(1140, 400)
	var s0_zones: Array[SurfaceZone] = [_zone(Surface.FAIRWAY, _corridor_pts(t0, b0, 110.0))]
	var s0_holes: Array[Hole] = [Hole.new("Practice — Throwing", t0, b0, 1)]
	tutorial_pseudo_levels.append(Level.new("Practice — Throwing",
		Vector2(FIELD_WIDTH, FIELD_HEIGHT), s0_holes, [],
		s0_zones, Vector2.ZERO, [] as Array[WindZone]))
	tutorial_titles.append("1. Throwing")
	tutorial_lines.append(PackedStringArray([
		"Drag from the disc and release to throw.",
		"Pull length = power, direction = throw direction.",
		"Try a few throws — aim for the basket.",
	]))
	tutorial_hints.append("Drag from the yellow disc → release.")

	# --- Scene 1: Power tiers ---
	var t1: Vector2 = Vector2(460, 400)
	var b1: Vector2 = Vector2(1180, 400)
	var s1_zones: Array[SurfaceZone] = [_zone(Surface.FAIRWAY, _corridor_pts(t1, b1, 100.0))]
	var s1_holes: Array[Hole] = [Hole.new("Practice — Power tiers", t1, b1, 1)]
	tutorial_pseudo_levels.append(Level.new("Practice — Power tiers",
		Vector2(FIELD_WIDTH, FIELD_HEIGHT), s1_holes, [],
		s1_zones, Vector2.ZERO, [] as Array[WindZone]))
	tutorial_titles.append("2. Power tiers — PUTT / MID / HUCK")
	tutorial_lines.append(PackedStringArray([
		"Drag length picks the throw mode automatically:",
		"   short = PUTT, medium = MID, full = HUCK.",
		"The power meter is colored by mode.",
		"Try a tiny drag, then a medium one, then full.",
		"Press Z / X / C to FORCE a tier; V = back to auto.",
	]))
	tutorial_hints.append("Try drags of different lengths — watch the mode change.")

	# --- Scene 2: Backhand vs Forehand ---
	var t2: Vector2 = Vector2(490, 400)
	var b2: Vector2 = Vector2(1140, 400)
	var s2_zones: Array[SurfaceZone] = [_zone(Surface.FAIRWAY, _corridor_pts(t2, b2, 130.0))]
	var s2_holes: Array[Hole] = [Hole.new("Practice — BH vs FH", t2, b2, 1)]
	tutorial_pseudo_levels.append(Level.new("Practice — BH vs FH",
		Vector2(FIELD_WIDTH, FIELD_HEIGHT), s2_holes, [],
		s2_zones, Vector2.ZERO, [] as Array[WindZone]))
	tutorial_titles.append("3. Backhand vs Forehand")
	tutorial_lines.append(PackedStringArray([
		"Press F to switch hand. Watch the disc's release",
		"point — BH from your LEFT, FH from your RIGHT.",
		"BH (RHBH) flat throw naturally drifts RIGHT,",
		"FH naturally drifts LEFT (mirror).",
		"Throw flat with each — see the curve flip.",
	]))
	tutorial_hints.append("Throw flat with BH, then F + throw flat with FH. Compare.")

	# --- Scene 3: Hyzer / Anhyzer ---
	var t3: Vector2 = Vector2(470, 560)
	var b3: Vector2 = Vector2(1140, 200)
	var s3_zones: Array[SurfaceZone] = [_zone(Surface.FAIRWAY, _corridor_pts(t3, b3, 130.0))]
	var s3_holes: Array[Hole] = [Hole.new("Practice — Hyzer", t3, b3, 1)]
	var s3_obstacles: Array = [_tree(Vector2(780, 380), 38.0)]
	tutorial_pseudo_levels.append(Level.new("Practice — Hyzer",
		Vector2(FIELD_WIDTH, FIELD_HEIGHT), s3_holes, s3_obstacles,
		s3_zones, Vector2.ZERO, [] as Array[WindZone]))
	tutorial_titles.append("4. Hyzer & Anhyzer (bank angle)")
	tutorial_lines.append(PackedStringArray([
		"Q = bank LEFT (hyzer). E = bank RIGHT (anhyzer).",
		"The disc icon visibly tilts; horizon gauge above.",
		"After landing, the cyan line shows the real path.",
		"Bigger bank = bigger arc = SHORTER distance.",
		"Try Q to curve the disc AROUND the tree.",
	]))
	tutorial_hints.append("Press Q a few times, then throw. Watch the cyan flight path.")

	# --- Scene 4: Surfaces & roll ---
	var t4: Vector2 = Vector2(470, 400)
	var b4: Vector2 = Vector2(1180, 400)
	var s4_zones: Array[SurfaceZone] = [
		_zone(Surface.ROUGH, [
			Vector2(400, 90), Vector2(FIELD_WIDTH - 60, 90),
			Vector2(FIELD_WIDTH - 60, 270), Vector2(400, 270)]),
		_zone(Surface.ROUGH, [
			Vector2(400, 530), Vector2(FIELD_WIDTH - 60, 530),
			Vector2(FIELD_WIDTH - 60, FIELD_HEIGHT - 60), Vector2(400, FIELD_HEIGHT - 60)]),
		_zone(Surface.FAIRWAY, _corridor_pts(t4, b4, 80.0)),
		_zone(Surface.WATER, [
			Vector2(850, 320), Vector2(990, 320),
			Vector2(990, 480), Vector2(850, 480)]),
	]
	var s4_holes: Array[Hole] = [Hole.new("Practice — Surfaces", t4, b4, 1)]
	tutorial_pseudo_levels.append(Level.new("Practice — Surfaces",
		Vector2(FIELD_WIDTH, FIELD_HEIGHT), s4_holes, [],
		s4_zones, Vector2.ZERO, [] as Array[WindZone]))
	tutorial_titles.append("5. Surfaces & rolling")
	tutorial_lines.append(PackedStringArray([
		"After landing, the disc ROLLS based on:",
		"  • landing tilt — flat rolls long, spike-hyzer dies",
		"  • surface — fairway long, rough fast stop",
		"  • sand barely rolls; water = +1 stroke",
		"Try a flat HUCK. Try a max-Q (spike) approach.",
		"Notice the water in the middle — avoid it.",
	]))
	tutorial_hints.append("Flat throws roll. Spike-hyzer (max Q) lands dead.")


# =============================================================
# Input dispatch
# =============================================================
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event.keycode)

	match state:
		State.PLAYING, State.TUTORIAL:
			_handle_play_mouse(event)
		State.TITLE:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_activate_menu_item(menu_idx)
		State.LEVEL_SELECT:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_begin_free_level(level_select_idx)
			elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				_level_select_move(1)
			elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				_level_select_move(-1)
		State.HOLE_COMPLETE:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_next_hole()
		State.LEVEL_INTRO:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_start_next_level_play()
		State.LEVEL_COMPLETE:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_advance_after_level_complete()
		State.ROUND_COMPLETE:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_to_title()

func _handle_key(kc: int) -> void:
	if kc == KEY_ESCAPE:
		_to_title()
		return
	if state == State.TITLE:
		if kc == KEY_UP:
			menu_idx = (menu_idx - 1 + TITLE_MENU_ITEMS.size()) % TITLE_MENU_ITEMS.size()
		elif kc == KEY_DOWN:
			menu_idx = (menu_idx + 1) % TITLE_MENU_ITEMS.size()
		elif kc == KEY_SPACE or kc == KEY_ENTER:
			_activate_menu_item(menu_idx)
		return
	if state == State.LEVEL_SELECT:
		if kc == KEY_UP:
			_level_select_move(-1)
		elif kc == KEY_DOWN:
			_level_select_move(1)
		elif kc == KEY_SPACE or kc == KEY_ENTER:
			_begin_free_level(level_select_idx)
		return
	if state == State.TUTORIAL:
		# Page navigation only when at rest (not mid-throw)
		if not disc_flying and not disc_rolling and not aim_dragging:
			if kc == KEY_SPACE or kc == KEY_ENTER or kc == KEY_RIGHT:
				_advance_tutorial(1)
				return
			elif kc == KEY_LEFT or kc == KEY_BACKSPACE:
				_advance_tutorial(-1)
				return
			elif kc == KEY_N or kc == KEY_S:
				_finish_tutorial()
				return
		# Otherwise fall through to PLAYING-style keys (Q/E/F/Z/X/C/V/P/R/1/2/3)
	if state == State.HOLE_COMPLETE:
		if kc == KEY_SPACE or kc == KEY_ENTER:
			_next_hole()
		return
	if state == State.LEVEL_INTRO:
		if kc == KEY_SPACE or kc == KEY_ENTER:
			_start_next_level_play()
		return
	if state == State.LEVEL_COMPLETE:
		if kc == KEY_SPACE or kc == KEY_ENTER:
			_advance_after_level_complete()
		return
	if state == State.ROUND_COMPLETE:
		if kc == KEY_SPACE or kc == KEY_ENTER:
			_to_title()
		return

	# PLAYING
	if disc_flying or disc_rolling:
		return
	match kc:
		KEY_R:
			_reset_current_hole()
		KEY_Q:
			hyzer_angle = clampf(hyzer_angle + 0.2, -1.0, 1.0)
			_recompute_preview()
		KEY_E:
			hyzer_angle = clampf(hyzer_angle - 0.2, -1.0, 1.0)
			_recompute_preview()
		KEY_F:
			throw_style = ThrowStyle.FOREHAND if throw_style == ThrowStyle.BACKHAND else ThrowStyle.BACKHAND
			_play(sfx_click, -10.0)
			_recompute_preview()
		KEY_1:
			_select_disc(0)
		KEY_2:
			_select_disc(1)
		KEY_3:
			_select_disc(2)
		KEY_Z:
			mode_override = ThrowMode.PUTT
			_play(sfx_click, -10.0)
			_recompute_preview()
		KEY_X:
			mode_override = ThrowMode.MID
			_play(sfx_click, -10.0)
			_recompute_preview()
		KEY_C:
			mode_override = ThrowMode.HUCK
			_play(sfx_click, -10.0)
			_recompute_preview()
		KEY_V:
			mode_override = -1  # back to auto
			_play(sfx_click, -10.0)
			_recompute_preview()
		KEY_P:
			pro_mode = not pro_mode
			_play(sfx_click, -10.0)

func _handle_play_mouse(event: InputEvent) -> void:
	if disc_flying or disc_rolling:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			aim_dragging = true
			aim_start = event.position
			aim_current = event.position
			_recompute_preview()
		else:
			if aim_dragging:
				aim_dragging = false
				var pull: Vector2 = aim_current - aim_start
				if pull.length() > 15.0:
					_throw_disc(pull)
				predicted_path = PackedVector2Array()
	elif event is InputEventMouseMotion and aim_dragging:
		aim_current = event.position
		_recompute_preview()

# =============================================================
# State transitions
# =============================================================
func _to_title() -> void:
	state = State.TITLE
	_play(sfx_click)

func _start_tutorial() -> void:
	state = State.TUTORIAL
	is_tutorial = true
	current_level = tutorial_pseudo_levels[0]
	holes = current_level.holes
	tutorial_page = 0
	current_hole_idx = 0
	hole_scores.clear()
	tutorial_done_current = false
	_setup_current_hole()
	_play(sfx_click)

func _advance_tutorial(dir: int) -> void:
	var new_page: int = tutorial_page + dir
	if new_page < 0:
		return
	if new_page >= tutorial_pseudo_levels.size():
		_finish_tutorial()
		return
	tutorial_page = new_page
	current_level = tutorial_pseudo_levels[new_page]
	holes = current_level.holes
	current_hole_idx = 0
	tutorial_done_current = false
	_setup_current_hole()
	_play(sfx_click, -10.0)

func _finish_tutorial() -> void:
	is_tutorial = false
	current_level_idx = 0
	current_level = levels[0]
	holes = current_level.holes
	current_hole_idx = 0
	hole_scores.clear()
	level_scores = []
	tutorial_done_current = false
	_setup_current_hole()
	state = State.PLAYING
	_play(sfx_click)

func _setup_current_hole() -> void:
	var h: Hole = holes[current_hole_idx]
	disc_pos = h.tee
	last_safe_pos = h.tee
	disc_vel = Vector2.ZERO
	disc_flying = false
	disc_rolling = false
	stroke_count = 0
	hyzer_angle = 0.0
	trail.clear()
	roll_trail.clear()
	aim_dragging = false
	mode_override = -1
	predicted_path = PackedVector2Array()
	# Snap camera to the new hole's framing immediately.
	if current_level != null:
		# If level restricts discs, ensure current selection is valid
		if not current_level.allowed_discs.is_empty() and not _disc_allowed(current_disc_idx):
			current_disc_idx = current_level.allowed_discs[0]
		var bnd: Vector2 = current_level.bounds
		var to_basket: Vector2 = h.basket - disc_pos
		var max_bias: float = FIELD_WIDTH * 0.18
		var bias: Vector2 = Vector2.ZERO
		if to_basket.length() > 0.001:
			bias = to_basket.normalized() * min(max_bias, to_basket.length() * 0.5)
		var center: Vector2 = disc_pos + bias
		var topleft: Vector2 = center - Vector2(FIELD_WIDTH, FIELD_HEIGHT) * 0.5
		topleft.x = clampf(topleft.x, 0.0, maxf(0.0, bnd.x - FIELD_WIDTH))
		topleft.y = clampf(topleft.y, 0.0, maxf(0.0, bnd.y - FIELD_HEIGHT))
		camera_pos = topleft

func _reset_current_hole() -> void:
	_setup_current_hole()

func _next_hole() -> void:
	hole_scores.append(stroke_count)
	current_hole_idx += 1
	if current_hole_idx >= holes.size():
		# Level done — save best total + unlock next, then show summary screen.
		_finalize_level_complete()
	else:
		state = State.PLAYING
		_setup_current_hole()
	_play(sfx_click)

# Called when last hole of current level is finished.
func _finalize_level_complete() -> void:
	var total: int = 0
	for s in hole_scores:
		total += s
	var is_new_best: bool = _record_level_score(current_level_idx, total)
	level_scores.append({
		"level_idx": current_level_idx,
		"hole_scores": hole_scores.duplicate(),
		"total": total,
		"new_best": is_new_best,
	})
	# Unlock next level if it exists (in CAMPAIGN mode, this is the gating).
	if current_level_idx + 1 < levels.size():
		_unlock_level(current_level_idx + 1)
	state = State.LEVEL_COMPLETE

# Advance from the level-complete screen.
func _advance_after_level_complete() -> void:
	if game_mode == GameMode.FREE:
		# Free play: go back to level select rather than auto-advance.
		state = State.LEVEL_SELECT
		return
	# Campaign: advance to next level intro (or round complete if last).
	current_level_idx += 1
	if current_level_idx >= levels.size():
		state = State.ROUND_COMPLETE
	else:
		current_level = levels[current_level_idx]
		holes = current_level.holes
		current_hole_idx = 0
		hole_scores.clear()
		state = State.LEVEL_INTRO

func _start_next_level_play() -> void:
	# Called after the LEVEL_INTRO splash is dismissed.
	state = State.PLAYING
	current_hole_idx = 0
	hole_scores.clear()
	_setup_current_hole()

# Start a specific level (used by level-select and campaign start).
func _begin_level(li: int) -> void:
	current_level_idx = li
	current_level = levels[li]
	holes = current_level.holes
	round_holes = holes
	current_hole_idx = 0
	hole_scores.clear()
	level_scores.clear()
	state = State.LEVEL_INTRO
	_play(sfx_click)

# =============================================================
# Mode / throw resolution
# =============================================================
# Compute effective mode from drag fraction (respecting override + distance cap).
# Distance cap: at close range, HUCK / MID are not realistic choices even with
# a full pull. A 10m approach is always a PUTT in real disc-golf.
func _resolve_mode(drag_frac: float) -> int:
	if mode_override >= 0:
		return mode_override
	var drag_mode: int
	if drag_frac < DRAG_PUTT_MAX:
		drag_mode = ThrowMode.PUTT
	elif drag_frac < DRAG_MID_MAX:
		drag_mode = ThrowMode.MID
	else:
		drag_mode = ThrowMode.HUCK
	# Cap by distance to basket
	var max_mode: int = _max_mode_by_distance()
	return mini(drag_mode, max_mode)

func _max_mode_by_distance() -> int:
	var h: Hole = holes[current_hole_idx]
	var dist_m: float = disc_pos.distance_to(h.basket) / PX_PER_METER
	if dist_m < 10.0:
		return ThrowMode.PUTT
	elif dist_m < 25.0:
		return ThrowMode.MID
	return ThrowMode.HUCK

# Map drag fraction → fraction of disc's potential range.
# Auto mode: piecewise tier-mapped so drag length picks tier and within-tier power.
# Override mode: drag % goes to within-tier scale of that tier's max.
func _resolve_power_frac(drag_frac: float, mode: int) -> float:
	if mode_override < 0:
		# Auto piecewise mapping
		match mode:
			ThrowMode.PUTT:
				return clampf(drag_frac / DRAG_PUTT_MAX, 0.1, 1.0) * MODE_DIST_FRAC[ThrowMode.PUTT]
			ThrowMode.MID:
				var t: float = (drag_frac - DRAG_PUTT_MAX) / (DRAG_MID_MAX - DRAG_PUTT_MAX)
				return MODE_DIST_FRAC[ThrowMode.PUTT] + clampf(t, 0.0, 1.0) * (MODE_DIST_FRAC[ThrowMode.MID] - MODE_DIST_FRAC[ThrowMode.PUTT])
			ThrowMode.HUCK:
				var t2: float = (drag_frac - DRAG_MID_MAX) / (1.0 - DRAG_MID_MAX)
				return MODE_DIST_FRAC[ThrowMode.MID] + clampf(t2, 0.0, 1.0) * (MODE_DIST_FRAC[ThrowMode.HUCK] - MODE_DIST_FRAC[ThrowMode.MID])
	# Override: drag % is power within tier
	return clampf(drag_frac, 0.1, 1.0) * MODE_DIST_FRAC[mode]

# Release point offset: BH releases from player's LEFT, FH from RIGHT.
func _release_offset(face_dir: Vector2, style: int) -> Vector2:
	var right_perp: Vector2 = Vector2(-face_dir.y, face_dir.x)
	return right_perp * (12.0 if style == ThrowStyle.FOREHAND else -12.0)

# Release height varies by throw mode — putt is wrist-high, huck is arm-low.
func _mode_launch_height(mode: int) -> float:
	match mode:
		ThrowMode.PUTT: return LAUNCH_HEIGHT_PUTT
		ThrowMode.MID:  return LAUNCH_HEIGHT_MID
		_:              return LAUNCH_HEIGHT_HUCK

# =============================================================
# Throwing
# =============================================================
func _throw_disc(pull: Vector2) -> void:
	var disc: DiscType = discs[current_disc_idx]
	var direction: Vector2 = pull.normalized()
	var drag_frac: float = clampf(pull.length() / POWER_FOR_FULL, 0.1, 1.0)

	var mode: int = _resolve_mode(drag_frac)
	var power_frac: float = _resolve_power_frac(drag_frac, mode)

	var jitter: float = JITTER_DEG[mode][throw_style]
	direction = direction.rotated(deg_to_rad(randf_range(-jitter, jitter)))

	var disc_potential: float = 220.0 + disc.speed * 75.0
	var hand_mult: float = HAND_RANGE_MULT[throw_style]
	var initial_speed: float = disc_potential * hand_mult * power_frac

	# Start disc at release offset, clamped well inside the field so the throw
	# doesn't immediately re-trigger boundary handling.
	var release_origin: Vector2 = disc_pos + _release_offset(direction, throw_style)
	release_origin.x = clampf(release_origin.x, 30.0, current_level.bounds.x - 30.0)
	release_origin.y = clampf(release_origin.y, 30.0, current_level.bounds.y - 30.0)
	disc_pos = release_origin

	disc_vel = direction * initial_speed
	disc_flying = true
	disc_rolling = false
	flight_time = 0.0
	hyzer_at_release = hyzer_angle
	disc_at_release = current_disc_idx
	style_at_release = throw_style
	power_at_release = power_frac
	# Initial bank from release hyzer; release height varies by mode (putt = high
	# wrist release, huck = low arm release that lift then sends climbing).
	disc_bank = hyzer_angle * MAX_BANK
	launch_height = _mode_launch_height(mode)
	disc_height = launch_height
	disc_vz = 0.0
	trail.clear()
	roll_trail.clear()
	trail.append(disc_pos)
	last_trail_pos = disc_pos
	last_safe_pos = disc_pos
	# Rough flight duration estimate for height curve (rises then falls)
	flight_duration_est = clampf(0.6 + power_frac * 1.4, 0.4, 2.2)
	stroke_count += 1
	_play(sfx_throw, -6.0 + power_frac * 6.0)
	# Hyzer is a per-throw choice — reset for the next shot so the player
	# starts each throw flat unless they explicitly bank again.
	hyzer_angle = 0.0
	# Initialize mando tracking — record the side the disc starts on for each
	# mando, so we can tell if it crossed legally during the throw.
	mando_pre_side.clear()
	mando_passed.clear()
	for m in current_level.mandos:
		mando_pre_side.append(_mando_side(m, disc_pos))
		mando_passed.append(false)
	mando_violated_msg = false
	portal_cooldown = 0.0

# =============================================================
# Physics — flight and roll
# =============================================================
func _process(delta: float) -> void:
	if disc_flying:
		_update_flight(delta)
	elif disc_rolling:
		_update_roll(delta)
	if landing_msg_timer > 0.0:
		landing_msg_timer -= delta
	_update_camera(delta)
	queue_redraw()

# Camera follows the disc with a small bias toward the basket so you can see
# a bit ahead, but always keeps the disc visible. Clamped within level bounds.
func _update_camera(delta: float) -> void:
	if current_level == null:
		camera_pos = Vector2.ZERO
		return
	var bnd: Vector2 = current_level.bounds
	if bnd.x <= FIELD_WIDTH and bnd.y <= FIELD_HEIGHT:
		camera_pos = Vector2.ZERO
		return
	var target_center: Vector2
	if (state == State.PLAYING or state == State.HOLE_COMPLETE) and current_hole_idx < holes.size():
		var h: Hole = holes[current_hole_idx]
		# Always center near the disc. Bias TOWARD the basket up to a quarter
		# of the viewport — but never far enough that the disc could leave the
		# visible area. This keeps the lie always on-screen even on huge holes.
		var to_basket: Vector2 = h.basket - disc_pos
		var max_bias: float = FIELD_WIDTH * 0.18
		var bias: Vector2 = Vector2.ZERO
		if to_basket.length() > 0.001:
			bias = to_basket.normalized() * min(max_bias, to_basket.length() * 0.5)
		target_center = disc_pos + bias
	else:
		target_center = Vector2(FIELD_WIDTH, FIELD_HEIGHT) * 0.5
	var target_topleft: Vector2 = target_center - Vector2(FIELD_WIDTH, FIELD_HEIGHT) * 0.5
	target_topleft.x = clampf(target_topleft.x, 0.0, maxf(0.0, bnd.x - FIELD_WIDTH))
	target_topleft.y = clampf(target_topleft.y, 0.0, maxf(0.0, bnd.y - FIELD_HEIGHT))
	var t: float = clampf(delta * 5.0, 0.0, 1.0)
	camera_pos = camera_pos.lerp(target_topleft, t)

func _update_flight(delta: float) -> void:
	var disc: DiscType = discs[disc_at_release]
	var speed: float = disc_vel.length()
	if speed < 1.0:
		_transition_to_roll()
		return

	var hand_mult: float = HAND_RANGE_MULT[style_at_release]
	var max_speed: float = (220.0 + disc.speed * 75.0) * hand_mult
	var speed_ratio: float = clampf(speed / max_speed, 0.0, 1.5)

	var forward: Vector2 = disc_vel / speed
	var right_lateral: Vector2 = Vector2(-forward.y, forward.x)
	var spin_sign: float = 1.0 if style_at_release == ThrowStyle.BACKHAND else -1.0

	# ---- 1. Lift magnitude — designed so lift ≈ gravity in mid-flight ----
	# Linear in speed_ratio (not squared) so the disc glides rather than arcs.
	# Glide boosts how much speed-ratio sustains lift (higher = stays aloft longer).
	var glide_boost: float = 0.85 + 0.06 * disc.glide
	var lift_mag: float = LIFT_BASE * speed_ratio * glide_boost

	# ---- 2. Lift split into vertical (vs gravity) and horizontal (turning) ----
	var bank_eff: float = disc_bank * spin_sign  # FH mirrors
	var lift_vertical: float = lift_mag * cos(bank_eff)
	# Horizontal lift bends path AWAY from the lowered edge:
	#  +bank (hyzer for BH) → bend LEFT → negative right_lateral
	var lift_horizontal: float = -lift_mag * sin(bank_eff) * LIFT_LATERAL_SCALE

	# Apply forces
	disc_vel += right_lateral * lift_horizontal * delta
	disc_vz += (lift_vertical - GRAVITY) * delta

	# ---- 3. Bank angle evolution (torques replace old lateral force model) ----
	# Short throws don't spin enough to develop full turn/fade torques.
	var arc_factor: float = clampf((power_at_release - 0.15) / 0.55, 0.0, 1.0)
	arc_factor = arc_factor * arc_factor

	# Commit factor: when player chose a strong bank (full Q/E), turn/fade
	# torques are suppressed so the disc holds its committed line. Without this,
	# turn/fade can asymmetrically pull a +bank disc flatter while reinforcing a
	# -bank disc, breaking the visual symmetry between Q and E.
	var commit: float = clampf((absf(hyzer_at_release) - 0.3) / 0.7, 0.0, 1.0)
	var commit_mult: float = 1.0 - 0.85 * commit

	# Sign conventions:
	#   +bank = hyzer (banks LEFT for RHBH); -bank = anhyzer.
	#   PDGA `turn` is NEGATIVE for understable (high-speed anhyzer drift).
	#   PDGA `fade` is POSITIVE for overstable (low-speed hyzer hook).
	var turn_torque: float = disc.turn * speed_ratio * speed_ratio * TURN_TORQUE * arc_factor * commit_mult
	var inv: float = 1.0 - speed_ratio
	var fade_torque: float = disc.fade * inv * inv * FADE_TORQUE * arc_factor * commit_mult
	# Restore bank toward the release set-point (the angle the player chose).
	# This is what creates the dynamic equilibrium that produces S-curves:
	# turn pushes one way, fade pushes the other, restore pulls toward release.
	var bank_set_point: float = hyzer_at_release * MAX_BANK
	var restore_torque: float = -(disc_bank - bank_set_point) * HYZER_RESTORE

	disc_bank += (turn_torque + fade_torque + restore_torque) * delta
	disc_bank = clampf(disc_bank, -MAX_BANK, MAX_BANK)

	# ---- 4. Wind (horizontal only — affects late flight more) ----
	var h: Hole = holes[current_hole_idx]
	disc_vel += _wind_at(disc_pos) * (0.4 + (1.0 - speed_ratio) * 0.8) * delta

	# ---- 5. Drag ----
	var drag_rate: float = lerpf(0.30, 0.10, clampf(disc.glide / 6.0, 0.0, 1.0))
	# Big bank → more induced drag
	# Bank-induced drag: quadratic so small Q/E barely penalize, full Q/E hurts.
	var bank_norm: float = clampf(absf(disc_bank) / MAX_BANK, 0.0, 1.0)
	drag_rate += bank_norm * bank_norm * 0.15
	disc_vel *= exp(-drag_rate * delta)
	disc_vz *= exp(-0.25 * delta)  # mild vertical damping

	# ---- 6. Integrate ----
	disc_pos += disc_vel * delta
	disc_height += disc_vz * delta
	flight_time += delta

	# Mando runtime check (mark passed mandos as we cross them)
	if current_level.mandos.size() > 0:
		_check_mandos_runtime()

	# Portal: instant teleport when disc enters a portal circle.
	# Cooldown prevents bouncing inside the destination portal.
	if portal_cooldown > 0.0:
		portal_cooldown -= delta
	else:
		for portal in current_level.portals:
			if disc_pos.distance_to(portal.pos) < portal.radius:
				disc_pos = portal.dest
				portal_cooldown = 0.4
				_play(sfx_click, -2.0)
				_show_landing_msg("Portal!")
				break

	# Trail sampling
	if disc_pos.distance_to(last_trail_pos) > 6.0:
		trail.append(disc_pos)
		last_trail_pos = disc_pos

	# Tree collision — trees are tall enough to block any height we model.
	# Push the disc well clear of the trunk (≈ an arm's length in logical px)
	# so the next throw has room to set a release offset and aim around the tree.
	for obs in current_level.obstacles:
		var op: Vector2 = obs["pos"]
		var orad: float = obs["radius"]
		if disc_pos.distance_to(op) < orad + 6.0:
			var away: Vector2 = (disc_pos - op).normalized()
			disc_pos = op + away * (orad + 30.0)
			disc_vel *= 0.15
			disc_vz = 0.0
			_play(sfx_tree, -4.0)
			_show_landing_msg("Hit a tree!")
			break

	# Track last safe ground position (water landing drops here)
	var surf_now: int = _surface_at(disc_pos)
	if surf_now != Surface.WATER:
		last_safe_pos = disc_pos

	# Boundary — pull the disc well inside so the next throw's release offset
	# can't push it back across.
	if disc_pos.x < 6 or disc_pos.x > current_level.bounds.x - 6 \
		or disc_pos.y < 6 or disc_pos.y > current_level.bounds.y - 6:
		disc_pos.x = clampf(disc_pos.x, 40.0, current_level.bounds.x - 40.0)
		disc_pos.y = clampf(disc_pos.y, 40.0, current_level.bounds.y - 40.0)
		disc_vel = Vector2.ZERO
		disc_vz = 0.0
		disc_height = 0.0
		_show_landing_msg("Out of bounds!")
		_transition_to_roll()
		return

	# Basket catch only when disc is at chains height (~25 px above ground).
	# A disc flying way above the basket sails over it.
	if disc_height < 40.0 and disc_pos.distance_to(h.basket) < BASKET_CATCH_RADIUS:
		# Eccentricity must be measured along the FLIGHT LINE, not at current
		# position — the disc enters the catch zone at the rim regardless of
		# whether it's headed for the center or the edge. Use perpendicular
		# distance from the basket center to the flight trajectory.
		var to_basket: Vector2 = h.basket - disc_pos
		var perp_dist: float = absf(to_basket.x * forward.y - to_basket.y * forward.x)
		if _try_catch_or_spit(speed, perp_dist):
			_finalize_basket()
			return

	# Ground contact: height fell to 0 → land
	if disc_height <= 0.0:
		disc_height = 0.0
		_transition_to_roll()
		return

func _transition_to_roll() -> void:
	disc_flying = false
	disc_rolling = true
	disc_height = 0.0
	disc_vz = 0.0
	# Mando violation check at flight end
	if _any_mando_missed():
		stroke_count += 1
		mando_violated_msg = true
		_show_landing_msg("Mando missed! +1 stroke")
	# Roll velocity: damped by current bank (steep bank = spike-hyzer = no roll).
	var v: Vector2 = disc_vel
	var land_speed: float = v.length()
	var bank_damp: float = 1.0 - 0.6 * clampf(absf(disc_bank) / MAX_BANK, 0.0, 1.0)
	var roll_speed: float = land_speed * bank_damp * 0.55
	if land_speed > 0.001:
		disc_vel = (v / land_speed) * roll_speed
	else:
		disc_vel = Vector2.ZERO
	roll_trail.clear()
	roll_trail.append(disc_pos)
	last_trail_pos = disc_pos
	_play(sfx_land, -2.0)
	# Show a roll indication
	var surf: int = _surface_at(disc_pos)
	if surf == Surface.SAND:
		_show_landing_msg("Sand — barely rolls")
	elif surf == Surface.ROUGH:
		_show_landing_msg("Rough — stops fast")

func _update_roll(delta: float) -> void:
	var speed: float = disc_vel.length()
	if speed < ROLL_STOP_SPEED:
		disc_vel = Vector2.ZERO
		disc_rolling = false
		_finalize_at_rest()
		return

	var surf: int = _surface_at(disc_pos)
	if surf == Surface.WATER:
		_water_penalty()
		return

	var drag: float = 1.6 * SURFACE_ROLL_DRAG[surf]
	disc_vel *= exp(-drag * delta)
	disc_pos += disc_vel * delta

	# Roll tick SFX — frequency scales with speed, played on dedicated channel
	roll_sfx_timer -= delta
	if roll_sfx_timer <= 0.0:
		var spd: float = disc_vel.length()
		roll_sfx_timer = clampf(40.0 / maxf(spd, 20.0), 0.06, 0.35)
		var vol: float = -22.0 + clampf(spd / 200.0, 0.0, 1.0) * 12.0
		roll_player.stream = sfx_roll
		roll_player.volume_db = vol
		roll_player.play()

	if disc_pos.distance_to(last_trail_pos) > 4.0:
		roll_trail.append(disc_pos)
		last_trail_pos = disc_pos

	# Boundary stop — pull well inside (same as flight) to leave room for next throw.
	if disc_pos.x < 12 or disc_pos.x > current_level.bounds.x - 12 \
		or disc_pos.y < 12 or disc_pos.y > current_level.bounds.y - 12:
		disc_pos.x = clampf(disc_pos.x, 40.0, current_level.bounds.x - 40.0)
		disc_pos.y = clampf(disc_pos.y, 40.0, current_level.bounds.y - 40.0)
		disc_vel = Vector2.ZERO
		disc_rolling = false
		_finalize_at_rest()
		return

	# Rolling discs cannot enter the basket — the chains/tray are off the ground.
	# They can only hit the pole base and stop. We don't model that as a catch.
	var h: Hole = holes[current_hole_idx]
	if disc_pos.distance_to(h.basket) < BASKET_RADIUS:
		# Bumped into the basket pole — stop here.
		var away: Vector2 = (disc_pos - h.basket).normalized()
		if away.length() < 0.5:
			away = Vector2(1, 0)
		disc_pos = h.basket + away * (BASKET_RADIUS + 2.0)
		disc_vel = Vector2.ZERO
		disc_rolling = false
		_finalize_at_rest()
		return

	# Track last-safe (we only enter water above; this just sanity-keeps it)
	if surf != Surface.WATER:
		last_safe_pos = disc_pos

# Returns true if caught; false if spit out (caller handles spit-out).
func _try_catch_or_spit(speed: float, perp_dist: float) -> bool:
	var h: Hole = holes[current_hole_idx]
	# Eccentricity = perpendicular distance from basket center to flight line,
	# normalized by catch radius. This is the disc's closest-approach distance,
	# not its current position — a centered throw has ecc=0 even at entry.
	var eccentricity: float = clampf(perp_dist / BASKET_CATCH_RADIUS, 0.0, 1.0)
	# `speed` is impact speed (already drag-decayed in flight).
	var spd: float = clampf((speed - BASKET_CATCH_SPEED) / (BASKET_HOT_SPEED - BASKET_CATCH_SPEED), 0.0, 1.0)
	var bnk: float = clampf(absf(disc_bank) / MAX_BANK, 0.0, 1.0)
	# Ecc penalty scales with speed — a slow disc grazing the rim still catches
	# most of the time (chains drag it down). Fast discs at edge fly past.
	var ecc_speed_scale: float = clampf((speed - 80.0) / 350.0, 0.0, 1.0)
	#   • speed^2.5 × 0.85      → raw power
	#   • ecc^1.3 × 0.85 × ess  → off-center penalty, mostly punishes fast discs
	#   • bank² × 0.12          → tilted disc slips (residual-bank-safe)
	var spit_chance: float = pow(spd, 2.5) * 0.85 \
		+ pow(eccentricity, 1.3) * 0.85 * ecc_speed_scale \
		+ bnk * bnk * 0.12
	spit_chance = clampf(spit_chance, 0.0, 1.0)
	if randf() < spit_chance:
		# Skip past the chains: keep most forward momentum, deflect slightly.
		var forward: Vector2 = disc_vel.normalized()
		var perp: Vector2 = Vector2(-forward.y, forward.x)
		var side: float = 1.0 if randf() < 0.5 else -1.0
		var max_deflect: float = lerpf(8.0, 26.0, spd)
		var deflect_rad: float = deg_to_rad(randf_range(max_deflect * 0.4, max_deflect)) * side
		var new_dir: Vector2 = forward.rotated(deflect_rad)
		disc_pos = h.basket + new_dir * (BASKET_CATCH_RADIUS + 6.0)
		disc_vel = new_dir * speed * 0.75
		_play(sfx_rim, -2.0)
		_show_landing_msg("Rim out!")
		return false
	return true

func _water_penalty() -> void:
	_play(sfx_splash, -2.0)
	_show_landing_msg("Splash! +1 stroke")
	disc_pos = last_safe_pos
	disc_vel = Vector2.ZERO
	disc_flying = false
	disc_rolling = false
	stroke_count += 1  # the penalty stroke (player's throw was already counted)

func _finalize_at_rest() -> void:
	disc_flying = false
	disc_rolling = false
	disc_vel = Vector2.ZERO
	# A disc on the ground does NOT count as a catch — the chains are elevated.
	# The next throw will have to be a real putt.

func _finalize_basket() -> void:
	var h: Hole = holes[current_hole_idx]
	disc_pos = h.basket
	disc_vel = Vector2.ZERO
	disc_flying = false
	disc_rolling = false
	_play(sfx_chain, 0.0)
	if is_tutorial:
		tutorial_done_current = true
		_show_landing_msg("Nice! Press SPACE for next lesson")
	else:
		state = State.HOLE_COMPLETE

func _show_landing_msg(s: String) -> void:
	landing_msg = s
	landing_msg_timer = 1.8

# =============================================================
# Surface query
# =============================================================
func _surface_at(p: Vector2) -> int:
	# Iterate zones in level order; LATER zones override earlier ones.
	# So a level that wants "everything is water with islands" lists water
	# FIRST then the fairway islands, and the islands win.
	# A level that wants "background grass with a pond" lists the pond
	# polygon (it wins inside the polygon, grass everywhere else).
	var matched: int = Surface.SHORT_GRASS  # default
	for z in current_level.zones:
		if Geometry2D.is_point_in_polygon(p, z.polygon):
			matched = z.type
	return matched

# Wind at a given world position. Wind zones override base wind inside their polygon.
func _wind_at(p: Vector2) -> Vector2:
	for wz in current_level.wind_zones:
		if Geometry2D.is_point_in_polygon(p, wz.polygon):
			return wz.wind
	return current_level.wind

# Disc allowed in current level?
func _disc_allowed(idx: int) -> bool:
	if current_level == null:
		return true
	if current_level.allowed_discs.is_empty():
		return true
	return current_level.allowed_discs.has(idx)

# Select a disc, respecting per-level allowed list.
func _select_disc(idx: int) -> void:
	if disc_flying or disc_rolling:
		return
	if not _disc_allowed(idx):
		_show_landing_msg("Disc not allowed in this level")
		_play(sfx_rim, -14.0)
		return
	current_disc_idx = idx
	_play(sfx_click, -10.0)
	_recompute_preview()

# +1 if `p` is to the LEFT of vector p1→p2, -1 if right, 0 if on the line.
func _mando_side(m: Mando, p: Vector2) -> int:
	var d: Vector2 = m.p2 - m.p1
	var rel: Vector2 = p - m.p1
	var cross: float = d.x * rel.y - d.y * rel.x
	if cross > 0.5:
		return 1
	elif cross < -0.5:
		return -1
	return 0

# Apply mando crossings — call each frame during flight to mark passed mandos.
# A mando is "passed" the first time disc moves from its starting side onto
# the required side (or beyond). Wrong side means the disc went around the wrong way.
func _check_mandos_runtime() -> void:
	for i in range(current_level.mandos.size()):
		if mando_passed[i]:
			continue
		var m: Mando = current_level.mandos[i]
		var current_side: int = _mando_side(m, disc_pos)
		var pre: int = mando_pre_side[i]
		# If we ended up on the required side and we crossed (pre != current),
		# AND the crossing point is between p1 and p2, count it as passed.
		if current_side == m.required_side and pre != current_side:
			# Check segment crossing: only count if disc is roughly between p1.p2.
			var t: float = _project_t_on_segment(m.p1, m.p2, disc_pos)
			if t > -0.1 and t < 1.1:
				mando_passed[i] = true

# Returns parameter t such that p ≈ p1 + t*(p2-p1) (closest point on the line).
func _project_t_on_segment(p1: Vector2, p2: Vector2, p: Vector2) -> float:
	var seg: Vector2 = p2 - p1
	var l2: float = seg.length_squared()
	if l2 < 0.001:
		return 0.0
	return (p - p1).dot(seg) / l2

# Returns true if any mando in the level was MISSED (wrong side at flight end).
func _any_mando_missed() -> bool:
	for i in range(current_level.mandos.size()):
		var m: Mando = current_level.mandos[i]
		var pre: int = mando_pre_side[i]
		var post: int = _mando_side(m, disc_pos)
		# If disc started on the wrong side AND never passed AND ended up still on the
		# wrong side OR crossed onto the wrong side — that's a miss.
		if not mando_passed[i] and post != m.required_side and pre != m.required_side:
			return true
		# Also: if disc started on required side but ended on wrong side without passing back.
		if not mando_passed[i] and pre == m.required_side and post != m.required_side:
			return true
	return false

# =============================================================
# Predicted trajectory simulation
# =============================================================
func _recompute_preview() -> void:
	# Predicted trajectory removed in v0.3 — keep stub so callers don't break.
	predicted_path = PackedVector2Array()

# Run flight forward (without jitter, without side-effects).
func _simulate_flight(pull: Vector2) -> PackedVector2Array:
	var disc: DiscType = discs[current_disc_idx]
	var direction: Vector2 = pull.normalized()
	var drag_frac: float = clampf(pull.length() / POWER_FOR_FULL, 0.1, 1.0)
	var mode: int = _resolve_mode(drag_frac)
	var power_frac: float = _resolve_power_frac(drag_frac, mode)

	var disc_potential: float = 220.0 + disc.speed * 75.0
	var hand_mult: float = HAND_RANGE_MULT[throw_style]
	var initial_speed: float = disc_potential * hand_mult * power_frac
	var hand_offset: Vector2 = _release_offset(direction, throw_style)
	var pos: Vector2 = disc_pos + hand_offset
	var vel: Vector2 = direction * initial_speed
	var bank: float = hyzer_angle * MAX_BANK
	var height: float = _mode_launch_height(mode)
	var vz: float = 30.0 + 60.0 * power_frac
	var spin_sign: float = 1.0 if throw_style == ThrowStyle.BACKHAND else -1.0
	var h: Hole = holes[current_hole_idx]
	var max_speed: float = disc_potential * hand_mult
	var arc_factor: float = clampf((power_frac - 0.15) / 0.55, 0.0, 1.0)
	arc_factor = arc_factor * arc_factor
	var pts := PackedVector2Array()
	pts.append(pos)
	var dt: float = 0.0167
	var steps: int = 0
	while steps < 600:
		var speed: float = vel.length()
		if speed < 1.0:
			break
		var speed_ratio: float = clampf(speed / max_speed, 0.0, 1.5)
		var forward: Vector2 = vel / speed
		var right_lateral: Vector2 = Vector2(-forward.y, forward.x)

		var lift_mag: float = LIFT_BASE * speed_ratio
		lift_mag *= (0.85 + 0.06 * disc.glide)
		var bank_eff: float = bank * spin_sign
		var lift_vertical: float = lift_mag * cos(bank_eff)
		var lift_horizontal: float = -lift_mag * sin(bank_eff) * LIFT_LATERAL_SCALE

		vel += right_lateral * lift_horizontal * dt
		vz += (lift_vertical - GRAVITY) * dt

		var commit: float = clampf((absf(hyzer_angle) - 0.3) / 0.7, 0.0, 1.0)
		var commit_mult: float = 1.0 - 0.85 * commit
		var turn_torque: float = disc.turn * speed_ratio * speed_ratio * TURN_TORQUE * arc_factor * commit_mult
		var inv: float = 1.0 - speed_ratio
		var fade_torque: float = disc.fade * inv * inv * FADE_TORQUE * arc_factor * commit_mult
		var bank_set_point: float = hyzer_angle * MAX_BANK
		var restore_torque: float = -(bank - bank_set_point) * HYZER_RESTORE
		bank += (turn_torque + fade_torque + restore_torque) * dt
		bank = clampf(bank, -MAX_BANK, MAX_BANK)

		vel += _wind_at(pos) * (0.4 + (1.0 - speed_ratio) * 0.8) * dt

		var bank_norm_p: float = clampf(absf(bank) / MAX_BANK, 0.0, 1.0)
		var drag_rate: float = lerpf(0.30, 0.10, clampf(disc.glide / 6.0, 0.0, 1.0)) + bank_norm_p * bank_norm_p * 0.35
		vel *= exp(-drag_rate * dt)
		vz *= exp(-0.25 * dt)

		pos += vel * dt
		height += vz * dt
		steps += 1
		if steps % 3 == 0:
			pts.append(pos)
		if height <= 0.0:
			break
		if pos.x < 6 or pos.x > current_level.bounds.x - 6 \
			or pos.y < 6 or pos.y > current_level.bounds.y - 6:
			break
	if pts.size() == 0 or pts[pts.size() - 1] != pos:
		pts.append(pos)
	return pts

# =============================================================
# Drawing
# =============================================================
func _draw() -> void:
	match state:
		State.TITLE:
			_draw_title()
		State.LEVEL_SELECT:
			_draw_level_select()
		State.ROUND_COMPLETE:
			_draw_round_complete()
		State.LEVEL_INTRO:
			_draw_level_intro()
		State.LEVEL_COMPLETE:
			_draw_level_complete()
		State.TUTORIAL:
			draw_set_transform(-camera_pos, 0.0, Vector2.ONE)
			_draw_course()
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_draw_tutorial_overlay()
		_:
			draw_set_transform(-camera_pos, 0.0, Vector2.ONE)
			_draw_course()
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_draw_hud()
			if state == State.HOLE_COMPLETE:
				_draw_hole_complete()

# ---- Title ----
# ---- Title menu ----
const TITLE_MENU_ITEMS := ["Start Campaign", "Tutorial", "Level Select / Records"]

# Returns the screen-space rect of menu item `i` (used for hover + click).
func _title_item_rect(i: int) -> Rect2:
	var w: float = 360.0
	var h: float = 48.0
	var x: float = FIELD_WIDTH / 2.0 - w / 2.0
	var y: float = 360.0 + i * 64.0
	return Rect2(x, y, w, h)

# Title menu action
func _activate_menu_item(i: int) -> void:
	match i:
		0: _begin_campaign()
		1: _start_tutorial()
		2:
			state = State.LEVEL_SELECT
			level_select_idx = 0
			level_select_scroll = 0

func _begin_campaign() -> void:
	game_mode = GameMode.CAMPAIGN
	level_scores.clear()
	_begin_level(0)

func _begin_free_level(li: int) -> void:
	if not levels_unlocked.get(li, false):
		_play(sfx_rim, -10.0)
		return
	game_mode = GameMode.FREE
	_begin_level(li)

# ---- Level select / records screen ----
const LS_ROW_HEIGHT := 50.0
const LS_START_Y := 130.0
const LS_LEFT_X := 80.0
const LS_RIGHT_X := FIELD_WIDTH - 80.0

func _ls_row_rect(visible_row: int) -> Rect2:
	return Rect2(LS_LEFT_X, LS_START_Y + visible_row * LS_ROW_HEIGHT,
		LS_RIGHT_X - LS_LEFT_X, LS_ROW_HEIGHT - 6)

func _draw_level_select() -> void:
	draw_rect(Rect2(0, 0, FIELD_WIDTH, FIELD_HEIGHT), Color(0.10, 0.18, 0.13))
	_label("LEVEL SELECT  •  RECORDS", Vector2(FIELD_WIDTH / 2.0 - 200, 60), 32, Color(1, 0.95, 0.5))
	_label("locked levels require completing the previous level once", Vector2(80, 96), 13, Color(1, 1, 1, 0.55))

	# Mouse hover updates selection.
	var mouse: Vector2 = get_viewport().get_mouse_position()
	for vr in range(LEVEL_SELECT_ROWS_VISIBLE):
		var li_check: int = level_select_scroll + vr
		if li_check >= levels.size():
			break
		if _ls_row_rect(vr).has_point(mouse):
			level_select_idx = li_check

	# Draw visible rows
	for vr in range(LEVEL_SELECT_ROWS_VISIBLE):
		var li: int = level_select_scroll + vr
		if li >= levels.size():
			break
		var lvl: Level = levels[li]
		var unlocked: bool = bool(levels_unlocked.get(li, false))
		var selected: bool = (li == level_select_idx)
		var r: Rect2 = _ls_row_rect(vr)
		var bg: Color
		if not unlocked:
			bg = Color(0.0, 0.0, 0.0, 0.45)
		elif selected:
			bg = Color(1, 0.95, 0.5, 0.18)
		else:
			bg = Color(0, 0, 0, 0.35)
		draw_rect(r, bg)
		var border: Color = Color(1, 0.95, 0.5) if selected else Color(1, 1, 1, 0.25)
		draw_rect(r, border, false, 1.5 if selected else 1.0)

		var fg: Color = Color(0.5, 0.5, 0.55) if not unlocked else (Color(1, 0.95, 0.5) if selected else Color(1, 1, 1))
		var prefix: String = "🔒  " if not unlocked else ""
		# Use ASCII fallback if unicode lock not supported by font
		if not unlocked:
			prefix = "[locked]  "
		_label("%sL%d  %s" % [prefix, li + 1, lvl.name],
			Vector2(r.position.x + 16, r.position.y + 28), 18, fg)

		# Right side: par + best
		var par_total: int = _level_par(lvl)
		var best_str: String = "—"
		if records.has(li):
			best_str = str(int(records[li]))
		var stats: String = "par %d   best %s" % [par_total, best_str]
		var stat_color: Color = Color(0.5, 0.5, 0.55) if not unlocked else Color(1, 1, 1, 0.85)
		_label(stats, Vector2(r.position.x + r.size.x - 220, r.position.y + 28), 16, stat_color)

	# Footer
	var pulse: float = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 350.0)
	_label("↑ / ↓ to choose  •  ENTER to play  •  ESC to title",
		Vector2(80, FIELD_HEIGHT - 28), 14, Color(1, 1, 0.6, pulse))

func _level_select_move(d: int) -> void:
	var n: int = levels.size()
	level_select_idx = clampi(level_select_idx + d, 0, n - 1)
	# Scroll so selection is visible
	if level_select_idx < level_select_scroll:
		level_select_scroll = level_select_idx
	elif level_select_idx >= level_select_scroll + LEVEL_SELECT_ROWS_VISIBLE:
		level_select_scroll = level_select_idx - LEVEL_SELECT_ROWS_VISIBLE + 1

# ---- Level complete summary (between levels) ----
func _draw_level_complete() -> void:
	# Frame underlying course faintly; overlay the summary card.
	draw_set_transform(-camera_pos, 0.0, Vector2.ONE)
	_draw_course()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(0, 0, FIELD_WIDTH, FIELD_HEIGHT), Color(0, 0, 0, 0.55))

	if level_scores.is_empty():
		return
	var entry: Dictionary = level_scores[level_scores.size() - 1]
	var li: int = int(entry["level_idx"])
	var lvl: Level = levels[li]
	var hs: Array = entry["hole_scores"]
	var total: int = int(entry["total"])
	var new_best: bool = bool(entry["new_best"])
	var par: int = _level_par(lvl)
	var diff: int = total - par

	var w: float = 480.0
	var hh: float = 200.0 + hs.size() * 26.0
	var x: float = (FIELD_WIDTH - w) / 2.0
	var y: float = (FIELD_HEIGHT - hh) / 2.0
	draw_rect(Rect2(x, y, w, hh), Color(0, 0, 0, 0.88))
	draw_rect(Rect2(x, y, w, hh), Color(1, 0.85, 0.3), false, 2.0)

	_label("LEVEL %d COMPLETE" % (li + 1), Vector2(x + 24, y + 40), 26, Color(1, 0.95, 0.5))
	_label(lvl.name, Vector2(x + 24, y + 72), 14, Color(1, 1, 1, 0.7))

	var row_y: float = y + 110
	for i in range(hs.size()):
		var d: int = int(hs[i]) - lvl.holes[i].par
		_label("Hole %d (Par %d):  %d  (%+d)" % [i + 1, lvl.holes[i].par, hs[i], d],
			Vector2(x + 28, row_y), 16, Color(1, 1, 1))
		row_y += 26

	var total_color: Color = Color(0.5, 1.0, 0.5) if diff <= 0 else Color(1, 1, 1)
	_label("TOTAL: %d  (Par %d, %+d)" % [total, par, diff],
		Vector2(x + 28, row_y + 14), 20, total_color)
	if new_best:
		_label("★ NEW BEST!", Vector2(x + w - 160, row_y + 14), 18, Color(1, 0.95, 0.5))

	var pulse: float = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 350.0)
	var hint: String
	if game_mode == GameMode.CAMPAIGN and li + 1 < levels.size():
		hint = "SPACE / click — next level"
	elif game_mode == GameMode.CAMPAIGN:
		hint = "SPACE / click — final summary"
	else:
		hint = "SPACE / click — back to level select"
	_label(hint, Vector2(x + 28, y + hh - 28), 14, Color(1, 1, 0.6, pulse))

func _draw_title() -> void:
	draw_rect(Rect2(0, 0, FIELD_WIDTH, FIELD_HEIGHT), Color(0.15, 0.30, 0.18))
	_label("DISC GOLF", Vector2(FIELD_WIDTH / 2.0 - 180, 180), 64, Color(1, 0.95, 0.5))
	_label("13 levels  •  campaign + free play  •  records", Vector2(FIELD_WIDTH / 2.0 - 230, 248), 16, Color(1, 1, 1, 0.7))

	# Mouse-hover updates menu_idx so click + arrows feel consistent.
	var mouse: Vector2 = get_viewport().get_mouse_position()
	for i in range(TITLE_MENU_ITEMS.size()):
		if _title_item_rect(i).has_point(mouse):
			menu_idx = i
			break

	for i in range(TITLE_MENU_ITEMS.size()):
		var r: Rect2 = _title_item_rect(i)
		var selected: bool = (i == menu_idx)
		var bg: Color = Color(1, 0.95, 0.5, 0.15) if selected else Color(0, 0, 0, 0.35)
		var fg: Color = Color(1, 0.95, 0.5) if selected else Color(1, 1, 1, 0.85)
		draw_rect(r, bg)
		draw_rect(r, fg, false, 1.5 if selected else 1.0)
		var label_x: float = r.position.x + 28
		_label(TITLE_MENU_ITEMS[i], Vector2(label_x, r.position.y + 32), 22, fg)
		if selected:
			_label(">", Vector2(r.position.x + 10, r.position.y + 32), 22, fg)

	_label("↑ / ↓ to choose  •  ENTER / click to select", Vector2(FIELD_WIDTH / 2.0 - 200, 610), 14, Color(1, 1, 1, 0.6))

# ---- Course ----
func _draw_course() -> void:
	# Clamp the hole index in case we're rendering a summary screen
	# right after the last hole completed.
	var idx: int = clampi(current_hole_idx, 0, holes.size() - 1)
	var h: Hole = holes[idx]
	var bnd: Vector2 = current_level.bounds
	# Base grass (short) — fills the entire LEVEL, not just viewport
	var grass_col: Color = SURFACE_COLORS[Surface.SHORT_GRASS]
	if current_level.theme_grass_color.a > 0.01:
		grass_col = current_level.theme_grass_color
	draw_rect(Rect2(0, 0, bnd.x, bnd.y), grass_col)
	# Subtle out-of-bounds border so player sees the playable extent
	draw_rect(Rect2(0, 0, bnd.x, bnd.y), Color(0.2, 0.3, 0.18, 0.8), false, 3.0)
	# Surface zones in order (later ones drawn on top so water always visible)
	for z in current_level.zones:
		var col: Color = SURFACE_COLORS[z.type]
		draw_colored_polygon(z.polygon, col)
		# Outline for sand/water to make them readable
		if z.type == Surface.WATER:
			_draw_polygon_outline(z.polygon, Color(0.15, 0.30, 0.55), 2.0)
		elif z.type == Surface.SAND:
			_draw_polygon_outline(z.polygon, Color(0.6, 0.4, 0.15), 2.0)

	# Wind zones: faint tinted overlay + small arrows so players can see them.
	for wz in current_level.wind_zones:
		var mag: float = wz.wind.length()
		# Tint color based on wind strength
		var tint: Color = Color(0.6, 0.85, 1.0, 0.10 + clampf(mag / 100.0, 0.0, 1.0) * 0.10)
		draw_colored_polygon(wz.polygon, tint)
		_draw_polygon_outline(wz.polygon, Color(0.6, 0.85, 1.0, 0.45), 1.5)
		# Scatter a few wind arrows inside the zone
		if mag > 0.5:
			var bbox_min := Vector2(INF, INF)
			var bbox_max := Vector2(-INF, -INF)
			for p in wz.polygon:
				bbox_min.x = minf(bbox_min.x, p.x)
				bbox_min.y = minf(bbox_min.y, p.y)
				bbox_max.x = maxf(bbox_max.x, p.x)
				bbox_max.y = maxf(bbox_max.y, p.y)
			var d: Vector2 = wz.wind / mag
			var step: float = 220.0
			var sx: float = bbox_min.x + step * 0.5
			while sx < bbox_max.x:
				var sy: float = bbox_min.y + step * 0.5
				while sy < bbox_max.y:
					var c := Vector2(sx, sy)
					if Geometry2D.is_point_in_polygon(c, wz.polygon):
						var tip: Vector2 = c + d * 22
						var back: Vector2 = c - d * 22
						var perp: Vector2 = Vector2(-d.y, d.x)
						var ac: Color = Color(0.7, 0.9, 1.0, 0.55)
						draw_line(back, tip, ac, 2.0)
						draw_line(tip, tip - d * 8 + perp * 5, ac, 2.0)
						draw_line(tip, tip - d * 8 - perp * 5, ac, 2.0)
					sy += step
				sx += step

	# Trees
	for obs in current_level.obstacles:
		var op: Vector2 = obs["pos"]
		var orad: float = obs["radius"]
		draw_circle(op, orad + 2.0, Color(0.12, 0.20, 0.10))
		draw_circle(op, orad, Color(0.22, 0.45, 0.20))
		draw_circle(op, orad * 0.55, Color(0.32, 0.62, 0.26))

	# Mandos — gates with an arrow showing required side.
	for m in current_level.mandos:
		var col: Color = Color(1.0, 0.4, 0.3, 0.9)
		# Posts at each end
		draw_circle(m.p1, 7, col)
		draw_circle(m.p2, 7, col)
		# Dashed connection line
		draw_dashed_line(m.p1, m.p2, Color(1.0, 0.4, 0.3, 0.65), 1.5, 8.0)
		# Arrow indicating required side at midpoint
		var mid: Vector2 = (m.p1 + m.p2) * 0.5
		var seg: Vector2 = (m.p2 - m.p1).normalized()
		var nrm: Vector2 = Vector2(-seg.y, seg.x) * float(m.required_side) * 24.0
		var tip: Vector2 = mid + nrm
		draw_line(mid, tip, col, 2.5)
		var perp: Vector2 = Vector2(-nrm.normalized().y, nrm.normalized().x) * 6.0
		draw_line(tip, tip - nrm.normalized() * 8.0 + perp, col, 2.5)
		draw_line(tip, tip - nrm.normalized() * 8.0 - perp, col, 2.5)
		_label(m.label, mid + nrm * 1.7, 11, col)

	# Portals — paired circles with same color, draw both with subtle ring.
	for portal in current_level.portals:
		draw_arc(portal.pos, portal.radius, 0, TAU, 30,
			Color(portal.pair_color.r, portal.pair_color.g, portal.pair_color.b, 0.85), 3.0)
		draw_arc(portal.pos, portal.radius * 0.55, 0, TAU, 20,
			Color(portal.pair_color.r, portal.pair_color.g, portal.pair_color.b, 0.45), 2.0)

	# Tee pad
	draw_rect(Rect2(h.tee.x - 32, h.tee.y - 22, 64, 44), Color(0.25, 0.25, 0.27))
	draw_rect(Rect2(h.tee.x - 32, h.tee.y - 22, 64, 44), Color(0.55, 0.55, 0.6), false, 2.0)
	_label("TEE", Vector2(h.tee.x - 14, h.tee.y + 38), 14, Color(1, 1, 1, 0.85))

	# Distance rings around basket — 20m / 40m / 60m reference circles
	_draw_distance_rings(h.basket)

	# Basket
	_draw_basket(h.basket)

	# Distance label above basket (live)
	var dist_m: float = disc_pos.distance_to(h.basket) / PX_PER_METER
	_label("%dm" % int(dist_m), Vector2(h.basket.x - 14, h.basket.y - BASKET_RADIUS - 14),
		14, Color(1, 0.95, 0.5))

	# (Predicted trajectory removed — felt misleading; rely on actual disc feel.)


	# Flight trail
	# - While flying:     elevated white line (current disc altitude) + faint ground shadow
	# - After landing:    strong ground-projected trajectory in cyan = "real flight path"
	#   This is what the disc actually traveled across the field.
	if trail.size() >= 2:
		var landed: bool = not disc_flying  # rolling or fully at rest
		if disc_flying:
			# Live mode: white elevated line + faint shadow under it
			for i in range(trail.size() - 1):
				var a: float = float(i) / float(trail.size())
				var ht_a: float = _height_at_index(i, trail.size())
				var ht_b: float = _height_at_index(i + 1, trail.size())
				var pa: Vector2 = trail[i] + Vector2(0, -ht_a)
				var pb: Vector2 = trail[i + 1] + Vector2(0, -ht_b)
				draw_line(trail[i], trail[i + 1], Color(0, 0, 0, 0.18), 1.5)
				draw_line(pa, pb, Color(1, 1, 1, 0.30 + a * 0.55), 2.5)
		else:
			# Landed: show the actual ground-track of the flight as a clear cyan line.
			# This is the "real flight path" the player asked for.
			for i in range(trail.size() - 1):
				var a2: float = float(i) / float(trail.size())
				draw_line(trail[i], trail[i + 1], Color(0.55, 0.85, 1.0, 0.55 + a2 * 0.35), 2.5)
			# Mark landing point distinctly
			var landing: Vector2 = trail[trail.size() - 1]
			draw_arc(landing, 8, 0, TAU, 18, Color(0.55, 0.85, 1.0, 0.9), 1.8)
			draw_circle(landing, 3, Color(0.55, 0.85, 1.0, 0.9))

	# Roll trail — brown, hugs the ground, dashed look via thinner segments
	if roll_trail.size() >= 2:
		for i in range(roll_trail.size() - 1):
			var ra: float = float(i) / float(roll_trail.size())
			draw_line(roll_trail[i], roll_trail[i + 1], Color(0.55, 0.38, 0.25, 0.45 + ra * 0.4), 2.0)

	# Player marker + disc (with hand offset and tilt visualization)
	_draw_player_and_disc(h)

	# Aim helpers
	if aim_dragging and not disc_flying and not disc_rolling:
		_draw_aim_helpers(h)

	# Q/E hyzer-direction helper at the tee — always visible while at rest so
	# the player can see which way each key will bend the disc. Follows the
	# drag direction during aim, otherwise points at the basket.
	if not disc_flying and not disc_rolling:
		var face_qe: Vector2 = (h.basket - disc_pos).normalized()
		if aim_dragging:
			var pull_q: Vector2 = aim_current - aim_start
			if pull_q.length() > 5.0:
				face_qe = pull_q.normalized()
		_draw_qe_helper_world(disc_pos, face_qe)

	# Landing message
	if landing_msg_timer > 0.0:
		var alpha: float = clampf(landing_msg_timer / 1.8, 0.0, 1.0)
		_label(landing_msg, Vector2(disc_pos.x - 80, disc_pos.y - 28), 16, Color(1, 0.7, 0.5, alpha))

func _draw_player_and_disc(h: Hole) -> void:
	var face: Vector2 = (h.basket - disc_pos).normalized()
	if aim_dragging:
		var pull: Vector2 = aim_current - aim_start
		if pull.length() > 5.0:
			face = pull.normalized()
	# Player triangle only when at rest
	if not disc_flying and not disc_rolling:
		var perp: Vector2 = Vector2(-face.y, face.x)
		var tip: Vector2 = disc_pos + face * 14.0
		var l: Vector2 = disc_pos - face * 6.0 + perp * 7.0
		var r: Vector2 = disc_pos - face * 6.0 - perp * 7.0
		draw_colored_polygon(PackedVector2Array([tip, l, r]), Color(0.3, 0.3, 0.34))
		draw_polyline(PackedVector2Array([tip, l, r, tip]), Color(0.85, 0.85, 0.9), 1.5, true)

	var disc: DiscType = discs[disc_at_release if (disc_flying or disc_rolling) else current_disc_idx]

	if disc_flying:
		# IN FLIGHT: ground shadow at disc_pos, disc elevated by current height
		var ht: float = _current_flight_height()
		var ground: Vector2 = disc_pos
		var air: Vector2 = disc_pos + Vector2(0, -ht)
		# Ground shadow: shrinks/darkens with altitude
		var shadow_scale: float = 1.0 - clampf(ht / 90.0, 0.0, 0.6)
		draw_circle(ground, 9 * shadow_scale, Color(0, 0, 0, 0.35 * (1.0 - clampf(ht/120.0, 0, 0.5))))
		# Faint tether so player connects shadow to disc
		draw_line(ground, air, Color(0, 0, 0, 0.18), 1.0)
		# Tilted disc up in the air — using LIVE bank (not just release hyzer)
		var bank_norm: float = clampf(disc_bank / MAX_BANK, -1.0, 1.0)
		var minor_air: float = 8.0 * (1.0 - 0.55 * absf(bank_norm))
		_draw_tilted_disc(air, face, disc.color, 8.0, minor_air, bank_norm)
		# Subtle white halo to emphasize "in flight"
		draw_arc(air, 10, 0, TAU, 16, Color(1, 1, 1, 0.35), 1.0)
	elif disc_rolling:
		# ROLLING: disc lies flat on the ground; render very thin (edge-on)
		var dir: Vector2 = disc_vel.normalized() if disc_vel.length() > 0.001 else face
		var minor_roll: float = 2.6  # nearly edge-on
		_draw_tilted_disc(disc_pos, dir, disc.color, 9.0, minor_roll, 0.0)
		# Small dust puffs trailing the rolling disc
		var perp_r: Vector2 = Vector2(-dir.y, dir.x)
		var back: Vector2 = disc_pos - dir * 8.0
		draw_circle(back + perp_r * 3, 1.8, Color(0.7, 0.65, 0.5, 0.35))
		draw_circle(back - perp_r * 3, 1.8, Color(0.7, 0.65, 0.5, 0.35))
	else:
		# AT REST: at hand offset, tilted by current hyzer setting
		var d_render_pos: Vector2 = disc_pos + _release_offset(face, throw_style)
		draw_circle(d_render_pos, 9, Color(0, 0, 0, 0.35))
		var minor_rest: float = 8.0 * (1.0 - 0.55 * absf(hyzer_angle))
		_draw_tilted_disc(d_render_pos, face, disc.color, 8.0, minor_rest, hyzer_angle)

# Real physics height during current flight
func _current_flight_height() -> float:
	return disc_height

# Trail elevation: we don't store per-sample heights, so fall back to a parabolic
# estimate keyed off `flight_duration_est`. Close enough for visual continuity.
func _height_at_index(i: int, n: int) -> float:
	if n <= 1:
		return 0.0
	var t: float = float(i) / float(n - 1)
	var arc: float = 4.0 * t * (1.0 - t)
	var peak: float = 30.0 + 70.0 * power_at_release
	return arc * peak

func _draw_tilted_disc(p: Vector2, face: Vector2, col: Color, major: float, minor: float, hyzer: float) -> void:
	# Draw an ellipse simulating bank: major along perpendicular-to-flight, minor along flight.
	# We rasterize as a polygon of N points so we can keep using draw_colored_polygon.
	var perp: Vector2 = Vector2(-face.y, face.x)
	var steps: int = 20
	var pts := PackedVector2Array()
	for i in range(steps):
		var a: float = TAU * float(i) / float(steps)
		# Local point on ellipse (perp = major axis, face = minor axis)
		pts.append(p + perp * cos(a) * major + face * sin(a) * minor)
	draw_colored_polygon(pts, col)
	# Highlight on the "raised" edge (gives a 3D-ish hint of which side is up)
	var raise_side: float = signf(hyzer)
	if absf(hyzer) > 0.08:
		var high: Vector2 = p - perp * raise_side * major
		var low: Vector2 = p + perp * raise_side * major
		draw_line(high, p, Color(1, 1, 1, 0.55), 1.5)
		draw_line(low, p, Color(0, 0, 0, 0.35), 1.5)
	# Outline
	pts.append(pts[0])
	draw_polyline(pts, Color(0.1, 0.1, 0.1, 0.85), 1.2, true)

func _draw_aim_helpers(h: Hole) -> void:
	var pull: Vector2 = aim_current - aim_start
	var pulldist: float = pull.length()
	if pulldist < 15.0:
		return
	var d: Vector2 = pull.normalized()
	var drag_frac: float = clampf(pulldist / POWER_FOR_FULL, 0.1, 1.0)
	var mode: int = _resolve_mode(drag_frac)
	var power_frac: float = _resolve_power_frac(drag_frac, mode)

	# Short aim indicator (direction only — not a range guide)
	var origin: Vector2 = disc_pos + _release_offset(d, throw_style)
	draw_dashed_line(origin, origin + d * 110.0, Color(1, 1, 0.4, 0.55), 1.5, 6.0)

	# Horizon-style hyzer gauge above the disc
	_draw_hyzer_gauge(origin + Vector2(0, -38), hyzer_angle)
	# Power meter is drawn separately in screen-space HUD (see _draw_hud).

func _draw_hyzer_gauge(p: Vector2, hyz: float) -> void:
	# A small horizon: a bar that rotates around p.
	# +hyzer = left side down (sky tilts right). For RHBH this means disc banks left.
	var len: float = 26.0
	var ang: float = hyz * 0.7  # radians; modest visual tilt
	var dir: Vector2 = Vector2(cos(ang), sin(ang))
	var lp: Vector2 = p - dir * len
	var rp: Vector2 = p + dir * len
	# Tick background
	draw_line(p + Vector2(-len, 0), p + Vector2(len, 0), Color(0, 0, 0, 0.4), 1.0)
	# Indicator
	var col := Color(0.6, 0.9, 1.0) if absf(hyz) > 0.05 else Color(1, 1, 1, 0.7)
	draw_line(lp, rp, col, 3.0)
	draw_circle(p, 2.0, col)

# ---- Basket ----
func _draw_basket(p: Vector2) -> void:
	draw_circle(p + Vector2(0, 18), 12, Color(0, 0, 0, 0.3))
	draw_circle(p, BASKET_RADIUS + 4, Color(0.15, 0.15, 0.18))
	draw_circle(p, BASKET_RADIUS, Color(0.65, 0.65, 0.7))
	draw_arc(p, BASKET_RADIUS - 4, 0, TAU, 24, Color(0.85, 0.85, 0.9), 2.0)
	draw_circle(p, 5, Color(0.2, 0.2, 0.22))

# Concentric reference rings around the basket so players can read distance
# at a glance. 20m / 40m / 60m — fades out farther.
func _draw_distance_rings(basket: Vector2) -> void:
	var rings := [
		{ "m": 20, "col": Color(1, 1, 1, 0.20) },
		{ "m": 40, "col": Color(1, 1, 1, 0.14) },
		{ "m": 60, "col": Color(1, 1, 1, 0.10) },
	]
	for ring in rings:
		var r: float = float(ring["m"]) * PX_PER_METER
		var col: Color = ring["col"]
		# Dashed circle = 36-segment arc with gaps every other segment
		var segs := 36
		for i in range(segs):
			if i % 2 == 1:
				continue
			var a0: float = TAU * float(i) / float(segs)
			var a1: float = TAU * float(i + 1) / float(segs)
			draw_arc(basket, r, a0, a1, 4, col, 1.2)
		# Label on the right side of each ring
		_label("%dm" % int(ring["m"]),
			Vector2(basket.x + r - 12, basket.y + 4), 11, col)

# ---- HUD ----
func _draw_hud() -> void:
	var idx: int = clampi(current_hole_idx, 0, holes.size() - 1)
	var h: Hole = holes[idx]
	var disc: DiscType = discs[current_disc_idx]
	draw_rect(Rect2(0, 0, FIELD_WIDTH, 56), Color(0, 0, 0, 0.5))
	var style_name := "BH" if throw_style == ThrowStyle.BACKHAND else "FH"
	var mode_status: String = "AUTO" if mode_override < 0 else String(MODE_NAMES[mode_override]) + "*"
	var line1: String = "%s  •  Par %d  •  Stroke %d  •  Disc %s [%d-%d-%d-%d]  •  %s  •  Hyzer %s%.1f  •  Mode %s" % [
		h.name, h.par, stroke_count, disc.name,
		int(disc.speed), int(disc.glide), int(disc.turn), int(disc.fade),
		style_name,
		"+" if hyzer_angle >= 0 else "", hyzer_angle,
		mode_status
	]
	_label(line1, Vector2(20, 22), 14, Color(1, 1, 1))
	var hint := "Drag throw • Q/E hyzer • 1/2/3 disc • F hand • Z/X/C mode (V auto) • P pro-mode • R reset • ESC title"
	_label(hint, Vector2(20, 44), 11, Color(1, 1, 1, 0.7))

	# Level restriction badges (allowed discs / mando count) — top-right cluster
	var badge_y: float = 60
	if not current_level.allowed_discs.is_empty():
		var names := PackedStringArray()
		for di in current_level.allowed_discs:
			names.append(discs[di].name)
		_label("DISC LIMIT: %s only" % ", ".join(names),
			Vector2(20, badge_y), 12, Color(1.0, 0.7, 0.4))
		badge_y += 14
	if not current_level.mandos.is_empty():
		var passed_n: int = 0
		for p in mando_passed:
			if p:
				passed_n += 1
		_label("MANDOS: %d / %d passed this throw" % [passed_n, current_level.mandos.size()],
			Vector2(20, badge_y), 12, Color(1.0, 0.5, 0.5))

	_draw_wind(_wind_at(disc_pos))
	_draw_scorecard()
	_draw_offscreen_basket_indicator(h)

	# Power meter — drawn here in HUD (screen-space) so it stays visible
	# regardless of camera position.
	if aim_dragging and not disc_flying and not disc_rolling:
		var pull: Vector2 = aim_current - aim_start
		var pulldist: float = pull.length()
		if pulldist >= 15.0:
			var drag_frac: float = clampf(pulldist / POWER_FOR_FULL, 0.1, 1.0)
			var mode: int = _resolve_mode(drag_frac)
			var power_frac: float = _resolve_power_frac(drag_frac, mode)
			_draw_power_meter(power_frac / MODE_DIST_FRAC[ThrowMode.HUCK], mode)

func _draw_wind(w: Vector2) -> void:
	var cx: float = FIELD_WIDTH - 88
	var cy: float = 28
	draw_circle(Vector2(cx, cy), 22, Color(0, 0, 0, 0.5))
	draw_arc(Vector2(cx, cy), 22, 0, TAU, 24, Color(1, 1, 1, 0.6), 1.0)
	var mag: float = w.length()
	if mag > 0.1:
		var d: Vector2 = w / mag
		var tip: Vector2 = Vector2(cx, cy) + d * 18
		var back: Vector2 = Vector2(cx, cy) - d * 14
		var perp: Vector2 = Vector2(-d.y, d.x)
		draw_line(back, tip, Color(0.7, 0.9, 1.0), 2.5)
		draw_line(tip, tip - d * 8 + perp * 5, Color(0.7, 0.9, 1.0), 2.5)
		draw_line(tip, tip - d * 8 - perp * 5, Color(0.7, 0.9, 1.0), 2.5)
	_label("WIND %d" % int(mag), Vector2(cx - 22, cy + 32), 11, Color(1, 1, 1, 0.85))

# Q/E curve helper anchored at the disc and rotated to follow the throw
# direction. Two arcs branch forward from the tee — one bending to the player's
# left, one to the right — labeled Q/E. The side that matches the currently
# committed hyzer_angle is highlighted and thickens with strength. The arc
# direction is derived from the bank-of-flight, so forehand mirrors for free.
func _draw_qe_helper_world(origin: Vector2, face: Vector2) -> void:
	var perp_right: Vector2 = Vector2(-face.y, face.x)  # screen-frame player's right
	var bh: bool = throw_style == ThrowStyle.BACKHAND
	# BH: Q (+hyzer) bends LEFT, E (-hyzer) bends RIGHT.
	# FH: spin flips, so Q bends RIGHT, E bends LEFT.
	var q_left: bool = bh
	var q_strength: float = clampf(hyzer_angle, 0.0, 1.0)
	var e_strength: float = clampf(-hyzer_angle, 0.0, 1.0)
	_draw_qe_world_arc(origin, face, perp_right, q_left, "Q", q_strength)
	_draw_qe_world_arc(origin, face, perp_right, not q_left, "E", e_strength)

func _draw_qe_world_arc(origin: Vector2, face: Vector2, perp_right: Vector2,
		curves_left: bool, key: String, strength: float) -> void:
	var side: Vector2 = -perp_right if curves_left else perp_right
	var active: bool = strength > 0.05
	var col: Color = Color(0.7, 0.95, 1.0, 0.95) if active else Color(1, 1, 1, 0.40)
	var w: float = 1.6 + 2.4 * strength
	# Start the arc a bit in front of the player triangle so it doesn't overlap.
	var start_offset: float = 20.0
	var length: float = 45.0
	var max_bend: float = 22.0
	var n: int = 14
	var prev: Vector2 = origin + face * start_offset
	for i in range(1, n + 1):
		var t: float = float(i) / float(n)
		var forward_amt: float = start_offset + t * length
		var bend_amt: float = (t * t) * max_bend
		var pt: Vector2 = origin + face * forward_amt + side * bend_amt
		draw_line(prev, pt, col, w)
		prev = pt
	var end_pt: Vector2 = origin + face * (start_offset + length) + side * max_bend
	_label(key, end_pt + Vector2(-3, 4), 12, col)

# Off-screen basket arrow + distance, drawn in HUD (screen) coords.
func _draw_offscreen_basket_indicator(h: Hole) -> void:
	var basket_screen: Vector2 = h.basket - camera_pos
	var margin: float = 56.0
	if basket_screen.x >= margin and basket_screen.x <= FIELD_WIDTH - margin \
		and basket_screen.y >= margin and basket_screen.y <= FIELD_HEIGHT - margin:
		return  # On-screen, no indicator needed.
	var center: Vector2 = Vector2(FIELD_WIDTH, FIELD_HEIGHT) * 0.5
	var dir: Vector2 = basket_screen - center
	var l: float = dir.length()
	if l < 0.001:
		return
	dir = dir / l
	# Find intersection with the screen rect (with margin)
	var t_x: float = 9999.0
	var t_y: float = 9999.0
	if absf(dir.x) > 0.001:
		t_x = (FIELD_WIDTH * 0.5 - margin) / absf(dir.x)
	if absf(dir.y) > 0.001:
		t_y = (FIELD_HEIGHT * 0.5 - margin) / absf(dir.y)
	var t: float = minf(t_x, t_y)
	var pos: Vector2 = center + dir * t
	# Background circle
	draw_circle(pos, 22, Color(0, 0, 0, 0.7))
	draw_arc(pos, 22, 0, TAU, 28, Color(1, 0.95, 0.5), 2.0)
	# Arrow inside
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var tip: Vector2 = pos + dir * 12
	var back: Vector2 = pos - dir * 8
	draw_line(back, tip, Color(1, 0.95, 0.5), 3.0)
	draw_line(tip, tip - dir * 8 + perp * 5, Color(1, 0.95, 0.5), 3.0)
	draw_line(tip, tip - dir * 8 - perp * 5, Color(1, 0.95, 0.5), 3.0)
	# Distance label below the indicator
	var dist_m: int = int(disc_pos.distance_to(h.basket) / PX_PER_METER)
	_label("BASKET %dm" % dist_m, pos + Vector2(-32, 36), 12, Color(1, 0.95, 0.5))

func _draw_scorecard() -> void:
	var x: float = FIELD_WIDTH - 240
	var y: float = 14
	for i in range(holes.size()):
		var col := Color(1, 1, 1, 0.5)
		var txt := "-"
		if i < hole_scores.size():
			txt = str(hole_scores[i])
			var diff: int = hole_scores[i] - holes[i].par
			col = Color(0.5, 1.0, 0.5) if diff < 0 else (Color(1, 1, 1) if diff == 0 else Color(1, 0.6, 0.6))
		elif i == current_hole_idx:
			txt = str(stroke_count)
			col = Color(1, 0.95, 0.5)
		_label("H%d" % (i + 1), Vector2(x + i * 40, y), 11, Color(1, 1, 1, 0.7))
		_label(txt, Vector2(x + i * 40 + 4, y + 18), 16, col)

func _draw_power_meter(p: float, mode: int) -> void:
	var w: float = 240.0
	var h: float = 14.0
	var x: float = FIELD_WIDTH / 2.0 - w / 2.0
	var y: float = FIELD_HEIGHT - 38
	draw_rect(Rect2(x, y, w, h), Color(0, 0, 0, 0.55))
	# Tier dividers
	draw_line(Vector2(x + w * DRAG_PUTT_MAX, y), Vector2(x + w * DRAG_PUTT_MAX, y + h), Color(1, 1, 1, 0.35), 1.0)
	draw_line(Vector2(x + w * DRAG_MID_MAX, y), Vector2(x + w * DRAG_MID_MAX, y + h), Color(1, 1, 1, 0.35), 1.0)
	var col: Color = MODE_COLORS[mode]
	draw_rect(Rect2(x, y, w * clampf(p, 0, 1), h), col)
	draw_rect(Rect2(x, y, w, h), Color(1, 1, 1, 0.6), false, 1.0)
	# Tier distance labels (approx max reach per tier with current disc + hand)
	var disc: DiscType = discs[current_disc_idx]
	var hand_mult: float = HAND_RANGE_MULT[throw_style]
	var disc_potential: float = 220.0 + disc.speed * 75.0
	var max_px: float = disc_potential * hand_mult
	# Each tier's "max" distance ≈ MODE_DIST_FRAC × max_px × 1.5 (lift+drag scaling)
	var label_y: float = y + h + 2
	for m in [ThrowMode.PUTT, ThrowMode.MID, ThrowMode.HUCK]:
		var frac: float = MODE_DIST_FRAC[m]
		var tier_max_m: int = int(max_px * frac * 1.2 / PX_PER_METER)
		var center_x: float
		match m:
			ThrowMode.PUTT: center_x = x + w * DRAG_PUTT_MAX * 0.5
			ThrowMode.MID:  center_x = x + w * (DRAG_PUTT_MAX + DRAG_MID_MAX) * 0.5
			_:              center_x = x + w * (DRAG_MID_MAX + 1.0) * 0.5
		_label("~%dm" % tier_max_m, Vector2(center_x - 14, label_y + 10),
			10, MODE_COLORS[m])
	_label("%s   %d%%" % [MODE_NAMES[mode], int(p * 100)], Vector2(x, y - 18), 12, Color(1, 1, 1, 0.9))

# Drawing helpers
func _label(text: String, pos: Vector2, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw_polygon_outline(poly: PackedVector2Array, col: Color, w: float) -> void:
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		draw_line(a, b, col, w)

# ---- Hole complete banner ----
func _draw_hole_complete() -> void:
	var h: Hole = holes[current_hole_idx]
	var w: float = 540.0
	var hh: float = 150.0
	var x: float = (FIELD_WIDTH - w) / 2.0
	var y: float = (FIELD_HEIGHT - hh) / 2.0
	draw_rect(Rect2(x, y, w, hh), Color(0, 0, 0, 0.78))
	draw_rect(Rect2(x, y, w, hh), Color(1, 0.85, 0.3), false, 2.0)
	var diff: int = stroke_count - h.par
	var label: String
	if stroke_count == 1:
		label = "ACE!!!"
	elif diff == -2:
		label = "EAGLE!"
	elif diff == -1:
		label = "BIRDIE!"
	elif diff == 0:
		label = "PAR"
	elif diff == 1:
		label = "BOGEY (+1)"
	else:
		label = "+%d" % diff
	_label("Hole %d Complete — %s" % [current_hole_idx + 1, label],
		Vector2(x + 24, y + 44), 26, Color(1, 0.95, 0.5))
	_label("%d strokes (par %d)" % [stroke_count, h.par],
		Vector2(x + 24, y + 78), 16, Color(1, 1, 1, 0.9))
	var next_text := "Click or press SPACE for next hole" \
		if current_hole_idx + 1 < holes.size() else "Click or SPACE to see final score"
	_label(next_text, Vector2(x + 24, y + 116), 14, Color(1, 1, 0.6))

# ---- Round complete ----
func _draw_level_intro() -> void:
	# Full-screen splash before each new level (not before level 1).
	draw_rect(Rect2(0, 0, FIELD_WIDTH, FIELD_HEIGHT), Color(0.08, 0.16, 0.12))
	var lvl: Level = levels[current_level_idx]
	# Header
	_label("LEVEL %d" % (current_level_idx + 1),
		Vector2(FIELD_WIDTH / 2.0 - 90, 180), 48, Color(1, 0.95, 0.5))
	# Strip "Level N — " from name if present
	var name_only: String = lvl.name
	var dash_idx: int = name_only.find("— ")
	if dash_idx >= 0:
		name_only = name_only.substr(dash_idx + 2)
	_label(name_only, Vector2(FIELD_WIDTH / 2.0 - 160, 250), 36, Color(1, 1, 1))

	_label("%d holes  •  par %d" % [lvl.holes.size(), _level_par(lvl)],
		Vector2(FIELD_WIDTH / 2.0 - 80, 320), 18, Color(1, 1, 1, 0.7))

	# Brief flavor description
	var blurb: String = _level_blurb(current_level_idx)
	_label(blurb, Vector2(FIELD_WIDTH / 2.0 - 350, 380), 18, Color(1, 1, 1, 0.9))

	var pulse: float = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 350.0)
	_label("Click or SPACE to begin", Vector2(FIELD_WIDTH / 2.0 - 130, 560), 22,
		Color(1, 1, 0.6, pulse))

func _level_par(lvl: Level) -> int:
	var p: int = 0
	for h in lvl.holes:
		p += h.par
	return p

func _level_blurb(idx: int) -> String:
	match idx:
		0: return "Practice park. Open, mild hazards. Get the feel."
		1: return "Open grassland with strong, complex wind. Read it."
		2: return "Dense forest. Curve shots and tight gaps required."
		3: return "Lake course. Every throw is a water carry decision."
		4: return "Hard ground around baskets — discs roll past. Approach with care."
		5: return "Boomerang loop. Each hole demands a different curve."
		6: return "Multiple lanes per hole — short risky vs long safe."
		7: return "Frozen ground. Every disc slides — overshoot is real."
		8: return "Mandatory gates. Pass on the marked side or +1."
		9: return "Island chain. Land on grass or take a swim."
		10: return "Wind tunnel. Tail / head / cross zones in sequence."
		11: return "One disc challenge. Putter only. Wrist game."
		12: return "Portals. Use them as shortcuts — or don't."
	return ""

func _draw_round_complete() -> void:
	draw_rect(Rect2(0, 0, FIELD_WIDTH, FIELD_HEIGHT), Color(0.12, 0.22, 0.15))
	var w: float = 620.0
	var rows: int = 0
	for entry in level_scores:
		var hs: Array = entry["hole_scores"]
		rows += hs.size() + 1
	var hh: float = 200.0 + rows * 22
	var x: float = (FIELD_WIDTH - w) / 2.0
	var y: float = (FIELD_HEIGHT - hh) / 2.0
	draw_rect(Rect2(x, y, w, hh), Color(0, 0, 0, 0.85))
	draw_rect(Rect2(x, y, w, hh), Color(1, 0.85, 0.3), false, 2.0)

	_label("CAMPAIGN COMPLETE", Vector2(x + 130, y + 40), 32, Color(1, 0.95, 0.5))

	var total: int = 0
	var par_total: int = 0
	var row_y: float = y + 90
	for entry2 in level_scores:
		var li: int = int(entry2["level_idx"])
		var lvl: Level = levels[li]
		_label("%s" % lvl.name, Vector2(x + 30, row_y), 16, Color(1, 0.85, 0.5))
		row_y += 22
		var hs2: Array = entry2["hole_scores"]
		for i in range(hs2.size()):
			total += int(hs2[i])
			par_total += lvl.holes[i].par
			var d: int = int(hs2[i]) - lvl.holes[i].par
			_label("  Hole %d (Par %d):  %d  (%+d)" % [i + 1, lvl.holes[i].par, hs2[i], d],
				Vector2(x + 30, row_y), 14, Color(1, 1, 1))
			row_y += 22

	var rel: int = total - par_total
	_label("TOTAL: %d  (Par %d, %+d)" % [total, par_total, rel],
		Vector2(x + 30, row_y + 12), 20, Color(1, 0.95, 0.5))
	var pulse: float = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 350.0)
	_label("Click or SPACE to return to title", Vector2(x + 30, y + hh - 24), 14, Color(1, 1, 0.6, pulse))

# ---- Tutorial overlay (rendered over the playable course) ----
func _draw_tutorial_overlay() -> void:
	# Semi-transparent panel on the left, leaves the right side clear for play.
	var panel_w: float = 380.0
	var panel_h: float = FIELD_HEIGHT
	draw_rect(Rect2(0, 0, panel_w, panel_h), Color(0, 0, 0, 0.62))
	draw_line(Vector2(panel_w, 0), Vector2(panel_w, panel_h), Color(1, 0.95, 0.5, 0.5), 1.5)

	# Page progress dots
	var dy: float = 30
	var n: int = tutorial_holes.size()
	for i in range(n):
		var cx: float = 28 + i * 22
		var col: Color = Color(1, 0.95, 0.5) if i == tutorial_page else Color(1, 1, 1, 0.3)
		draw_circle(Vector2(cx, dy), 6, col)
	_label("Lesson %d / %d" % [tutorial_page + 1, n], Vector2(28 + n * 22 + 16, dy + 4), 13, Color(1, 1, 1, 0.65))

	# Title
	if tutorial_page < tutorial_titles.size():
		_label(tutorial_titles[tutorial_page], Vector2(28, 70), 22, Color(1, 0.95, 0.5))

	# Body text
	var y: float = 120
	if tutorial_page < tutorial_lines.size():
		var lines: PackedStringArray = tutorial_lines[tutorial_page]
		for line in lines:
			_label(line, Vector2(28, y), 15, Color(1, 1, 1, 0.92))
			y += 24

	# Hint (highlighted)
	if tutorial_page < tutorial_hints.size():
		y += 12
		_label("HINT", Vector2(28, y), 12, Color(0.6, 0.95, 1.0, 0.8))
		y += 18
		_label(tutorial_hints[tutorial_page], Vector2(28, y), 14, Color(0.7, 0.95, 1.0))
		y += 28

	# Mini status (mode, hand, hyzer, disc)
	var disc: DiscType = discs[current_disc_idx]
	var status_y: float = FIELD_HEIGHT - 200
	_label("Current setup:", Vector2(28, status_y), 12, Color(1, 1, 1, 0.6))
	var hand_text := "Backhand" if throw_style == ThrowStyle.BACKHAND else "Forehand"
	var mode_text := "AUTO" if mode_override < 0 else String(MODE_NAMES[mode_override]) + " (forced)"
	_label("  Disc: %s [%d-%d-%d-%d]" % [disc.name, int(disc.speed), int(disc.glide), int(disc.turn), int(disc.fade)],
		Vector2(28, status_y + 22), 14, Color(1, 1, 1, 0.85))
	_label("  Hand: %s" % hand_text, Vector2(28, status_y + 44), 14, Color(1, 1, 1, 0.85))
	_label("  Mode: %s" % mode_text, Vector2(28, status_y + 66), 14, Color(1, 1, 1, 0.85))
	_label("  Hyzer: %s%.1f" % ["+" if hyzer_angle >= 0 else "", hyzer_angle],
		Vector2(28, status_y + 88), 14, Color(1, 1, 1, 0.85))

	# Footer controls
	var pulse: float = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 350.0)
	if tutorial_done_current:
		_label("✓ Lesson complete!", Vector2(28, FIELD_HEIGHT - 78), 18, Color(0.5, 1.0, 0.5, pulse))
	var next_text := "Press SPACE or → for next lesson" if tutorial_page < n - 1 \
		else "Press SPACE to start the round"
	_label(next_text, Vector2(28, FIELD_HEIGHT - 52), 14, Color(1, 1, 0.6))
	_label("← back   •   S = skip tutorial   •   R = reset hole", Vector2(28, FIELD_HEIGHT - 28),
		11, Color(1, 1, 1, 0.55))

	# Mini HUD on the right (basket distance + wind)
	_draw_tutorial_topbar()

	# Power meter — same screen-space placement as the real HUD so the
	# tutorial UX matches the round.
	if aim_dragging and not disc_flying and not disc_rolling:
		var pull: Vector2 = aim_current - aim_start
		var pulldist: float = pull.length()
		if pulldist >= 15.0:
			var drag_frac: float = clampf(pulldist / POWER_FOR_FULL, 0.1, 1.0)
			var mode: int = _resolve_mode(drag_frac)
			var power_frac: float = _resolve_power_frac(drag_frac, mode)
			_draw_power_meter(power_frac / MODE_DIST_FRAC[ThrowMode.HUCK], mode)

func _draw_tutorial_topbar() -> void:
	var disc: DiscType = discs[current_disc_idx]
	var hand_short := "BH" if throw_style == ThrowStyle.BACKHAND else "FH"
	var line: String = "%s [%d-%d-%d-%d]   %s   Hyzer %s%.1f" % [
		disc.name, int(disc.speed), int(disc.glide), int(disc.turn), int(disc.fade),
		hand_short,
		"+" if hyzer_angle >= 0 else "", hyzer_angle
	]
	var bg_x: float = 400.0
	draw_rect(Rect2(bg_x, 0, FIELD_WIDTH - bg_x, 40), Color(0, 0, 0, 0.45))
	_label(line, Vector2(bg_x + 14, 24), 14, Color(1, 1, 1, 0.9))
	_label("Drag throw • Q/E hyzer • F hand • Z/X/C mode (V auto) • 1/2/3 disc • P pro • R reset",
		Vector2(bg_x + 14, 38), 10, Color(1, 1, 1, 0.6))

# =============================================================
# Audio — procedurally synthesized
# =============================================================
func _init_audio() -> void:
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	roll_player = AudioStreamPlayer.new()
	add_child(roll_player)
	sfx_throw = _make_throw_sfx()
	sfx_chain = _make_chain_sfx()
	sfx_rim   = _make_rim_sfx()
	sfx_land  = _make_land_sfx()
	sfx_roll  = _make_roll_sfx()
	sfx_tree  = _make_tree_sfx()
	sfx_splash = _make_splash_sfx()
	sfx_click = _make_click_sfx()

func _play(stream: AudioStreamWAV, db: float = 0.0) -> void:
	if stream == null:
		return
	audio_player.stream = stream
	audio_player.volume_db = db
	audio_player.play()

const SR := 22050

func _wrap(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v: float = clampf(samples[i], -1.0, 1.0)
		var s: int = int(v * 32767.0)
		bytes[i * 2] = s & 0xff
		bytes[i * 2 + 1] = (s >> 8) & 0xff
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = bytes
	return w

func _make_throw_sfx() -> AudioStreamWAV:
	var dur := 0.32
	var n := int(SR * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in range(n):
		var t: float = float(i) / float(n)
		var env: float = sin(PI * t) * (1.0 - t * 0.5)
		var raw: float = randf() * 2.0 - 1.0
		var alpha: float = 0.05 + t * 0.35
		prev = prev * (1.0 - alpha) + raw * alpha
		out[i] = prev * env * 0.6
	return _wrap(out)

func _make_chain_sfx() -> AudioStreamWAV:
	var dur := 0.55
	var n := int(SR * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var freqs := [820.0, 1240.0, 1675.0, 2300.0, 3100.0]
	for i in range(n):
		var t: float = float(i) / SR
		var s: float = 0.0
		for f in freqs:
			s += sin(TAU * f * t)
		s /= float(freqs.size())
		var env: float = exp(-t * 8.0) + 0.7 * exp(-max(0.0, t - 0.07) * 11.0) \
			+ 0.5 * exp(-max(0.0, t - 0.18) * 14.0)
		out[i] = s * env * 0.45
	return _wrap(out)

func _make_rim_sfx() -> AudioStreamWAV:
	# Sharp single ping — chains hit hard but disc didn't catch
	var dur := 0.28
	var n := int(SR * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t: float = float(i) / SR
		var env: float = exp(-t * 12.0)
		var s: float = sin(TAU * 1500.0 * t) * 0.5 + sin(TAU * 2400.0 * t) * 0.5
		out[i] = s * env * 0.55
	return _wrap(out)

func _make_land_sfx() -> AudioStreamWAV:
	var dur := 0.18
	var n := int(SR * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in range(n):
		var t: float = float(i) / float(n)
		var env: float = exp(-t * 9.0)
		var raw: float = randf() * 2.0 - 1.0
		prev = prev * 0.92 + raw * 0.08
		out[i] = prev * env * 0.7
	return _wrap(out)

func _make_roll_sfx() -> AudioStreamWAV:
	# Short low rustle — a brief band-limited noise blip
	var dur := 0.09
	var n := int(SR * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in range(n):
		var t: float = float(i) / float(n)
		var env: float = sin(PI * t) * 0.8
		var raw: float = randf() * 2.0 - 1.0
		prev = prev * 0.93 + raw * 0.07
		out[i] = prev * env * 0.55
	return _wrap(out)

func _make_tree_sfx() -> AudioStreamWAV:
	var dur := 0.22
	var n := int(SR * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t: float = float(i) / SR
		var env: float = exp(-t * 22.0)
		var s: float = sin(TAU * 220.0 * t) * 0.6 + (randf() * 2.0 - 1.0) * 0.4
		out[i] = s * env * 0.7
	return _wrap(out)

func _make_splash_sfx() -> AudioStreamWAV:
	# Low-passed noise with slow attack + decay
	var dur := 0.5
	var n := int(SR * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in range(n):
		var t: float = float(i) / float(n)
		var env: float = (1.0 - exp(-t * 9.0)) * exp(-t * 3.0)
		var raw: float = randf() * 2.0 - 1.0
		prev = prev * 0.85 + raw * 0.15
		out[i] = prev * env * 0.8
	return _wrap(out)

func _make_click_sfx() -> AudioStreamWAV:
	var dur := 0.05
	var n := int(SR * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t: float = float(i) / SR
		var env: float = exp(-t * 70.0)
		out[i] = sin(TAU * 1200.0 * t) * env * 0.5
	return _wrap(out)
