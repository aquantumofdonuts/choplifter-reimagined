extends CanvasLayer
class_name PauseMenu

@onready var resume_button: Button = $Panel/VBox/Resume
@onready var quit_button: Button = $Panel/VBox/QuitToMenu

func _ready() -> void:
	layer = 50  # Above HUD (default layer 1), below SceneTransition (layer 100)
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	# World is PAUSABLE, so its _unhandled_input is suspended while the tree is paused —
	# the un-pause half of the toggle must live here (PROCESS_MODE_ALWAYS). Children get
	# unhandled input before the scene root, so marking the event handled also stops
	# World from re-opening the menu in the same press.
	if visible and event.is_action_pressed("pause"):
		if GameState.input_locked:
			return
		hide_pause()
		get_viewport().set_input_as_handled()

func show_pause() -> void:
	visible = true
	get_tree().paused = true
	resume_button.grab_focus()

func hide_pause() -> void:
	visible = false
	get_tree().paused = false

func _on_resume_pressed() -> void:
	hide_pause()

func _on_quit_to_menu_pressed() -> void:
	if GameState.input_locked:
		return
	hide_pause()
	GameState.input_locked = false
	SceneTransition.transition_to("res://src/scenes/MainMenu.tscn")
