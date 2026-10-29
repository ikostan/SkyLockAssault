## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## audio_manager.gd
## Autoload singleton for audio-related globals and logic.
## Handles volume variables, bus constants, loading/saving volumes, and applying to AudioServer.
## SFX playback (pool, cache, UI button clicks) lives in the SfxManager autoload.
## Access from any script as AudioManager.master_volume, etc.

extends Node

# --- NEW SIGNALS FOR WEB BRIDGE & UI SYNC ---
## Emitted when the volume of an audio bus changes.
##
## [param bus_name]: The name of the audio bus.
## [param volume]: The new volume level in decibels or linear scale.
signal volume_changed(bus_name: String, volume: float)
## Emitted when the mute state of an audio bus changes.
##
## [param bus_name]: The name of the audio bus.
## [param is_muted]: The new mute state, where [code]true[/code] means muted.
signal mute_toggled(bus_name: String, is_muted: bool)
# --------------------------------------------
## Emitted when the last open confirmation-click window closes and the feedback
## path has been re-synced (Issue #1047). change_volume() awaits it for its own hold.
signal feedback_path_settled

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

# --- UNMUTE-FROM-ZERO STATE (Issue #1046) ---
## Last committed volume above AUTO_MUTE_VOLUME_THRESHOLD, per bus name. In memory only.
## Captured at commit points (save_volumes / load_volumes), not on every set_volume(),
## because a slider drag down to 0 passes through near-silent steps (0.066, 0.033, ...)
## that must not overwrite the volume the user actually had before the drag.
var _last_audible_volume: Dictionary = {}

# --- CONFIRMATION-CLICK WINDOWS (Issues #1075, #1047) ---
## Number of confirmation clicks still streaming out. Every SFX_CHECK click AudioManager plays
## (auto-mute, auto-unmute, mute button) opens a MUTE_HARDWARE_DELAY window. The click plays
## on SFX_Menu and passes through every bus on its feedback path (SFX_Menu -> SFX -> Master),
## so while any window is open, a write that would silence one of those buses is deferred:
## the mixer is kept at FEEDBACK_HOLD_VOLUME_LINEAR (or left as is) instead. When the last
## window closes, every bus whose write was deferred is re-synced from the manager's current
## state (see _deferred_buses). Tracking
## clicks rather than buses covers overlaps across buses (SFX_Menu then SFX within the delay)
## and mute toggles, not just repeated updates on one bus. In memory only.
## Not a generation token: it only decides when the mixer is written, never which state wins;
## the re-sync still re-reads the newest state (Issue #1041).
## Deliberately not cleared by cleanup_for_test(): a window still awaiting its timer would
## then close a newer window early.
var _clicks_in_flight: int = 0
## Buses whose silencing write was deferred while a click window was open, used as a set.
## Recorded per bus rather than re-derived from the feedback path when the last window
## closes, so a bus held under one routing is still re-synced if the route changes before
## then. Cleared after that re-sync; like _clicks_in_flight, kept by cleanup_for_test().
var _deferred_buses: Dictionary = {}


func _ready() -> void:
	## Initializes to defaults and loads/applies volumes.
	_init_to_defaults()  # Set to defaults from AudioConstants
	load_volumes()  # Load persisted volumes (overrides defaults if saved)
	apply_all_volumes()  # Apply to AudioServer buses


## Initialize all volumes and mutes to defaults from AudioConstants
## :rtype: void
func _init_to_defaults() -> void:
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		var config_data: Dictionary = AudioConstants.BUS_CONFIG[bus]
		set_bus_state(bus, config_data["default_volume"], config_data["default_muted"])


## Retrieve the state dictionary for the specified audio bus.
##
## Returns a dictionary containing volume and muted status for the bus.
##
## [param bus_name]: Name of the bus to query.
## Returns Dictionary containing the volume and muted status.
func get_bus_state(bus_name: String) -> Dictionary:
	return {"volume": get_volume(bus_name), "muted": get_muted(bus_name)}


## Sets volume and mute state for an audio bus without auto-mute rules.
##
## Raw setter that writes volume then mute exactly as given and never applies the near-zero
## auto-mute rule. Used by config load, reset, and init so a saved state does not emit a
## spurious unmute or re-mute.
##
## [param bus_name]: Name of the audio bus.
## [param volume]: Volume level ranging from 0.0 to 1.0.
## [param muted]: Mute flag indicating whether the bus is muted.
func set_bus_state(bus_name: String, volume: float, muted: bool) -> void:
	set_volume(bus_name, volume)
	set_muted(bus_name, muted)


## Return the current volume for the specified audio bus.
##
## Retrieves the volume level associated with the given bus name.
##
## [param bus_name]: Name of the audio bus to query.
## Returns the volume level as a float value.
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


## Set volume for a bus without applying auto-mute or saving.
##
## Raw setter that updates state and emits volume_changed only. Never applies the near-zero
## auto-mute rule, never touches AudioServer and never saves.
##
## [param bus_name]: Name of the bus.
## [param vol]: Volume level (0.0 to 1.0).
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


## Return the muted state for the specified audio bus.
##
## Retrieves the mute status of the requested audio bus.
##
## [param bus_name]: Name of the bus to check.
## Returns true if the bus is muted, otherwise false.
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


## Set muted state for a bus.
##
## Updates the mute state for the specified audio bus and emits a signal if successful.
##
## [param bus_name]: Name of the audio bus.
## [param muted]: Mute flag to apply.
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


## Returns the volume a bus should be restored to when unmuted from (near) zero:
## the last committed volume above AUTO_MUTE_VOLUME_THRESHOLD, or
## AudioConstants.UNMUTE_FROM_ZERO_FALLBACK_VOLUME if none is known (Issue #1046).
## :param bus_name: Name of the bus.
## :type bus_name: String
## :rtype: float
func _get_last_audible_volume(bus_name: String) -> float:
	return float(
		_last_audible_volume.get(bus_name, AudioConstants.UNMUTE_FROM_ZERO_FALLBACK_VOLUME)
	)


## Toggles the mute state of an audio bus with optional hardware cutoff delay and confirmation
## click.
##
## Owns the confirmation click, deferred hardware cutoff, and unmute-from-zero volume restore.
## Manual interactions play a confirmation click and defer the AudioServer cutoff by
## MUTE_HARDWARE_DELAY. Unmuting at near zero volume restores the last audible volume.
##
## [param bus_name]: Name of the audio bus.
## [param muted]: True to mute the bus, or false to unmute it.
## [param is_manual_interaction]: True for real user presses to play a confirmation click and
## defer hardware cutoff; false for programmatic callers.
func toggle_mute(bus_name: String, muted: bool, is_manual_interaction: bool = false) -> void:
	if not AudioConstants.BUS_CONFIG.has(bus_name):
		Globals.log_message("Unknown bus for toggle_mute: " + bus_name, Globals.LogLevel.WARNING)
		return

	if is_manual_interaction:
		_play_confirmation_click()

	set_muted(bus_name, muted)
	if not muted:
		_restore_volume_for_unmute(bus_name)

	# ENGINE WORKAROUND: defer the hardware cutoff so the confirmation click is not cut off.
	if muted and is_manual_interaction and is_inside_tree():
		await get_tree().create_timer(AudioConstants.MUTE_HARDWARE_DELAY).timeout

	# Re-read the newest state: a toggle issued during the delay must not be overwritten.
	# A mute on the feedback path waits for any click still streaming (Issue #1047).
	_sync_bus_or_defer(bus_name)


## Changes bus volume with near-zero auto-mute rules and optional confirmation clicks.
##
## Single volume entry point that applies the near-zero auto-mute rule. Edge-triggered on
## AUTO_MUTE_VOLUME_THRESHOLD crossings, updating AudioServer and handling feedback-path holds
## during confirmation clicks.
##
## [param bus_name]: Name of the target audio bus.
## [param volume]: Volume level ranging from 0.0 to 1.0.
## [param is_manual_interaction]: True for real user input triggering a click and feedback-path
## hold; false for programmatic callers.
func change_volume(bus_name: String, volume: float, is_manual_interaction: bool = false) -> void:
	if not AudioConstants.BUS_CONFIG.has(bus_name):
		Globals.log_message("Unknown bus for change_volume: " + bus_name, Globals.LogLevel.WARNING)
		return

	var threshold: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	# Read before set_volume(): the crossing is judged against the previous stored volume.
	var old_volume: float = get_volume(bus_name)
	var crossed_down: bool = old_volume > threshold and volume <= threshold
	var crossed_up: bool = old_volume <= threshold and volume > threshold

	set_volume(bus_name, volume)
	# The manager owns the AudioServer write for this path. This write carries the pre-rule
	# mute flag; a transition below re-syncs AudioServer once the rule has run.
	if volume > threshold or not _is_path_write_deferred(bus_name):
		apply_volume_to_bus(bus_name, volume, get_muted(bus_name))
	else:
		# A click is still streaming through this bus (Issues #1075, #1047): writing the muted
		# state now would cut it short. The last click window re-syncs this newest state.
		_deferred_buses[bus_name] = true
		_apply_feedback_hold_level(bus_name)

	# --- AUTO-MUTE ON CROSSING DOWN TO NEAR-ZERO ---
	if crossed_down and not get_muted(bus_name):
		# Flip state first so rapid consecutive updates short-circuit.
		set_muted(bus_name, true)
		if is_manual_interaction:
			_play_confirmation_click()

		# Re-sync from current state (Issue #1041), unless a click is still streaming through
		# this bus: then hold an audible level, and the last click window re-syncs instead, so
		# a newer change or unmute made in the meantime is what gets applied (Issue #1047).
		_sync_bus_or_defer(bus_name)
		if is_manual_interaction and _is_path_write_deferred(bus_name):
			await feedback_path_settled

	# --- AUTO-UNMUTE ON CROSSING UP FROM NEAR-ZERO ---
	elif crossed_up and get_muted(bus_name):
		set_muted(bus_name, false)
		# Apply the unmuted state right away: the write above still carried the old mute flag,
		# and without this the mixer would stay muted while AudioManager reports unmuted.
		apply_volume_to_bus(bus_name, volume, false)
		if is_manual_interaction:
			_play_confirmation_click()


## Returns true when a bus carries the auto-mute confirmation click (Issue #1047): the click
## bus itself (SFX_Menu, SfxManager.play_sfx()'s default) or any bus it sends to, found by
## walking AudioServer.get_bus_send() up the layout. Today that is SFX_Menu, SFX and Master.
## Read live from AudioServer, so a changed bus layout is followed without code changes.
## The walk is capped at bus_count steps so a misconfigured send cycle cannot loop forever.
## :param bus_name: Name of the bus.
## :type bus_name: String
## :rtype: bool
func _is_in_feedback_path(bus_name: String) -> bool:
	var current: String = AudioConstants.BUS_SFX_MENU
	for _step in range(AudioServer.bus_count):
		if AudioServer.get_bus_index(current) == -1:
			return false
		if current == bus_name:
			return true
		current = String(AudioServer.get_bus_send(AudioServer.get_bus_index(current)))
		if current.is_empty():
			return false
	return false


## Plays the SFX_CHECK confirmation click and, inside the tree, keeps its window open for
## MUTE_HARDWARE_DELAY so silencing writes on the feedback path wait for it (Issue #1047).
## Callers do not await it; change_volume() awaits feedback_path_settled when it must.
## :rtype: void
func _play_confirmation_click() -> void:
	SfxManager.play_sfx(AudioConstants.SFX_CHECK)
	if not is_inside_tree():
		return
	_clicks_in_flight += 1
	await get_tree().create_timer(AudioConstants.MUTE_HARDWARE_DELAY).timeout
	_end_click_window()


## Closes one confirmation-click window. When it was the last one, re-syncs every bus whose
## write was deferred from the manager's current state and emits feedback_path_settled.
## Never drops below zero, so a stray call cannot open a negative balance.
## :rtype: void
func _end_click_window() -> void:
	_clicks_in_flight = maxi(_clicks_in_flight - 1, 0)
	if _clicks_in_flight == 0:
		_resync_deferred_buses()
		feedback_path_settled.emit()


## Returns true while a confirmation click is streaming through a bus, i.e. a click window is
## open and the bus is on the click's feedback path. Silencing writes to it must wait.
## :param bus_name: Name of the bus.
## :type bus_name: String
## :rtype: bool
func _is_path_write_deferred(bus_name: String) -> bool:
	return _clicks_in_flight > 0 and _is_in_feedback_path(bus_name)


## Applies a bus's current state to AudioServer, unless that would silence a bus a click is
## still streaming through. Then an at-or-below-threshold bus is held at
## FEEDBACK_HOLD_VOLUME_LINEAR and a muted audible bus is left as it is; the mute flag is
## never touched, so a bus the player already muted stays muted. The last click window
## re-syncs it (Issue #1047).
## :param bus_name: Name of the bus.
## :type bus_name: String
## :rtype: void
func _sync_bus_or_defer(bus_name: String) -> void:
	var volume: float = get_volume(bus_name)
	var at_or_below: bool = volume <= AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	if (get_muted(bus_name) or at_or_below) and _is_path_write_deferred(bus_name):
		_deferred_buses[bus_name] = true
		if at_or_below:
			_apply_feedback_hold_level(bus_name)
		return
	apply_volume_to_bus(bus_name, volume, get_muted(bus_name))


## Re-applies the current state of every bus whose write was deferred, then forgets them.
## Runs when the last click window closes. Uses the recorded buses, not the current feedback
## path, so a bus held before a re-route is still settled.
## :rtype: void
func _resync_deferred_buses() -> void:
	var buses: Array = _deferred_buses.keys()
	_deferred_buses.clear()
	for bus: String in buses:
		apply_volume_to_bus(bus, get_volume(bus), get_muted(bus))


## Writes FEEDBACK_HOLD_VOLUME_LINEAR to a bus's AudioServer volume so the confirmation click
## stays audible. Leaves the AudioServer mute flag alone: the hold's re-sync owns that.
## :param bus_name: Name of the bus.
## :type bus_name: String
## :rtype: void
func _apply_feedback_hold_level(bus_name: String) -> void:
	var bus_idx: int = AudioServer.get_bus_index(bus_name)
	if bus_idx != -1:
		AudioServer.set_bus_volume_db(
			bus_idx, linear_to_db(AudioConstants.FEEDBACK_HOLD_VOLUME_LINEAR)
		)


## Guarantees a bus is never left unmuted at (near) zero volume (Issue #1046).
## Called by toggle_mute() right after set_muted(bus_name, false). If the bus volume is at or
## below AUTO_MUTE_VOLUME_THRESHOLD, it is raised to _get_last_audible_volume(); otherwise it
## is left unchanged. Uses the raw set_volume() setter, so volume_changed still fires and
## the menu slider and the web DOM follow. Because the bus is already unmuted, the UI's
## near-zero auto-unmute branch does not re-run. AudioServer is not touched here.
## :param bus_name: Name of the bus being unmuted.
## :type bus_name: String
## :rtype: float
func _restore_volume_for_unmute(bus_name: String) -> float:
	var current_vol: float = get_volume(bus_name)
	if current_vol > AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD:
		return current_vol

	var restored_vol: float = _get_last_audible_volume(bus_name)
	Globals.log_message(
		"Unmuted " + bus_name + " at zero volume; restoring " + str(restored_vol),
		Globals.LogLevel.DEBUG
	)
	set_volume(bus_name, restored_vol)
	return restored_vol


## Records every bus whose current volume is above AUTO_MUTE_VOLUME_THRESHOLD as its last
## audible volume, clamped to 0.0-1.0 so an out-of-range value set directly through
## set_volume() is never restored. Buses at or below the threshold keep their previous
## entry (Issue #1046).
## :rtype: void
func _snapshot_audible_volumes() -> void:
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		var vol: float = get_volume(bus)
		if vol > AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD:
			_last_audible_volume[bus] = clampf(vol, 0.0, 1.0)


## Load persisted volumes from config, overriding current values only if saved and valid.
##
## Acts strictly as an I/O coordinator by reading the file via Globals.safe_load_config,
## delegating parsing to apply_volumes_from_config, handling legacy migration, and syncing the
## resulting state to the AudioServer.
##
## [param path]: Config file path, defaulting to current_config_path.
func load_volumes(path: String = current_config_path) -> void:
	current_config_path = path

	# 1. Disk I/O: Read and decrypt configuration file
	var load_data: Dictionary = Globals.safe_load_config(path)
	var audio_cfg: ConfigFile = load_data["config"]
	var err: int = load_data["err"]
	var needs_migration: bool = load_data["is_legacy"]

	if needs_migration:
		Globals.log_message(
			"Legacy plaintext audio settings found. Migration required.", Globals.LogLevel.INFO
		)
	elif err != OK and err != ERR_FILE_NOT_FOUND:
		Globals.log_message("Failed to load audio config: " + str(err), Globals.LogLevel.ERROR)

	if err == OK:
		# 2. Apply in-memory configuration to AudioManager state
		apply_volumes_from_config(audio_cfg)
		Globals.log_message("Loaded volumes from config.", Globals.LogLevel.DEBUG)

		# 3. Legacy migration: re-save in encrypted format
		if needs_migration:
			Globals.log_message(
				"Upgrading audio settings file to encrypted format...", Globals.LogLevel.INFO
			)
			save_volumes(path)

	elif err == ERR_FILE_NOT_FOUND:
		Globals.log_message("No audio config file found, using defaults.", Globals.LogLevel.DEBUG)

	# 4. Loaded state is the new baseline: rebuild last-audible volumes from it (Issue #1046)
	_last_audible_volume.clear()
	_snapshot_audible_volumes()

	# 5. Sync runtime state to AudioServer buses
	apply_all_volumes()


## Applies volume and mute values from a ConfigFile to the manager state.
##
## Updates AudioManager state using well-typed values from an in-memory ConfigFile. Clamps
## volumes to 0.0-1.0 and auto-mutes buses at or below the auto-mute threshold. Updates state
## via set_bus_state without touching the AudioServer directly.
##
## [param config]: The ConfigFile instance containing the audio section.
func apply_volumes_from_config(config: ConfigFile) -> void:
	if config == null:
		return

	for bus: String in AudioConstants.BUS_CONFIG.keys():
		var config_data: Dictionary = AudioConstants.BUS_CONFIG[bus]
		var volume_key: String = config_data["volume_var"]
		var muted_key: String = config_data["muted_var"]

		var volume: float = get_volume(bus)
		var muted: bool = get_muted(bus)

		if config.has_section_key("audio", volume_key):
			var loaded_volume: Variant = config.get_value("audio", volume_key)
			if loaded_volume is float or loaded_volume is int:
				volume = clampf(float(loaded_volume), 0.0, 1.0)
				if not is_equal_approx(volume, float(loaded_volume)):
					Globals.log_message(
						"Out-of-range value for '" + volume_key + "' clamped to " + str(volume),
						Globals.LogLevel.WARNING
					)
			else:
				Globals.log_message(
					"Unsupported config value type for '" + volume_key + "': skipped",
					Globals.LogLevel.WARNING
				)

		if config.has_section_key("audio", muted_key):
			var loaded_muted: Variant = config.get_value("audio", muted_key)
			if loaded_muted is bool:
				muted = loaded_muted
			else:
				Globals.log_message(
					"Unsupported config value type for '" + muted_key + "': skipped",
					Globals.LogLevel.WARNING
				)

		# Enforce the auto-mute rule on load: never start a bus unmuted at zero volume.
		if volume <= AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD and not muted:
			Globals.log_message(
				bus + " loaded at zero volume while unmuted; loading it muted.",
				Globals.LogLevel.INFO
			)
			muted = true

		set_bus_state(bus, volume, muted)


## Save audio volumes to config shared with other settings.
##
## A save acts as a commit point, remembering audible volumes even if disk write fails.
##
## [param path]: Path to config file.
func save_volumes(path: String = "") -> void:
	if path == "":
		path = current_config_path

	# A save is a commit point: remember audible volumes even if the disk write fails (Issue #1046)
	_snapshot_audible_volumes()

	var load_data: Dictionary = Globals.safe_load_config(path)
	var config: ConfigFile = load_data["config"]
	var err: int = load_data["err"]

	if err != OK and err != ERR_FILE_NOT_FOUND:
		Globals.log_message("Failed to load config for save: " + str(err), Globals.LogLevel.ERROR)
		return

	for bus: String in AudioConstants.BUS_CONFIG.keys():
		var config_data: Dictionary = AudioConstants.BUS_CONFIG[bus]
		var state: Dictionary = get_bus_state(bus)
		config.set_value("audio", config_data["volume_var"], state["volume"])
		config.set_value("audio", config_data["muted_var"], state["muted"])

	# FIX: Use the centralized key helper
	err = config.save_encrypted_pass(path, Globals.ensure_encryption_key())

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


## Apply a single volume and mute state to a named audio bus.
##
## Helper to apply a single volume to a named bus, checking bus validity before updating the
## AudioServer.
##
## [param bus_name]: Name of the audio bus.
## [param volume]: Volume level from 0.0 to 1.0.
## [param muted]: Mute flag to apply.
func apply_volume_to_bus(bus_name: String, volume: float, muted: bool) -> void:
	# 1. Guard against null or invalid Engine access
	if not is_instance_valid(AudioServer):
		return

	var bus_idx: int = AudioServer.get_bus_index(bus_name)
	# 2. Add an explicit check to prevent the 'p_ptr is null' error
	# if the bus was removed by a test or logic error
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


## FOR GUT UNIT TEST ONLY
## Clears AudioManager's in-memory state and resets the SFX pool/caches in SfxManager,
## so existing test teardowns keep a single call. Guarded for debug builds only.
func cleanup_for_test() -> void:
	if not OS.is_debug_build():
		return

	_last_audible_volume.clear()
	SfxManager.cleanup_for_test()
