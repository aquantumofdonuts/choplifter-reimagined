extends CanvasLayer
class_name HUD

@onready var rescued_label: Label = $Panel/Rescued
@onready var killed_label: Label = $Panel/Killed
@onready var aboard_label: Label = $Panel/Aboard
@onready var lives_container: HBoxContainer = $Panel/Lives

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # Visible during pause
	refresh()

func _process(_delta: float) -> void:
	refresh()

func refresh() -> void:
	rescued_label.text = "%02d" % GameState.total_rescues
	killed_label.text = "%02d" % GameState.hostages_killed
	aboard_label.text = "%02d" % GameState.hostages_loaded
	_update_lives()

func get_rescued_text() -> String:
	return rescued_label.text

func _update_lives() -> void:
	for i in range(lives_container.get_child_count()):
		var icon := lives_container.get_child(i) as TextureRect
		if icon:
			icon.modulate.a = 1.0 if i < GameState.lives_remaining else 0.3
