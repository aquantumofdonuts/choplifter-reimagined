extends GdUnitTestSuite

# Cleanup runs even if the test body aborts on a runtime error: the world node is auto_free'd
# by GdUnit and GameState is reset here, so a mid-test failure can't poison other suites.
func after_test() -> void:
	GameState.reset()

# Boots the actual World scene and runs the full house→run→board→deliver→rescue loop.
func test_full_rescue_increments_total_rescues() -> void:
	GameState.reset()
	var world: World = auto_free(preload("res://src/world/World.tscn").instantiate())
	add_child(world)

	# Deviation (documented): disable enemy spawns for this gate. SpawnManager runs on the REAL
	# frame loop and would spawn a tank within ±0xB0 of the landed chopper; Shell._on_area_entered
	# calls chopper.die() on contact, which fires World._on_chopper_died → SceneTransition mid-test
	# and torpedoes the whole suite. The gate is about the RESCUE loop, not enemies — enemy combat
	# has its own unit suites (test_tank, test_jet, test_alien).
	world.spawn_manager.tank_scene = null
	world.spawn_manager.jet_scene = null
	world.spawn_manager.alien_scene = null

	await get_tree().physics_frame

	var gs := GameState
	var start_rescues := gs.total_rescues

	# R3 house model: open only house 0 and drop the game-start house-3 squad so every spawn
	# lands within the chopper's detect range — keeps the test deterministic instead of relying
	# on the RNG to pick house 0 before the active cap fills. (1 = ignited/open, 0 = closed.)
	# NOTE: GameState.reset() seeded 8 field records at house 3 which World._ready() already
	# instantiated as nodes; clearing field_hostage_records does NOT remove them. There is no
	# detect radius (R3 model), so they ARE nudged to run toward the landed chopper from any
	# distance and at 2 units/frame they COULD cross the ~770 source units to house 0 well
	# inside the 1200-frame budget. What protects this gate is the provenance assert below on
	# house 0's reservoir (16 → 15): it proves the boarded hostage came through the house-spawn
	# pipeline (_spawn_field_hostage/_choose_house), not from a leftover house-3 walker. The
	# base leg is safe by distance alone: ≥3008 source units exceeds 1200 frames × 2 units.
	gs.house_states = [1, 0, 0, 0]
	gs.hostages_in_houses = [16, 16, 16, 16]
	gs.hostages_left = 64
	gs.hostages_active = 0
	gs.field_hostage_records.clear()

	# 1) Land the chopper at a field house so a hostage spawns and runs to it.
	world.chopper.pos_x = float(gs.HOUSE_SRC_X[0])
	world.chopper.pos_y = 0.0
	world.chopper.vel_x = 0
	world.chopper.vel_y = 0
	world.chopper.over_base = false   # field landing, not the base

	# Pump frames until a hostage spawns from the house, runs over, and boards.
	var boarded := false
	for _i in range(1200):  # ≤20 s @60Hz
		await get_tree().physics_frame
		if world.chopper.hostages_aboard >= 1:
			boarded = true
			break
	assert_bool(boarded).is_true()
	# Provenance: the boarded hostage must have been drawn from house 0's reservoir (16 → 15),
	# not a restored house-3 walker — guards against a broken house-spawn pipeline going green.
	assert_int(gs.hostages_in_houses[0]).is_equal(15)

	# 2) Fly to the base and land; the HostageManager must unload via a base-runner.
	world.chopper.pos_x = float(gs.SRC_BASE_X)
	world.chopper.pos_y = 0.0
	world.chopper.vel_x = 0
	world.chopper.vel_y = 0
	world.chopper.over_base = true

	var delivered := false
	for _i in range(1200):
		await get_tree().physics_frame
		if gs.total_rescues > start_rescues:
			delivered = true
			break
	assert_bool(delivered).is_true()
