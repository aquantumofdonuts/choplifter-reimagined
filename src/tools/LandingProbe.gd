extends Node

# Dev repro tool: boots the real World, scripts a landing approach at house 0 through the
# REAL Input layer, and logs chopper/hostage state every physics tick.
#   godot --headless res://src/tools/LandingProbe.tscn

var world: Node2D
var tick := 0

func _ready() -> void:
	GameState.reset()
	world = preload("res://src/world/World.tscn").instantiate()
	add_child(world)
	var c: Chopper = world.get_node("Chopper")
	# Start airborne above house 0, slightly left of the emerge point.
	c.pos_x = float(GameState.HOUSE_SRC_X[0])
	c.pos_y = 40.0
	c.airborne = true
	GameState.house_states = [1, 0, 0, 0]
	GameState.hostages_in_houses = [16, 16, 16, 16]
	GameState.hostages_left = 64
	GameState.hostages_active = 0
	GameState.field_hostage_records.clear()
	for h in get_tree().get_nodes_in_group("hostages"):
		h.free()

func _physics_process(_d: float) -> void:
	tick += 1
	# Scripted input mimicking a player's sideways landing approach: fly left while
	# descending, release BOTH at ground contact (the common human pattern).
	if tick == 1:
		Input.action_press("descend")
		Input.action_press("move_left")
	elif tick == 8:
		Input.action_release("descend")
		Input.action_release("move_left")
	var c: Chopper = world.get_node("Chopper")
	var nearest := ""
	var best := 99999.0
	for h in get_tree().get_nodes_in_group("hostages"):
		var dx: float = absf(h.position.x - c.pos_x)
		if dx < best:
			best = dx
			nearest = "%s dx=%.0f" % [Hostage.State.keys()[h.state], dx]
	if tick % 5 == 0 or tick < 12:
		print("t=%3d ay=%2d ax=%2d posY=%5.1f vyH=%3d air=%s land=%s aboard=%d active=%d %s" % [
			tick, c.accely_index, c.accelx, c.pos_y, c.vel_y_hi(),
			str(c.airborne), str(c.landed), c.hostages_aboard, GameState.hostages_active, nearest])
	if tick >= 220:
		get_tree().quit()
