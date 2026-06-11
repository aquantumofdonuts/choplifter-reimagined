extends Node

const SFX_BASE_PATH: String = "res://assets/audio/sfx/"
const MUSIC_BASE_PATH: String = "res://assets/audio/music/"

var _sfx_players: Dictionary = {}
var _loop_players: Dictionary = {}    # name → AudioStreamPlayer for sustained loops
var _music_calm: AudioStreamPlayer
var _music_tension: AudioStreamPlayer
var _music_action: AudioStreamPlayer
var _current_music_state: String = "calm"
var _audio_unlocked: bool = false     # HTML5/Web: audio starts muted until a user gesture

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # Persist through pause
	_music_calm = _make_music_player("calm")
	_music_tension = _make_music_player("tension")
	_music_action = _make_music_player("action")
	# Web export: browsers suspend the AudioContext until the first user gesture.
	# Keep the master bus muted until we see one, then unmute. Harmless on desktop.
	if OS.has_feature("web"):
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)

func _unhandled_input(event: InputEvent) -> void:
	if _audio_unlocked or not OS.has_feature("web"):
		return
	if event is InputEventKey or event is InputEventMouseButton \
	   or event is InputEventJoypadButton or event is InputEventScreenTouch:
		_audio_unlocked = true
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), false)

func _make_music_player(layer: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = "Music_" + layer
	p.bus = "Music"
	add_child(p)
	return p

func play_sfx(sfx_name: String) -> void:
	var path := SFX_BASE_PATH + sfx_name + ".ogg"
	if not ResourceLoader.exists(path):
		push_warning("AudioManager: SFX not found: " + path)
		return
	if not _sfx_players.has(sfx_name):
		var p := AudioStreamPlayer.new()
		p.name = sfx_name.to_pascal_case()
		p.bus = "SFX"
		p.stream = load(path)
		add_child(p)
		_sfx_players[sfx_name] = p
	var player: AudioStreamPlayer = _sfx_players[sfx_name]
	player.volume_db = linear_to_db(Settings.master_volume * Settings.sfx_volume)
	player.play()

# --- Sustained loops (chopper engine, alien crackle) ---------------------------
# Lifecycle: start_loop on spawn/engine-on, stop_loop on death/despawn/engine-off.
# Idempotent — calling start twice is a no-op; stop on an absent loop is safe.
func start_loop(loop_name: String) -> void:
	if _loop_players.has(loop_name) and _loop_players[loop_name].playing:
		return
	var path := SFX_BASE_PATH + loop_name + ".ogg"
	if not ResourceLoader.exists(path):
		push_warning("AudioManager: loop SFX not found: " + path)
		return
	var p: AudioStreamPlayer
	if _loop_players.has(loop_name):
		p = _loop_players[loop_name]
	else:
		p = AudioStreamPlayer.new()
		p.name = "Loop_" + loop_name.to_pascal_case()
		p.bus = "SFX"
		var stream := load(path)
		if stream is AudioStreamOggVorbis:
			stream.loop = true   # ensure the .ogg actually loops
		p.stream = stream
		add_child(p)
		_loop_players[loop_name] = p
	p.volume_db = linear_to_db(Settings.master_volume * Settings.sfx_volume)
	p.play()

func stop_loop(loop_name: String) -> void:
	if _loop_players.has(loop_name):
		_loop_players[loop_name].stop()

func set_music_state(state: String, biome: String = "desert") -> void:
	if not Settings.music_enabled:
		return
	_current_music_state = state
	# Crossfade logic: fade out non-active layers, fade in active layer
	# Simple version: just play/stop (crossfade added in v0.4)
	for layer_name in ["calm", "tension", "action"]:
		var player: AudioStreamPlayer = get_node("Music_" + layer_name)
		if layer_name == state:
			if not player.playing:
				var path := MUSIC_BASE_PATH + "music_%s_%s.ogg" % [biome, layer_name]
				if ResourceLoader.exists(path):
					player.stream = load(path)
					player.play()
		else:
			player.stop()

func stop_music() -> void:
	for layer_name in ["calm", "tension", "action"]:
		get_node("Music_" + layer_name).stop()
