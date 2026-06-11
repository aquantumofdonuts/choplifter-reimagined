extends GdUnitTestSuite

func test_scroll_lead_left():
	assert_float(World.SCROLL_LEAD_LEFT).is_equal(70.0)   # source units

func test_scroll_lead_right():
	assert_float(World.SCROLL_LEAD_RIGHT).is_equal(210.0)  # source units
