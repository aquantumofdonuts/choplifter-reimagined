extends Control

@onready var label: Label = $Label

func _ready() -> void:
	label.text = "Sortie %d\nRescued: %d  Killed: %d" % [
		GameState.sortie + 1, GameState.total_rescues, GameState.hostages_killed
	]
	await get_tree().create_timer(2.0).timeout
	SceneTransition.transition_to("res://src/world/World.tscn")
