## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## audio_manager.gd
## Autoload singleton for audio-related globals and logic.
## Handles volume variables, bus constants, loading/saving volumes, and applying to AudioServer.
## Access from any script as AudioManager.master_volume, etc.

extends Node

# --- NEW SIGNALS FOR WEB BRIDGE & UI SYNC ---
signal volume_changed(bus_name: String, volume: float)
signal mute_toggled(bus_name: String, is_muted: bool)
# --------------------------------------------

# --- NEW: SFX CACHING & MANAGEMENT ---
## Base path for all UI sound effects.
const SFX_DIR_PATH: String = "res://files/sounds/sfx/"

## Hard cap for cached SFX streams to prevent unbounded memory growth.
const MAX_SFX_CACHE_SIZE: int = 20

## Number of reusable AudioStreamPlayers to keep in memory for UI sounds.
const SFX_POOL_SIZE: int = 8

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
@export var menu_volume: float
@export var menu_muted: bool

var current_config_path: String = Settings.CONFIG_PATH

# --- SFX CACHE STATE ---
## Dictionary to store preloaded AudioStreams to prevent disk I/O stutter.
var _sfx_cache: Dictionary = {}

## Dictionary acting as a set to track missing SFX and prevent repeated load attempts/log spam.
var _missing_sfx_cache: Dictionary = {}

## Array of pre-instantiated AudioStreamPlayers to prevent node instantiation churn.
var _sfx_pool: Array[AudioStreamPlayer] = []


func _ready() -> void:
	## Initializes to defaults and loads/applies volumes.
	_init_to_defaults()  # Set to defaults from AudioConstants
	load_volumes()  # Load persisted volumes (overrides defaults if saved)
	apply_all_volumes()  # Apply to AudioServer buses

	# Initialize the SFX object pool
	for i in range(SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_pool.append(p)


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
	return {"volume": get_volume(bus_name), "muted": get_muted(bus_name)}


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
	var current_vol: float = 0.0

	match bus_name:
		AudioConstants.BUS_MASTER:
			current_vol = master_volume
		AudioConstants.BUS_MUSIC:
			current_vol = music_volume
		AudioConstants.BUS_SFX:
			current_vol = sfx_volume
		AudioConstants.BUS_SFX_WEAPON:
			current_vol = weapon_volume
		AudioConstants.BUS_SFX_ROTORS:
			current_vol = rotors_volume
		AudioConstants.BUS_SFX_MENU:
			current_vol = menu_volume
		_:
			Globals.log_message("Unknown bus for get_volume: " + bus_name, Globals.LogLevel.WARNING)

	return current_vol


## Set volume for a bus
## :param bus_name: Name of the bus.
## :type bus_name: String
## :param vol: Volume level (0.0 to 1.0).
## :type vol: float
## :rtype: void
func set_volume(bus_name: String, vol: float) -> void:
	if not AudioConstants.BUS_CONFIG.has(bus_name):
		Globals.log_message("Unknown bus for set_volume: " + bus_name, Globals.LogLevel.WARNING)
		return

	var success: bool = true
	match bus_name:
		AudioConstants.BUS_MASTER:
			master_volume = vol
			Globals.log_message(
				"Master Volume Level in AudioManager: " + str(vol), Globals.LogLevel.DEBUG
			)
		AudioConstants.BUS_MUSIC:
			music_volume = vol
			Globals.log_message(
				"Music Volume Level in AudioManager: " + str(vol), Globals.LogLevel.DEBUG
			)
		AudioConstants.BUS_SFX:
			sfx_volume = vol
			Globals.log_message(
				"SFX Volume Level in AudioManager: " + str(vol), Globals.LogLevel.DEBUG
			)
		AudioConstants.BUS_SFX_WEAPON:
			weapon_volume = vol
			Globals.log_message(
				"Weapon Volume Level in AudioManager: " + str(vol), Globals.LogLevel.DEBUG
			)
		AudioConstants.BUS_SFX_ROTORS:
			rotors_volume = vol
			Globals.log_message(
				"Rotors Volume Level in AudioManager: " + str(vol), Globals.LogLevel.DEBUG
			)
		AudioConstants.BUS_SFX_MENU:
			menu_volume = vol
			Globals.log_message(
				"Menu Volume Level in AudioManager: " + str(vol), Globals.LogLevel.DEBUG
			)
		_:
			Globals.log_message(
				"Unsupported bus in set_volume match (check config drift): " + bus_name,
				Globals.LogLevel.ERROR
			)
			success = false

	# NEW: Emit the signal if the volume was successfully updated
	if success:
		volume_changed.emit(bus_name, vol)


## Get muted state for a bus
## :param bus_name: Name of the bus.
## :type bus_name: String
## :rtype: bool
func get_muted(bus_name: String) -> bool:
	var is_muted: bool = false

	match bus_name:
		AudioConstants.BUS_MASTER:
			is_muted = master_muted
		AudioConstants.BUS_MUSIC:
			is_muted = music_muted
		AudioConstants.BUS_SFX:
			is_muted = sfx_muted
		AudioConstants.BUS_SFX_WEAPON:
			is_muted = weapon_muted
		AudioConstants.BUS_SFX_ROTORS:
			is_muted = rotors_muted
		AudioConstants.BUS_SFX_MENU:
			is_muted = menu_muted
		_:
			Globals.log_message("Unknown bus for get_muted: " + bus_name, Globals.LogLevel.WARNING)

	return is_muted


## Set muted state for a bus
## :param bus_name: Name of the bus.
## :type bus_name: String
## :param muted: Mute flag.
## :type muted: bool
## :rtype: void
func set_muted(bus_name: String, muted: bool) -> void:
	var success: bool = true
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
		AudioConstants.BUS_SFX_MENU:
			menu_muted = muted
		_:
			Globals.log_message("Unknown bus for set_muted: " + bus_name, Globals.LogLevel.WARNING)
			success = false

	# NEW: Emit the signal if the mute state was successfully updated
	if success:
		mute_toggled.emit(bus_name, muted)


## load_volumes
## Loads persisted volumes from config if valid types;
## skips invalid/missing to keep current.
## :param path: Config file path (default: current_config_path).
## :type path: String
## :rtype: void
func load_volumes(path: String = current_config_path) -> void:
	current_config_path = path  # Update to keep in sync with the path used
	# SECURITY GUARD: Ensure encryption key is initialized
	if Globals.save_encryption_pass.is_empty():
		Globals.save_encryption_pass = Globals._get_encryption_key()

	var audio_cfg: ConfigFile = ConfigFile.new()
	var err: int = audio_cfg.load_encrypted_pass(path, Globals.save_encryption_pass)
	var needs_migration: bool = false

	# Step 2: Migration Check for Legacy Plaintext Files
	if err == ERR_INVALID_DATA or err == ERR_FILE_CORRUPT:
		Globals.log_message(
			"Encrypted load failed (Code %d). Checking if file is legacy plaintext..." % err,
			Globals.LogLevel.DEBUG
		)

		# Reset config object before trying legacy load
		audio_cfg = ConfigFile.new()
		err = audio_cfg.load(path)

		if err == OK:
			Globals.log_message(
				"Legacy plaintext audio settings found. Migration required.", Globals.LogLevel.INFO
			)
			needs_migration = true
		else:
			Globals.log_message(
				"File is not valid plaintext either. Proceeding to defaults.",
				Globals.LogLevel.ERROR
			)

	elif err != OK and err != ERR_FILE_NOT_FOUND:
		Globals.log_message("Failed to load audio config: " + str(err), Globals.LogLevel.ERROR)

	if err == OK:
		for bus: String in AudioConstants.BUS_CONFIG.keys():
			var config_data: Dictionary = AudioConstants.BUS_CONFIG[bus]
			var volume_key: String = config_data["volume_var"]
			var muted_key: String = config_data["muted_var"]

			# Start with current values (defaults if not yet overridden)
			var volume: float = get_volume(bus)
			var muted: bool = get_muted(bus)

			# Load volume if present and valid
			if audio_cfg.has_section_key("audio", volume_key):
				var loaded_volume: Variant = audio_cfg.get_value("audio", volume_key)
				if loaded_volume is float or loaded_volume is int:
					volume = float(loaded_volume)
				else:
					Globals.log_message(
						(
							"Invalid type for "
							+ volume_key
							+ ": "
							+ type_string(typeof(loaded_volume))
						),
						Globals.LogLevel.WARNING
					)

			# Load muted if present and valid
			if audio_cfg.has_section_key("audio", muted_key):
				var loaded_muted: Variant = audio_cfg.get_value("audio", muted_key)
				if loaded_muted is bool:
					muted = loaded_muted
				else:
					Globals.log_message(
						"Invalid type for " + muted_key + ": " + str(typeof(loaded_muted)),
						Globals.LogLevel.WARNING
					)

			# Apply via setter for encapsulation
			set_bus_state(bus, volume, muted)

		Globals.log_message("Loaded volumes from config.", Globals.LogLevel.DEBUG)

		# Execute the migration save
		if needs_migration:
			Globals.log_message(
				"Upgrading audio settings file to encrypted format...", Globals.LogLevel.INFO
			)
			save_volumes(path)

	elif err == ERR_FILE_NOT_FOUND:
		Globals.log_message("No audio config file found, using defaults.", Globals.LogLevel.DEBUG)

	apply_all_volumes()


## Save volumes to config (shared with other settings)
## :param path: Path to config file.
## :type path: String
## :rtype: void
func save_volumes(path: String = "") -> void:
	if path == "":
		path = current_config_path  # Fall back to the last loaded path if empty
	# SECURITY GUARD: Ensure encryption key is initialized
	if Globals.save_encryption_pass.is_empty():
		Globals.save_encryption_pass = Globals._get_encryption_key()

	current_config_path = path  # Update to keep in sync with the path used
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load_encrypted_pass(path, Globals.save_encryption_pass)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		Globals.log_message("Failed to load config for save: " + str(err), Globals.LogLevel.ERROR)
		return
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		var config_data: Dictionary = AudioConstants.BUS_CONFIG[bus]
		var state: Dictionary = get_bus_state(bus)
		config.set_value("audio", config_data["volume_var"], state["volume"])
		config.set_value("audio", config_data["muted_var"], state["muted"])
	err = config.save_encrypted_pass(path, Globals.save_encryption_pass)
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


## Centralized SFX Playback API (Issue #565)
## Handles non-positional audio with LRU caching and auto-cleanup.
## :param sfx_name: The filename without extension (e.g., "slider").
## :param bus_name: Target audio bus (defaults to SFX_Menu).
## :param pitch_scale: Pitch override for variety.
## :param volume_db: Volume offset in decibels.
func play_sfx(
	sfx_name: String,
	bus_name: String = AudioConstants.BUS_SFX_MENU,
	pitch_scale: float = 1.0,
	volume_db: float = 0.0
) -> void:
	if sfx_name.is_empty():
		return

	# Short-circuit: If we already know this file is missing, do not attempt to load it again.
	if _missing_sfx_cache.has(sfx_name):
		return

	# 1. Resolve and Cache the AudioStream (with LRU Eviction)
	if not _sfx_cache.has(sfx_name):
		var full_path: String = SFX_DIR_PATH + sfx_name + ".wav"
		var stream: AudioStream = load(full_path)

		if stream:
			# Eviction strategy: If cache is full, remove the oldest (first) entry
			if _sfx_cache.size() >= MAX_SFX_CACHE_SIZE:
				var oldest_key: String = _sfx_cache.keys()[0]
				_sfx_cache.erase(oldest_key)
				Globals.log_message(
					"SFX cache full. Evicted: " + oldest_key, Globals.LogLevel.DEBUG
				)

			_sfx_cache[sfx_name] = stream
		else:
			Globals.log_message(
				"SFX file not found or failed to load: " + full_path, Globals.LogLevel.WARNING
			)
			# Cache the failure so we don't spam the disk and logs on subsequent requests
			_missing_sfx_cache[sfx_name] = true
			return
	else:
		# LRU Update: Godot 4 Dictionaries preserve insertion order.
		# By erasing and re-inserting, we push this active sound to the "newest" end of the dictionary.
		var stream: AudioStream = _sfx_cache[sfx_name]
		_sfx_cache.erase(sfx_name)
		_sfx_cache[sfx_name] = stream

	# 2. Grab an available player from the object pool
	var player: AudioStreamPlayer = null
	for p: AudioStreamPlayer in _sfx_pool:
		if not p.playing:
			player = p
			break

	# Fallback: If all players are busy, hijack the first one in the pool
	# to prevent dropping the new sound entirely.
	if player == null:
		player = _sfx_pool[0]

	player.stream = _sfx_cache[sfx_name]
	player.pitch_scale = pitch_scale
	player.volume_db = volume_db

	# 3. Bus Validation & Routing
	if AudioServer.get_bus_index(bus_name) == -1:
		Globals.log_message(
			"Invalid bus '%s' requested for SFX. Falling back to SFX_Menu." % bus_name,
			Globals.LogLevel.WARNING
		)
		player.bus = AudioConstants.BUS_SFX_MENU
	else:
		player.bus = bus_name

	# 4. Play (No queue_free needed since we reuse the nodes)
	player.play()
