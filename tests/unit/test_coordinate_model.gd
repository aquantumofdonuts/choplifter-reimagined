extends GdUnitTestSuite

# Task 3c: source-unit coordinate model. Mode 1 simulates in raw source units;
# the only source→pixel scale is the World Camera2D zoom (SRC_TO_PX).

func test_source_bounds():
	assert_int(GameState.SRC_BOUNDS_LEFT).is_equal(720)    # $02D0
	assert_int(GameState.SRC_BOUNDS_RIGHT).is_equal(4864)  # $1300
	assert_int(GameState.SRC_BASE_X).is_equal(4724)        # $1274
	assert_int(GameState.SRC_FARHOUSE_X).is_equal(896)     # $0380

func test_camera_scroll_clamps():
	assert_int(GameState.SRC_SCROLL_END_X).is_equal(688)     # $02B0
	assert_int(GameState.SRC_SCROLL_START_X).is_equal(4616)  # $1208

func test_src_to_px_scale():
	# One source viewport width (280 units) spans the full 480px screen width.
	assert_float(GameState.src_to_px(280.0)).is_equal_approx(480.0, 0.001)
