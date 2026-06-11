extends Node
class_name HostageManager

# Faithful port of spawnHostages (choplifter.s:62f2). Ticked every physics frame by World (CF4).
var _world: Node = null
var _chopper: Chopper = null
var _hostage_scene: PackedScene = preload("res://src/entities/Hostage.tscn")

func setup(world: Node, chopper: Chopper) -> void:
	_world = world
	_chopper = chopper

func tick(frame_count: int) -> void:
	# Source emits hostages on a 4-frame cadence (FRAME_COUNT AND $03 == 0).
	if frame_count & 0x03 != 0:
		return
	# Active cap: BASE_RUNNERS + HOSTAGES_ACTIVE may not exceed 16.
	if GameState.base_runners + GameState.hostages_active >= GameState.MAX_ACTIVE_HOSTAGES:
		return
	if _chopper.landed and _chopper.landed_at_base:
		_unload_one()
	elif GameState.hostages_left > 0 and GameState.hostages_active < GameState.MAX_SPAWN_BATCH:
		_spawn_field_hostage()
	# When a landed (non-base) chopper is present, nudge field hostages into their run.
	if _chopper.landed and not _chopper.landed_at_base:
		for h in get_tree().get_nodes_in_group("hostages"):
			h.on_chopper_landed(_chopper)

func _unload_one() -> void:
	# HF6: disembark one carried hostage per cycle into a base-runner walking to the door.
	if GameState.hostages_loaded <= 0:
		return
	GameState.total_rescues += 1
	GameState.hostages_loaded -= 1
	GameState.base_runners += 1
	_chopper.hostages_aboard = maxi(_chopper.hostages_aboard - 1, 0)
	AudioManager.play_sfx("hostage_rescued")
	# R3-H4: CURR_LEVEL increments once per batch, where a "batch" is delimited by BOARDING —
	# CHOP_LOADED is armed on each boarding and cleared on the FIRST unload after it
	# (choplifter.s:3552–3557, 3819–3826). Partial-unload → re-board → re-unload increments again.
	if GameState.chop_loaded:
		GameState.chop_loaded = false
		GameState.increment_level_on_unload()
	_spawn_base_runner()
	if GameState.is_victory():
		_world.emit_signal("victory_achieved")

func _spawn_base_runner() -> void:
	var h: Hostage = _hostage_scene.instantiate()
	h.state = Hostage.State.BASE_RUNNER
	h.counted_in_base_runners = true      # this runner DID increment BASE_RUNNERS (R3-H7)
	_world.add_child(h)
	h.position.x = _chopper.pos_x + 4.0   # disembark just right of the chopper, walk to door

func _spawn_field_hostage() -> void:
	var idx := _choose_house()
	if idx < 0:
		return
	GameState.hostages_in_houses[idx] -= 1
	GameState.hostages_left -= 1
	GameState.hostages_active += 1
	var h: Hostage = _hostage_scene.instantiate()
	h.state = Hostage.State.WAVING
	_world.add_child(h)
	h.position.x = float(GameState.HOUSE_SRC_X[idx] + 0x0A)   # anchor + $0A emerge offset — applied
	                                                          # ONCE, here only (R3-M2)

func _choose_house() -> int:
	# R3-H3, source-exact (choplifter.s:3756–3795): prefer the house UNDER the chopper
	# (CHOP_POS_X_H − FARHOUSE_X_H in 0..3), else a random-start RING SCAN over all four houses —
	# exactly ONE RNG call, guaranteed to find any eligible house.
	var strip := (int(_chopper.pos_x) >> 8) - (GameState.SRC_FARHOUSE_X >> 8)
	if strip >= 0 and strip < GameState.NUM_HOUSES and _house_eligible(strip):
		return strip
	var start := GameState.random_byte() & 0x03
	var idx := start
	while true:
		if _house_eligible(idx):
			return idx
		idx = (idx + 1) % GameState.NUM_HOUSES
		if idx == start:
			break
	return -1

func _house_eligible(idx: int) -> bool:
	return GameState.house_states[idx] == 1 and GameState.hostages_in_houses[idx] > 0

# --- R3-C3: field hostages must survive World.tscn reloads (the source hostageTable persists in
# RAM across deaths; scene nodes do not). World calls serialize before the sortie transition and
# restore from _ready() on the next sortie. RUNNING demotes to WAVING — the chopper respawns at
# the base, so the run trigger re-evaluates naturally next time it lands nearby.
func serialize_field_hostages() -> void:
	GameState.field_hostage_records.clear()
	for h in get_tree().get_nodes_in_group("hostages"):
		if h.state in [Hostage.State.WAVING, Hostage.State.RUNNING, Hostage.State.BASE_RUNNER]:
			GameState.field_hostage_records.append({
				"x": h.position.x,
				"state": Hostage.State.WAVING if h.state == Hostage.State.RUNNING else h.state,
				"counted_in_base_runners": h.counted_in_base_runners,
			})

func restore_field_hostages() -> void:
	for rec in GameState.field_hostage_records:
		var h: Hostage = _hostage_scene.instantiate()
		h.state = rec["state"]
		h.counted_in_base_runners = rec["counted_in_base_runners"]
		_world.add_child(h)
		h.position.x = rec["x"]
	GameState.field_hostage_records.clear()
