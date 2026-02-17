## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
# settings.gd
# Input settings singleton: Loads/saves InputMap events to preserve custom mappings.
# Supports keys, joypad buttons, and joypad axes (serialized).
# Autoload as "Settings".

extends Node

const CONFIG_PATH: String = "user://settings.cfg"

## Critical actions that must be bound for playable game.
const CRITICAL_ACTIONS: Array[String] = [
	"fire", "speed_up", "speed_down", "move_left", "move_right", "next_weapon", "pause"
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
	"speed_up": {"type": "axis", "axis": JOY_AXIS_TRIGGER_RIGHT, "value": 1.0},  # Throttle up.
	"speed_down": {"type": "axis", "axis": JOY_AXIS_TRIGGER_LEFT, "value": 1.0},  # Throttle down.
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

var _needs_migration: bool = false  # Flag for old-format upgrade


## Initializes the settings by loading input mappings.
## If migration is needed, saves the updated mappings.
func _ready() -> void:
	load_input_mappings()
	_ensure_defaults_saved()
	if _needs_migration:
		save_input_mappings()  # Only save if upgrade needed (old format detected)
		_needs_migration = false


## Shared helper: Adds missing keyboard/gamepad defaults to InputMap.
## Respects explicit unbounds (e.g. user saved [] for a device).
## Returns true if anything was added (so caller can save).
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

		# Device-specific "explicitly unbound" check (copied from both old blocks,
		# with your robust type guard from load_input_mappings())
		var explicitly_unbound_keyboard: bool = false
		var explicitly_unbound_gamepad: bool = false
		if config.has_section_key("input", action):
			var saved_val: Variant = config.get_value("input", action)
			if saved_val is Array or saved_val is PackedStringArray:
				var has_saved_key: bool = false
				var has_saved_joy: bool = false
				for item: Variant in saved_val:
					if item is String:
						var s: String = item
						if s.begins_with("key:"):
							has_saved_key = true
						elif s.begins_with("joybtn:") or s.begins_with("joyaxis:"):
							has_saved_joy = true
					else:
						Globals.log_message(
							"Non-string item in unbound check for action '" + action + "': skipped",
							Globals.LogLevel.WARNING
						)
				explicitly_unbound_keyboard = not has_saved_key
				explicitly_unbound_gamepad = not has_saved_joy

		# === Keyboard defaults ===
		if not has_keyboard and DEFAULT_KEYBOARD.has(action) and not explicitly_unbound_keyboard:
			var nev: InputEventKey = InputEventKey.new()
			nev.physical_keycode = DEFAULT_KEYBOARD[action]
			InputMap.action_add_event(action, nev)
			changed = true
			Globals.log_message(
				"Added missing default keyboard mapping for " + action, Globals.LogLevel.DEBUG
			)

		# === Gamepad defaults (unified with match, like in _ensure) ===
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
					"Added missing default gamepad mapping for " + action, Globals.LogLevel.DEBUG
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
	var preferred: String = Globals.current_input_device
	var events: Array[InputEvent] = InputMap.action_get_events("pause")

	if events.is_empty():
		return "UNBOUND"

	for ev: InputEvent in events:
		if (
			(preferred == "keyboard" and ev is InputEventKey)
			or (
				preferred == "gamepad"
				and (ev is InputEventJoypadButton or ev is InputEventJoypadMotion)
			)
		):
			var temp: Button = InputRemapButton.new()
			var label: String = temp.get_event_label(ev)
			temp.queue_free()
			return label.to_upper()

	# Fallback
	var temp: Button = InputRemapButton.new()
	var label: String = temp.get_event_label(events[0])
	temp.queue_free()
	return label.to_upper()


## Returns true if the given event is bound to any action.
## :param event: Input event to check.
## :type event: InputEvent
## :rtype: bool
func is_event_bound(event: InputEvent) -> bool:
	for action: String in ACTIONS:
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
			elif value is int:
				serialized_events = ["key:" + str(value)]  # Old int keycode—migrate
				_needs_migration = true
			elif value is String:
				serialized_events = [value]  # Old string format
				_needs_migration = true
			else:
				Globals.log_message(
					"Unexpected type for action '" + action + "': " + str(typeof(value)),
					Globals.LogLevel.WARNING
				)

			InputMap.action_erase_events(action)
			for serialized: String in serialized_events:
				_deserialize_and_add(action, serialized)

	# ── SHARED DEFAULTS BACKFILL (DRY: used by _add_missing_defaults + _ensure_defaults_saved) ──
	# Ensures EC-01, EC-04, EC-05 pass when load_input_mappings() called directly (tests).
	# For corrupt/no-file: config empty → add defaults.
	# Sets _needs_migration=true if added → triggers save in _ready() (first-run/repair).
	# Idempotent with _ensure_defaults_saved().
	var defaults_config: ConfigFile = ConfigFile.new()
	defaults_config.load(path)
	if _add_missing_defaults(defaults_config):
		_needs_migration = true


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
		_needs_migration = true  # Ensure save if we hit this old case
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
## :param device_type: "keyboard" or "gamepad"
## :type device_type: String
## :rtype: void
func reset_to_defaults(device_type: String) -> void:
	if device_type not in ["keyboard", "gamepad"]:
		return
	for action: String in ACTIONS:
		var events: Array[InputEvent] = InputMap.action_get_events(action).duplicate()
		for ev: InputEvent in events:
			if device_type == "keyboard" and ev is InputEventKey:
				InputMap.action_erase_event(action, ev)
			elif (
				device_type == "gamepad"
				and (ev is InputEventJoypadButton or ev is InputEventJoypadMotion)
			):
				InputMap.action_erase_event(action, ev)
		if device_type == "keyboard" and DEFAULT_KEYBOARD.has(action):
			var nev: InputEventKey = InputEventKey.new()
			nev.physical_keycode = DEFAULT_KEYBOARD[action]
			InputMap.action_add_event(action, nev)
		elif device_type == "gamepad" and DEFAULT_GAMEPAD.has(action):
			var def: Dictionary = DEFAULT_GAMEPAD[action]
			if def["type"] == "button":
				var nev: InputEventJoypadButton = InputEventJoypadButton.new()
				nev.button_index = def["button"]  # FIX: Use "button" instead of "index"
				nev.device = -1
				InputMap.action_add_event(action, nev)
			elif def["type"] == "axis":
				var nev: InputEventJoypadMotion = InputEventJoypadMotion.new()
				nev.axis = def["axis"]
				nev.axis_value = def["value"]
				nev.device = -1
				InputMap.action_add_event(action, nev)
	save_input_mappings()


## Ensures default keyboard and gamepad mappings are present in InputMap.
## Now the *single source* of truth for defaults (after load_input_mappings()).
## Respects explicit [] = "user wants this unbound".
## Saves to config if anything was added (first-run, new actions, etc.).
func _ensure_defaults_saved() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(CONFIG_PATH)

	if _add_missing_defaults(config):
		save_input_mappings()
		Globals.log_message("Defaults filled → saved", Globals.LogLevel.INFO)


## Returns true if two events are exactly the same binding.
func _events_match(a: InputEvent, b: InputEvent) -> bool:
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
			if _events_match(ev, event):
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
func load_last_input_device() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(CONFIG_PATH) == OK and config.has_section_key("input", "last_input_device"):
		Globals.current_input_device = config.get_value("input", "last_input_device")
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
			var temp: Button = InputRemapButton.new()
			var label: String = temp.get_event_label(ev)
			temp.queue_free()
			return label.to_upper()

	# Fallback
	var temp: Button = InputRemapButton.new()
	var label: String = temp.get_event_label(events[0])
	temp.queue_free()
	return label.to_upper()


## Returns true if there is at least one unbound critical action for the currently selected device.
## This respects Globals.current_input_device.
func has_unbound_critical_actions_for_current_device() -> bool:
	var preferred: String = Globals.current_input_device
	for action: String in CRITICAL_ACTIONS:
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		if events.is_empty():
			continue  # action is unbound, but we check per device

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
