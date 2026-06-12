extends Node

# Dev tool: boots a scene, waits N frames, saves a PNG of the window, quits.
# Lets the agent/CI see actual rendered output (headless runs can't render).
#   SHOT_SCENE=res://src/world/World.tscn SHOT_FRAMES=40 SHOT_PATH=/tmp/shot.png \
#     godot res://src/tools/ScreenshotProbe.tscn

func _ready() -> void:
	var scene_path := OS.get_environment("SHOT_SCENE")
	if scene_path == "":
		scene_path = "res://src/world/World.tscn"
	var frames_env := OS.get_environment("SHOT_FRAMES")
	var frames := int(frames_env) if frames_env != "" else 40
	var out := OS.get_environment("SHOT_PATH")
	if out == "":
		out = "/tmp/shot.png"
	var ps: PackedScene = load(scene_path)
	add_child(ps.instantiate())
	for _i in range(frames):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
