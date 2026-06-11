extends Control

@onready var play_button: Button = $Panel/VBox/Play
# Settings panel lands in Task 40 — the button ships disabled until then.
@onready var settings_button: Button = $Panel/VBox/Settings
@onready var quit_button: Button = $Panel/VBox/Quit
@onready var mode_label: Label = $Panel/ModeLabel

func _ready() -> void:
	# Hide Quit on web export
	quit_button.visible = OS.get_name() != "Web"
	_update_mode_display()
	play_button.grab_focus()

func _on_play_pressed() -> void:
	GameState.reset()
	if GameState.visual_mode == GameState.VisualMode.RETRO:
		SceneTransition.transition_to("res://src/scenes/RetroTitle.tscn")
	else:
		SceneTransition.transition_to("res://src/scenes/SortieBanner.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _update_mode_display() -> void:
	var names := ["Retro", "Modern", "Hi-Res"]
	mode_label.text = names[GameState.visual_mode - 1]
