extends CharacterBody2D
class_name Chopper

signal chopper_died    # emitted by die() after the death sequence; World drives the sortie reset
signal chopper_landed  # declared for later tasks (HUD/boarding cues); emitted on the landed transition

# --- Source-faithful tables (choplifter.s:5262–5267) ---
# Y: TARGET velocities (units/frame, high-byte). Velocity eases toward these — never added.
const ACCEL_Y_TABLE: Array[int] = [-10, -9, -8, -7, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 6]
# X: 16-bit signed acceleration magnitudes, indexed by bank amount |turn_state| (0 = head-on).
const ACCEL_X_TABLE: Array[int] = [0x0000, 0x0060, 0x00B4, 0x0108, 0x015C, 0x01A4]

const GRAVITY_INDEX: int = 8          # ZP_ACCELY default (no thrust) — target −2
const FULL_THRUST_INDEX: int = 15     # ZP_ACCELY max — target +6
const DESCEND_INDEX: int = 0          # ZP_ACCELY min — full stick-down, target −10 (R3-C1: required
                                      # to reach MIN_VY and land; gravity alone tops out at −2)
const VEL_X_CLAMP_HI: int = 0x15      # high-byte clamp ±21 (source cmp #$15 / #$EB)
const CEILING_ALT: float = 105.0      # BOUNDS_TOP $70 (choplifter.s:4818) minus the $07 ground
                                      # offset (CHOP_POS_Y ground = $07, zeropage.s:13) — the
                                      # source clamps Y here and zeroes VY (choplifter.s:5613–5621)
const VEL_FRAC: int = 256             # velocity is 8.8 fixed point (low byte = fraction)
const MAX_BULLETS: int = 5
const TURN_STATES: int = 11           # -5 to +5
const DEATH_DURATION: float = 1.5     # Seconds for explosion animation

# --- Bullet gravity table from choplifter.s:7260 (|turn_state| → drop) ---
const BULLET_GRAVITY_TABLE: Array[int] = [-2, -2, -1, -1, -1, 0]

# Source ground reference; altitude 0 sits on the ground line (Y flip applied at render only).
const GROUND_SRC_Y: float = 0.0

# --- Body sprite frames (extracted Apple II sprites, 4x scale → 0.25 node scale) ---
# Side view (|turn_state| == 5): tilt frame indexed by the X stick (accelx -5..+5 → 0..10).
const SIDE_BY_TILT: Array[Texture2D] = [
	preload("res://assets/graphics/mode1/chopper_side/tilt_m5.png"),
	preload("res://assets/graphics/mode1/chopper_side/tilt_m4.png"),
	preload("res://assets/graphics/mode1/chopper_side/tilt_m3.png"),
	preload("res://assets/graphics/mode1/chopper_side/tilt_m2.png"),
	preload("res://assets/graphics/mode1/chopper_side/tilt_m1.png"),
	preload("res://assets/graphics/mode1/chopper_side/tilt_0.png"),
	preload("res://assets/graphics/mode1/chopper_side/tilt_p1.png"),
	preload("res://assets/graphics/mode1/chopper_side/tilt_p2.png"),
	preload("res://assets/graphics/mode1/chopper_side/tilt_p3.png"),
	preload("res://assets/graphics/mode1/chopper_side/tilt_p4.png"),
	preload("res://assets/graphics/mode1/chopper_side/tilt_p5.png"),
]
# Turning (|turn_state| 0..4): head-on rotation frames.
const ROTATE_BY_TURN: Array[Texture2D] = [
	preload("res://assets/graphics/mode1/chopper_headon/headon_0.png"),
	preload("res://assets/graphics/mode1/chopper_headon/rotate_1.png"),
	preload("res://assets/graphics/mode1/chopper_headon/rotate_2.png"),
	preload("res://assets/graphics/mode1/chopper_headon/rotate_3.png"),
	preload("res://assets/graphics/mode1/chopper_headon/rotate_4.png"),
]

# --- Landing constants (choplifter.s:4792–4804), in source high-byte units ---
const MIN_VY_HI: int = -5        # MIN_VY $FBA0 — min downward speed to register ground
const CRASHSPEED_HI: int = 0x15  # CRASHSPEED $EB01 — |vx_hi| at/above which a touchdown crashes
const LAUNCHTHRESH_HI: int = 1   # LAUNCHTHRESH $0100 — upward speed to leave the ground
const MAX_SINK: int = 6          # MAX_SINK $06 — max ground settle depth (source units)

# --- 16-bit fixed-point velocity (source ZP_VELX_16 / ZP_VELY_16) ---
var vel_x: int = 0   # 8.8 fixed point, source units/frame
var vel_y: int = 0   # 8.8 fixed point; low byte is forced to 0 each frame by the Y algorithm

# --- Position in SOURCE units (Task 3c); render layer scales to pixels ---
var pos_x: float = 0.0   # source X (SRC_BOUNDS_LEFT … SRC_BOUNDS_RIGHT)
var pos_y: float = 0.0   # source altitude, UP-POSITIVE (0 = ground); Godot Y negated at render

# --- State ---
var accely_index: int = GRAVITY_INDEX
var target_turn_state: int = 0 # turn_state animates toward this (Task 9)
var accelx: int = 0            # ZP_STICKX: joystick-X input, -5…+5; |accelx| indexes ACCEL_X_TABLE
var turn_state: int = 0        # -5 (left side) … 0 (head-on) … +5 (right side); rotor facing
var face_mode: int = 0         # CHOP_FACE: commanded facing — -1 left, 0 camera, +1 right.
                               # Spawns camera-facing like the source sortie start.
var logical_face: int = 1      # 1 = right, -1 = left (flips instantly on input)
var over_base: bool = false    # set true while the chopper hitbox overlaps the Base Area2D
var airborne: bool = false     # set by ground check (Task 13)
var landed: bool = false       # set by ground check (Task 13)
var landed_at_base: bool = false
var grounding: bool = false    # ZP_GROUNDING — ground-intersection latch (Task 13)
var dying: bool = false
var hostages_aboard: int = 0
var active_bullets: int = 0
var fuel: float = 1.0          # Tier C only; ignored in Mode 1

@onready var _body: Sprite2D = $BodySprite

func _ready() -> void:
	add_to_group("chopper")    # entities/managers resolve the player via this group
	# Engine loop lifecycle (Task 24): started here on spawn; stopped in die() before the
	# death-sequence await, in PauseMenu.show_pause() (AudioManager is PROCESS_MODE_ALWAYS,
	# so a paused tree would not silence it), and in World._start_victory/_start_loss
	# (those transitions leave the chopper alive while swapping to MainMenu).
	AudioManager.start_loop("engine_loop")

# Arithmetic shift right (sign-preserving) — matches source arithmeticShiftRight16.
func _asr(v: int, n: int) -> int:
	return v >> n

func vel_y_hi() -> int:
	return _asr(vel_y, 8)

func vel_x_hi() -> int:
	return _asr(vel_x, 8)

func get_y_target() -> int:
	return ACCEL_Y_TABLE[accely_index]

# --- The integration step (CF1): X first, then Y, matching integrateAcceleration ---
func integrate_acceleration() -> void:
	_integrate_x()
	_integrate_y()

func _integrate_x() -> void:
	# Per-frame friction/drag: VELX -= VELX >> 4 (source caches, ASR16 by 4, subtracts).
	vel_x -= _asr(vel_x, 4)
	# Joystick acceleration: magnitude from table[|accelx|], direction = sign(accelx).
	# (Source stores accel sign-reversed internally vs. screen velocity; the net on-screen effect is
	# acceleration toward the input direction, which this expresses directly.)
	var idx := absi(accelx)
	var a := ACCEL_X_TABLE[idx]
	vel_x += signi(accelx) * a
	# Clamp the high byte (source cmp #$15 / cmp #$EB, choplifter.s:5240–5258): the positive side
	# clamps AT +$15 (zeroing the low byte at exactly $15xx); the negative side clamps below −$15
	# to $EB00. R3-L1.
	var hi := vel_x_hi()
	if hi >= VEL_X_CLAMP_HI:
		vel_x = VEL_X_CLAMP_HI << 8
	elif hi < -VEL_X_CLAMP_HI:
		vel_x = -(VEL_X_CLAMP_HI << 8)

func _integrate_y() -> void:
	# Ease Y velocity HIGH BYTE toward the table TARGET (halve remaining distance while ≥ 2).
	var target := get_y_target()
	var vy_h := vel_y_hi()
	var diff := target - vy_h
	var mag := absi(diff)
	if mag >= 2:
		mag = mag >> 1                       # source: cmp #$02 / lsr
	var step := (1 if diff >= 0 else -1) * mag
	vy_h += step
	vel_y = vy_h << 8                         # VELY_L := 0

func integrate_velocity() -> void:
	# Advance source-unit position by the 8.8 fixed-point velocity.
	pos_x += float(vel_x) / float(VEL_FRAC)
	pos_y += float(vel_y) / float(VEL_FRAC)  # up-positive (thrust +6 raises altitude)

func _physics_process(_delta: float) -> void:
	if dying or GameState.input_locked:
		return
	_handle_input()          # Task 10: sets accely_index, accelx, target_turn_state, fires
	_advance_turn_state()    # Task 9: animates turn_state toward target_turn_state
	integrate_acceleration()
	integrate_velocity()
	_clamp_to_world_bounds()
	_check_ground()                          # implemented in Task 13 (source thresholds)
	_update_render_position()
	if landed and not dying:
		_check_boarding_nearby_hostages()

func _clamp_to_world_bounds() -> void:
	if pos_x < GameState.SRC_BOUNDS_LEFT:
		pos_x = GameState.SRC_BOUNDS_LEFT
		vel_x = 0
	elif pos_x > GameState.SRC_BOUNDS_RIGHT:
		pos_x = GameState.SRC_BOUNDS_RIGHT
		vel_x = 0
	# Ceiling: clamp to top of sky and zero VY, exactly as the source does after applying
	# velocity (integrateVelocityClampY, choplifter.s:5613–5621).
	if pos_y > CEILING_ALT:
		pos_y = CEILING_ALT
		vel_y = 0

func _update_render_position() -> void:
	# Node positions are SOURCE units 1:1 (the World Camera2D zoom scales source→screen at render).
	# Only the Y axis is flipped here (source altitude is up-positive; Godot Y is down-positive).
	position.x = pos_x
	position.y = GROUND_SRC_Y - pos_y
	_update_sprite()

func _update_sprite() -> void:
	var t := absi(turn_state)
	if t >= 5:
		# Full side view: tilt frame from the X stick, mirrored when facing left.
		_body.texture = SIDE_BY_TILT[clampi(accelx + 5, 0, 10)]
		_body.flip_h = logical_face < 0
	else:
		# Facing camera / mid-turn: head-on rotation frames, mirrored for left turns.
		_body.texture = ROTATE_BY_TURN[t]
		_body.flip_h = turn_state < 0

func _handle_input() -> void:
	if GameState.input_locked or dying:
		return

	# Facing (logical_face flips instantly; turn_state animates separately).
	# Source: "Can't rotate when on the ground" (checkJoystick1, choplifter.s:906-908).
	if airborne:
		if Input.is_action_just_pressed("face_left"):
			face_left()
		elif Input.is_action_just_pressed("face_right"):
			face_right()
		elif Input.is_action_just_pressed("face_camera"):
			face_camera()

	# Vertical: proportional collective (source joystickYTable maps deflection to ACCELY
	# index 0-15; choplifter.s:5630-5658). Action strength is analog on gamepad sticks and
	# 0/1 on keys, so this single mapping gives: W/full-up → 15, S/full-down → 0 (R3-C1,
	# required to land), neutral → 8 (gravity sink −2), and every analog stop in between.
	var collective := Input.get_action_strength("thrust_up") - Input.get_action_strength("descend")
	accely_index = clampi(roundi(7.5 + 7.5 * collective), 0, 15)

	# Horizontal movement: ramp accelx toward ±5 while held; SNAP to 0 on release (a real
	# joystick re-centers within one source tick — the old gradual decay kept accelx nonzero
	# for ~5 ticks after release, blocking the centered-stick touchdown gate and forcing the
	# player to "press down again" to land; v0.1 round 5). Grounded chopper takes no X input
	# (the source's grounded state has no taxiing; lift off first).
	if landed:
		accelx = 0
	elif Input.is_action_pressed("move_right"):
		accelx = mini(accelx + 1, 5)
	elif Input.is_action_pressed("move_left"):
		accelx = maxi(accelx - 1, -5)
	else:
		accelx = 0

	# Facing → turn target. Commanded side-facing goes to ±5; in camera mode the chopper
	# LEANS with the stick (facingTurnTable[ACCELX+5] = ±1 at hard deflection, 0 otherwise;
	# choplifter.s:1030 — table is sign-reversed there because the source stores accel
	# inverted; ours is screen-signed).
	if face_mode != 0:
		target_turn_state = 5 * face_mode
	elif accelx >= 4:
		target_turn_state = 1
	elif accelx <= -4:
		target_turn_state = -1
	else:
		target_turn_state = 0

	# Fire
	if Input.is_action_just_pressed("fire") and can_fire():
		_fire_bullet()

@export var bullet_scene: PackedScene = preload("res://src/entities/Bullet.tscn")

func _fire_bullet() -> void:
	if not can_fire():
		return
	active_bullets += 1
	var b: Bullet = bullet_scene.instantiate()
	# Signed turn_state and stick_x (accelx = ZP_STICKX), plus whole-unit chopper VX
	# (16-bit velocity high byte), per initBulletPhysics (choplifter.s:7194–7259)
	b.init(turn_state, accelx, vel_x_hi())
	b.owner_chopper = self
	b.position = Vector2(pos_x + float(logical_face) * 24.0, -pos_y)
	get_parent().add_child(b)
	AudioManager.play_sfx("bullet_fire")

# --- Turn state machine (Task 9, DESIGN.md §7) ---
# 11 states (-5…+5); 2 steps/frame while distance ≥ 2, 1 step at distance 1 —
# a full -5→+5 turn takes 5 frames. logical_face flips instantly on input.
func face_left() -> void:
	logical_face = -1
	face_mode = -1

func face_right() -> void:
	logical_face = 1
	face_mode = 1

func face_camera() -> void:
	face_mode = 0

func _advance_turn_state() -> void:
	var dist := target_turn_state - turn_state
	if dist == 0:
		return
	var step := 2 if abs(dist) >= 2 else 1
	turn_state += sign(dist) * step
	turn_state = clamp(turn_state, -5, 5)

func can_fire() -> bool:
	return airborne and not dying and active_bullets < MAX_BULLETS

func get_bullet_gravity() -> int:
	return BULLET_GRAVITY_TABLE[abs(turn_state)]

func _check_ground() -> void:
	if pos_y > 0.0:
		airborne = true
		landed = false
		landed_at_base = false
		return
	# At or below the ground line.
	pos_y = max(pos_y, float(-MAX_SINK))
	var vy_h := vel_y_hi()
	if airborne:
		# Touchdown only registers when descending at least MIN_VY *with the X stick centered* —
		# the source reaches the intersection check only through the ZP_ACCELX == 0 branch
		# (chopperPhysicsNoAccel, choplifter.s:5287–5292). R3-M3.
		if accelx == 0 and vy_h <= MIN_VY_HI:
			if absi(vel_x_hi()) >= CRASHSPEED_HI:
				crash()
				return
			_settle()
		else:
			# Hover AT the ground line without latching landed. The source clamps POSITION
			# ONLY ("Keep chopper out of ground", choplifter.s:5299–5301) — VY keeps its
			# value. Zeroing VY here (the round-3 version) broke sideways landings: arriving
			# with drift blocked the centered-stick gate, the wipe killed the descent
			# velocity, and gravity's −2 could never re-reach MIN_VY −5 — the chopper then
			# hovered forever unless the player pressed down AGAIN (v0.1 rounds 4-5 bug).
			# With VY preserved, centering the stick within the decay window still lands.
			pos_y = maxf(pos_y, 0.0)
	else:
		# Already grounded: lift off only when upward thrust beats the launch threshold.
		if vy_h >= LAUNCHTHRESH_HI:
			airborne = true
			landed = false
			landed_at_base = false
		else:
			_settle()

func _settle() -> void:
	pos_y = 0.0
	vel_y = 0
	vel_x -= _asr(vel_x, 1)       # ground X decay (source chopperPhysics_Decay: ASR by 1)
	if not landed and airborne:
		# Landed TRANSITION only (airborne → ground). The spawn frame also reaches _settle()
		# (grounded, not yet landed) but with airborne == false — no touchdown sound there.
		chopper_landed.emit()
		AudioManager.play_sfx("landing")  # Task 24 — v0.1 checklist requires an audible touchdown
	landed = true
	airborne = false
	landed_at_base = over_base

func crash() -> void:
	if dying:
		return
	die()

func die() -> void:
	if dying:
		return
	dying = true
	GameState.on_chopper_death(hostages_aboard)
	hostages_aboard = 0  # GameState zeroed its loaded count; keep the chopper's copy in sync (HUD reads it)
	AudioManager.stop_loop("engine_loop")  # silence the engine the instant the chopper dies
	AudioManager.play_sfx("explosion")
	# Hold for DEATH_DURATION so the explosion SFX plays out before the sortie transition.
	await get_tree().create_timer(DEATH_DURATION).timeout
	chopper_died.emit()

func _check_boarding_nearby_hostages() -> void:
	for hostage in get_tree().get_nodes_in_group("hostages"):
		hostage.check_boarding(self)

func _on_hitbox_area_entered(_area: Area2D) -> void:
	# Hit resolution lands with the entities that can hit us (Task 16+); resolve via area.owner.
	pass
