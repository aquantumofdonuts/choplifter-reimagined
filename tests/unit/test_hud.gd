extends GdUnitTestSuite

func test_hud_updates_on_rescue():
	var hud: HUD = preload("res://src/ui/HUD.tscn").instantiate()
	add_child(hud)
	GameState.total_rescues = 5
	hud.refresh()
	assert_str(hud.get_rescued_text()).is_equal("05")
	hud.queue_free()
	GameState.reset()

func test_hud_dims_spent_lives():
	var hud: HUD = preload("res://src/ui/HUD.tscn").instantiate()
	add_child(hud)
	GameState.lives_remaining = 1
	hud.refresh()
	var lives: HBoxContainer = hud.get_node("Panel/Lives")
	var first := lives.get_child(0) as TextureRect
	var second := lives.get_child(1) as TextureRect
	var third := lives.get_child(2) as TextureRect
	assert_float(first.modulate.a).is_equal_approx(1.0, 0.001)
	assert_float(second.modulate.a).is_equal_approx(0.3, 0.001)
	assert_float(third.modulate.a).is_equal_approx(0.3, 0.001)
	hud.queue_free()
	GameState.reset()
