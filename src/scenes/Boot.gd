extends Node

func _ready() -> void:
	# The project boots in viewport+integer (pixel) scale mode, but Boot/MainMenu are
	# native-resolution menu scenes (DESIGN.md §11.3). Boot is not in PIXEL_SCENES, so
	# this switches the window to native res before the splash renders.
	SceneTransition.apply_scale_mode_for("res://src/scenes/Boot.tscn")
	# Load settings (already done by Settings autoload _ready)
	GameState.visual_mode = Settings.selected_visual_mode as GameState.VisualMode
	GameState.gameplay_variant = Settings.selected_variant as GameState.GameplayVariant
	await get_tree().create_timer(1.5).timeout  # Boot logo display
	SceneTransition.transition_to("res://src/scenes/MainMenu.tscn")
