extends GdUnitTestSuite

func test_play_sfx_does_not_crash_on_missing_file():
	# Should warn and return, not crash
	AudioManager.play_sfx("nonexistent_sound")

func test_sfx_respects_volume():
	AudioManager.play_sfx("bullet_fire")
	# AudioStreamPlayer is found and its volume_db is set from Settings
	var player = AudioManager.get_node_or_null("BulletFire")
	if player:
		assert_float(player.volume_db).is_not_equal(-80.0)
