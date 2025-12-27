# audio_manager.gd
# Autoload singleton for audio-related globals and logic.
# Handles volume variables, bus constants, loading/saving volumes, and applying to AudioServer.
# Access from any script as AudioManager.master_volume, etc.

extends Node

# Audio bus constants: Use these everywhere instead of hard-coded strings.
# This prevents typos and makes renaming buses easy.
const BUS_MASTER: String = "Master"
const BUS_MUSIC: String = "Music"
const BUS_SFX: String = "SFX"
const BUS_SFX_ROTORS: String = "SFX_Rotors"

@export var master_volume: float = 1.0
@export var music_volume: float = 1.0
@export var sfx_volume: float = 1.0
@export var rotors_volume: float = 1.0


func _ready() -> void:
	_load_volumes()  # Load persisted volumes
	_apply_all_volumes()  # Apply to AudioServer buses


# Load volumes from config (shared with other settings)
func _load_volumes() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load("user://settings.cfg")
	if err != OK:
		if err != ERR_FILE_NOT_FOUND:
			Globals.log_message("Failed to load settings config: " + str(err), Globals.LogLevel.ERROR)
		return  # Use defaults if not found or error

	master_volume = config.get_value("audio", "master_volume", master_volume)
	music_volume = config.get_value("audio", "music_volume", music_volume)
	sfx_volume = config.get_value("audio", "sfx_volume", sfx_volume)
	rotors_volume = config.get_value("audio", "rotors_volume", rotors_volume)
	Globals.log_message("Loaded saved master_volume: " + str(master_volume), Globals.LogLevel.DEBUG)
	Globals.log_message("Loaded saved music_volume: " + str(music_volume), Globals.LogLevel.DEBUG)
	Globals.log_message("Loaded saved sfx_volume: " + str(sfx_volume), Globals.LogLevel.DEBUG)
	Globals.log_message("Loaded saved rotors_volume: " + str(rotors_volume), Globals.LogLevel.DEBUG)


# Save volumes to config (shared with other settings)
func _save_volumes() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load("user://settings.cfg")  # Load existing to preserve other sections
	if err != OK and err != ERR_FILE_NOT_FOUND:
		Globals.log_message("Failed to load settings config for save: " + str(err), Globals.LogLevel.ERROR)
		return

	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "rotors_volume", rotors_volume)

	err = config.save("user://settings.cfg")
	if err != OK:
		Globals.log_message("Failed to save audio settings: " + str(err), Globals.LogLevel.ERROR)
	else:
		Globals.log_message("Audio settings saved.", Globals.LogLevel.DEBUG)


# Apply all loaded volumes to AudioServer buses
func _apply_all_volumes() -> void:
	_apply_volume_to_bus(BUS_MASTER, master_volume)
	_apply_volume_to_bus(BUS_MUSIC, music_volume)
	_apply_volume_to_bus(BUS_SFX, sfx_volume)
	_apply_volume_to_bus(BUS_SFX_ROTORS, rotors_volume)


# Helper to apply a single volume to a named bus
func _apply_volume_to_bus(bus_name: String, volume: float) -> void:
	var bus_idx: int = AudioServer.get_bus_index(bus_name)
	if bus_idx != -1:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(volume))
		Globals.log_message(
			"Applied loaded " + bus_name + " volume to AudioServer: " + str(volume), Globals.LogLevel.DEBUG
		)
	else:
		Globals.log_message(bus_name + " audio bus not found!", Globals.LogLevel.ERROR)
