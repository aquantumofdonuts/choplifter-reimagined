extends Area2D
class_name Base

func _ready() -> void:
	position.x = float(GameState.SRC_BASE_X)   # source units 1:1
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

func _on_area_entered(area: Area2D) -> void:
	var entity := area.owner
	if entity is Chopper:
		entity.over_base = true

func _on_area_exited(area: Area2D) -> void:
	var entity := area.owner
	if entity is Chopper:
		entity.over_base = false
