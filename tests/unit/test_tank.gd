extends GdUnitTestSuite

func test_tank_aims_cannon_at_chopper():
	var tank: Tank = preload("res://src/entities/Tank.tscn").instantiate()
	add_child(tank)
	var chopper_pos := Vector2(300, 150)
	tank.position = Vector2(100, 200)
	tank.aim_cannon(chopper_pos)
	# Cannon angle should point roughly at chopper
	assert_float(tank.cannon_angle).is_not_equal(0.0)
	tank.queue_free()

func test_shell_has_gravity():
	var shell: Shell = preload("res://src/entities/Shell.tscn").instantiate()
	add_child(shell)
	var initial_vy := shell.vel_y
	shell._physics_process(1.0 / 60.0)
	assert_int(shell.vel_y).is_less(initial_vy)  # Falling
	shell.queue_free()

func test_shell_bursts_on_ground():
	# Falling shells stop at the dirt — they must not pass below the ground line.
	var shell: Shell = preload("res://src/entities/Shell.tscn").instantiate()
	add_child(shell)
	shell.position = Vector2(1000, -1)
	shell.vel_y = -1                  # already falling
	shell._physics_process(1.0 / 15.0)
	assert_bool(shell.is_queued_for_deletion()).is_true()
	shell.queue_free()

func test_mode1_spawn_bug_replicated():
	# spawnTankPosV: ENTITY_X_H always 0 when player heading right → X pinned to page 0
	var spawn_manager: SpawnManager = preload("res://src/world/SpawnManager.tscn").instantiate()
	add_child(spawn_manager)
	var x := spawn_manager.spawn_tank_pos_v(4724.0)   # base-side chopper X
	# ENTITY_X_H == 0 → X < 256 (within first page)
	assert_float(x).is_less(256.0)
	spawn_manager.queue_free()
