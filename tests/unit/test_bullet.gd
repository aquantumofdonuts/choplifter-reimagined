extends GdUnitTestSuite

func test_bullet_gravity_at_turn_state_0():
	# Head-on facing: gravity = -2 (steepest drop)
	var b: Bullet = preload("res://src/entities/Bullet.tscn").instantiate()
	b.init(0, 0, 0)  # turn_state = 0, stick centered, chopper stationary
	assert_int(b.gravity_step).is_equal(-2)
	b.queue_free()

func test_bullet_gravity_at_turn_state_5():
	# Full side: gravity = 0 (flies straight)
	var b: Bullet = preload("res://src/entities/Bullet.tscn").instantiate()
	b.init(5, 0, 0)
	assert_int(b.gravity_step).is_equal(0)
	b.queue_free()

func test_bullet_velocity_full_side_inherits_chopper_speed():
	# bulletVelocityTable row 5, stick 0 = (26, 0); chopper vx 4 → bullet vx 30
	var b: Bullet = preload("res://src/entities/Bullet.tscn").instantiate()
	b.init(5, 0, 4)
	assert_int(b.vel_x).is_equal(30)
	b.queue_free()

func test_bullet_velocity_facing_left_negates_table_vx():
	var b: Bullet = preload("res://src/entities/Bullet.tscn").instantiate()
	b.init(-5, 0, -4)  # full side left, flying left
	assert_int(b.vel_x).is_equal(-30)
	b.queue_free()

func test_5_bullet_cap():
	var chopper: Chopper = preload("res://src/entities/Chopper.tscn").instantiate()
	add_child(chopper)
	chopper.airborne = true
	chopper.active_bullets = 5
	assert_bool(chopper.can_fire()).is_false()
	chopper.queue_free()
