extends CharacterBody2D
class_name Chopper

signal chopper_died  # emitted by die() (Task 19); World drives the sortie reset from it

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
const VEL_FRAC: int = 256             # velocity is 8.8 fixed point (low byte = fraction)
const MAX_BULLETS: int = 5
const TURN_STATES: int = 11           # -5 to +5

# --- Bullet gravity table from choplifter.s:7260 (|turn_state| → drop) ---
const BULLET_GRAVITY_TABLE: Array[int] = [-2, -2, -1, -1, -1, 0]

# Source ground reference; altitude 0 sits on the ground line (Y flip applied at render only).
const GROUND_SRC_Y: float = 0.0

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
var logical_face: int = 1      # 1 = right, -1 = left (flips instantly on input)
var over_base: bool = false    # set true while the chopper hitbox overlaps the Base Area2D
var airborne: bool = false     # set by ground check (Task 13)
var landed: bool = false       # set by ground check (Task 13)
var landed_at_base: bool = false
var grounding: bool = false    # ZP_GROUNDING — ground-intersection latch (Task 13)
var dying: bool = false
var death_timer: int = 0
var hostages_aboard: int = 0
var active_bullets: int = 0
var fuel: float = 1.0          # Tier C only; ignored in Mode 1

func _ready() -> void:
	add_to_group("chopper")    # entities/managers resolve the player via this group

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

func _update_render_position() -> void:
	# Node positions are SOURCE units 1:1 (the World Camera2D zoom scales source→screen at render).
	# Only the Y axis is flipped here (source altitude is up-positive; Godot Y is down-positive).
	position.x = pos_x
	position.y = GROUND_SRC_Y - pos_y

func _handle_input() -> void:
	if GameState.input_locked or dying:
		return

	# Facing (logical_face flips instantly; turn_state animates separately)
	if Input.is_action_just_pressed("face_left"):
		face_left()
	elif Input.is_action_just_pressed("face_right"):
		face_right()
	elif Input.is_action_just_pressed("face_camera"):
		face_camera()

	# Vertical: thrust up, descend (required to land — R3-C1), or gravity.
	if Input.is_action_pressed("thrust_up"):
		accely_index = FULL_THRUST_INDEX
	elif Input.is_action_pressed("descend"):
		accely_index = DESCEND_INDEX
	else:
		accely_index = GRAVITY_INDEX

	# Horizontal movement: ramp accelx toward ±5 while held, decay toward 0 when released.
	# |accelx| indexes ACCEL_X_TABLE (0 = no input, 5 = full deflection).
	if Input.is_action_pressed("move_right"):
		accelx = mini(accelx + 1, 5)
	elif Input.is_action_pressed("move_left"):
		accelx = maxi(accelx - 1, -5)
	else:
		accelx = signi(accelx) * maxi(absi(accelx) - 1, 0)

	# Fire
	if Input.is_action_just_pressed("fire") and can_fire():
		_fire_bullet()

func _fire_bullet() -> void:
	# Stub here; Task 15 implements bullet spawning with the source velocity table.
	pass

# --- Turn state machine (Task 9, DESIGN.md §7) ---
# 11 states (-5…+5); 2 steps/frame while distance ≥ 2, 1 step at distance 1 —
# a full -5→+5 turn takes 5 frames. logical_face flips instantly on input.
func face_left() -> void:
	logical_face = -1
	target_turn_state = -5

func face_right() -> void:
	logical_face = 1
	target_turn_state = 5

func face_camera() -> void:
	target_turn_state = 0

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
		# Gentle approach: hover at ground without latching landed.
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
	landed = true
	airborne = false
	landed_at_base = over_base

func crash() -> void:
	if dying:
		return
	die()

func die() -> void:
	# Minimal core; Task 19 adds the explosion/death sequence and sortie accounting on top.
	if dying:
		return
	dying = true
	chopper_died.emit()

func _check_boarding_nearby_hostages() -> void:
	for hostage in get_tree().get_nodes_in_group("hostages"):
		hostage.check_boarding(self)

func _on_hitbox_area_entered(_area: Area2D) -> void:
	# Hit resolution lands with the entities that can hit us (Task 16+); resolve via area.owner.
	pass
