extends CharacterBody2D
class_name Hostage

# State machine. FIELD hostages emerge → wave → run → board. BASE_RUNNER hostages are the disembarked
# survivors walking to the base door (source: BASE_RUNNERS walking right to DOOR_X).
enum State { WAVING, RUNNING, LOADING, RESCUED, DEAD, BASE_RUNNER }

# Boarding proximity in SOURCE units (choplifter.s:3500–3556): board when the chopper is 8–9 units to
# one side; closer than 8 crushes the hostage; 10+ keeps running.
const BOARD_MIN: int = 8
const BOARD_MAX: int = 10
const RUN_STEP: float = 2.0          # source moves a hostage 2 units/frame
# NOTE: there is NO detect radius in the source (choplifter.s:3407–3423). Every field hostage
# runs toward a landed chopper at ANY distance; the only gates are airborne, landed-at-base,
# and a full cabin (HOSTAGES_LOADED == 16). An earlier draft used DETECT_RANGE = 96.0 — removed.

var state: State = State.WAVING
var house: House = null
var countdown_timer: float = 0.0     # Tier C: stranded countdown
var counted_in_base_runners: bool = false  # true only for unloaded runners (those that inc'd
                                           # BASE_RUNNERS); chopper-full run-backs stay false (R3-H7)

func _ready() -> void:
	add_to_group("hostages")

func on_chopper_landed(chopper: Chopper) -> void:
	# Field hostages re-decide EVERY tick (updateHostagesPlayerAloft, choplifter.s:3407-3415):
	# run toward the chopper only while it is landed in the field with cabin space; the moment
	# it lifts off / sits at the base / fills up, they stop and wave. (v0.1 round 4 fix — the
	# old latched RUNNING state made hostages chase a flying chopper and pile into one clump.)
	if state != State.WAVING and state != State.RUNNING:
		return
	var pickable := chopper.landed and not chopper.landed_at_base \
		and GameState.hostages_loaded < GameState.MAX_ABOARD   # full-cabin gate (choplifter.s:3414)
	state = State.RUNNING if pickable else State.WAVING

func _physics_process(_delta: float) -> void:
	match state:
		State.RUNNING:
			_run_toward(_nearest_chopper_x())
		State.BASE_RUNNER:
			_run_to_base_door()

func _nearest_chopper_x() -> float:
	var c := get_tree().get_first_node_in_group("chopper") as Chopper
	return c.pos_x if c else position.x

func _run_toward(target_x: float) -> void:
	position.x += signf(target_x - position.x) * RUN_STEP

func _run_to_base_door() -> void:
	position.x += RUN_STEP            # walk right toward the base door
	if position.x >= float(GameState.SRC_BASE_X):
		# R3-H7 (Approximation, documented in the Fidelity Ledger): door arrival despawns the
		# hostage SAFE but UNCREDITED — faithful to source, which never increments TOTAL_RESCUES
		# at the door (choplifter.s:3460–3471). Unlike the source we keep the counters clean: the
		# source dec's BASE_RUNNERS even for chopper-full run-backs that never incremented it
		# (underflow to $FF) and leaks HOSTAGES_ACTIVE forever.
		if counted_in_base_runners:
			GameState.base_runners = maxi(GameState.base_runners - 1, 0)
		else:
			GameState.hostages_active = maxi(GameState.hostages_active - 1, 0)
		queue_free()                  # reached the door — safe!

# Called by Chopper._check_boarding_nearby_hostages() each frame while landed.
func check_boarding(chopper: Chopper) -> void:
	if state != State.RUNNING:
		return
	var dx := absi(int(round(position.x - chopper.pos_x)))
	if dx < BOARD_MIN:
		_crush()                      # too close — crushed by the chopper
	elif dx < BOARD_MAX:
		_try_board(chopper)

func _try_board(chopper: Chopper) -> void:
	if GameState.hostages_loaded >= GameState.MAX_ABOARD:
		# HF5: chopper full — turn back toward the base instead of boarding. The hostage remains
		# an ACTIVE field hostage (counted_in_base_runners stays false) — source keeps it in
		# HOSTAGES_ACTIVE (choplifter.s:3521–3526).
		state = State.BASE_RUNNER
		return
	state = State.RESCUED
	chopper.hostages_aboard += 1
	GameState.hostages_loaded += 1
	GameState.chop_loaded = true      # CHOP_LOADED — re-arms the per-batch CURR_LEVEL gate (R3-H4)
	GameState.hostages_active = maxi(GameState.hostages_active - 1, 0)
	AudioManager.play_sfx("hostage_board")
	queue_free()

func _crush() -> void:
	_die()

func _die() -> void:
	state = State.DEAD
	GameState.hostages_killed += 1
	GameState.hostages_active = maxi(GameState.hostages_active - 1, 0)
	AudioManager.play_sfx("hostage_death")
	queue_free()
