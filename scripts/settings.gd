## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
# settings.gd
# Input settings singleton: Loads/saves InputMap events to preserve custom mappings.
# Supports keys, joypad buttons, and joypad axes (serialized).
# Autoload as "Settings".

extends Node

const CONFIG_PATH: String = "user://settings.cfg"

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
	"ui_accept": {"type": "button", "button": JOY_BUTTON_A},
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
	if _needs_migration:
		save_input_mappings()  # Only save if upgrade needed (old format detected)
		_needs_migration = false


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
		return
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

			if value is Array:
				var temp: Array = value
				for item: Variant in temp:
					if item is String:
						serialized_events.append(item)
					else:
						Globals.log_message(
							"Non-string item in array for action '" + action + "': skipped",
							Globals.LogLevel.WARNING
						)
			elif value is int:
				serialized_events = ["key:" + str(value)]  # Old int keycode—migrate to key format
				_needs_migration = true
			elif value is String:
				serialized_events = [value]  # Old string—could be "key:87" or plain "87"
				_needs_migration = true
			else:
				Globals.log_message(
					"Unexpected type for action '" + action + "': " + str(typeof(value)),
					Globals.LogLevel.WARNING
				)
				# Fallback: Treat as empty to avoid errors

			InputMap.action_erase_events(action)
			for serialized: String in serialized_events:
				_deserialize_and_add(action, serialized)

	for action: String in actions:
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		var has_key_event: bool = false
		var has_joy_event: bool = false
		for ev: InputEvent in events:
			if ev is InputEventKey:
				has_key_event = true
			elif ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				has_joy_event = true
		if not has_key_event and DEFAULT_KEYBOARD.has(action):
			var nev: InputEventKey = InputEventKey.new()
			nev.physical_keycode = DEFAULT_KEYBOARD[action]
			InputMap.action_add_event(action, nev)
			Globals.log_message(
				"Added default keyboard event for " + action, Globals.LogLevel.DEBUG
			)
		if not has_joy_event and DEFAULT_GAMEPAD.has(action):
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
			Globals.log_message("Added default gamepad event for " + action, Globals.LogLevel.DEBUG)


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
## If any defaults were missing, they are added and the config is saved.
## Called after load_input_mappings() to guarantee a complete first-run state.
func _ensure_defaults_saved() -> void:
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

		# === Keyboard defaults ===
		if not has_keyboard and DEFAULT_KEYBOARD.has(action):
			var nev := InputEventKey.new()
			nev.physical_keycode = DEFAULT_KEYBOARD[action]
			InputMap.action_add_event(action, nev)
			changed = true
			Globals.log_message(
				"Added missing default keyboard mapping for " + action, Globals.LogLevel.DEBUG
			)

		# === Gamepad defaults ===
		if not has_gamepad and DEFAULT_GAMEPAD.has(action):
			var def: Dictionary = DEFAULT_GAMEPAD[action]
			var nev: InputEvent

			if def["type"] == "button":
				nev = InputEventJoypadButton.new()
				(nev as InputEventJoypadButton).button_index = def["button"]
			elif def["type"] == "axis":
				nev = InputEventJoypadMotion.new()
				(nev as InputEventJoypadMotion).axis = def["axis"]
				(nev as InputEventJoypadMotion).axis_value = def["value"]

			(nev as InputEventJoypadButton if nev is InputEventJoypadButton else nev as InputEventJoypadMotion).device = -1
			InputMap.action_add_event(action, nev)
			changed = true
			Globals.log_message(
				"Added missing default gamepad mapping for " + action, Globals.LogLevel.DEBUG
			)

	if changed:
		save_input_mappings()
		Globals.log_message("Defaults were missing → saved to settings.cfg", Globals.LogLevel.INFO)
