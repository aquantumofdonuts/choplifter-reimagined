extends Area2D
class_name Bullet

# Source-exact ballistics (initBulletPhysics, choplifter.s:7194–7259).
# bulletVelocityTable ($6f8d, 72 bytes): rows by |turn_state| 0–5, columns by |stick_x| 0–5,
# (vx, vy) pairs in source units/frame; source index = 12·|turn| + 2·|stick|.
const VELOCITY_TABLE: Array = [
	[[0, 0],  [0, 0],  [1, 0],  [2, 0],  [2, 0],  [2, 0]],   # |turn| 0 (facing camera)
	[[3, 0],  [3, 0],  [3, 0],  [3, 0],  [3, 1],  [4, 2]],   # |turn| 1
	[[8, 0],  [8, 0],  [8, 0],  [8, 1],  [8, 2],  [8, 2]],   # |turn| 2
	[[12, 0], [12, 0], [12, 1], [12, 2], [11, 2], [10, 2]],  # |turn| 3
	[[16, 0], [16, 1], [16, 1], [16, 1], [15, 2], [14, 2]],  # |turn| 4
	[[26, 0], [26, 2], [26, 4], [26, 6], [25, 8], [25, 10]], # |turn| 5 (full side)
]
# From choplifter.s:7260 — |turn_state| → bullet drop (Euler accumulation, per source).
const GRAVITY_TABLE: Array[int] = [-2, -2, -1, -1, -1, 0]

var gravity_step: int = 0  # named to avoid Area2D.gravity native member
var vel_x: int = 0           # signed units/frame; table vx signed by facing + chopper VX inherited
var vel_y: int = 0           # integer units/frame; accumulates gravity each frame
var owner_chopper: Chopper = null

func init(turn_state: int, stick_x: int, chop_vx: int) -> void:
	# turn_state and stick_x are signed as in the source; chop_vx is the chopper's
	# 16-bit X velocity high byte (whole units/frame) — bullets inherit chopper speed.
	var t := clampi(absi(turn_state), 0, 5)
	var s := clampi(absi(stick_x), 0, 5)
	var face := -1 if turn_state < 0 else 1
	vel_x = face * VELOCITY_TABLE[t][s][0] + chop_vx
	# vy sign flips when turn and stick disagree (tilt direction, choplifter.s:7243–7250)
	var tilt_flip := (turn_state < 0) != (stick_x < 0)
	vel_y = -VELOCITY_TABLE[t][s][1] if tilt_flip else VELOCITY_TABLE[t][s][1]
	gravity_step = GRAVITY_TABLE[t]

func _ready() -> void:
	add_to_group("projectiles")   # sortie-reset cleanup frees this group (Task 33) — R3-M7
	# Hitbox lives on this Area2D root (layer 4 = player_bullets; mask = enemies|hostages|houses).
	area_entered.connect(_on_area_entered)

func _physics_process(_delta: float) -> void:
	# Frame-based integer arithmetic (requires the 60Hz locked tick). Positions are source units.
	vel_y += gravity_step
	position.x += float(vel_x)
	position.y -= float(vel_y)    # vel_y negative → moves down (Godot Y down-positive)
	if position.x < GameState.SRC_BOUNDS_LEFT - 32 \
	   or position.x > GameState.SRC_BOUNDS_RIGHT + 32 \
	   or position.y < -200 or position.y > 200:
		_despawn()

func _on_area_entered(area: Area2D) -> void:
	var entity := area.owner
	# Enemies (Tank/Jet/Alien, Tasks 16–18) expose take_hit(); duck-typed so this compiles
	# before those classes exist and stays decoupled after.
	if entity is Hostage:
		entity._die()
		_despawn()
	elif entity is House:
		# R3 house model: shooting a closed house ignites it, RELEASING its occupants
		# (ordnance-vs-house check + igniteHouse, choplifter.s:8605–8616, 8985–8998).
		entity.ignite()
		_despawn()
	elif entity != null and entity.has_method("take_hit"):
		entity.take_hit()
		_despawn()

func _despawn() -> void:
	if owner_chopper:
		owner_chopper.active_bullets -= 1
	queue_free()
