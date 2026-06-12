extends GdUnitTestSuite

# Deviation (documented): reset GameState before each test so a stale input_locked left behind
# by another suite can't silently freeze _physics_process and fail these gates flakily.
func before_test() -> void:
	GameState.reset()

# Release held actions even if a test body aborts on a runtime error, so a held action
# can't leak into the next test.
func after_test() -> void:
	Input.action_release("thrust_up")
	Input.action_release("descend")

func test_thrust_trace_through_physics_process() -> void:
	var chopper := preload("res://src/entities/Chopper.tscn").instantiate()
	add_child(chopper)
	chopper.pos_y = 20.0    # airborne, but low enough that 5 thrust frames (+24 units) stay
	                        # under the source ceiling clamp at 105, which zeroes VY
	chopper.airborne = true
	chopper.vel_y = 0

	Input.action_press("thrust_up")   # simulate holding thrust through the real input path
	var trace := []
	for _i in range(5):
		chopper._physics_process(1.0 / 60.0)
		trace.append(chopper.vel_y_hi())
	Input.action_release("thrust_up")
	assert_array(trace).is_equal([3, 4, 5, 6, 6])
	chopper.queue_free()

func test_gravity_trace_through_physics_process() -> void:
	var chopper := preload("res://src/entities/Chopper.tscn").instantiate()
	add_child(chopper)
	chopper.pos_y = 100.0
	chopper.airborne = true
	chopper.vel_y = 0

	var trace := []   # no thrust held → gravity ease-down
	for _i in range(3):
		chopper._physics_process(1.0 / 60.0)
		trace.append(chopper.vel_y_hi())
	assert_array(trace).is_equal([-1, -2, -2])
	chopper.queue_free()

func test_descend_and_land_via_input_path() -> void:
	# Third DoD gate (R3-C1 / R3-H8): the chopper must be able to LAND using only real input
	# actions — the other two gates bypass the input layer and stay green even when no control
	# path can reach MIN_VY. Descend (index 0, target −10) passes vy_hi ≤ −5 on the first frame (the ease step from 0 toward −10 is −5 immediately).
	var chopper := preload("res://src/entities/Chopper.tscn").instantiate()
	add_child(chopper)
	chopper.pos_y = 40.0
	chopper.airborne = true
	chopper.vel_x = 0
	chopper.vel_y = 0

	Input.action_press("descend")
	for _i in range(120):
		chopper._physics_process(1.0 / 60.0)
		if chopper.landed:
			break
	Input.action_release("descend")
	assert_bool(chopper.landed).is_true()
	chopper.queue_free()
