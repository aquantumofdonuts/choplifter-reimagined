extends Area2D
class_name Base

# Visual anchor for the base. landed_at_base is computed by the chopper from the source's
# pad X-window (BASE_X+$0D..$3F, handleGround, choplifter.s:5795-5808) — no area signal needed.

func _ready() -> void:
	position.x = float(GameState.SRC_BASE_X)   # source units 1:1
