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
@export var music_muted: bool = false

@export_category("SFX Volume")
@export var sfx_volume: float = 1.0
@export var sfx_muted: bool = false
@export var weapon_volume: float = 1.0
@export var weapon_muted: bool = false
@export var rotors_volume: float = 1.0
@export var rotors_muted: bool = false

var current_config_path: String = Settings.CONFIG_PATH


func _ready() -> void:
	load_volumes()  # Load persisted volumes
	apply_all_volumes()  # Apply to AudioServer buses


## Load volumes from config (shared with other settings)
## :param path: Path to config file.
## :type path: String
## :rtype: void
func load_volumes(path: String = Settings.CONFIG_PATH) -> void:
	current_config_path = path
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(path)
	if err != OK:
		if err != ERR_FILE_NOT_FOUND:
			Globals.log_message("Failed to load config: " + str(err), Globals.LogLevel.ERROR)
		return  # Use defaults on not found or error
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		var config_data: Dictionary = AudioConstants.BUS_CONFIG[bus]
		set(
			config_data["volume_var"],
			config.get_value("audio", config_data["volume_var"], get(config_data["volume_var"]))
		)
		set(
			config_data["muted_var"],
			config.get_value("audio", config_data["muted_var"], get(config_data["muted_var"]))
		)
	Globals.log_message("Loaded volumes from config.", Globals.LogLevel.DEBUG)


## Save volumes to config (shared with other settings)
## :param path: Path to config file.
## :type path: String
## :rtype: void
func save_volumes(path: String = "") -> void:
	if path == "":
		path = current_config_path  # Fall back to the last loaded path if empty
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		Globals.log_message("Failed to load config for save: " + str(err), Globals.LogLevel.ERROR)
		return
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		var config_data: Dictionary = AudioConstants.BUS_CONFIG[bus]
		config.set_value("audio", config_data["volume_var"], get(config_data["volume_var"]))
		config.set_value("audio", config_data["muted_var"], get(config_data["muted_var"]))
	err = config.save(path)
	if err == OK:
		Globals.log_message("Saved volumes to config.", Globals.LogLevel.DEBUG)
	else:
		Globals.log_message("Failed to save config: " + str(err), Globals.LogLevel.ERROR)


## Apply all loaded volumes to AudioServer buses
## :rtype: void
func apply_all_volumes() -> void:
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		var config_data: Dictionary = AudioConstants.BUS_CONFIG[bus]
		apply_volume_to_bus(bus, get(config_data["volume_var"]), get(config_data["muted_var"]))


## Helper to apply a single volume to a named bus
## :param bus_name: Name of the bus.
## :type bus_name: String
## :param volume: Volume level (0.0 to 1.0).
## :type volume: float
## :param muted: Mute flag.
## :type muted: bool
## :rtype: void
func apply_volume_to_bus(bus_name: String, volume: float, muted: bool) -> void:
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


## Reset all volumes and mute flags to defaults
## :rtype: void
func reset_volumes() -> void:
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		var config_data: Dictionary = AudioConstants.BUS_CONFIG[bus]
		set(config_data["volume_var"], config_data["default_volume"])
		set(config_data["muted_var"], config_data["default_muted"])
	apply_all_volumes()
	save_volumes()
	Globals.log_message("Audio volumes reset to defaults.", Globals.LogLevel.DEBUG)
