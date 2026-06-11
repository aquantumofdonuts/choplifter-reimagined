extends GdUnitTestSuite

func test_alien_accelerates_toward_chopper():
	var alien: Alien = preload("res://src/entities/Alien.tscn").instantiate()
	add_child(alien)
	# In-bounds X (plan's x=100 is outside SRC_BOUNDS_LEFT=720, which triggers the
	# off-world VY damp and would zero the vertical chase).
	alien.position = Vector2(1000, 100)
	alien.vel_x = 0.0; alien.vel_y = 0.0
	alien.chase(Vector2(1100, 150))  # Chopper is right and below
	assert_float(alien.vel_x).is_greater(0.0)  # Moved right
	assert_float(alien.vel_y).is_greater(0.0)  # Moved down (Godot Y)
	alien.queue_free()

func test_alien_vel_capped():
	var alien: Alien = preload("res://src/entities/Alien.tscn").instantiate()
	add_child(alien)
	alien.position = Vector2(1000, 100)   # inside world bounds (off-world zeroes VY)
	alien.vel_x = 100.0; alien.vel_y = 100.0
	alien.chase(Vector2(alien.position.x + 500, alien.position.y))
	assert_float(alien.vel_x).is_less_equal(5.0)
	assert_float(abs(alien.vel_y)).is_less_equal(1.0)
	alien.queue_free()

func test_alien_only_fires_at_level_3_in_mode1():
	GameState.visual_mode = GameState.VisualMode.RETRO
	GameState.curr_level = 2
	var alien: Alien = preload("res://src/entities/Alien.tscn").instantiate()
	add_child(alien)
	assert_bool(alien.can_fire()).is_false()
	GameState.curr_level = 3
	assert_bool(alien.can_fire()).is_true()
	alien.queue_free()
	GameState.reset()

func test_alien_despawns_when_far():
	var alien: Alien = preload("res://src/entities/Alien.tscn").instantiate()
	add_child(alien)
	alien.position = Vector2(0, 100)
	# ~2 view widths = 560 source units
	alien.check_despawn(Vector2(1100, 100))
	assert_bool(alien.is_queued_for_deletion()).is_true()
	alien.queue_free()
