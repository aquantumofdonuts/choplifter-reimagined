extends Node

const SETTINGS_PATH: String = "user://settings.cfg"

var master_volume: float = 1.0
var sfx_volume: float = 1.0
var music_volume: float = 0.8
var music_enabled: bool = false  # Off by default in Mode 1; toggled by visual_mode on load
var selected_visual_mode: int = 1
var selected_variant: int = 0
var fuel_enabled: bool = false

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return  # Use defaults on missing or corrupt file
	# settings.cfg is user-writable: every value must be type-checked and range-clamped, or a
	# hand-edited file crashes at boot (typed-assignment error) or later in menu code that
	# indexes by visual_mode (e.g. MainMenu's names[visual_mode - 1]).
	master_volume = _read_float(cfg, "audio", "master_volume", 1.0, 0.0, 1.0)
	sfx_volume = _read_float(cfg, "audio", "sfx_volume", 1.0, 0.0, 1.0)
	music_volume = _read_float(cfg, "audio", "music_volume", 0.8, 0.0, 1.0)
	music_enabled = _read_bool(cfg, "audio", "music_enabled", false)
	selected_visual_mode = _read_int(cfg, "game", "visual_mode", 1, 1, 3)  # GameState.VisualMode range
	selected_variant = _read_int(cfg, "game", "variant", 0, 0, 2)         # GameState.GameplayVariant range
	fuel_enabled = _read_bool(cfg, "game", "fuel_enabled", false)

func _read_int(cfg: ConfigFile, section: String, key: String, default: int, lo: int, hi: int) -> int:
	var v: Variant = cfg.get_value(section, key, default)
	return clampi(v, lo, hi) if v is int else default

func _read_float(cfg: ConfigFile, section: String, key: String, default: float, lo: float, hi: float) -> float:
	var v: Variant = cfg.get_value(section, key, default)
	return clampf(v, lo, hi) if (v is float or v is int) else default

func _read_bool(cfg: ConfigFile, section: String, key: String, default: bool) -> bool:
	var v: Variant = cfg.get_value(section, key, default)
	return v if v is bool else default

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "music_enabled", music_enabled)
	cfg.set_value("game", "visual_mode", selected_visual_mode)
	cfg.set_value("game", "variant", selected_variant)
	cfg.set_value("game", "fuel_enabled", fuel_enabled)
	cfg.save(SETTINGS_PATH)
