extends GdUnitTestSuite

func before_test():
	GameState.reset()

func _new_hostage(src_x: float) -> Hostage:
	var h: Hostage = preload("res://src/entities/Hostage.tscn").instantiate()
	add_child(h)
	h.position.x = src_x
	return h

func test_hostage_initial_state_is_waving():
	var h := _new_hostage(1000.0)
	assert_int(h.state).is_equal(Hostage.State.WAVING)
	h.queue_free()

func test_hostage_runs_when_landed_chopper_in_range():
	var h := _new_hostage(1000.0)
	var chopper: Chopper = preload("res://src/entities/Chopper.tscn").instantiate()
	add_child(chopper)
	chopper.pos_x = 1040.0          # within detect range, left of hostage
	chopper.landed = true
	chopper.landed_at_base = false
	h.on_chopper_landed(chopper)
	assert_int(h.state).is_equal(Hostage.State.RUNNING)
	h.queue_free(); chopper.queue_free()

func test_board_respects_16_aboard_cap_runs_back_when_full():
	# HF5: chopper full → hostage does NOT board; it turns back toward base.
	GameState.hostages_loaded = 16
	var h := _new_hostage(1000.0)
	h.state = Hostage.State.RUNNING
	var chopper: Chopper = preload("res://src/entities/Chopper.tscn").instantiate()
	add_child(chopper)
	chopper.pos_x = 992.0           # within boarding prox (8 units left)
	h.check_boarding(chopper)
	assert_int(h.state).is_not_equal(Hostage.State.RESCUED)
	assert_int(GameState.hostages_loaded).is_equal(16)   # unchanged
	h.queue_free(); chopper.queue_free()

func test_board_when_space_available():
	GameState.hostages_loaded = 0
	GameState.hostages_active = 1
	var h := _new_hostage(1000.0)
	h.state = Hostage.State.RUNNING
	var chopper: Chopper = preload("res://src/entities/Chopper.tscn").instantiate()
	add_child(chopper)
	chopper.pos_x = 992.0           # 8 units left → in boarding band [8,10)
	h.check_boarding(chopper)
	assert_int(GameState.hostages_loaded).is_equal(1)
	assert_int(chopper.hostages_aboard).is_equal(1)
	h.queue_free(); chopper.queue_free()
