## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## audio_manager.gd
## Autoload singleton for audio-related globals and logic.
## Handles volume variables, bus constants, loading/saving volumes, and applying to AudioServer.
## SFX playback (pool, cache, UI button clicks) lives in the SfxManager autoload.
## Access from any script as AudioManager.master_volume, etc.

extends Node

# --- NEW SIGNALS FOR WEB BRIDGE & UI SYNC ---
signal volume_changed(bus_name: String, volume: float)
signal mute_toggled(bus_name: String, is_muted: bool)
# --------------------------------------------

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

# --- NEAR-ZERO AUTO-MUTE STATE (Issue #1039) ---
## Generation counter for the Master feedback hold started by change_volume(). Every new
## Master auto-mute/auto-unmute bumps it, so a hold whose timer fires after a newer change
## does not flatten the bus. Ported as-is from audio_settings.gd::_master_zero_token;
## T4 (#1041) replaces it with an idempotent re-sync and removes it.
var _master_hold_token: int = 0


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


## Get state for a bus
## :param bus_name: Name of the bus.
## :type bus_name: String
## :rtype: Dictionary
func get_bus_state(bus_name: String) -> Dictionary:
	return {"volume": get_volume(bus_name), "muted": get_muted(bus_name)}


## Set state for a bus
## Raw setter: writes volume then mute exactly as given and never applies the near-zero
## auto-mute rule (use change_volume() for that). Config load, reset and init rely on this,
## so a saved {0.5, muted} does not emit a spurious unmute/re-mute.
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
## Raw setter: updates state and emits volume_changed only. Never applies the near-zero
## auto-mute rule, never touches AudioServer and never saves. Use change_volume() when a
## volume change should be able to auto-mute or auto-unmute the bus.
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


## Single mute/unmute pipeline shared by the Audio Settings menu and the web bridge
## (Issue #1048). Owns the confirmation click, the deferred hardware cutoff and the
## unmute-from-zero restore (Issue #1046), so callers never sequence state/apply themselves.
## Flow:
##   1. Manual interactions play the confirmation click.
##   2. The logical mute state flips immediately (mute_toggled fires, so UI locks update).
##   3. Unmuting a bus at (near) zero volume restores its last audible volume.
##   4. Manual mutes defer the AudioServer cutoff by MUTE_HARDWARE_DELAY so the click can
##      finish streaming; unmutes and programmatic calls apply immediately.
##   5. The newest state is applied to AudioServer (a newer toggle during the delay wins).
## Does not save: callers follow up with save_volumes(), mirroring set_volume().
## :param bus_name: Name of the bus.
## :type bus_name: String
## :param muted: True to mute, false to unmute.
## :type muted: bool
## :param is_manual_interaction: True for real user presses (click + deferred cutoff);
##     false for programmatic callers such as the web bridge (silent, immediate).
## :type is_manual_interaction: bool
## :rtype: void
func toggle_mute(bus_name: String, muted: bool, is_manual_interaction: bool = false) -> void:
	if not AudioConstants.BUS_CONFIG.has(bus_name):
		Globals.log_message("Unknown bus for toggle_mute: " + bus_name, Globals.LogLevel.WARNING)
		return

	if is_manual_interaction:
		SfxManager.play_sfx(AudioConstants.SFX_CHECK)

	set_muted(bus_name, muted)
	if not muted:
		_restore_volume_for_unmute(bus_name)

	# ENGINE WORKAROUND: defer the hardware cutoff so the confirmation click is not cut off.
	if muted and is_manual_interaction and is_inside_tree():
		await get_tree().create_timer(AudioConstants.MUTE_HARDWARE_DELAY).timeout

	# Re-read the newest state: a toggle issued during the delay must not be overwritten.
	apply_volume_to_bus(bus_name, get_volume(bus_name), get_muted(bus_name))


## Single volume entry point that applies the near-zero auto-mute rule (Issue #1039, epic #725).
## Runs with no menu in the tree, and callers state their intent instead of the code guessing
## it from slider focus:
##   1. The previous volume is read, then the new one is stored (volume_changed fires) and
##      written to AudioServer with the bus's current mute flag.
##   2. The rule is edge-triggered on AUTO_MUTE_VOLUME_THRESHOLD crossings (Issue #1040):
##      - crossing down (old > T, new <= T) on an unmuted bus -> auto-mute;
##      - crossing up (old <= T, new > T) on a muted bus -> auto-unmute.
##      Anything else leaves the mute flag alone, so a mute the player chose at an audible
##      volume survives any volume change that stays above the threshold, and repeated
##      near-zero updates are no-ops. No extra state: the previous volume is enough, so the
##      rule survives restarts.
##      Accepted corner case: a bus muted with its button at 0.8, then set to 0 and back up,
##      is unmuted on the way up; at zero, an explicit mute and an auto-mute look the same.
##   3. Manual interactions play the SFX_CHECK confirmation click on a transition.
##      Programmatic calls (web bridge, cutscenes, sync loops) are always silent.
##   4. Manual Master auto-mute holds the bus at FEEDBACK_HOLD_VOLUME_LINEAR for
##      MUTE_HARDWARE_DELAY so the click can stream out, then flattens it to 0.0.
##   5. Auto-unmute (any bus, manual or programmatic) applies the unmuted state to
##      AudioServer immediately and cancels a pending Master hold.
## Does not save: persistence stays with callers (slider debounce, web bridge).
## The raw setters (set_volume, set_bus_state, load_volumes, reset_volumes) never apply this.
## Await it only if you need the Master hold to have finished.
## :param bus_name: Name of the bus.
## :type bus_name: String
## :param volume: Volume level (0.0 to 1.0).
## :type volume: float
## :param is_manual_interaction: True for real user input (click + Master hold);
##     false for programmatic callers (silent, no hold).
## :type is_manual_interaction: bool
## :rtype: void
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
	# The manager owns the AudioServer write for this path. The mute flag is the pre-rule
	# state, matching today's slider/bridge behavior; T4 (#1041) re-syncs it after the rule.
	apply_volume_to_bus(bus_name, volume, get_muted(bus_name))

	var is_master: bool = bus_name == AudioConstants.BUS_MASTER

	# --- AUTO-MUTE ON CROSSING DOWN TO NEAR-ZERO ---
	if crossed_down and not get_muted(bus_name):
		# Flip state first so rapid consecutive updates short-circuit.
		set_muted(bus_name, true)
		if not is_manual_interaction:
			return

		SfxManager.play_sfx(AudioConstants.SFX_CHECK)
		if not is_master:
			return

		_master_hold_token += 1
		var hold_token: int = _master_hold_token
		var bus_idx: int = AudioServer.get_bus_index(bus_name)
		if bus_idx == -1:
			return

		# Hold an audible level so the click can stream out before the bus is flattened.
		AudioServer.set_bus_volume_db(
			bus_idx, linear_to_db(AudioConstants.FEEDBACK_HOLD_VOLUME_LINEAR)
		)
		if not is_inside_tree():
			AudioServer.set_bus_volume_db(bus_idx, linear_to_db(0.0))
			return

		await get_tree().create_timer(AudioConstants.MUTE_HARDWARE_DELAY).timeout

		# A newer Master change (or an unmute) during the hold wins: leave the bus alone.
		if hold_token == _master_hold_token and get_muted(bus_name):
			AudioServer.set_bus_volume_db(bus_idx, linear_to_db(0.0))

	# --- AUTO-UNMUTE ON CROSSING UP FROM NEAR-ZERO ---
	elif crossed_up and get_muted(bus_name):
		set_muted(bus_name, false)
		# Apply the unmuted state right away: the write above still carried the old mute flag,
		# and without this the mixer would stay muted while AudioManager reports unmuted.
		apply_volume_to_bus(bus_name, volume, false)
		if is_master:
			# Invalidate any pending hold so it cannot flatten the bus after this unmute.
			_master_hold_token += 1
		if is_manual_interaction:
			SfxManager.play_sfx(AudioConstants.SFX_CHECK)


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


## load_volumes
## Loads persisted volumes from config, overriding current values only if saved and valid.
## Acts strictly as an I/O coordinator: reads the file via `Globals.safe_load_config`,
## delegates parsing to `apply_volumes_from_config`, handles legacy migration, and
## syncs the resulting state to the AudioServer.
## :param path: Config file path (default: current_config_path).
## :type path: String
## :rtype: void
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


## Applies volume and mute values from an in-memory ConfigFile to AudioManager state.
## Pure GDScript helper with no disk I/O or decryption, intended for in-memory testing.
## Only well-typed values in the "audio" section are applied: volumes must be float or int,
## mute flags must be bool. Missing or invalid keys keep the bus's current value.
## Volumes are clamped to 0.0-1.0, and a bus at or below AUTO_MUTE_VOLUME_THRESHOLD is loaded
## muted, so a saved file can never start a bus unmuted at zero volume (Issue #1046).
## Note: state is updated via set_bus_state(), so volume_changed / mute_toggled are emitted
## for every bus. AudioServer is not touched; call apply_all_volumes() to sync buses.
## :param config: The ConfigFile instance containing the "audio" section.
## :type config: ConfigFile
## :rtype: void
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


## Save volumes to config (shared with other settings)
## :param path: Path to config file.
## :type path: String
## :rtype: void
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


## Helper to apply a single volume to a named bus
## :param bus_name: Name of the bus.
## :type bus_name: String
## :param volume: Volume level (0.0 to 1.0).
## :type volume: float
## :param muted: Mute flag.
## :type muted: bool
## :rtype: void
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
	_master_hold_token += 1  # Orphan any pending Master hold from a previous test
	SfxManager.cleanup_for_test()
