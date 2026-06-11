extends CharacterBody2D
class_name Tank

const PATROL_SPEED: float = 0.5         # source units/frame
const PATROL_HALF_WIDTH: float = 320.0  # patrol ±320 source units around spawn
const FIRE_INTERVAL: int = 30           # source ticks between shots (~2 s at the 15 Hz source tick)

var depth_plane: int = 1   # z_index 1-8
var cannon_angle: float = 0.0
var fire_cooldown: int = 0
var _spawn_x: float = 0.0
var _patrol_dir: int = 1

@export var shell_scene: PackedScene = preload("res://src/entities/Shell.tscn")

@onready var _cannon: Sprite2D = $Cannon

func _ready() -> void:
	z_index = depth_plane
	_spawn_x = position.x       # source units
	add_to_group("enemies")

func aim_cannon(chopper_world_pos: Vector2) -> void:
	var d := chopper_world_pos - position
	cannon_angle = rad_to_deg(atan2(-d.y, d.x))

func take_hit() -> void:
	AudioManager.play_sfx("explosion")
	queue_free()

func _physics_process(_delta: float) -> void:
	if position.x >= _spawn_x + PATROL_HALF_WIDTH:
		_patrol_dir = -1
	elif position.x <= _spawn_x - PATROL_HALF_WIDTH:
		_patrol_dir = 1
	position.x += PATROL_SPEED * float(_patrol_dir)
	var chopper := get_tree().get_first_node_in_group("chopper") as Chopper
	if chopper:
		aim_cannon(Vector2(chopper.pos_x, -chopper.pos_y))
		_cannon.rotation_degrees = -cannon_angle
	fire_cooldown -= 1
	if fire_cooldown <= 0:
		_fire_shell(chopper)
		fire_cooldown = FIRE_INTERVAL

func _fire_shell(chopper: Chopper) -> void:
	if not shell_scene or not chopper:
		return
	var shell: Shell = shell_scene.instantiate()
	shell.position = position
	shell.launch_at(Vector2(chopper.pos_x, -chopper.pos_y))
	get_parent().add_child(shell)
	AudioManager.play_sfx("tank_fire")
