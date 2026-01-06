## audio_manager.gd
## Autoload singleton for audio-related globals and logic.
## Handles volume variables, bus constants, loading/saving volumes, and applying to AudioServer.
## Access from any script as AudioManager.master_volume, etc.

extends Node

@export_category("Master Volume")
@export var master_volume: float
@export var master_muted: bool

@export_category("Music Volume")
@export var music_volume: float
@export var music_muted: bool

@export_category("SFX Volume")
@export var sfx_volume: float
@export var sfx_muted: bool
@export var weapon_volume: float
@export var weapon_muted: bool
@export var rotors_volume: float
@export var rotors_muted: bool

var current_config_path: String = Settings.CONFIG_PATH


func _ready() -> void:
	## Initializes to defaults and loads/applies volumes.
	## :rtype: void
	_init_to_defaults()  # Set to defaults from AudioConstants
	load_volumes()  # Load persisted volumes (overrides defaults if saved)
	apply_all_volumes()  # Apply to AudioServer buses


## Initialize all volumes and mutes to defaults from AudioConstants
## :rtype: void
func _init_to_defaults() -> void:
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		var config_data: Dictionary = AudioConstants.BUS_CONFIG[bus]
		set_bus_state(bus, config_data["default_volume"], config_data["default_muted"])


## Get state for a bus
## :param bus_name: Name of the bus.
## :type bus_name: String
## :rtype: Dictionary
func get_bus_state(bus_name: String) -> Dictionary:
	return {
		"volume": get_volume(bus_name),
		"muted": get_muted(bus_name)
	}


## Set state for a bus
## :param bus_name: Name of the bus.
## :type bus_name: String
## :param volume: Volume level (0.0 to 1.0).
## :type volume: float
## :param muted: Mute flag.
## :type muted: bool
## :rtype: void
func set_bus_state(bus_name: String, volume: float, muted: bool) -> void:
	set_volume(bus_name, volume)
	set_muted(bus_name, muted)


## Get volume for a bus
## :param bus_name: Name of the bus.
## :type bus_name: String
## :rtype: float
func get_volume(bus_name: String) -> float:
	match bus_name:
		AudioConstants.BUS_MASTER:
			return master_volume
		AudioConstants.BUS_MUSIC:
			return music_volume
		AudioConstants.BUS_SFX:
			return sfx_volume
		AudioConstants.BUS_SFX_WEAPON:
			return weapon_volume
		AudioConstants.BUS_SFX_ROTORS:
			return rotors_volume
		_:
			Globals.log_message("Unknown bus for get_volume: " + bus_name, Globals.LogLevel.WARNING)
			return 0.0


## Set volume for a bus
## :param bus_name: Name of the bus.
## :type bus_name: String
## :param vol: Volume level (0.0 to 1.0).
## :type vol: float
## :rtype: void
func set_volume(bus_name: String, vol: float) -> void:
	match bus_name:
		AudioConstants.BUS_MASTER:
			master_volume = vol
		AudioConstants.BUS_MUSIC:
			music_volume = vol
		AudioConstants.BUS_SFX:
			sfx_volume = vol
		AudioConstants.BUS_SFX_WEAPON:
			weapon_volume = vol
		AudioConstants.BUS_SFX_ROTORS:
			rotors_volume = vol
		_:
			Globals.log_message("Unknown bus for set_volume: " + bus_name, Globals.LogLevel.WARNING)


## Get muted state for a bus
## :param bus_name: Name of the bus.
## :type bus_name: String
## :rtype: bool
func get_muted(bus_name: String) -> bool:
	match bus_name:
		AudioConstants.BUS_MASTER:
			return master_muted
		AudioConstants.BUS_MUSIC:
			return music_muted
		AudioConstants.BUS_SFX:
			return sfx_muted
		AudioConstants.BUS_SFX_WEAPON:
			return weapon_muted
		AudioConstants.BUS_SFX_ROTORS:
			return rotors_muted
		_:
			Globals.log_message("Unknown bus for get_muted: " + bus_name, Globals.LogLevel.WARNING)
			return false


## Set muted state for a bus
## :param bus_name: Name of the bus.
## :type bus_name: String
## :param muted: Mute flag.
## :type muted: bool
## :rtype: void
func set_muted(bus_name: String, muted: bool) -> void:
	match bus_name:
		AudioConstants.BUS_MASTER:
			master_muted = muted
		AudioConstants.BUS_MUSIC:
			music_muted = muted
		AudioConstants.BUS_SFX:
			sfx_muted = muted
		AudioConstants.BUS_SFX_WEAPON:
			weapon_muted = muted
		AudioConstants.BUS_SFX_ROTORS:
			rotors_muted = muted
		_:
			Globals.log_message("Unknown bus for set_muted: " + bus_name, Globals.LogLevel.WARNING)


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
		var state: Dictionary = get_bus_state(bus)
		set_bus_state(
			bus,
			config.get_value("audio", config_data["volume_var"], state["volume"]),
			config.get_value("audio", config_data["muted_var"], state["muted"])
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
		var state: Dictionary = get_bus_state(bus)
		config.set_value("audio", config_data["volume_var"], state["volume"])
		config.set_value("audio", config_data["muted_var"], state["muted"])
	err = config.save(path)
	if err == OK:
		Globals.log_message("Saved volumes to config.", Globals.LogLevel.DEBUG)
	else:
		Globals.log_message("Failed to save config: " + str(err), Globals.LogLevel.ERROR)


## Apply all loaded volumes to AudioServer buses
## :rtype: void
func apply_all_volumes() -> void:
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		var state: Dictionary = get_bus_state(bus)
		apply_volume_to_bus(bus, state["volume"], state["muted"])


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
		set_bus_state(bus, config_data["default_volume"], config_data["default_muted"])
	apply_all_volumes()
	save_volumes()
	Globals.log_message("Audio volumes reset to defaults.", Globals.LogLevel.DEBUG)
