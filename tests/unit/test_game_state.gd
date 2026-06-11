extends GdUnitTestSuite

func before_test():
	# GdUnit4 hook is before_test, NOT before_each (plan's name was never called)
	GameState.reset()

func test_initial_values():
	assert_int(GameState.sortie).is_equal(0)
	assert_int(GameState.lives_remaining).is_equal(3)
	assert_int(GameState.curr_level).is_equal(0)
	assert_int(GameState.total_rescues).is_equal(0)
	assert_int(GameState.hostages_killed).is_equal(0)
	assert_int(GameState.hostages_loaded).is_equal(0)
	assert_bool(GameState.input_locked).is_false()
	assert_int(GameState.visual_mode).is_equal(1)

func test_source_coordinate_constants():
	assert_int(GameState.SRC_BOUNDS_RIGHT).is_equal(4864)
	assert_int(GameState.SRC_BASE_X).is_equal(4724)
	assert_float(GameState.src_to_px(280.0)).is_equal_approx(480.0, 0.001)

func test_hostage_universe_initialized():
	# 4 houses × 16 = 64 reservoir; max 16 active; max 16 aboard. Game start (source
	# spawnInitialHostages): house 3 pre-ignited (open) with 8 hostages already fielded.
	assert_int(GameState.NUM_HOUSES).is_equal(4)
	assert_array(GameState.hostages_in_houses).is_equal([16, 16, 16, 8])
	assert_array(GameState.house_states).is_equal([0, 0, 0, 1])  # 0 = closed, 1 = ignited/open
	assert_int(GameState.hostages_left).is_equal(56)
	assert_int(GameState.hostages_active).is_equal(8)
	assert_int(GameState.base_runners).is_equal(0)
	assert_int(GameState.field_hostage_records.size()).is_equal(8)

func test_source_rng_is_deterministic():
	GameState._rnd = 0x42
	GameState._rnd_seed = 0x00
	GameState._rnd_carry = 0
	var first := GameState.random_byte()
	GameState._rnd = 0x42
	GameState._rnd_seed = 0x00
	GameState._rnd_carry = 0
	var repeat := GameState.random_byte()
	assert_int(first).is_equal(repeat)          # same seed → same sequence
	assert_int(first).is_between(0, 255)

func test_win_condition():
	GameState.total_rescues = 64
	assert_bool(GameState.is_victory()).is_true()

func test_loss_condition_all_accounted():
	GameState.total_rescues = 10
	GameState.hostages_killed = 54
	assert_bool(GameState.is_mission_loss()).is_true()

func test_no_loss_when_victory_also_met():
	# Win check runs first — 64 rescues = win even if no kills
	GameState.total_rescues = 64
	GameState.hostages_killed = 0
	assert_bool(GameState.is_victory()).is_true()
	assert_bool(GameState.is_mission_loss()).is_false()
