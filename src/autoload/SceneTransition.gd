extends CanvasLayer

@onready var _overlay: ColorRect = $Overlay

const FADE_DURATION: float = 0.3

var _transitioning := false  # re-entrancy guard: first transition wins, late callers are dropped

# Runtime scale-mode switch (DESIGN.md §11.3): the project default is viewport+integer
# (pixel-perfect game world), which renders ALL canvas items at 480×270 — including Control
# UI. Menu scenes therefore run at native resolution instead. This list names the scenes
# that keep the pixel-art viewport scaling; everything else is treated as a menu.
const PIXEL_SCENES: Array[String] = [
	"res://src/world/World.tscn",
	"res://src/scenes/SortieBanner.tscn",
	"res://src/scenes/RetroTitle.tscn",
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_overlay.color = Color.BLACK
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.modulate.a = 0.0
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func transition_to(scene_path: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	GameState.input_locked = true
	await _fade_to(1.0)
	apply_scale_mode_for(scene_path)
	get_tree().change_scene_to_file(scene_path)
	get_tree().paused = false  # scene changes must never strand a paused tree
	await get_tree().process_frame
	await _fade_to(0.0)
	GameState.input_locked = false
	_transitioning = false

# Public so Boot can apply the menu mode at startup without a transition (Task 21).
func apply_scale_mode_for(scene_path: String) -> void:
	var window := get_tree().root
	if scene_path in PIXEL_SCENES:
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	else:
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL

func _fade_to(target_alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_overlay, "modulate:a", target_alpha, FADE_DURATION)
	await tween.finished
