extends GdUnitTestSuite

var chopper: Chopper

func before_test():
	GameState.reset()
	chopper = preload("res://src/entities/Chopper.tscn").instantiate()
	add_child(chopper)

func after_test():
	chopper.queue_free()

func test_safe_landing_sets_landed():
	chopper.airborne = true
	chopper.over_base = false
	chopper.pos_y = -1.0          # just below ground line
	chopper.vel_y = -(6 << 8)       # descending at vy_hi = -6 (past MIN_VY = -5)
	chopper.vel_x = 0             # horizontal speed safe
	chopper._check_ground()
	assert_bool(chopper.landed).is_true()
	assert_bool(chopper.dying).is_false()
	assert_int(chopper.vel_y).is_equal(0)

func test_crash_when_horizontal_speed_at_max():
	chopper.airborne = true
	chopper.pos_y = -1.0
	chopper.vel_y = -(6 << 8)
	chopper.vel_x = 0x15 << 8     # |vx_hi| == CRASHSPEED magnitude
	chopper._check_ground()
	assert_bool(chopper.dying).is_true()

func test_launch_requires_threshold():
	chopper.airborne = false
	chopper.landed = true
	chopper.pos_y = 0.0
	chopper.vel_y = 1 << 8        # vy_hi = +1 == LAUNCHTHRESH
	chopper._check_ground()
	assert_bool(chopper.airborne).is_true()

func test_gentle_hover_floors_at_ground_line():
	# Slow approach (vy above MIN_VY): no touchdown latch, but the chopper must hover AT
	# the ground line, never sink below it (source "Keep chopper out of ground",
	# choplifter.s:5299-5301; v0.1 round 3: it parked at -MAX_SINK and 'landed upward').
	chopper.airborne = true
	chopper.pos_y = -3.0
	chopper.vel_y = -(2 << 8)     # gentle sink, NOT enough to register touchdown
	chopper.vel_x = 0
	chopper._check_ground()
	assert_bool(chopper.landed).is_false()
	assert_float(chopper.pos_y).is_equal(0.0)
	# VY is PRESERVED while floored (source clamps position only) — zeroing it here made
	# sideways approaches unlandable once the drift wiped the descent velocity (round 6 fix).
	assert_int(chopper.vel_y).is_equal(-(2 << 8))

func test_sideways_approach_lands_after_release():
	# Round 6 regression gate: arrive at the ground with sideways drift (gate blocked),
	# then center the stick — the preserved descent velocity must still register touchdown.
	chopper.airborne = true
	chopper.pos_y = -1.0
	chopper.vel_y = -(10 << 8)
	chopper.accelx = -5            # drifting: touchdown gate blocked this tick
	chopper._check_ground()
	assert_bool(chopper.landed).is_false()
	chopper.accelx = 0             # stick centered next tick; VY survived the floor
	chopper.pos_y = -0.5
	chopper._check_ground()
	assert_bool(chopper.landed).is_true()

func test_base_landing_sets_landed_at_base():
	chopper.airborne = true
	chopper.over_base = true       # set by Base.area_entered
	chopper.pos_y = -1.0
	chopper.vel_y = -(6 << 8)
	chopper.vel_x = 0
	chopper._check_ground()
	assert_bool(chopper.landed_at_base).is_true()
