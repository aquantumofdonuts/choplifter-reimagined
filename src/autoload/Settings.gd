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
	master_volume = cfg.get_value("audio", "master_volume", 1.0)
	sfx_volume = cfg.get_value("audio", "sfx_volume", 1.0)
	music_volume = cfg.get_value("audio", "music_volume", 0.8)
	music_enabled = cfg.get_value("audio", "music_enabled", false)
	selected_visual_mode = cfg.get_value("game", "visual_mode", 1)
	selected_variant = cfg.get_value("game", "variant", 0)
	fuel_enabled = cfg.get_value("game", "fuel_enabled", false)

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
