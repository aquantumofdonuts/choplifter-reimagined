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
	# AudioManager is PROCESS_MODE_ALWAYS, so pausing the tree alone would leave the
	# sustained loops droning over the pause menu — stop them explicitly (Task 24).
	AudioManager.stop_loop("engine_loop")
	AudioManager.stop_loop("alien_crackle_mid")
	resume_button.grab_focus()

func hide_pause() -> void:
	visible = false
	get_tree().paused = false
	# Restart the engine only if a living (not mid-death) chopper exists. Quit-to-menu
	# also routes through hide_pause(); _on_quit_to_menu_pressed re-stops the loop after
	# this so no engine voice leaks onto MainMenu.
	var chopper := get_tree().get_first_node_in_group("chopper") as Chopper
	if chopper and not chopper.dying:
		AudioManager.start_loop("engine_loop")
	# Crackle resumes only if an alien is still alive (quit-to-menu re-stops loops after this).
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Alien:
			AudioManager.start_loop("alien_crackle_mid")
			break

func _on_resume_pressed() -> void:
	hide_pause()

func _on_quit_to_menu_pressed() -> void:
	if GameState.input_locked:
		return
	hide_pause()
	# hide_pause() just restarted the loops (the chopper/aliens are alive while quitting);
	# kill them again so nothing is left playing on MainMenu (Task 24).
	AudioManager.stop_loop("engine_loop")
	AudioManager.stop_loop("alien_crackle_mid")
	GameState.input_locked = false
	SceneTransition.transition_to("res://src/scenes/MainMenu.tscn")
