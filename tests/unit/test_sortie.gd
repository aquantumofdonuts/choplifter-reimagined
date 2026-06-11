extends GdUnitTestSuite

func test_death_counts_aboard_as_killed():
	GameState.reset()
	var chopper: Chopper = preload("res://src/entities/Chopper.tscn").instantiate()
	add_child(chopper)
	chopper.hostages_aboard = 3
	GameState.on_chopper_death(3)
	assert_int(GameState.hostages_killed).is_equal(3)
	assert_int(GameState.lives_remaining).is_equal(2)
	chopper.queue_free()
	GameState.reset()

func test_loss_when_sorties_exhausted():
	GameState.lives_remaining = 0
	assert_bool(GameState.is_sorties_loss()).is_true()
	GameState.reset()

func test_win_at_64_rescues():
	GameState.total_rescues = 64
	assert_bool(GameState.is_victory()).is_true()
	GameState.reset()
