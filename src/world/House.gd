extends Node2D
class_name House

# Houses do NOT own hostage counts — GameState does (HF2). A house is a view + an ignition flag
# bound to its index in GameState.hostages_in_houses / GameState.house_states.
#
# R3 house-model fix (the earlier draft had this inverted): source polarity is 0 = untouched/
# CLOSED, 1 = on fire/OPEN ($7311, choplifter.s:5097). Igniting a house RELEASES its occupants —
# they emerge over time via the spawn tick — it does NOT kill them (igniteHouse,
# choplifter.s:8985–8998). The player opens houses by shooting them; house 3 starts open.
@export var house_index: int = 0

const TEX_CLOSED: Texture2D = preload("res://assets/graphics/mode1/house/normal.png")
const TEX_OPEN: Texture2D = preload("res://assets/graphics/mode1/house/on_fire.png")

@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	position.x = float(GameState.HOUSE_SRC_X[house_index])
	_refresh_sprite()

func _process(_delta: float) -> void:
	_refresh_sprite()

func _refresh_sprite() -> void:
	_sprite.texture = TEX_OPEN if is_open() else TEX_CLOSED

func is_open() -> bool:
	return GameState.house_states[house_index] == 1

func ignite() -> void:
	# Idempotent — the source returns early if the house is already burning.
	GameState.house_states[house_index] = 1
