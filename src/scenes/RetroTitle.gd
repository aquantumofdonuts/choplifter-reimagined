extends Control

enum Phase { BRODERBUND = 0, LOGO = 1, MISSION = 2, DEMO = 3 }

# Ordered array used by _advance_phase — avoids invalid .values() call on GDScript 4 enum
const PHASE_ORDER: Array = [Phase.BRODERBUND, Phase.LOGO, Phase.MISSION, Phase.DEMO]

var phase: Phase = Phase.BRODERBUND
var phase_timer: float = 0.0

# Input-skip guard: the click/Enter that pressed Play on MainMenu is often still held
# when this scene loads, and Input.is_anything_pressed() would report it. Arm the skip
# only after a frame where NOTHING is pressed.
var _skip_armed: bool = false

const PHASE_DURATIONS: Dictionary = {
	Phase.BRODERBUND: 2.0,
	Phase.LOGO: 3.0,
	Phase.MISSION: 2.0,
	Phase.DEMO: 10.0,
}
# LF1: durations are APPROXIMATE (not reverse-engineered) — ledger class "Approximation".
# DEVIATION (v0.1): the DEMO phase is a static card that loops back to BRODERBUND after
# ~10 s (attract loop). The recorded-input attract demo (data/demo_input.tres + embedded
# World) is out of scope for v0.1 and lands in v1.0 per the plan.

@onready var _cards: Dictionary = {
	Phase.BRODERBUND: $BroderbundCard,
	Phase.LOGO: $LogoCard,
	Phase.MISSION: $MissionCard,
	Phase.DEMO: $DemoCard,
}

func _ready() -> void:
	_show_card()

func _process(delta: float) -> void:
	# Ignore everything while SceneTransition's fade still owns input — otherwise the
	# arrival fade window lets a held press skip the title instantly.
	if GameState.input_locked:
		return
	if not _skip_armed:
		if not Input.is_anything_pressed():
			_skip_armed = true  # nothing held this frame — real input may now skip
	elif Input.is_anything_pressed():
		# Any real input → go to first sortie (must keep working DURING the demo phase, R3-M6)
		_go_to_sortie()
		return
	phase_timer += delta
	match phase:
		Phase.BRODERBUND:
			if phase_timer >= PHASE_DURATIONS[Phase.BRODERBUND]:
				_advance_phase()
		Phase.LOGO:
			if phase_timer >= PHASE_DURATIONS[Phase.LOGO]:
				_advance_phase()
		Phase.MISSION:
			if phase_timer >= PHASE_DURATIONS[Phase.MISSION]:
				phase = Phase.DEMO
				GameState.demo_mode = true
				phase_timer = 0.0
				_show_card()
		Phase.DEMO:
			if phase_timer >= PHASE_DURATIONS[Phase.DEMO]:
				# v0.1 attract loop: back to the Broderbund card instead of a live demo.
				GameState.demo_mode = false
				phase = Phase.BRODERBUND
				phase_timer = 0.0
				_show_card()

func _advance_phase() -> void:
	var idx := PHASE_ORDER.find(int(phase))
	if idx >= 0 and idx + 1 < PHASE_ORDER.size():
		phase = PHASE_ORDER[idx + 1] as Phase
	phase_timer = 0.0
	_show_card()

func _show_card() -> void:
	for p: int in _cards:
		(_cards[p] as Control).visible = p == int(phase)

func _go_to_sortie() -> void:
	GameState.demo_mode = false
	SceneTransition.transition_to("res://src/scenes/SortieBanner.tscn")
