extends Node
class_name SpawnManager

@export var tank_scene: PackedScene = preload("res://src/entities/Tank.tscn")
@export var jet_scene: PackedScene = preload("res://src/entities/Jet.tscn")
@export var alien_scene: PackedScene = preload("res://src/entities/Alien.tscn")

# Source spawn schedule: FRAME_COUNT AND $2F == 0
# Bitmask $2F = 0b00101111; fires when bits 0,1,2,3,5 are all zero
const SPAWN_BITMASK: int = 0x2F  # Mode 1: faithful non-uniform cadence

var active_tanks: Array = []
var active_jets: Array = []
var active_aliens: Array = []

func tick(frame_count: int) -> void:
	if frame_count & SPAWN_BITMASK == 0:
		_try_spawn_enemy()

func _max_tanks() -> int:  return [1, 2, 2, 2][clampi(GameState.curr_level, 0, 3)]
func _max_jets() -> int:   return [0, 1, 2, 2][clampi(GameState.curr_level, 0, 3)]
func _max_aliens() -> int: return [0, 0, 1, 2][clampi(GameState.curr_level, 0, 3)]

func can_spawn_jet() -> bool:
	return GameState.curr_level >= 1 and active_jets.size() < _max_jets()

func can_spawn_alien() -> bool:
	return GameState.curr_level >= 2 and active_aliens.size() < _max_aliens()

func _try_spawn_enemy() -> void:
	# R3-H2, source-exact (spawnEnemyVehicles, choplifter.s:4582–4618): ONE spawn attempt per $2F
	# tick. A single RNG byte gates the pick — alien needs (rnd & $28) == 0 (level 2+), jet needs
	# bit 7 clear (level 1+), otherwise tank. A failed gate or full cap falls through to the next
	# type. (Round-2 MF3 replaced this with parallel per-type spawns; that over-corrected — it
	# fixed elif starvation but spawned up to 3 enemies per tick, which the source never does.)
	var r := GameState.random_byte()
	if GameState.curr_level >= 2 and (r & 0x28) == 0 and active_aliens.size() < _max_aliens():
		_spawn_alien()
		return
	if GameState.curr_level >= 1 and (r & 0x80) == 0 and active_jets.size() < _max_jets():
		_spawn_jet()
		return
	if active_tanks.size() < _max_tanks():
		_spawn_tank()

# --- Source-faithful tank X selection (choplifter.s spawnTank{Pos,Neg,Med}V) ---
# Branch on the chopper X-velocity high byte:
#   |vx_hi| <= 0x10            → MedV: random behind/ahead (RNG and #$08)
#   vx_hi <  0 (moving left)   → NegV: spawn left of player (X = chop_x - 0xB0)
#   vx_hi >= 0 (moving right)  → PosV: spawn right of player  **but ENTITY_X_H = 0 (bug)**
func select_tank_spawn_x(chopper: Chopper) -> float:
	var vx_hi := chopper.vel_x_hi()
	if vx_hi > -0x11 and vx_hi < 0x11:
		if GameState.random_byte() & 0x08 != 0:
			return spawn_tank_pos_v(chopper.pos_x)
		return spawn_tank_neg_v(chopper.pos_x)
	elif vx_hi < 0:
		return spawn_tank_neg_v(chopper.pos_x)
	else:
		return spawn_tank_pos_v(chopper.pos_x)

func spawn_tank_pos_v(chopper_pos_x: float) -> float:
	# BUG replicated: low byte = (CHOP_POS_X_L + 0xB0) & 0xFF, ENTITY_X_H forced to 0.
	# Result is always pinned to source page 0 (X < 256) regardless of player position.
	return float((int(chopper_pos_x) + 0xB0) & 0xFF)

func spawn_tank_neg_v(chopper_pos_x: float) -> float:
	# Correct: X = CHOP_POS_X - 0xB0 (full 16-bit), clamped to the world.
	return clampf(chopper_pos_x - float(0xB0),
		float(GameState.SRC_BOUNDS_LEFT), float(GameState.SRC_BOUNDS_RIGHT))

func _spawn_tank() -> void:
	if not tank_scene:
		return
	var chopper := get_tree().get_first_node_in_group("chopper") as Chopper
	if not chopper:
		return
	var tank: Tank = tank_scene.instantiate()
	tank.position = Vector2(select_tank_spawn_x(chopper), 0.0)   # ground = altitude 0
	tank.depth_plane = (GameState.random_byte() & 0x07) + 1   # z 1-8
	get_parent().add_child(tank)
	active_tanks.append(tank)
	tank.tree_exiting.connect(func(): active_tanks.erase(tank))

func _spawn_jet() -> void:
	# Jet motion is a ledgered Approximation ($6C00 velocity tables not ported): enter from the
	# off-view side ~1.5 view widths out, above the chopper's altitude, flying toward it.
	if not jet_scene:
		return
	var chopper := get_tree().get_first_node_in_group("chopper") as Chopper
	if not chopper:
		return
	var jet: Jet = jet_scene.instantiate()
	var from_left := GameState.random_byte() & 0x01 == 0
	var offset := 420.0  # 1.5 × 280 source units
	jet.facing = 1 if from_left else -1
	jet.position = Vector2(
		chopper.pos_x + (-offset if from_left else offset),
		minf(-chopper.pos_y - 40.0, -60.0))   # above the chopper, never below 60 units altitude
	get_parent().add_child(jet)
	active_jets.append(jet)
	jet.tree_exiting.connect(func(): active_jets.erase(jet))

func _spawn_alien() -> void:
	# Alien hunts from ~1 view width away at altitude; chase() drives it from there.
	if not alien_scene:
		return
	var chopper := get_tree().get_first_node_in_group("chopper") as Chopper
	if not chopper:
		return
	var alien: Alien = alien_scene.instantiate()
	var from_left := GameState.random_byte() & 0x01 == 0
	alien.position = Vector2(
		chopper.pos_x + (-280.0 if from_left else 280.0),
		-100.0)
	get_parent().add_child(alien)
	active_aliens.append(alien)
	alien.tree_exiting.connect(func(): active_aliens.erase(alien))
