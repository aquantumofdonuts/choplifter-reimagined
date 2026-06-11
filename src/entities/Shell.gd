extends Area2D
class_name Shell

const SPEED: float = 2.0     # source units/frame horizontal

var vel_x: float = 0.0
var vel_y: int = 0           # source convention: +up; gravity decrements each frame

func _ready() -> void:
	add_to_group("projectiles")   # sortie-reset cleanup (Task 33) — R3-M7
	# Hitbox on this Area2D root (layer 5 = enemy_projectiles, mask 2 = chopper).
	area_entered.connect(_on_area_entered)

func launch_at(target_world_pos: Vector2) -> void:
	var dx := target_world_pos.x - position.x
	vel_x = signf(dx) * SPEED
	vel_y = 3                # initial upward V — source shellLaunchVTable is always 3
	                         # (choplifter.s:4560–4565)

func launch_downward() -> void:
	vel_x = 0.0
	vel_y = -3               # straight down (the alien shot reuses the tank-shell entity type)

func _physics_process(_delta: float) -> void:
	vel_y -= 1               # gravity
	position.x += vel_x
	position.y -= float(vel_y)   # +vel_y rises, -vel_y falls (Godot Y down-positive)
	if position.y > 200 or position.x < GameState.SRC_BOUNDS_LEFT - 32 \
	   or position.x > GameState.SRC_BOUNDS_RIGHT + 32:
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	if area.owner is Chopper:
		area.owner.die()
		queue_free()
