extends CharacterBody2D
class_name Alien

const MAX_VX: float = 5.0
const MAX_VY: float = 1.0
const DESPAWN_DIST_X: float = 560.0  # ~2 view widths (2 × 280 source units)
const FIRE_MIN_ALTITUDE: float = 72.0  # R3-H6b: source gates on the ALIEN'S OWN screen Y < $58
                                       # (choplifter.s:9289–9291) — i.e. the alien must be high
                                       # enough. ≈ altitude > 72 source units with the ground at
                                       # screen row ~160. Ledgered Approximation (screen-row map).

var vel_x: float = 0.0
var vel_y: float = 0.0
var mid_section_frame: int = 0  # Reuses ENTITY_DIR field — 0,1,2 cycle
var _physics_frame: int = 0

@export var shell_scene: PackedScene = preload("res://src/entities/Shell.tscn")

func _ready() -> void:
	add_to_group("enemies")    # R3-M7 — bullet hits and sortie-reset cleanup resolve via this group
	# Sustained crackle loop (Task 24). The plan names "alien_crackle_0", which doesn't exist —
	# the generated files are alien_crackle_lo/mid/hi; mid is the sustained voice (the lo/hi
	# variants are for the visual mid-section frames, future polish). All aliens share ONE loop
	# voice per name in AudioManager (an autoload that outlives this scene), so the loop stops
	# when the LAST alien leaves the tree for ANY reason — kill, despawn, or scene teardown.
	AudioManager.start_loop("alien_crackle_mid")
	tree_exiting.connect(_stop_crackle_if_last)

func _stop_crackle_if_last() -> void:
	# Shared-voice rule: another living alien keeps the loop. Runs from tree_exiting, so this
	# alien has not yet left the group — count the others.
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Alien and e != self:
			return
	AudioManager.stop_loop("alien_crackle_mid")

func chase(chopper_pos: Vector2) -> void:
	# Accelerate toward chopper
	vel_x += sign(chopper_pos.x - position.x)
	vel_y += sign(chopper_pos.y - position.y)
	vel_x = clamp(vel_x, -MAX_VX, MAX_VX)
	vel_y = clamp(vel_y, -MAX_VY, MAX_VY)
	# Hover damp: if off-world horizontally, zero VY
	if position.x < GameState.SRC_BOUNDS_LEFT or position.x > GameState.SRC_BOUNDS_RIGHT:
		vel_y = 0.0

func can_fire() -> bool:
	if GameState.visual_mode == GameState.VisualMode.RETRO:
		return GameState.curr_level == 3  # Mode 1: exact equality (source bug)
	else:
		return GameState.curr_level >= 3  # Mode 2: fixed to >= (Tier A fix)

func check_despawn(chopper_pos: Vector2) -> void:
	if abs(position.x - chopper_pos.x) > DESPAWN_DIST_X:
		queue_free()   # crackle stop handled by the tree_exiting hook

func _physics_process(_delta: float) -> void:
	_physics_frame += 1
	var chopper := get_tree().get_first_node_in_group("chopper") as Chopper
	if not chopper:
		return
	var cpos := Vector2(chopper.pos_x, -chopper.pos_y)   # source units, world space
	chase(cpos)
	position.x += vel_x
	position.y += vel_y
	check_despawn(cpos)
	_update_mid_section_animation()
	_try_fire(cpos)

func _update_mid_section_animation() -> void:
	# Mid-section cycles 0→1→2; jitters by 1px on odd physics frames
	if _physics_frame % 3 == 0:
		mid_section_frame = (mid_section_frame + 1) % 3

func _try_fire(_chopper_pos: Vector2) -> void:
	# R3-H6b — source gate order (choplifter.s:9280–9296):
	if not can_fire():                       # CURR_LEVEL check (Mode 1: == 3)
		return
	if mid_section_frame != 0:               # only on mid-section animation frame 0 (ENTITY_DIR)
		return
	# (source also requires alienStillAnimating; our mid-section animates continuously)
	if -position.y < FIRE_MIN_ALTITUDE:      # only when the ALIEN itself is high enough (Y < $58)
		return
	if (GameState.random_byte() & 0x48) == 0:  # and #$48 — fires on ~1/4 of eligible frames
		_fire_shell()

func _fire_shell() -> void:
	if not shell_scene:
		return
	var shell: Shell = shell_scene.instantiate()
	shell.position = position
	shell.launch_downward()
	get_parent().add_child(shell)

func take_hit() -> void:
	AudioManager.play_sfx("explosion")
	queue_free()   # crackle stop handled by the tree_exiting hook
