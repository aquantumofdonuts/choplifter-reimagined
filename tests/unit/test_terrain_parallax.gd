extends GdUnitTestSuite

func test_mountain_parallax_is_half_speed():
	var terrain: Terrain = preload("res://src/world/Terrain.tscn").instantiate()
	add_child(terrain)
	# Simulate scroll position of 200
	var mountain_x := terrain.compute_mountain_x(200)
	# Source: scrollpos - (scrollpos >> 1), then AND #$FE (clear bit 0)
	var expected := (200 - (200 >> 1)) & ~1  # = 100, bit 0 cleared = 100
	assert_int(int(mountain_x)).is_equal(expected)
	terrain.queue_free()

func test_mountains_appear_at_half_scroll_speed_on_screen():
	# Screen position = world position − camera scroll. The mountains' world position must
	# advance with the camera such that their on-screen drift is ~half the scroll delta.
	var terrain: Terrain = preload("res://src/world/Terrain.tscn").instantiate()
	add_child(terrain)
	terrain.update_scroll(0)
	var screen_a: float = terrain.get_node("Mountains").position.x - 0.0
	terrain.update_scroll(100)
	var screen_b: float = terrain.get_node("Mountains").position.x - 100.0
	# Scrolled +100 (within one pattern period, no wrap); mountains drift ≈ −50 on screen
	# (half speed, AND #$FE quantized).
	assert_float(screen_b - screen_a).is_equal_approx(-50.0, 2.0)
	terrain.queue_free()
