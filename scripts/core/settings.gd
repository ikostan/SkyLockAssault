## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## settings.gd
## Input settings singleton: Loads/saves InputMap events to preserve custom mappings.
## Supports keys, joypad buttons, and joypad axes (serialized).
## Autoload as "Settings".

extends Node

## Emitted when the current input device changes, see [method set_input_device].
## [param device]: The new device, [code]keyboard[/code] or [code]gamepad[/code].
signal input_device_changed(device: String)
## Emitted after [method rebind] or [method reset_to_defaults] changed the bindings in InputMap.
## Observers re-read what they need, for example the unbound-controls check in MainScene.
signal bindings_changed

# Change to v3 if you add another migration etc...
const LEGACY_MIGRATION_KEY: String = "settings_migrated_v2"
## One-time repair of saves broken by the shared arrow-key and left-stick defaults (see
## [method _migrate_input_layout_v3]).
const INPUT_LAYOUT_MIGRATION_KEY: String = "input_layout_migrated_v3"
## Run-once migration flags. Each is saved as [code]true[/code] under the config's
## [code][meta][/code] section, with its key as the name. The on-disk keys must never change,
## or existing saves would run their migrations again.
const MIGRATION_KEYS: Array[String] = [LEGACY_MIGRATION_KEY, INPUT_LAYOUT_MIGRATION_KEY]
## Input devices the player can pick in Key Mapping.
const INPUT_DEVICES: Array[String] = ["keyboard", "gamepad"]
const CONFIG_PATH: String = "user://settings.cfg"
const InputDefaults = preload("res://scripts/core/input_defaults.gd")
const InputLayoutMigration = preload("res://scripts/core/input_layout_migration.gd")

# Critical actions that must be bound for playable game.
const CRITICAL_ACTIONS: Array[String] = [
	"fire",
	"speed_up",
	"speed_down",
	"move_left",
	"move_right",
	"next_weapon",
	"pause",
	"ui_accept",
	"ui_up",
	"ui_down",
	"ui_left",
	"ui_right"
]

const ACTIONS: Array[String] = [
	"speed_up",
	"speed_down",
	"move_left",
	"move_right",
	"fire",
	"next_weapon",
	"pause",
	"ui_up",
	"ui_down",
	"ui_left",
	"ui_right",
	"ui_accept",
	"ui_focus_next",
	"ui_focus_prev",
]

## Gameplay/menu conflict groups and default bindings live in input_defaults.gd; these
## aliases keep the Settings API (Settings.DEFAULT_KEYBOARD, ...) unchanged for callers.
const GAMEPLAY_ACTIONS: Array[String] = InputDefaults.GAMEPLAY_ACTIONS
const MENU_ACTIONS: Array[String] = InputDefaults.MENU_ACTIONS
const DEFAULT_KEYBOARD: Dictionary = InputDefaults.KEYBOARD
const DEFAULT_GAMEPAD: Dictionary = InputDefaults.GAMEPAD

# Flag for legacy upgrade OR missing defaults (first-run, new actions)
var _needs_save: bool = false
# Set by apply_config_to_input_map when it skips a saved binding it cannot parse, so
# load_input_mappings re-saves and the corrupt entry does not come back on every start.
var _skipped_invalid_bindings: bool = false
# Device the UI shows bindings and prompts for. Written only by set_input_device(), so
# input_device_changed always fires; read it with get_input_device().
var _current_input_device: String = "keyboard"
# Keys from MIGRATION_KEYS whose migration has run. Restored from the config's [meta] section
# by load_input_mappings() and written back by save_input_mappings().
var _completed_migrations: Dictionary[String, bool] = {}


## Initializes the settings by loading input mappings.
## Triggers save if defaults were backfilled or legacy migration occurred.
func _ready() -> void:
	load_input_mappings()
	# Load last input device early to fix unbound warning on first load when
	# gamepad is saved preference.
	# Ensures has_unbound_critical_actions_for_current_device() uses correct device from config.
	load_last_input_device()
	# ONE-TIME MIGRATION: Fix legacy unbound/empty states from old saves (PR#409)
	# Runs only on first load after the unbound refactor.
	if not is_migration_done(LEGACY_MIGRATION_KEY):
		_migrate_legacy_unbound_states()
		Globals.log_message(
			"Legacy settings migration completed (first run after unbound refactor)",
			Globals.LogLevel.INFO
		)
	# ONE-TIME MIGRATION: Repair saves broken by the old shared arrow-key/left-stick defaults.
	if not is_migration_done(INPUT_LAYOUT_MIGRATION_KEY):
		_migrate_input_layout_v3()

	if _needs_save:
		save_input_mappings()
		_needs_save = false


## Shared helper: Adds missing keyboard/gamepad defaults to InputMap.
## Respects explicit user unbind (saved as [] in config) — so conflict-unbind stays unbound.
## Empty array = unbound.
## :param config: Loaded ConfigFile for unbound checks.
## :rtype: bool
func _add_missing_defaults(config: ConfigFile) -> bool:
	var changed: bool = false

	for action: String in ACTIONS:
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		var has_keyboard: bool = false
		var has_gamepad: bool = false
		for ev: InputEvent in events:
			var ev_device: String = InputEventCodec.get_event_device_type(ev)
			if ev_device == "keyboard":
				has_keyboard = true
			elif ev_device == "gamepad":
				has_gamepad = true

		# ── Explicitly unbound check (handles [] and non-empty) ──
		var explicitly_unbound_keyboard: bool = false
		var explicitly_unbound_gamepad: bool = false
		if config.has_section_key("input", action):
			var saved_val: Variant = config.get_value("input", action)
			if saved_val is Array or saved_val is PackedStringArray:
				if saved_val.is_empty():
					explicitly_unbound_keyboard = true
					explicitly_unbound_gamepad = true
				else:
					var has_saved_key: bool = false
					var has_saved_joy: bool = false
					for item: Variant in saved_val:
						if item is String:
							if item.begins_with("key:") or item.begins_with("lkey:"):
								has_saved_key = true
							elif item.begins_with("joybtn:") or item.begins_with("joyaxis:"):
								has_saved_joy = true
					explicitly_unbound_keyboard = not has_saved_key
					explicitly_unbound_gamepad = not has_saved_joy

		# === Keyboard defaults ===
		if not has_keyboard and not explicitly_unbound_keyboard:
			var key_default: InputEvent = InputDefaults.make_event(action, "keyboard")
			if key_default and _add_default_event(config, action, key_default, "keyboard"):
				changed = true

		# === Gamepad defaults ===
		if not has_gamepad and not explicitly_unbound_gamepad:
			var pad_default: InputEvent = InputDefaults.make_event(action, "gamepad")
			if pad_default and _add_default_event(config, action, pad_default, "gamepad"):
				changed = true

	return changed


## Adds a backfilled default event to an action unless a saved binding already uses it.
##
## A default is backfilled when the action has no binding for a device, for example after its
## saved binding was rejected as corrupt. If another action's saved binding already uses the
## same input (the player moved that key there), adding the default would make both actions
## fire on one input. The action is left unbound for that device instead, a warning is logged,
## and the player can rebind it from the key mapping menu.
##
## Only bindings loaded from the config count as owners. Inputs that come only from the
## project's built-in InputMap, where gameplay and UI actions may share keys, are not treated
## as conflicts, so a first run with no saved settings still gets every default.
##
## [param config]: Loaded ConfigFile, used to tell saved bindings from built-in ones.
## [param action]: Action that is missing a binding for the device.
## [param event]: The default event for that action and device.
## [param device]: Device name used in log messages, keyboard or gamepad.
## Returns [code]true[/code] if the event was added.
func _add_default_event(
	config: ConfigFile, action: String, event: InputEvent, device: String
) -> bool:
	var conflicts: Array[String] = []
	for other: String in get_conflicting_actions(event, action):
		if config.has_section_key("input", other):
			conflicts.append(other)
	if not conflicts.is_empty():
		Globals.log_message(
			(
				"Not restoring default %s binding for %s: already used by %s"
				% [device, action, str(conflicts)]
			),
			Globals.LogLevel.WARNING
		)
		return false

	InputMap.action_add_event(action, event)
	Globals.log_message(
		"Added missing default " + device + " for " + action, Globals.LogLevel.DEBUG
	)
	return true


## Returns true if any critical action has zero events.
## :rtype: bool
func has_unbound_critical_actions() -> bool:
	for action: String in CRITICAL_ACTIONS:
		if InputMap.action_get_events(action).is_empty():
			return true
	return false


## Returns the pause binding label in ALL CAPS for the current input device.
func get_pause_binding_label() -> String:
	return get_pause_binding_label_for_device(_current_input_device)


## Returns the current input device, [code]keyboard[/code] or [code]gamepad[/code].
func get_input_device() -> String:
	return _current_input_device


## Sets the current input device and emits [signal input_device_changed] if it changed.
##
## The only writer of the device. It does not save it: Key Mapping, where the player picks the
## device, also calls [method save_last_input_device].
##
## [param device]: [code]keyboard[/code] or [code]gamepad[/code]. Any other value is logged
## and ignored.
func set_input_device(device: String) -> void:
	if device not in INPUT_DEVICES:
		Globals.log_message(
			"Ignoring unknown input device: '%s'" % device, Globals.LogLevel.WARNING
		)
		return
	if device == _current_input_device:
		return
	_current_input_device = device
	input_device_changed.emit(device)


## Determine if the run-once migration has completed.
##
## Returns true if the run-once migration saved under the specified key has run.
##
## [param key]: One of [constant MIGRATION_KEYS].
## Returns true if the migration under the key has completed, otherwise false.
func is_migration_done(key: String) -> bool:
	return _completed_migrations.get(key, false)


## Records that the migration saved under [param key] has run. The flag is written to disk on
## the next [method save_input_mappings].
func _mark_migration_done(key: String) -> void:
	_completed_migrations[key] = true


## Determine if the given input event is bound to any action in InputMap.
##
## [param event]: The input event to check against all actions.
## Returns true if the event is bound to any action, false otherwise.
func is_event_bound(event: InputEvent) -> bool:
	for action: String in InputMap.get_actions():
		if InputMap.event_is_action(event, action):
			return true
	return false


## Removes `event` from all actions listed in `conflicts`.
## Used on load to preserve the loaded mapping and unbind duplicates elsewhere, and by
## [method rebind] when the player confirms a conflicting remap.
## :param event: The event to remove from conflicting actions.
## :param conflicts: Action names that currently contain the same event. Unknown names are
## skipped.
## :rtype: void
func _remove_event_from_conflicts(event: InputEvent, conflicts: Array[String]) -> void:
	for other_action: String in conflicts:
		if not InputMap.has_action(other_action):
			continue
		var events: Array[InputEvent] = InputMap.action_get_events(other_action)
		for existing: InputEvent in events:
			if InputEventCodec.events_match(existing, event):
				InputMap.action_erase_event(other_action, existing)
				break


## Deserializes a string to an InputEvent and adds it to the specified action.
## Handles various serialized formats and logs warnings for invalid data.
## Skips and warns on malformed serialized strings, including invalid int/float values,
## with robust error handling.
## :param action: Target action.
## :type action: String
## :param serialized: Serialized event string.
## :type serialized: String
## :rtype: void
func _deserialize_and_add(action: String, serialized: String) -> void:
	# Use the shared logic from deserialize_event
	var ev: InputEvent = InputEventCodec.deserialize_event(serialized)

	if ev != null:
		InputMap.action_add_event(action, ev)
	else:
		# If it's not a valid prefixed string, it fails here.
		# No more "elif serialized.is_valid_int()" legacy fallback.
		Globals.log_message(
			"Invalid or unknown serialized format: " + serialized, Globals.LogLevel.WARNING
		)


## Binds an event to an action, replacing the action's binding for the same device.
##
## Binds an event to an action, replacing the action's binding for the same device. The first
## event of the action on the event's device is removed so the other device keeps its binding.
## Before that, the same input is removed from each action in unbind_from. Does not save;
## caller saves with save_input_mappings. Emits bindings_changed.
##
## [param action]: Action to bind, e.g. "fire". Must exist in InputMap.
## [param event]: The new key, joypad button or joypad axis event.
## [param unbind_from]: Actions that lose this exact input first. Empty by default, which
## leaves other actions untouched.
func rebind(action: String, event: InputEvent, unbind_from: Array[String] = []) -> void:
	if event == null or not InputMap.has_action(action):
		Globals.log_message(
			"Ignoring rebind of '%s': unknown action or null event" % action,
			Globals.LogLevel.WARNING
		)
		return
	var device: String = InputEventCodec.get_event_device_type(event)
	if device not in INPUT_DEVICES:
		Globals.log_message(
			"Ignoring rebind of '%s': not a keyboard or gamepad event" % action,
			Globals.LogLevel.WARNING
		)
		return

	_remove_event_from_conflicts(event, unbind_from)

	for old_ev: InputEvent in InputMap.action_get_events(action):
		if InputEventCodec.get_event_device_type(old_ev) == device:
			InputMap.action_erase_event(action, old_ev)
			break  # only the first binding for this device, as the remap button shows it

	InputMap.action_add_event(action, event)
	bindings_changed.emit()


## Resets input mappings to defaults for the specified device type.
##
## Fully erases all events for the specified device type and forces defaults to fix duplicates.
## Saves the result and emits [signal bindings_changed].
##
## [param device_type]: The target device type, accepting either keyboard or gamepad.
func reset_to_defaults(device_type: String) -> void:
	if device_type not in INPUT_DEVICES:
		return
	for action: String in ACTIONS:
		# FULL erase for the device
		# (prevents cross-action duplicates like Space on FIRE + NEXT_WEAPON)
		var events: Array[InputEvent] = InputMap.action_get_events(action).duplicate()
		for ev: InputEvent in events:
			if InputEventCodec.get_event_device_type(ev) == device_type:
				InputMap.action_erase_event(action, ev)

		# Add fresh defaults
		var nev: InputEvent = InputDefaults.make_event(action, device_type)
		if nev:
			InputMap.action_add_event(action, nev)

	save_input_mappings()
	Globals.log_message(
		"🔄 Full RESET for " + device_type + " — defaults forced!", Globals.LogLevel.INFO
	)
	bindings_changed.emit()


## Finds every other managed action that already uses the exact event.
##
## Only actions listed in [constant ACTIONS] are checked. Conflicts are scoped by group, and
## built-in actions are ignored. With an empty or unknown action, every managed action is
## checked.
##
## [param event]: The event the player just pressed, compared with
## [method InputEventCodec.events_match].
## [param exclude_action]: The action being remapped, skipped during the check.
## Returns the conflicting action names, e.g. [code]["fire"][/code], or an empty array.
func get_conflicting_actions(event: InputEvent, exclude_action: String = "") -> Array[String]:
	var conflicts: Array[String] = []
	var scope: Array[String] = InputDefaults.conflict_scope(exclude_action, ACTIONS)
	for action: String in scope:
		if action == exclude_action:
			continue
		for ev: InputEvent in InputMap.action_get_events(action):
			if InputEventCodec.events_match(ev, event):
				conflicts.append(action)
				break  # one match per action is enough
	return conflicts


## Return the pause binding label in ALL CAPS for the specific device.
##
## Iterates through InputMap events for the pause action and finds the first matching event for
## the specified device type, returning its label in uppercase or a fallback.
##
## [param device_type]: The target device type, such as keyboard or gamepad.
## Returns The uppercase string label of the pause input binding for the device.
func get_pause_binding_label_for_device(device_type: String) -> String:
	var events: Array[InputEvent] = InputMap.action_get_events("pause")
	if events.is_empty():
		return "UNBOUND"

	for ev: InputEvent in events:
		if InputEventCodec.get_event_device_type(ev) == device_type:
			return InputEventCodec.get_event_label(ev).to_upper()

	# Fallback
	return InputEventCodec.get_event_label(events[0]).to_upper()


## Returns true if there is at least one unbound critical action for the currently selected device.
## This respects [method get_input_device].
func has_unbound_critical_actions_for_current_device() -> bool:
	var preferred: String = _current_input_device
	for action: String in CRITICAL_ACTIONS:
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		if events.is_empty():
			# continue  # action is unbound, but we check per device
			return true  # unbound for all devices, including current

		var has_binding_for_device: bool = false
		for ev: InputEvent in events:
			if InputEventCodec.get_event_device_type(ev) == preferred:
				has_binding_for_device = true
				break

		if not has_binding_for_device:
			return true  # unbound for the current device

	return false


## One-time migration for legacy configs.
## Forces defaults for CRITICAL_ACTIONS that are unbound/empty.
## Ensures "Unbound" labels appear correctly for UI actions.
## Sets the run-once flag to prevent re-run (works even if called directly in tests).
## :rtype: void
func _migrate_legacy_unbound_states() -> void:
	var changed: bool = false
	for action: String in CRITICAL_ACTIONS:
		if InputMap.action_get_events(action).is_empty():
			# Force keyboard and gamepad defaults
			for device: String in ["keyboard", "gamepad"]:
				var nev: InputEvent = InputDefaults.make_event(action, device)
				if nev:
					InputMap.action_add_event(action, nev)
					changed = true
					Globals.log_message(
						"Migrated legacy unbound: %s (%s default)" % [action, device],
						Globals.LogLevel.INFO
					)

	if changed:
		save_input_mappings()  # Persist the migration

	# Set the flag HERE (so direct calls in tests work, and _ready() is consistent)
	_mark_migration_done(LEGACY_MIGRATION_KEY)


## One-time repair for saves written before the menu/gameplay input split.
##
## Delegates to [code]input_layout_migration.gd[/code], sets the run-once flag and always flags a
## save, even when no binding changed: [method save_input_mappings] is what persists the flag,
## and without it the migration would run again on every launch until something else saved.
func _migrate_input_layout_v3() -> void:
	var changed: bool = InputLayoutMigration.migrate(self)
	_mark_migration_done(INPUT_LAYOUT_MIGRATION_KEY)
	_needs_save = true
	Globals.log_message(
		"Migration v3 done (%s)" % ("bindings repaired" if changed else "no changes"),
		Globals.LogLevel.DEBUG
	)


## Loads input mappings from config, overriding project defaults only if saved.
##
## Acts strictly as an I/O coordinator by loading the file via Globals.safe_load_config,
## applying mappings via apply_config_to_input_map, and backfilling missing defaults.
##
## [param path]: The file path used to load the configuration.
## [param actions]: The array of action names to apply.
func load_input_mappings(path: String = CONFIG_PATH, actions: Array[String] = ACTIONS) -> void:
	# 1. Disk I/O: Read and decrypt configuration file
	var load_data: Dictionary = Globals.safe_load_config(path)
	var config: ConfigFile = load_data["config"]
	var err: int = load_data["err"]

	if load_data.get("is_legacy", false):
		Globals.log_message(
			"Legacy plaintext input mappings found. Migration required.", Globals.LogLevel.INFO
		)
		_needs_save = true

	if err != OK and err != ERR_FILE_NOT_FOUND:
		Globals.log_message(
			"Error loading settings file at " + path + ": " + str(err), Globals.LogLevel.ERROR
		)

	# 2. Metadata restoring: a flag missing from the config leaves the in-memory flag as is.
	for key: String in MIGRATION_KEYS:
		var saved_flag: Variant = config.get_value("meta", key, false)
		if saved_flag is bool and saved_flag:
			_mark_migration_done(key)
			Globals.log_message(
				"Restored migration flag '%s' from config." % key, Globals.LogLevel.DEBUG
			)

	# 3. Apply memory configuration to InputMap & collect conflict resolution status
	var conflicts_resolved: bool = apply_config_to_input_map(config, actions)

	# 4. Backfill missing defaults and aggregate save requirements
	var defaults_added: bool = _add_missing_defaults(config)
	_needs_save = conflicts_resolved or defaults_added or _skipped_invalid_bindings or _needs_save


## Saves current InputMap events to config as an array per action.
##
## Safely pre-loads the config file to preserve other sections during the save operation,
## logging an error if loading fails.
##
## [param path]: The target file path where the configuration is saved.
## [param actions]: The list of action names whose events will be serialized and saved.
func save_input_mappings(path: String = CONFIG_PATH, actions: Array[String] = ACTIONS) -> void:
	# Safely pre-load the config to preserve other sections during the save
	var load_data: Dictionary = Globals.safe_load_config(path)
	var config: ConfigFile = load_data["config"]
	var err: int = load_data["err"]

	if err != OK and err != ERR_FILE_NOT_FOUND:
		Globals.log_message(
			"Failed to load input config for save: " + str(err), Globals.LogLevel.ERROR
		)
		return

	for key: String in MIGRATION_KEYS:
		if is_migration_done(key):
			config.set_value("meta", key, true)

	for action: String in actions:
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		var serials: Array[String] = []
		for ev: InputEvent in events:
			var s: String = InputEventCodec.serialize_event(ev)
			if not s.is_empty():
				serials.append(s)
		config.set_value("input", action, serials)

	err = Globals.save_config(config, path)

	if err != OK:
		Globals.log_message(
			(
				"🚨 ENCRYPTION FAILURE: Failed to save encrypted input mappings to "
				+ path
				+ " (Error: "
				+ str(err)
				+ ")"
			),
			Globals.LogLevel.ERROR
		)
	else:
		Globals.log_message("🔒 Encrypted input mappings saved to " + path, Globals.LogLevel.DEBUG)


## Saves the last selected input device to config.
##
## Saves the last selected input device to the configuration file after validating the device
## type.
##
## [param device]: The input device type, accepted values are keyboard or gamepad.
func save_last_input_device(device: String) -> void:
	if device not in INPUT_DEVICES:
		return

	# Use the helper to safely pre-load
	var load_data: Dictionary = Globals.safe_load_config(CONFIG_PATH)
	var config: ConfigFile = load_data["config"]
	var err: int = load_data["err"]

	# GUARD: Prevent overwriting the entire file if it exists but failed to load
	if err != OK and err != ERR_FILE_NOT_FOUND:
		Globals.log_message(
			"Failed to load input config for save_last_input_device: " + str(err),
			Globals.LogLevel.ERROR
		)
		return

	config.set_value("input", "last_input_device", device)

	# Shared save helper: encrypted, or plaintext if the key is empty (#1145)
	err = Globals.save_config(config, CONFIG_PATH)

	if err != OK:
		Globals.log_message(
			(
				"🚨 ENCRYPTION FAILURE: Failed to save encrypted last input device (Error: "
				+ str(err)
				+ ")"
			),
			Globals.LogLevel.ERROR
		)
	else:
		Globals.log_message("🔒 Encrypted last input device saved.", Globals.LogLevel.DEBUG)


## Loads the last selected input device and makes it current through [method set_input_device].
## A missing, unreadable or unknown saved value selects [code]keyboard[/code].
func load_last_input_device() -> void:
	# Use the helper to safely load
	var load_data: Dictionary = Globals.safe_load_config(CONFIG_PATH)
	var config: ConfigFile = load_data["config"]
	var err: int = load_data["err"]

	var device: String = "keyboard"
	if err == OK and config.has_section_key("input", "last_input_device"):
		var saved: Variant = config.get_value("input", "last_input_device")
		if saved is String and saved in INPUT_DEVICES:
			device = saved
	set_input_device(device)


## Applies input mapping definitions from an in-memory ConfigFile to the global InputMap.
##
## Performs no file I/O and does not modify the [code]_needs_save[/code] flag, so it can be
## tested without touching disk. It is not side-effect free: for every action found in the
## config it erases and re-adds events in the global InputMap, unbinds duplicate events from
## other actions, and logs warnings through Globals. It also records whether any saved
## binding was skipped as invalid, which [method load_input_mappings] uses to re-save the
## cleaned bindings.
##
## [param config]: Loaded ConfigFile to read the [code]input[/code] section from. A
## [code]null[/code] config is a no-op that returns [code]false[/code].
## [param actions]: Action names to apply. Defaults to [constant ACTIONS].
## Returns [code]true[/code] if any conflicting bindings were removed from other actions.
func apply_config_to_input_map(config: ConfigFile, actions: Array[String] = ACTIONS) -> bool:
	_skipped_invalid_bindings = false
	if config == null:
		return false

	var conflicts_resolved: bool = false

	for action: String in actions:
		if not config.has_section_key("input", action):
			continue

		var raw_val: Variant = config.get_value("input", action)
		if not (
			raw_val is Array or raw_val is PackedStringArray or raw_val is String or raw_val is int
		):
			Globals.log_message(
				"Unsupported config value type for action '" + action + "': skipped",
				Globals.LogLevel.WARNING
			)
			continue  # Preserve existing bindings for invalid types

		var serialized_events: Array[String] = _normalize_input_value(raw_val, action)
		InputMap.action_erase_events(action)

		for serialized: String in serialized_events:
			var ev: InputEvent = InputEventCodec.deserialize_event(serialized)
			if ev == null:
				# _add_missing_defaults restores the device default if nothing else binds it.
				Globals.log_message(
					"Skipping invalid saved binding for " + action + ": " + serialized,
					Globals.LogLevel.WARNING
				)
				_skipped_invalid_bindings = true
				continue

			var already_present := false
			for existing_ev in InputMap.action_get_events(action):
				if InputEventCodec.events_match(existing_ev, ev):
					already_present = true
					break

			if already_present:
				continue

			var conflicts: Array[String] = get_conflicting_actions(ev, action)
			if not conflicts.is_empty():
				Globals.log_message(
					(
						"Skipping duplicate event for "
						+ action
						+ " (conflicts: "
						+ str(conflicts)
						+ ")"
					),
					Globals.LogLevel.WARNING
				)
				_remove_event_from_conflicts(ev, conflicts)
				conflicts_resolved = true

			InputMap.action_add_event(action, ev)

	return conflicts_resolved


## Helper function to convert raw ConfigFile values (Array, String, or int) into serialized strings.
func _normalize_input_value(value: Variant, action: String) -> Array[String]:
	var serials: Array[String] = []
	if value is Array or value is PackedStringArray:
		for item: Variant in value:
			if item is String:
				serials.append(item)
			else:
				Globals.log_message(
					"Non-string item in array for action '" + action + "': skipped",
					Globals.LogLevel.WARNING
				)
	elif value is String:
		serials.append(value)
	elif value is int:
		serials.append("key:" + str(value))
	return serials


# ==============================================================================
# TEST SUPPORT HELPERS (Do not use in production code)
# ==============================================================================


## Backfills missing action defaults into InputMap for testing.
##
## Public wrapper for backfilling missing action defaults into InputMap. Intended exclusively
## for test suites to prevent direct access to private methods.
##
## [param config]: The configuration file containing action defaults to backfill.
## Returns true if any missing defaults were added to InputMap, or false if nothing
## was missing.
func backfill_missing_defaults(config: ConfigFile) -> bool:
	return _add_missing_defaults(config)


## Resets the internal save flag during test setup or teardown.
##
## This function is intended for testing purposes only. It allows direct manipulation of the
## internal save state flag.
##
## [param value]: The boolean value to assign to the internal save state flag.
func set_needs_save_for_test(value: bool = false) -> void:
	_needs_save = value


## Marks a run-once migration as done or not done, so a test can force or skip it.
##
## Test only. Production code marks migrations through the migrations themselves.
##
## [param key]: One of [constant MIGRATION_KEYS].
## [param done]: [code]true[/code] to mark it done, [code]false[/code] to make it run again.
func set_migration_done_for_test(key: String, done: bool) -> void:
	if done:
		_completed_migrations[key] = true
	else:
		_completed_migrations.erase(key)


## Returns current state of _needs_save for test assertions.
##
## Test only function to check the current state of _needs_save.
## Returns the current boolean value of _needs_save
func needs_save() -> bool:
	return _needs_save
