extends GdUnitTestSuite

func test_default_volumes():
	assert_float(Settings.master_volume).is_equal(1.0)
	assert_float(Settings.sfx_volume).is_equal(1.0)
	assert_float(Settings.music_volume).is_equal(0.8)

func test_music_default_off_in_mode1():
	GameState.visual_mode = GameState.VisualMode.RETRO
	assert_bool(Settings.music_enabled).is_false()

func test_save_and_reload():
	Settings.master_volume = 0.5
	Settings.save()
	Settings.master_volume = 1.0  # Overwrite in memory
	Settings.load_settings()      # Reload from user://settings.cfg
	assert_float(Settings.master_volume).is_equal(0.5)

func after_test():
	# Restore defaults so saved cfg doesn't pollute other tests or the next process
	# (GdUnit4 hook is after_test, NOT after_each — the plan's name was never called)
	Settings.master_volume = 1.0
	Settings.save()
