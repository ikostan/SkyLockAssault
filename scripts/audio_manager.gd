## audio_manager.gd
## Autoload singleton for audio-related globals and logic.
## Handles volume variables, bus constants, loading/saving volumes, and applying to AudioServer.
## Access from any script as AudioManager.master_volume, etc.

extends Node

@export_category("Master Volume")
@export var master_volume: float = 1.0
@export var master_muted: bool = false

@export_category("Music Volume")
@export var music_volume: float = 1.0
@export var music_muted: bool

@export_category("SFX Volume")
@export var sfx_volume: float = 1.0
@export var sfx_muted: bool
@export var weapon_volume: float = 1.0
@export var weapon_muted: bool
@export var rotors_volume: float = 1.0
@export var rotors_muted: bool


func _ready() -> void:
	load_volumes()  # Load persisted volumes
	apply_all_volumes()  # Apply to AudioServer buses


## Load volumes from config (shared with other settings)
## :param path: Path to config file.
## :type path: String
## :rtype: void
func load_volumes(path: String = Settings.CONFIG_PATH) -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(path)
	if err != OK:
		if err != ERR_FILE_NOT_FOUND:
			Globals.log_message(
				"Failed to load settings config: " + str(err), Globals.LogLevel.ERROR
			)
		return  # Use defaults if not found or error
	# Master Volume
	master_volume = config.get_value("audio", "master_volume", master_volume)
	master_muted = config.get_value("audio", "master_muted", master_muted)
	Globals.log_message("Loaded saved master_volume: " + str(master_volume), Globals.LogLevel.DEBUG)
	Globals.log_message("Loaded saved master_muted: " + str(master_muted), Globals.LogLevel.DEBUG)
	# Music Volume
	music_volume = config.get_value("audio", "music_volume", music_volume)
	Globals.log_message("Loaded saved music_volume: " + str(music_volume), Globals.LogLevel.DEBUG)
	# SFX
	sfx_volume = config.get_value("audio", "sfx_volume", sfx_volume)
	rotors_volume = config.get_value("audio", "rotors_volume", rotors_volume)
	weapon_volume = config.get_value("audio", "weapon_volume", weapon_volume)
	Globals.log_message("Loaded saved sfx_volume: " + str(sfx_volume), Globals.LogLevel.DEBUG)
	Globals.log_message("Loaded saved rotors_volume: " + str(rotors_volume), Globals.LogLevel.DEBUG)
	Globals.log_message("Loaded saved weapon_volume: " + str(weapon_volume), Globals.LogLevel.DEBUG)


## Save volumes to config (shared with other settings)
## :param path: Path to config file.
## :type path: String
## :rtype: void
func save_volumes(path: String = Settings.CONFIG_PATH) -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(path)  # Load existing to preserve other sections
	if err != OK and err != ERR_FILE_NOT_FOUND:
		Globals.log_message(
			"Failed to load settings config for save: " + str(err), Globals.LogLevel.ERROR
		)
		return

	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "master_muted", master_muted)
	
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "rotors_volume", rotors_volume)
	config.set_value("audio", "weapon_volume", weapon_volume)

	err = config.save(path)
	if err != OK:
		Globals.log_message("Failed to save audio settings: " + str(err), Globals.LogLevel.ERROR)
	else:
		Globals.log_message("Audio settings saved.", Globals.LogLevel.DEBUG)


## Apply all loaded volumes to AudioServer buses
## :rtype: void
func apply_all_volumes() -> void:
	apply_volume_to_bus(AudioConstants.BUS_MASTER, master_volume, master_muted)
	apply_volume_to_bus(AudioConstants.BUS_MUSIC, music_volume)
	apply_volume_to_bus(AudioConstants.BUS_SFX, sfx_volume)
	apply_volume_to_bus(AudioConstants.BUS_SFX_ROTORS, rotors_volume)
	apply_volume_to_bus(AudioConstants.BUS_SFX_WEAPON, weapon_volume)


## Helper to apply a single volume to a named bus
## :param bus_name: Name of the bus.
## :type bus_name: String
## :param volume: Volume level (0.0 to 1.0).
## :type volume: float
## :rtype: void
func apply_volume_to_bus(bus_name: String, volume: float, muted: bool = false) -> void:
	var bus_idx: int = AudioServer.get_bus_index(bus_name)
	if bus_idx != -1:
		# Always set the volume level (so it's ready when unmuted)
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(volume))
		# Set mute flag separately for full silence
		AudioServer.set_bus_mute(bus_idx, muted)
		# Logs
		if muted:
			Globals.log_message(bus_name + " is muted.", Globals.LogLevel.DEBUG)
		else:
			Globals.log_message(
				"Applied loaded " + bus_name + " volume to AudioServer: " + str(volume),
				Globals.LogLevel.DEBUG
			)
	else:
		Globals.log_message(bus_name + " audio bus not found!", Globals.LogLevel.ERROR)
