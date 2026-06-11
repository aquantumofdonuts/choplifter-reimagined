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

func test_base_landing_sets_landed_at_base():
	chopper.airborne = true
	chopper.over_base = true       # set by Base.area_entered
	chopper.pos_y = -1.0
	chopper.vel_y = -(6 << 8)
	chopper.vel_x = 0
	chopper._check_ground()
	assert_bool(chopper.landed_at_base).is_true()
