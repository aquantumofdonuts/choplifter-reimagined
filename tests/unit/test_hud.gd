extends GdUnitTestSuite

func test_hud_updates_on_rescue():
	var hud: HUD = preload("res://src/ui/HUD.tscn").instantiate()
	add_child(hud)
	GameState.total_rescues = 5
	hud.refresh()
	assert_str(hud.get_rescued_text()).is_equal("05")
	hud.queue_free()
	GameState.reset()
