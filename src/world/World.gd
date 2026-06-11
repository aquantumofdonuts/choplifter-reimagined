extends Node2D
class_name World

const SCROLL_LEAD_LEFT: float = 70.0    # source units (original 70px / 280-unit viewport)
const SCROLL_LEAD_RIGHT: float = 210.0  # source units (original 210px / 280-unit viewport)

const SRC_VIEW_HEIGHT: float = 270.0 / (480.0 / 280.0)  # 157.5 source units visible vertically
const GROUND_MARGIN_SRC: float = 24.0  # source units of terrain visible BELOW the ground line (tune by eye)

signal victory_achieved  # emitted by HostageManager when TOTAL_HOSTAGES are rescued

@onready var camera: Camera2D = $Camera2D
@onready var chopper: Chopper = $Chopper
@onready var spawn_manager: SpawnManager = $SpawnManager
@onready var hostage_manager: HostageManager = $HostageManager
@onready var terrain: Terrain = $Terrain
@onready var hud: CanvasLayer = $HUD

var _frame_count: int = 0  # global frame counter (replicates FRAME_COUNT)

func _ready() -> void:
	# The ONLY source→pixel scaling in the game: zoom maps source units to screen pixels.
	camera.zoom = Vector2(GameState.SRC_TO_PX, GameState.SRC_TO_PX)
	camera.position_smoothing_enabled = false  # we drive the camera manually
	# Top-left anchoring so camera.position == viewport top-left in source-unit world space,
	# keeping the scroll-lead formulas (source-unit offsets) correct as written.
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	chopper.chopper_died.connect(_on_chopper_died)
	victory_achieved.connect(_start_victory)
	hostage_manager.setup(self, chopper)
	hostage_manager.restore_field_hostages()  # R3-C3: re-instantiate survivors from the prior sortie

func _physics_process(_delta: float) -> void:
	_frame_count = (_frame_count + 1) & 0xFF  # 8-bit wrap (matches source FRAME_COUNT)
	_update_camera()
	spawn_manager.tick(_frame_count)
	hostage_manager.tick(_frame_count)

func _update_camera() -> void:
	# Work entirely in source units; the camera zoom handles the render scale.
	var view := float(GameState.SRC_VIEW_WIDTH)  # 280 source units
	var target_x: float
	if chopper.logical_face >= 0:  # facing right
		target_x = chopper.pos_x - SCROLL_LEAD_RIGHT
	else:
		target_x = chopper.pos_x - (view - SCROLL_LEAD_LEFT)
	# R3-M1: clamp to the source scroll limits SCROLL_END/SCROLL_START ($02B0–$1208,
	# choplifter.s:4768–4775) — the viewport may show up to 32 units beyond the world bounds.
	target_x = clampf(target_x,
		float(GameState.SRC_SCROLL_END_X), float(GameState.SRC_SCROLL_START_X))
	camera.position.x = target_x
	# R3-C2: vertical framing. Gameplay renders at y ≤ 0 (altitude is up-positive, negated once at
	# render), so the camera's top-left must sit ABOVE the ground line: the visible band is
	# [-(SRC_VIEW_HEIGHT - GROUND_MARGIN_SRC), +GROUND_MARGIN_SRC] — sky above, a strip of terrain
	# below. With y = 0 the camera would show only the underground half-plane.
	camera.position.y = -(SRC_VIEW_HEIGHT - GROUND_MARGIN_SRC)
	terrain.update_scroll(int(target_x))  # parallax mountains track the scroll (Task 12 wiring)

func _on_chopper_died() -> void:
	# Task 19 implements the sortie reset / loss flow.
	pass

func _start_victory() -> void:
	# Task 19 implements the victory flow.
	pass
