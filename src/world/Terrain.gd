extends Node2D
class_name Terrain

# The 4 mountain patterns tile with this period (48+36+54+56 source units).
# The source renders the pattern modulo its table length; wrapping by the period keeps the
# repeating ridge covering the viewport with a fixed, small set of sprites.
const MOUNTAIN_PERIOD: int = 194

@onready var mountains_layer: Node2D = $Mountains
@onready var ground_rect: ColorRect = $Ground  # flat ground strip below the y=0 line

func compute_mountain_x(scroll_pos: int) -> int:
	# Source: renderMountains — SCROLLPOS - (SCROLLPOS >> 1) AND #$FE
	return (scroll_pos - (scroll_pos >> 1)) & ~1

func update_scroll(scroll_pos: int) -> void:
	# Screen position = world − camera, so placing the layer at
	# scroll − (compute % period) makes the ridge drift at half the scroll speed on screen.
	# (The plan's −compute form would move mountains FASTER than the ground — foreground.)
	mountains_layer.position.x = float(scroll_pos) - float(compute_mountain_x(scroll_pos) % MOUNTAIN_PERIOD)
