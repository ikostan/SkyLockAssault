## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
# settings.gd
# Input settings singleton: Loads/saves InputMap events to preserve custom mappings.
# Supports keys, joypad buttons, and joypad axes (serialized).
# Autoload as "Settings".

extends Node

# Change to v3 if you add another migration etc...
const LEGACY_MIGRATION_KEY: String = "settings_migrated_v2"
const CONFIG_PATH: String = "user://settings.cfg"

## Critical actions that must be bound for playable game.
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
]
# New: Default keyboard mappings.
const DEFAULT_KEYBOARD: Dictionary = {
	"speed_up": KEY_W,
	"speed_down": KEY_X,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"fire": KEY_SPACE,
	"next_weapon": KEY_Q,
	"pause": KEY_ESCAPE,
	"ui_up": KEY_UP,
	"ui_down": KEY_DOWN,
	"ui_left": KEY_LEFT,
	"ui_right": KEY_RIGHT,
	"ui_accept": KEY_ENTER,
}
# New: Default gamepad mappings (assumes Xbox layout; adjust if needed).
const DEFAULT_GAMEPAD: Dictionary = {
	# "speed_up": {"type": "axis", "axis": JOY_AXIS_TRIGGER_RIGHT, "value": 1.0},  # Throttle up.
	# "speed_down": {"type": "axis", "axis": JOY_AXIS_TRIGGER_LEFT, "value": 1.0},  # Throttle down.
	"speed_up": {"type": "axis", "axis": JOY_AXIS_RIGHT_Y, "value": -1.0},  # Right Stick (Up)
	"speed_down": {"type": "axis", "axis": JOY_AXIS_RIGHT_Y, "value": 1.0},  # Right Stick (Down)
	"move_left": {"type": "axis", "axis": JOY_AXIS_LEFT_X, "value": -1.0},
	"move_right": {"type": "axis", "axis": JOY_AXIS_LEFT_X, "value": 1.0},
	"fire": {"type": "button", "button": JOY_BUTTON_A},
	"next_weapon": {"type": "button", "button": JOY_BUTTON_Y},
	"pause": {"type": "button", "button": JOY_BUTTON_START},
	"ui_accept": {"type": "button", "button": JOY_BUTTON_B},
	"ui_up": {"type": "button", "button": JOY_BUTTON_DPAD_UP},
	"ui_down": {"type": "button", "button": JOY_BUTTON_DPAD_DOWN},
	"ui_left": {"type": "button", "button": JOY_BUTTON_DPAD_LEFT},
	"ui_right": {"type": "button", "button": JOY_BUTTON_DPAD_RIGHT},
}

# Flag for legacy upgrade OR missing defaults (first-run, new actions)
var _needs_save: bool = false


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
	if not Globals.has_meta(LEGACY_MIGRATION_KEY):
		_migrate_legacy_unbound_states()
		Globals.set_meta(LEGACY_MIGRATION_KEY, true)
		Globals.log_message(
			"Legacy settings migration completed (first run after unbound refactor)",
			Globals.LogLevel.INFO
		)

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
			if ev is InputEventKey:
				has_keyboard = true
			elif ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
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
							if item.begins_with("key:"):
								has_saved_key = true
							elif item.begins_with("joybtn:") or item.begins_with("joyaxis:"):
								has_saved_joy = true
					explicitly_unbound_keyboard = not has_saved_key
					explicitly_unbound_gamepad = not has_saved_joy

		# === Keyboard defaults ===
		if not has_keyboard and DEFAULT_KEYBOARD.has(action) and not explicitly_unbound_keyboard:
			var nev: InputEventKey = InputEventKey.new()
			nev.physical_keycode = DEFAULT_KEYBOARD[action]
			InputMap.action_add_event(action, nev)
			changed = true
			Globals.log_message(
				"Added missing default keyboard for " + action, Globals.LogLevel.DEBUG
			)

		# === Gamepad defaults ===
		if not has_gamepad and DEFAULT_GAMEPAD.has(action) and not explicitly_unbound_gamepad:
			var def: Dictionary = DEFAULT_GAMEPAD[action]
			var nev: InputEvent = null
			match def.get("type"):
				"button":
					var button := InputEventJoypadButton.new()
					button.button_index = def["button"]
					button.device = -1
					nev = button
				"axis":
					var motion := InputEventJoypadMotion.new()
					motion.axis = def["axis"]
					motion.axis_value = def["value"]
					motion.device = -1
					nev = motion
			if nev:
				InputMap.action_add_event(action, nev)
				changed = true
				Globals.log_message(
					"Added missing default gamepad for " + action, Globals.LogLevel.DEBUG
				)

	return changed


## Returns true if any critical action has zero events.
## :rtype: bool
func has_unbound_critical_actions() -> bool:
	for action: String in CRITICAL_ACTIONS:
		if InputMap.action_get_events(action).is_empty():
			return true
	return false


## Returns the pause binding label in ALL CAPS.
## Strictly follows the last selected device in Key Mapping menu.
func get_pause_binding_label() -> String:
	return get_pause_binding_label_for_device(Globals.current_input_device)


## Returns true if the given event is bound to any action in InputMap.
## :param event: Input event to check.
## :type event: InputEvent
## :rtype: bool
func is_event_bound(event: InputEvent) -> bool:
	for action: String in InputMap.get_actions():
		if InputMap.event_is_action(event, action):
			return true
	return false


## Serializes an InputEvent to string for ConfigFile storage.
## Handles Key (no device), JoypadButton, and JoypadMotion (with device).
## :param ev: The event to serialize.
## :type ev: InputEvent
## :rtype: String
func serialize_event(ev: InputEvent) -> String:
	if ev is InputEventKey:
		return "key:" + str(ev.physical_keycode)

	if ev is InputEventJoypadButton:
		return "joybtn:" + str(ev.button_index) + ":" + str(ev.device)

	if ev is InputEventJoypadMotion:
		return "joyaxis:" + str(ev.axis) + ":" + str(ev.axis_value) + ":" + str(ev.device)

	return ""


## Loads input mappings from config, overriding project defaults only if saved.
## Handles various formats for backward compatibility and adds defaults if necessary.
## Proceeds even if no file to add defaults where events missing.
## Skips adding deserialized event if it matches any existing in other actions (per device).
## :param path: Config file path (default: CONFIG_PATH).
## :type path: String
## :param actions: Actions to load (default: ACTIONS).
## :type actions: Array[String]
## :rtype: void
func load_input_mappings(path: String = CONFIG_PATH, actions: Array[String] = ACTIONS) -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(path)
	if err != OK and err != ERR_FILE_NOT_FOUND:  # Handle errors except missing file
		Globals.log_message(
			"Error loading settings file at " + path + ": " + str(err), Globals.LogLevel.ERROR
		)
		# Do not return: proceed to defaults for corrupt files (EC-05).
		# Ensures fallback to defaults on parse errors.

	if err == ERR_FILE_NOT_FOUND:
		Globals.log_message(
			"No settings file found at " + path + "—adding defaults where missing.",
			Globals.LogLevel.INFO
		)

	for action: String in actions:
		var has_saved: bool = config.has_section_key("input", action)
		if has_saved:
			var value: Variant = config.get_value("input", action)
			var serialized_events: Array[String] = []

			# ── ROBUST ARRAY HANDLING (FIX FOR PackedStringArray) ─────────────────────
			# FIXED: Explicit type guard to skip non-string items (e.g. int 999 from EC-01 test).
			# This prevents crash on corrupted/malformed config files
			# (real-world case: disk errors, manual edits).
			# Log warning for visibility in console/tests.
			# Keeps defaults backfill intact (as asserted in EC-01).
			# Minimal change: only affects invalid data paths, no impact on normal saves.
			if value is Array or value is PackedStringArray:
				for item: Variant in value:
					if item is String:
						serialized_events.append(item)
					else:
						Globals.log_message(
							"Non-string item in array for action '" + action + "': skipped",
							Globals.LogLevel.WARNING
						)

			# ── Backward compatibility: Scalar string or int → single serialized ─────
			elif value is String:
				serialized_events = [value]  # Treat as one serialized event
			elif value is int:
				serialized_events = ["key:" + str(value)]  # Legacy keycode scalar

			# ── Deserialize and add ───────────────────────────────────────────────────
			# Erase project defaults first (to avoid mixing with saved).
			InputMap.action_erase_events(action)

			for serialized: String in serialized_events:
				var ev: InputEvent = deserialize_event(serialized)
				if ev == null:
					Globals.log_message(
						"Invalid serialized event for " + action + ": " + serialized,
						Globals.LogLevel.WARNING
					)
					continue

				var already_present := false
				for existing_ev in InputMap.action_get_events(action):
					if events_match(existing_ev, ev):
						already_present = true
						break

				if already_present:
					Globals.log_message(
						"Skipping intra-action duplicate for " + action, Globals.LogLevel.DEBUG
					)
					continue  # It's already in this action, skip to the next one

				# ── NEW: Skip if duplicate in other actions (per device) ──────────────
				# Prevents cross-action duplicates from corrupted config.
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
					#continue
					# prefer the loaded mapping and remove it from conflicting actions
					# (for the same device type), then mark _needs_save
					_remove_event_from_conflicts(ev, conflicts)
					_needs_save = true

				InputMap.action_add_event(action, ev)

	# ── Backfill missing defaults (after loading/erasing) ─────────────────────────
	_needs_save = _add_missing_defaults(config) or _needs_save


## Removes `event` from all actions listed in `conflicts`.
## Used on load to preserve the loaded mapping and unbind duplicates elsewhere.
## :param event: The event to remove from conflicting actions.
## :param conflicts: Action names that currently contain the same event.
## :rtype: void
func _remove_event_from_conflicts(event: InputEvent, conflicts: Array[String]) -> void:
	for other_action: String in conflicts:
		var events: Array[InputEvent] = InputMap.action_get_events(other_action)
		for existing: InputEvent in events:
			if events_match(existing, event):
				InputMap.action_erase_event(other_action, existing)
				break


## Deserializes a string back to InputEvent.
## Handles "key:code", "joybtn:index:device", "joyaxis:axis:value:device".
## :param serialized: The string to deserialize.
## :type serialized: String
## :rtype: InputEvent|null
func deserialize_event(serialized: String) -> InputEvent:
	var parts: PackedStringArray = serialized.split(":", true)
	if parts.is_empty():
		return null

	match parts[0]:
		"key":
			if parts.size() == 2:
				var code: int = parts[1].to_int()
				if code > 0:
					var ev: InputEventKey = InputEventKey.new()
					ev.physical_keycode = code
					return ev
		"joybtn":
			if parts.size() == 3:
				var index: int = parts[1].to_int()
				var device: int = parts[2].to_int()
				var ev: InputEventJoypadButton = InputEventJoypadButton.new()
				ev.button_index = index
				ev.device = device
				return ev
		"joyaxis":
			if parts.size() == 4:
				var axis: int = parts[1].to_int()
				var value: float = parts[2].to_float()
				var device: int = parts[3].to_int()
				var ev: InputEventJoypadMotion = InputEventJoypadMotion.new()
				ev.axis = axis
				ev.axis_value = value
				ev.device = device
				return ev
	return null


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
	if serialized.begins_with("key:"):
		var kc_str: String = serialized.substr(4)
		if kc_str.is_empty() or not kc_str.is_valid_int():
			Globals.log_message("Invalid key serialized: " + serialized, Globals.LogLevel.WARNING)
			return
		var kc: int = int(kc_str)
		var nev: InputEventKey = InputEventKey.new()
		nev.physical_keycode = kc
		InputMap.action_add_event(action, nev)
	elif serialized.begins_with("joybtn:"):
		var parts: PackedStringArray = serialized.split(":")
		var error: String = ""
		if parts.size() < 2:
			error = "insufficient parts"
		elif not parts[1].is_valid_int():
			error = "invalid button index"
		else:
			var btn: int = int(parts[1])
			var dev: int = -1
			if parts.size() >= 3:
				if not parts[2].is_empty():
					if not parts[2].is_valid_int():
						error = "invalid device"
					else:
						dev = int(parts[2])
			if error == "":
				var nev: InputEventJoypadButton = InputEventJoypadButton.new()
				nev.button_index = btn
				nev.device = dev
				InputMap.action_add_event(action, nev)
		if error != "":
			Globals.log_message(
				"Invalid joybtn serialized: " + serialized + " (" + error + ")",
				Globals.LogLevel.WARNING
			)
			return
	elif serialized.begins_with("joyaxis:"):
		var parts: PackedStringArray = serialized.split(":")
		var error: String = ""
		if parts.size() < 3:
			error = "insufficient parts"
		elif not parts[1].is_valid_int() or not parts[2].is_valid_float():
			error = "invalid axis or axis_value"
		else:
			var axis: int = int(parts[1])
			var aval: float = float(parts[2])
			var dev: int = -1
			if parts.size() >= 4:
				if not parts[3].is_empty():
					if not parts[3].is_valid_int():
						error = "invalid device"
					else:
						dev = int(parts[3])
			if error == "":
				var nev: InputEventJoypadMotion = InputEventJoypadMotion.new()
				nev.axis = axis
				nev.axis_value = aval
				nev.device = dev
				InputMap.action_add_event(action, nev)
		if error != "":
			Globals.log_message(
				"Invalid joyaxis serialized: " + serialized + " (" + error + ")",
				Globals.LogLevel.WARNING
			)
			return
	elif serialized.is_valid_int():
		var kc: int = int(serialized)
		var nev: InputEventKey = InputEventKey.new()
		nev.physical_keycode = kc
		InputMap.action_add_event(action, nev)
		_needs_save = true  # Ensure save if we hit this old case
	else:
		Globals.log_message("Unknown serialized prefix: " + serialized, Globals.LogLevel.WARNING)
		return


## Saves current InputMap events to config (all per action as array).
## :param path: Config file path (default: CONFIG_PATH).
## :type path: String
## :param actions: Actions to save (default: ACTIONS).
## :type actions: Array[String]
## :rtype: void
func save_input_mappings(path: String = CONFIG_PATH, actions: Array[String] = ACTIONS) -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(path)  # Load existing to preserve other sections
	if err != OK and err != ERR_FILE_NOT_FOUND:
		Globals.log_message(
			"Failed to load input config for save: " + str(err), Globals.LogLevel.ERROR
		)
		return

	# Persist legacy migration flag for next runs/tests.
	if (
		Globals.has_meta(LEGACY_MIGRATION_KEY)
		and bool(Globals.get_meta(LEGACY_MIGRATION_KEY)) == true
	):
		config.set_value("meta", LEGACY_MIGRATION_KEY, true)

	for action: String in actions:
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		var serials: Array[String] = []
		for ev: InputEvent in events:
			var s: String = serialize_event(ev)
			if not s.is_empty():
				serials.append(s)
		config.set_value("input", action, serials)  # Set even if empty

	err = config.save(path)
	if err != OK:
		Globals.log_message("Failed to save input mappings: " + str(err), Globals.LogLevel.ERROR)
	else:
		Globals.log_message("Input mappings saved.", Globals.LogLevel.DEBUG)


## Resets input mappings to defaults for the specified device type.
## Now fully erases ALL events for the device + forces defaults (fixes duplicates).
## :param device_type: "keyboard" or "gamepad"
## :type device_type: String
## :rtype: void
func reset_to_defaults(device_type: String) -> void:
	if device_type not in ["keyboard", "gamepad"]:
		return
	for action: String in ACTIONS:
		# FULL erase for the device
		# (prevents cross-action duplicates like Space on FIRE + NEXT_WEAPON)
		var events: Array[InputEvent] = InputMap.action_get_events(action).duplicate()
		for ev: InputEvent in events:
			if device_type == "keyboard" and ev is InputEventKey:
				InputMap.action_erase_event(action, ev)
			elif (
				device_type == "gamepad"
				and (ev is InputEventJoypadButton or ev is InputEventJoypadMotion)
			):
				InputMap.action_erase_event(action, ev)

		# Add fresh defaults
		if device_type == "keyboard" and DEFAULT_KEYBOARD.has(action):
			var nev: InputEventKey = InputEventKey.new()
			nev.physical_keycode = DEFAULT_KEYBOARD[action]
			InputMap.action_add_event(action, nev)
		elif device_type == "gamepad" and DEFAULT_GAMEPAD.has(action):
			var def: Dictionary = DEFAULT_GAMEPAD[action]
			if def["type"] == "button":
				var nev: InputEventJoypadButton = InputEventJoypadButton.new()
				nev.button_index = def["button"]
				nev.device = -1
				InputMap.action_add_event(action, nev)
			elif def["type"] == "axis":
				var nev: InputEventJoypadMotion = InputEventJoypadMotion.new()
				nev.axis = def["axis"]
				nev.axis_value = def["value"]
				nev.device = -1
				InputMap.action_add_event(action, nev)

	save_input_mappings()
	Globals.log_message(
		"🔄 Full RESET for " + device_type + " — defaults forced!", Globals.LogLevel.INFO
	)


## Returns true if two events are exactly the same binding.
func events_match(a: InputEvent, b: InputEvent) -> bool:
	if a == null or b == null:
		return false  # treat null as "no match"
	if a.get_class() != b.get_class():
		return false
	if a is InputEventKey:
		return a.physical_keycode == b.physical_keycode
	if a is InputEventJoypadButton:
		return a.button_index == b.button_index and a.device == b.device
	if a is InputEventJoypadMotion:
		return a.axis == b.axis and a.axis_value == b.axis_value and a.device == b.device
	return false


## Finds every other action that already uses this exact event.
## :param event: The new event the player just pressed.
## :param exclude_action: The action we are currently remapping (ignored).
## :rtype: Array[String]  # e.g. ["fire"] or ["next_weapon", "pause"]
func get_conflicting_actions(event: InputEvent, exclude_action: String = "") -> Array[String]:
	var conflicts: Array[String] = []
	for action: String in ACTIONS:
		if action == exclude_action:
			continue
		for ev: InputEvent in InputMap.action_get_events(action):
			if events_match(ev, event):
				conflicts.append(action)
				break  # one match per action is enough
	return conflicts


## Saves the last selected input device to config.
func save_last_input_device(device: String) -> void:
	if device not in ["keyboard", "gamepad"]:
		return
	var config: ConfigFile = ConfigFile.new()
	config.load(CONFIG_PATH)
	config.set_value("input", "last_input_device", device)
	config.save(CONFIG_PATH)


## Loads the last selected input device (defaults to keyboard).
## Validates against ["keyboard", "gamepad"] to prevent corrupted config values.
## Mirrors save_last_input_device() for consistency.
## :rtype: void
func load_last_input_device() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(CONFIG_PATH) == OK and config.has_section_key("input", "last_input_device"):
		var device: String = config.get_value("input", "last_input_device")
		Globals.current_input_device = device if device in ["keyboard", "gamepad"] else "keyboard"
	else:
		Globals.current_input_device = "keyboard"


## Returns "keyboard" or "gamepad" based on the type of the event.
func get_event_device_type(event: InputEvent) -> String:
	if event is InputEventKey:
		return "keyboard"
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return "gamepad"
	return "unknown"


## Returns the pause binding label (ALL CAPS) for the specific device that was just used.
## Returns the pause binding label (ALL CAPS) for the specific device that was just used.
func get_pause_binding_label_for_device(device_type: String) -> String:
	var events: Array[InputEvent] = InputMap.action_get_events("pause")
	if events.is_empty():
		return "UNBOUND"

	for ev: InputEvent in events:
		if (
			(device_type == "keyboard" and ev is InputEventKey)
			or (
				device_type == "gamepad"
				and (ev is InputEventJoypadButton or ev is InputEventJoypadMotion)
			)
		):
			return get_event_label(ev).to_upper()

	# Fallback
	return get_event_label(events[0]).to_upper()


## Returns true if there is at least one unbound critical action for the currently selected device.
## This respects Globals.current_input_device.
func has_unbound_critical_actions_for_current_device() -> bool:
	var preferred: String = Globals.current_input_device
	for action: String in CRITICAL_ACTIONS:
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		if events.is_empty():
			# continue  # action is unbound, but we check per device
			return true  # unbound for all devices, including current

		var has_binding_for_device: bool = false
		for ev: InputEvent in events:
			if (
				(preferred == "keyboard" and ev is InputEventKey)
				or (
					preferred == "gamepad"
					and (ev is InputEventJoypadButton or ev is InputEventJoypadMotion)
				)
			):
				has_binding_for_device = true
				break

		if not has_binding_for_device:
			return true  # unbound for the current device

	return false


## One-time migration for legacy configs.
## Forces defaults for CRITICAL_ACTIONS that are unbound/empty.
## Ensures "Unbound" labels appear correctly for UI actions.
## Sets the meta flag to prevent re-run (works even if called directly in tests).
## :rtype: void
func _migrate_legacy_unbound_states() -> void:
	var changed: bool = false
	for action: String in CRITICAL_ACTIONS:
		if InputMap.action_get_events(action).is_empty():
			# Force keyboard default
			if DEFAULT_KEYBOARD.has(action):
				var nev: InputEventKey = InputEventKey.new()
				nev.physical_keycode = DEFAULT_KEYBOARD[action]
				InputMap.action_add_event(action, nev)
				changed = true
				Globals.log_message(
					"Migrated legacy unbound: " + action + " (keyboard default)",
					Globals.LogLevel.INFO
				)

			# Force gamepad default
			if DEFAULT_GAMEPAD.has(action):
				var def: Dictionary = DEFAULT_GAMEPAD[action]
				var nev: InputEvent = null
				match def.get("type"):
					"button":
						var button := InputEventJoypadButton.new()
						button.button_index = def["button"]
						button.device = -1
						nev = button
					"axis":
						var motion := InputEventJoypadMotion.new()
						motion.axis = def["axis"]
						motion.axis_value = def["value"]
						motion.device = -1
						nev = motion
				if nev:
					InputMap.action_add_event(action, nev)
					changed = true
					Globals.log_message(
						"Migrated legacy unbound: " + action + " (gamepad default)",
						Globals.LogLevel.INFO
					)

	if changed:
		save_input_mappings()  # Persist the migration

	# Set the meta flag HERE (so direct calls in tests work, and _ready() is consistent)
	Globals.set_meta(LEGACY_MIGRATION_KEY, true)


## Static helper: Returns human-readable label for an InputEvent (e.g., "SPACE", "A", "RT").
## Supports keys, joypad buttons (Xbox/PS labels), and axes (e.g., "LT (+)", "Left Stick (Right)").
## :param ev: The event to label.
## :rtype: String
static func get_event_label(ev: InputEvent) -> String:
	if ev is InputEventKey:
		# Prefer physical_keycode (layout-independent),
		# but it can be 0 for project defaults/migration.
		var code: int = int(ev.physical_keycode)
		if code == 0:
			code = int(ev.keycode)

		# Migration / project-default case:
		# physical_keycode == 0 but keycode is valid
		# Avoid returning OS.get_keycode_string(0) == "" (blank label).
		if code == 0:
			return "Unbound"

		return OS.get_keycode_string(code)

	if ev is InputEventJoypadButton:
		match ev.button_index:
			JOY_BUTTON_A:
				return "A"
			JOY_BUTTON_B:
				return "B"
			JOY_BUTTON_X:
				return "X"
			JOY_BUTTON_Y:
				return "Y"
			JOY_BUTTON_BACK:
				return "Back"
			JOY_BUTTON_GUIDE:
				return "Guide"
			JOY_BUTTON_START:
				return "Start"
			JOY_BUTTON_LEFT_STICK:
				return "LS Press"
			JOY_BUTTON_RIGHT_STICK:
				return "RS Press"
			JOY_BUTTON_LEFT_SHOULDER:
				return "LB"
			JOY_BUTTON_RIGHT_SHOULDER:
				return "RB"
			JOY_BUTTON_DPAD_UP:
				return "D-Pad Up"
			JOY_BUTTON_DPAD_DOWN:
				return "D-Pad Down"
			JOY_BUTTON_DPAD_LEFT:
				return "D-Pad Left"
			JOY_BUTTON_DPAD_RIGHT:
				return "D-Pad Right"
			_:
				return "Button " + str(ev.button_index)
	if ev is InputEventJoypadMotion:
		var dir: String = " (+)" if ev.axis_value > 0 else " (-)"
		match ev.axis:
			JOY_AXIS_LEFT_X:
				return "Left Stick (Right)" if ev.axis_value > 0 else "Left Stick (Left)"
			JOY_AXIS_LEFT_Y:
				return "Left Stick (Down)" if ev.axis_value > 0 else "Left Stick (Up)"
			JOY_AXIS_RIGHT_X:
				return "Right Stick (Right)" if ev.axis_value > 0 else "Right Stick (Left)"
			JOY_AXIS_RIGHT_Y:
				return "Right Stick (Down)" if ev.axis_value > 0 else "Right Stick (Up)"
			JOY_AXIS_TRIGGER_LEFT:
				Globals.log_message("Left Trigger dir: " + str(dir), Globals.LogLevel.DEBUG)
				return ("Left Trigger" + dir).strip_edges()
			JOY_AXIS_TRIGGER_RIGHT:
				Globals.log_message("Right Trigger dir: " + str(dir), Globals.LogLevel.DEBUG)
				return ("Right Trigger" + dir).strip_edges()
			_:
				# return "Axis " + str(ev.axis) + dir
				# normalize the non-trigger fallback line:
				return ("Axis " + str(ev.axis) + dir).strip_edges()
	return "Unknown"
