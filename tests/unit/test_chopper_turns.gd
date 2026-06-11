extends GdUnitTestSuite

var chopper: Chopper

func before_test():
	chopper = preload("res://src/entities/Chopper.tscn").instantiate()
	add_child(chopper)

func after_test():
	chopper.queue_free()

func test_full_turn_takes_5_frames():
	chopper.turn_state = -5  # Full left
	chopper.target_turn_state = 5  # Full right
	var frames := 0
	while chopper.turn_state != 5 and frames < 10:
		chopper._advance_turn_state()
		frames += 1
	assert_int(frames).is_equal(5)

func test_fast_advance_when_distance_gte_2():
	chopper.turn_state = 0
	chopper.target_turn_state = 5
	chopper._advance_turn_state()
	assert_int(chopper.turn_state).is_equal(2)  # Advances 2 at a time

func test_slow_advance_when_distance_1():
	chopper.turn_state = 4
	chopper.target_turn_state = 5
	chopper._advance_turn_state()
	assert_int(chopper.turn_state).is_equal(5)

func test_logical_face_flips_instantly():
	chopper.logical_face = -1  # facing left
	chopper.face_right()
	assert_int(chopper.logical_face).is_equal(1)
	# turn_state has NOT reached +5 yet (it animates separately)
	assert_bool(chopper.turn_state == 5).is_false()

func test_firing_allowed_during_turn():
	chopper.turn_state = 2  # Mid-turn
	chopper.airborne = true
	chopper.active_bullets = 0
	assert_bool(chopper.can_fire()).is_true()
