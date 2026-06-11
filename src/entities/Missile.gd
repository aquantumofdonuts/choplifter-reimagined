extends Area2D
class_name Missile

# Constant horizontal velocity, level flight (source units).
const SPEED: float = 3.0   # source units/frame

var dir: int = 1

func _ready() -> void:
	add_to_group("projectiles")   # sortie-reset cleanup (Task 33) — R3-M7
	# layer 5 = enemy_projectiles, mask 2 = chopper
	area_entered.connect(_on_area_entered)

func launch(d: int) -> void:
	dir = d

func _physics_process(_delta: float) -> void:
	position.x += float(dir) * SPEED
	if position.x < GameState.SRC_BOUNDS_LEFT - 64 \
	   or position.x > GameState.SRC_BOUNDS_RIGHT + 64:
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	if area.owner is Chopper:
		area.owner.die()
		queue_free()
