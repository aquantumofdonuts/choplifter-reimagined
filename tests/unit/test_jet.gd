extends GdUnitTestSuite

func test_jet_only_spawns_at_level_1_plus():
	GameState.curr_level = 0
	# SpawnManager should not spawn jets at level 0
	var spawn_manager: SpawnManager = preload("res://src/world/SpawnManager.tscn").instantiate()
	add_child(spawn_manager)
	assert_bool(spawn_manager.can_spawn_jet()).is_false()
	GameState.curr_level = 1
	assert_bool(spawn_manager.can_spawn_jet()).is_true()
	spawn_manager.queue_free()
	GameState.reset()

func test_missile_flies_horizontally():
	var missile: Missile = preload("res://src/entities/Missile.tscn").instantiate()
	add_child(missile)
	missile.launch(1)  # Facing right
	var initial_y := missile.position.y
	missile._physics_process(0.5)
	assert_float(missile.position.y).is_equal_approx(initial_y, 1.0)  # Level flight
	missile.queue_free()

func test_bomb_falls_with_gravity():
	var bomb: Bomb = preload("res://src/entities/Bomb.tscn").instantiate()
	add_child(bomb)
	var initial_y := bomb.position.y
	bomb._physics_process(0.5)
	assert_float(bomb.position.y).is_greater(initial_y)  # Falling in Godot
	bomb.queue_free()
