extends Node

# --- Visual and variant ---
enum VisualMode { RETRO = 1, MODERN = 2, HI_RES = 3 }
enum GameplayVariant { STANDARD = 0, DIRECTORS_CUT = 1, REIMAGINED = 2 }

var visual_mode: VisualMode = VisualMode.RETRO
var gameplay_variant: GameplayVariant = GameplayVariant.STANDARD

# --- Game progress ---
var sortie: int = 0           # 0-based sortie index (0 = first life)
var lives_remaining: int = 3
var curr_level: int = 0       # 0-3 in Mode 1; 0-7 in Mode 2/3
var total_rescues: int = 0    # TOTAL_RESCUES — credited at UNLOAD as each carried hostage disembarks
                              # (choplifter.s:3814); door arrival only decrements BASE_RUNNERS (R3-M10)
var hostages_killed: int = 0  # HOSTAGES_KILLED
var hostages_loaded: int = 0  # HOSTAGES_LOADED — currently aboard the chopper
var input_locked: bool = false

# --- Tier C extras ---
var fuel_enabled: bool = false
var scatter_on_death: bool = true  # Always true in Reimagined

# --- Demo mode ---
var demo_mode: bool = false

const TOTAL_HOSTAGES: int = 64
const MAX_SORTIES: int = 3
const MODE1_LEVEL_CAP: int = 3
const MODE2_LEVEL_CAP: int = 7

# --- Source coordinate & unit model (Task 3c) — Mode 1 simulates in raw source units ---
# Node positions are these source units 1:1; the World Camera2D zoom scales source→screen at render.
const SRC_BOUNDS_LEFT: int = 0x02D0     # 720  — BOUNDS_LEFT
const SRC_BOUNDS_RIGHT: int = 0x1300    # 4864 — BOUNDS_RIGHT
const SRC_BASE_X: int = 0x1274          # 4724 — BASE_X
const SRC_FARHOUSE_X: int = 0x0380      # 896  — FARHOUSE_X (left-most house anchor)
const SRC_SCROLL_END_X: int = 0x02B0    # 688  — SCROLL_END: leftmost viewport-left camera clamp (R3-M1)
const SRC_SCROLL_START_X: int = 0x1208  # 4616 — SCROLL_START: rightmost viewport-left camera clamp
const SRC_VIEW_WIDTH: int = 280         # source viewport width (units visible across the screen)
const SRC_TO_PX: float = 480.0 / 280.0  # render scale = Camera2D zoom factor (screen px per src unit)

# Aliases kept so existing references resolve; these are SOURCE units, not pixels.
const WORLD_BOUNDS_LEFT: float = float(SRC_BOUNDS_LEFT)    # 720
const WORLD_BOUNDS_RIGHT: float = float(SRC_BOUNDS_RIGHT)  # 4864

static func src_to_px(src_x: float) -> float:
	return src_x * SRC_TO_PX

# --- Hostage universe (authoritative; OWNED BY GameState so it survives World.tscn reloads) ---
# Source: 4 houses, 16 hostages each = 64 reservoir; max 16 active records; max 16 aboard.
const NUM_HOUSES: int = 4                # spawnHostages iterates cpx #$04 (choplifter.s:3776)
const HOSTAGES_PER_HOUSE: int = 16       # 4 × 16 = 64 = TOTAL_HOSTAGES
const MAX_ACTIVE_HOSTAGES: int = 16      # MAX_HOSTAGES hostageTable record count
const MAX_ABOARD: int = 16               # HOSTAGES_LOADED cmp #$10 cap
const MAX_SPAWN_BATCH: int = 5           # HOSTAGES_ACTIVE cmp #$05 spawn throttle
# Source X anchors for the 4 houses: FARHOUSE_X + index*256 (high byte += index).
# These are the house ANCHORS — the +$0A hostage-emerge offset is applied once, at spawn
# (choplifter.s:3858–3866). Do not bake it in here too (R3-M2).
const HOUSE_SRC_X: Array[int] = [0x0380, 0x0480, 0x0580, 0x0680]

var hostages_in_houses: Array[int] = []  # hostagesInHouses[4] — remaining inside each house
var house_states: Array[int] = []        # houseStates[4] — 0 = untouched/closed, 1 = ignited/open
var hostages_left: int = 0               # HOSTAGES_LEFT — reservoir not yet emerged
var hostages_active: int = 0             # HOSTAGES_ACTIVE — emerged & in the field
var base_runners: int = 0                # BASE_RUNNERS — disembarked, walking to the base door
var chop_loaded: bool = false            # CHOP_LOADED — armed on each boarding, cleared on the first
                                         # unload of the batch; gates the CURR_LEVEL increment (R3-H4)

# R3-C3: field-hostage records that must survive World.tscn reloads (the source hostageTable lives
# in RAM across deaths; scene nodes do not). Serialized by World before a sortie reload,
# re-instantiated by HostageManager.restore_field_hostages() on the next sortie.
var field_hostage_records: Array[Dictionary] = []  # [{ "x": float, "state": int, "counted_in_base_runners": bool }]

# --- Source RNG (HF8 / R3-H1) — faithful port of randomNumber (choplifter.s:6069–6083) ---
# 6502 rol/ror rotate THROUGH the carry flag (9-bit), adc consumes the carry left by ror, and the
# extra seed bump is gated on the OVERFLOW flag (bvc), not carry. The carry flag is modeled as
# persistent state. Ledger: Exact algorithm; the source seed ("whatever was in the accumulator
# when the loader was done") and initial carry are approximated as fixed values — a bit-exact
# stream vs. real hardware is unattainable by design.
var _rnd: int = 0x42         # ZP_RND seed (any nonzero start)
var _rnd_seed: int = 0x00    # randomSeed
var _rnd_carry: int = 0      # modeled 6502 carry flag

func _ready() -> void:
	_init_hostage_universe()

func random_byte() -> int:
	var a := _rnd                                        # lda ZP_RND
	var c := _rnd_carry
	var c_out := (_rnd >> 7) & 1                         # rol ZP_RND — 9-bit, through carry
	_rnd = ((_rnd << 1) | c) & 0xFF
	c = c_out
	a = a ^ _rnd                                         # eor ZP_RND
	c_out = _rnd & 1                                     # ror ZP_RND — 9-bit, through carry
	_rnd = ((_rnd >> 1) | (c << 7)) & 0xFF
	c = c_out
	_rnd_seed = (_rnd_seed + 1) & 0xFF                   # inc randomSeed (does not touch flags)
	var sum := a + _rnd_seed + c                         # adc randomSeed — consumes ror's carry
	var result := sum & 0xFF
	_rnd_carry = 1 if sum > 0xFF else 0
	# bvc randomNumberAlt — the extra seed bump fires on signed OVERFLOW (V flag), not carry
	if (~(a ^ _rnd_seed) & (a ^ result)) & 0x80 != 0:
		_rnd_seed = (_rnd_seed + 1) & 0xFF
	_rnd = result                                        # sta ZP_RND
	return result

func _init_hostage_universe() -> void:
	# R3 house-model fix — source polarity ($7311, choplifter.s:5097): 0 = untouched/CLOSED,
	# 1 = on fire/OPEN. Hostages emerge ONLY from ignited (open) houses; igniting RELEASES the
	# occupants, it does not kill them (igniteHouse, choplifter.s:8985–8998). The player opens
	# houses by shooting them (ordnance-vs-house check, choplifter.s:8605–8616).
	hostages_in_houses = []
	house_states = []
	for _i in range(NUM_HOUSES):
		hostages_in_houses.append(HOSTAGES_PER_HOUSE)
		house_states.append(0)  # closed
	hostages_left = TOTAL_HOSTAGES
	hostages_active = 0
	base_runners = 0
	# Game-start setup (spawnInitialHostages, choplifter.s:11341–11360): the right-most house
	# begins IGNITED with 8 of its hostages already in the field beside it. Seed them as field
	# records; World._ready()'s restore_field_hostages() instantiates them.
	house_states[3] = 1
	hostages_in_houses[3] -= 8
	hostages_left -= 8
	hostages_active = 8
	field_hostage_records.clear()
	for i in range(8):
		field_hostage_records.append({
			"x": float(HOUSE_SRC_X[3] + 0x0A + i * 6),
			"state": 0,  # Hostage.State.WAVING (raw int — avoids a cross-class dependency here)
			"counted_in_base_runners": false,
		})

func reset() -> void:
	sortie = 0
	lives_remaining = MAX_SORTIES
	curr_level = 0
	total_rescues = 0
	hostages_killed = 0
	hostages_loaded = 0
	input_locked = false
	demo_mode = false
	chop_loaded = false
	field_hostage_records.clear()
	_init_hostage_universe()

func is_victory() -> bool:
	return total_rescues >= TOTAL_HOSTAGES

func is_mission_loss() -> bool:
	# Win check runs first — call is_victory() before this
	if is_victory():
		return false
	return total_rescues + hostages_killed >= TOTAL_HOSTAGES

func is_sorties_loss() -> bool:
	return lives_remaining <= 0

func level_cap() -> int:
	return MODE1_LEVEL_CAP if visual_mode == VisualMode.RETRO else MODE2_LEVEL_CAP

# Source increments CURR_LEVEL during base unload, gated by cmp #$03 (choplifter.s:3822–3826).
# Mode 2/3 extend the cap to 7 — use level_cap(), not the hardcoded Mode 1 constant (R3-H5).
func increment_level_on_unload() -> void:
	if curr_level < level_cap():
		curr_level += 1

func on_chopper_death(aboard: int) -> void:
	# Hostages aboard are lost; active field hostages persist (state owned here, not in the scene).
	hostages_killed += aboard
	hostages_loaded = 0
	lives_remaining -= 1
	sortie += 1
