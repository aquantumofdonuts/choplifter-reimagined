extends GdUnitTestSuite

# The source landing rule (handleGround, choplifter.s:5747-5905): touching the ground +
# |VX| under CRASHSPEED + X stick centered = LANDED. No minimum descent velocity.
# landed_at_base = pad X window BASE_X+$0D..$3F.

var chopper: Chopper

func before_test():
	GameState.reset()
	chopper = preload("res://src/entities/Chopper.tscn").instantiate()
	add_child(chopper)

func after_test():
	chopper.queue_free()

func test_ground_contact_with_centered_stick_lands():
	chopper.airborne = true
	chopper.pos_y = -1.0          # touching the ground line
	chopper.vel_y = -(2 << 8)     # ANY descent speed — no MIN_VY gate in the source
	chopper.vel_x = 0
	chopper.accelx = 0
	chopper._handle_ground()
	assert_bool(chopper.landed).is_true()
	assert_bool(chopper.airborne).is_false()
	assert_bool(chopper.dying).is_false()

func test_angled_contact_does_not_land_until_stick_centers():
	# handleGroundZeroVX: stick deflected = "touched down but not landed" — the moment the
	# stick centers, landed latches. (The v0.1 'press down again' saga ended here.)
	chopper.airborne = true
	chopper.pos_y = -1.0
	chopper.vel_x = 0
	chopper.accelx = -5
	chopper._handle_ground()
	assert_bool(chopper.airborne).is_false()
	assert_bool(chopper.landed).is_false()
	chopper.accelx = 0
	chopper._handle_ground()
	assert_bool(chopper.landed).is_true()

func test_crash_on_contact_at_excess_horizontal_speed():
	chopper.airborne = true
	chopper.pos_y = -1.0
	chopper.vel_x = 0x15 << 8     # |vx_hi| == CRASHSPEED magnitude
	chopper._handle_ground()
	assert_bool(chopper.dying).is_true()

func test_launch_requires_threshold():
	chopper.airborne = false
	chopper.landed = true
	chopper.pos_y = 0.0
	chopper.vel_y = 1 << 8        # vy_hi = +1 == LAUNCHTHRESH → position integrates upward
	chopper._grounded_physics()
	chopper._handle_ground()
	assert_bool(chopper.airborne).is_true()

func test_no_launch_below_threshold():
	chopper.airborne = false
	chopper.landed = true
	chopper.pos_y = 0.0
	chopper.vel_y = 0
	chopper.accelx = 0
	chopper._grounded_physics()
	chopper._handle_ground()
	assert_bool(chopper.airborne).is_false()
	assert_float(chopper.pos_y).is_equal(0.0)

func test_base_pad_is_the_source_x_window():
	chopper.airborne = true
	chopper.pos_y = -1.0
	chopper.vel_x = 0
	chopper.accelx = 0
	chopper.pos_x = float(GameState.SRC_BASE_X + 0x20)   # inside $0D..$3F
	chopper._handle_ground()
	assert_bool(chopper.landed_at_base).is_true()
	chopper.pos_x = float(GameState.SRC_BASE_X)          # AT the label = outside the window
	chopper._handle_ground()
	assert_bool(chopper.landed_at_base).is_false()
