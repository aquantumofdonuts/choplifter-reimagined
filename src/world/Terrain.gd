extends Node2D
class_name Terrain

# Source renderMountains (choplifter.s:6634-6707): the mountains are NOT a continuous tiled
# strip — THREE ridge instances are drawn per frame, spaced one source page (256 units) apart
# on a HALF-SPEED parallax layer, each picking one of four patterns from its scaled position.
# Tiling them edge-to-edge (the first implementation) produced a continuous "noise band".
const MOUNTAIN_SPACING: float = 256.0
const MOUNTAIN_PATTERNS: Array[Texture2D] = [
	preload("res://assets/graphics/mode1/mountain/pattern_0.png"),
	preload("res://assets/graphics/mode1/mountain/pattern_1.png"),
	preload("res://assets/graphics/mode1/mountain/pattern_2.png"),
	preload("res://assets/graphics/mode1/mountain/pattern_3.png"),
]

@onready var mountains_layer: Node2D = $Mountains
@onready var ground_rect: ColorRect = $Ground  # flat ground strip below the y=0 line

func compute_mountain_x(scroll_pos: int) -> int:
	# Source: renderMountains — SCROLLPOS - (SCROLLPOS >> 1) AND #$FE
	return (scroll_pos - (scroll_pos >> 1)) & ~1

func update_scroll(scroll_pos: int) -> void:
	# Screen position = world − camera: placing the layer at scroll − compute makes the
	# ridges drift at half the scroll speed on screen (background parallax).
	var offset := float(scroll_pos) - float(compute_mountain_x(scroll_pos))
	mountains_layer.position.x = offset
	# Position the 3 ridge instances on the 256-unit grid of the half-speed layer so the
	# visible window is always covered; pattern choice keys off the grid index (the source
	# derives it from the scaled position — varied but deterministic, same idea).
	var first_k := int(floor((float(scroll_pos) - offset) / MOUNTAIN_SPACING))
	for i in range(mountains_layer.get_child_count()):
		var k := first_k + i
		var spr := mountains_layer.get_child(i) as Sprite2D
		spr.position.x = float(k) * MOUNTAIN_SPACING
		spr.texture = MOUNTAIN_PATTERNS[k & 3]
