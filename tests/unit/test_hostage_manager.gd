extends GdUnitTestSuite

func before_test():
	GameState.reset()

func test_field_spawn_draws_from_house_reservoir():
	var mgr: HostageManager = preload("res://src/world/HostageManager.gd").new()
	add_child(mgr)
	mgr.setup(self, _stub_chopper(0.0, false))   # chopper not at base
	# R3 house model: hostages emerge only from IGNITED houses, and the game-start state has
	# house 3 open with 8 already-active fielded hostages (which would block the <5 spawn
	# throttle). Set up a clean single-open-house state for this test.
	GameState.house_states = [1, 0, 0, 0]        # only house 0 ignited/open
	GameState.hostages_in_houses = [16, 16, 16, 16]
	GameState.hostages_left = 64
	GameState.hostages_active = 0
	GameState.field_hostage_records.clear()
	var before := GameState.hostages_left
	mgr.tick(0)                                   # frame 0 passes the &3 cadence gate
	assert_int(GameState.hostages_left).is_equal(before - 1)
	assert_int(GameState.hostages_active).is_equal(1)
	mgr.queue_free()

func test_unload_at_base_increments_rescues_and_level():
	GameState.hostages_loaded = 2
	GameState.chop_loaded = true     # armed by boarding (CHOP_LOADED) — gates the level increment
	GameState.curr_level = 0
	var chopper := _stub_chopper(float(GameState.SRC_BASE_X), true)
	chopper.hostages_aboard = 2
	var mgr: HostageManager = preload("res://src/world/HostageManager.gd").new()
	add_child(mgr)
	mgr.setup(self, chopper)
	mgr.tick(0)                                   # unloads one hostage this cycle
	assert_int(GameState.total_rescues).is_equal(1)
	assert_int(GameState.hostages_loaded).is_equal(1)
	assert_int(GameState.base_runners).is_equal(1)
	assert_int(GameState.curr_level).is_equal(1)  # CURR_LEVEL +1 on first unload of the batch
	mgr.queue_free(); chopper.queue_free()

func _stub_chopper(src_x: float, at_base: bool) -> Chopper:
	var c: Chopper = preload("res://src/entities/Chopper.tscn").instantiate()
	add_child(c)
	c.pos_x = src_x
	c.landed = true
	c.landed_at_base = at_base
	return c
