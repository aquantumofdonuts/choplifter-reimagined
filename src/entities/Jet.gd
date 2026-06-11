extends CharacterBody2D
class_name Jet

const SPEED: float = 2.0            # source units/frame
const FIRE_INTERVAL: int = 45       # source ticks between missiles (~3 s at the 15 Hz source tick)
const BOMB_PROXIMITY: float = 150.0  # source units

@export var missile_scene: PackedScene = preload("res://src/entities/Missile.tscn")
@export var bomb_scene: PackedScene = preload("res://src/entities/Bomb.tscn")

var facing: int = 1  # 1 = right, -1 = left
var fire_timer: int = 0
var bank_frame: int = 0  # animation frame for barrel-roll
var _bomb_dropped: bool = false  # one bomb per proximity pass, not one per frame (R3-H6a)

func _ready() -> void:
	add_to_group("enemies")

func _physics_process(_delta: float) -> void:
	position.x += float(facing) * SPEED
	if position.x < GameState.SRC_BOUNDS_LEFT - 64 \
	   or position.x > GameState.SRC_BOUNDS_RIGHT + 64:
		queue_free()
		return
	fire_timer -= 1
	if fire_timer <= 0:
		_fire_missile()
		fire_timer = FIRE_INTERVAL
	_check_bomb_drop()

func _fire_missile() -> void:
	if not missile_scene:
		return
	var m: Missile = missile_scene.instantiate()
	m.position = position
	m.launch(facing)
	get_parent().add_child(m)
	AudioManager.play_sfx("jet_fire")

func _check_bomb_drop() -> void:
	var chopper := get_tree().get_first_node_in_group("chopper") as Chopper
	if not chopper:
		return
	if absf(position.x - chopper.pos_x) < BOMB_PROXIMITY:
		if _bomb_dropped or not bomb_scene:
			return                   # R3-H6a: latch — one bomb per pass
		_bomb_dropped = true
		var b: Bomb = bomb_scene.instantiate()
		b.position = position
		get_parent().add_child(b)
		AudioManager.play_sfx("bomb_drop")
	else:
		_bomb_dropped = false        # re-arm once outside the proximity window

func take_hit() -> void:
	AudioManager.play_sfx("explosion")
	queue_free()
