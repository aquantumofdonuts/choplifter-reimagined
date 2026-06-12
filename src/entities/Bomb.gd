extends Area2D
class_name Bomb

# Gravity drop from jet altitude (source units).
var vel_y: int = 0   # source units/frame, accumulates downward each frame

func _ready() -> void:
	add_to_group("projectiles")   # sortie-reset cleanup (Task 33) — R3-M7
	area_entered.connect(_on_area_entered)

func _physics_process(_delta: float) -> void:
	vel_y += 1
	position.y += float(vel_y)   # Godot Y down-positive → falls
	if position.y >= 0.0:        # bombs burst on the dirt (v0.1 round 3)
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	if area.owner is Chopper:
		area.owner.die()
		queue_free()
