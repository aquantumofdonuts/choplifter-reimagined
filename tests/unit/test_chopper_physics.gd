extends GdUnitTestSuite

# Y target-velocity table from choplifter.s:5266
const ACCEL_Y_TABLE := [-10, -9, -8, -7, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 6]

func _new_chopper() -> Chopper:
	var c: Chopper = preload("res://src/entities/Chopper.tscn").instantiate()
	add_child(c)
	return c

func test_target_table_values():
	assert_int(ACCEL_Y_TABLE[8]).is_equal(-2)   # gravity target
	assert_int(ACCEL_Y_TABLE[15]).is_equal(6)   # full thrust target

func test_chopper_table_matches_source():
	var c := _new_chopper()
	assert_array(c.ACCEL_Y_TABLE).is_equal(ACCEL_Y_TABLE)
	c.queue_free()

func test_y_eases_toward_thrust_target_not_added():
	# From rest, full thrust (target +6): high byte eases 0→3→4→5→6→6 (halve-when-≥2),
	# NOT 0→6→12 (which a naive vel+=accel would produce).
	var c := _new_chopper()
	c.vel_y = 0
	c.accely_index = 15
	var trace := []
	for i in range(5):
		c.integrate_acceleration()
		trace.append(c.vel_y_hi())
	assert_array(trace).is_equal([3, 4, 5, 6, 6])
	c.queue_free()

func test_y_gravity_eases_to_minus_2():
	# From rest, gravity (target -2): high byte eases 0→-1→-2→-2.
	var c := _new_chopper()
	c.vel_y = 0
	c.accely_index = 8
	var trace := []
	for i in range(3):
		c.integrate_acceleration()
		trace.append(c.vel_y_hi())
	assert_array(trace).is_equal([-1, -2, -2])
	c.queue_free()

func test_x_velocity_clamped_to_high_byte_0x15():
	# Hold full right joystick; X high byte must clamp at +0x15 (21), never exceed.
	var c := _new_chopper()
	c.vel_x = 0
	c.accelx = 5  # max joystick-X magnitude (ACCEL_X_TABLE[5])
	for i in range(40):
		c.integrate_acceleration()
	assert_int(c.vel_x_hi()).is_less_equal(0x15)
	assert_int(c.vel_x_hi()).is_greater(0)
	c.queue_free()

func test_ceiling_clamps_altitude_and_zeroes_vy():
	# BOUNDS_TOP $70 minus the $07 ground offset = 105; source zeroes VY on clamp
	# (integrateVelocityClampY, choplifter.s:5613–5621).
	var c := _new_chopper()
	c.pos_y = 104.0
	c.vel_y = 6 << 8
	c.integrate_velocity()
	c._clamp_to_world_bounds()
	assert_float(c.pos_y).is_equal(105.0)
	assert_int(c.vel_y).is_equal(0)
	c.queue_free()

func test_x_friction_decays_velocity_when_centered():
	# With no joystick input (accelx 0, ACCEL_X_TABLE[0]=0), friction VELX -= VELX>>4 decays to 0.
	var c := _new_chopper()
	c.vel_x = 0x1000
	c.accelx = 0
	var before := c.vel_x
	c.integrate_acceleration()
	assert_int(c.vel_x).is_less(before)
	c.queue_free()
