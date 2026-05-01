## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## settings.gd
## Input settings singleton: Loads/saves InputMap events to preserve custom mappings.
## Supports keys, joypad buttons, and joypad axes (serialized).
## Autoload as "Settings".

extends Node

# Change to v3 if you add another migration etc...
const LEGACY_MIGRATION_KEY: String = "settings_migrated_v2"
const CONFIG_PATH: String = "user://settings.cfg"

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
	"ui_focus_next": KEY_TAB,
	"ui_focus_prev": {"keycode": KEY_TAB, "shift": true},  # Store as a sub-dictionary
}
# New: Default gamepad mappings (assumes Xbox layout; adjust if needed).
const DEFAULT_GAMEPAD: Dictionary = {
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
	"ui_focus_next": {"type": "button", "button": JOY_BUTTON_RIGHT_SHOULDER},
	"ui_focus_prev": {"type": "button", "button": JOY_BUTTON_LEFT_SHOULDER},
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
			var def: Variant = DEFAULT_KEYBOARD[action]
			var nev: InputEventKey = InputEventKey.new()

			if def is Dictionary:
				nev.physical_keycode = def["keycode"]
				nev.shift_pressed = def.get("shift", false)
				nev.ctrl_pressed = def.get("ctrl", false)  # Matches your serialization format
			else:
				nev.physical_keycode = def

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
		var s: String = "key:" + str(ev.physical_keycode)
		if ev.shift_pressed:
			s += ":shift"
		if ev.ctrl_pressed:
			s += ":ctrl"
		if ev.alt_pressed:  # NEW: Persist Alt
			s += ":alt"
		if ev.meta_pressed:  # NEW: Persist Meta/Cmd
			s += ":meta"
		return s

	if ev is InputEventJoypadButton:
		return "joybtn:" + str(ev.button_index) + ":" + str(ev.device)

	if ev is InputEventJoypadMotion:
		return "joyaxis:" + str(ev.axis) + ":" + str(ev.axis_value) + ":" + str(ev.device)

	return ""


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
func deserialize_event(serialized: String) -> InputEvent:
	var event_to_return: InputEvent = null

	# 1. Reject invalid prefixes immediately
	if not (
		serialized.begins_with("key:")
		or serialized.begins_with("joybtn:")
		or serialized.begins_with("joyaxis:")
	):
		return null

	var parts: PackedStringArray = serialized.split(":", true)
	if parts.size() < 2:
		return null

	match parts[0]:
		"key":
			if parts.size() >= 2 and parts[1].is_valid_int():
				var code := parts[1].to_int()

				# OPINION: Explicitly reject 0 to prevent "silent drops"
				# as suggested by Sourcery.
				if code == 0:
					Globals.log_message(
						"Ignoring key event with keycode 0", Globals.LogLevel.WARNING
					)
					return null

				var ev := InputEventKey.new()
				ev.physical_keycode = code
				ev.shift_pressed = "shift" in parts
				ev.ctrl_pressed = "ctrl" in parts
				ev.alt_pressed = "alt" in parts
				ev.meta_pressed = "meta" in parts
				event_to_return = ev
		"joybtn":
			if parts.size() == 3 and parts[1].is_valid_int() and parts[2].is_valid_int():
				var ev := InputEventJoypadButton.new()
				ev.button_index = parts[1].to_int()
				ev.device = parts[2].to_int()
				event_to_return = ev
		"joyaxis":
			if (
				parts.size() == 4
				and parts[1].is_valid_int()
				and parts[2].is_valid_float()
				and parts[3].is_valid_int()
			):
				var ev := InputEventJoypadMotion.new()
				ev.axis = parts[1].to_int()
				ev.axis_value = parts[2].to_float()
				ev.device = parts[3].to_int()
				event_to_return = ev

	return event_to_return


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
	var ev: InputEvent = deserialize_event(serialized)

	if ev != null:
		InputMap.action_add_event(action, ev)
	else:
		# If it's not a valid prefixed string, it fails here.
		# No more "elif serialized.is_valid_int()" legacy fallback.
		Globals.log_message(
			"Invalid or unknown serialized format: " + serialized, Globals.LogLevel.WARNING
		)


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
			var def: Variant = DEFAULT_KEYBOARD[action]
			var nev: InputEventKey = InputEventKey.new()
			if def is Dictionary:
				nev.physical_keycode = def["keycode"]
				nev.shift_pressed = def.get("shift", false)
				nev.ctrl_pressed = def.get("ctrl", false)
			else:
				nev.physical_keycode = def
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
		return false
	if a.get_class() != b.get_class():
		return false

	if a is InputEventKey:
		# FIXED: Must compare modifiers to distinguish between Tab and Shift+Tab
		return (
			a.physical_keycode == b.physical_keycode
			and a.shift_pressed == b.shift_pressed
			and a.ctrl_pressed == b.ctrl_pressed
			and a.alt_pressed == b.alt_pressed
		)

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
		var modifiers: Array[String] = []
		if ev.ctrl_pressed:
			modifiers.append("Ctrl")
		if ev.alt_pressed:
			modifiers.append("Alt")
		if ev.shift_pressed:
			modifiers.append("Shift")
		if ev.meta_pressed:
			modifiers.append("Meta")
		# Prefer physical_keycode (layout-independent),
		# but it can be 0 for project defaults/migration.
		var code: int = int(ev.physical_keycode) if ev.physical_keycode != 0 else int(ev.keycode)
		if code == 0:
			return "Unbound"

		var key_name: String = OS.get_keycode_string(code)
		if modifiers.is_empty():
			return key_name

		return "+".join(modifiers) + "+" + key_name

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


## Loads input mappings from config, overriding project defaults only if saved.
func load_input_mappings(path: String = CONFIG_PATH, actions: Array[String] = ACTIONS) -> void:
	# Use our new centralized helper to safely read the file
	var load_data: Dictionary = Globals.safe_load_config(path)
	var config: ConfigFile = load_data["config"]
	var err: int = load_data["err"]

	if load_data["is_legacy"]:
		Globals.log_message(
			"Legacy plaintext input mappings found. Migration required.", Globals.LogLevel.INFO
		)
		_needs_save = true

	if err != OK and err != ERR_FILE_NOT_FOUND:
		Globals.log_message(
			"Error loading settings file at " + path + ": " + str(err), Globals.LogLevel.ERROR
		)

	# Restore migration metadata
	if config.has_section_key("meta", LEGACY_MIGRATION_KEY):
		var migrated: bool = config.get_value("meta", LEGACY_MIGRATION_KEY, false)
		if migrated:
			Globals.set_meta(LEGACY_MIGRATION_KEY, true)
			Globals.log_message(
				"Restored legacy migration flag from config.", Globals.LogLevel.DEBUG
			)

	for action: String in actions:
		var has_saved: bool = config.has_section_key("input", action)
		if has_saved:
			var value: Variant = config.get_value("input", action)
			var serialized_events: Array[String] = []

			if value is Array or value is PackedStringArray:
				for item: Variant in value:
					if item is String:
						serialized_events.append(item)
					else:
						Globals.log_message(
							"Non-string item in array for action '" + action + "': skipped",
							Globals.LogLevel.WARNING
						)
			elif value is String:
				serialized_events = [value]
			elif value is int:
				serialized_events = ["key:" + str(value)]

			InputMap.action_erase_events(action)

			for serialized: String in serialized_events:
				var ev: InputEvent = deserialize_event(serialized)
				if ev == null:
					continue

				var already_present := false
				for existing_ev in InputMap.action_get_events(action):
					if events_match(existing_ev, ev):
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
					_needs_save = true

				InputMap.action_add_event(action, ev)

	_needs_save = _add_missing_defaults(config) or _needs_save


## Saves current InputMap events to config (all per action as array).
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
		config.set_value("input", action, serials)

	# FIX: Use the centralized key helper
	err = config.save_encrypted_pass(path, Globals.ensure_encryption_key())

	if err != OK:
		Globals.log_message("Failed to save input mappings: " + str(err), Globals.LogLevel.ERROR)
	else:
		Globals.log_message("Input mappings saved.", Globals.LogLevel.DEBUG)


## Saves the last selected input device to config.
func save_last_input_device(device: String) -> void:
	if device not in ["keyboard", "gamepad"]:
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

	# FIX: Use the centralized key helper and capture the save error
	err = config.save_encrypted_pass(CONFIG_PATH, Globals.ensure_encryption_key())
	
	if err != OK:
		Globals.log_message("Failed to save last input device: " + str(err), Globals.LogLevel.ERROR)
	else:
		Globals.log_message("Last input device saved.", Globals.LogLevel.DEBUG)


## Loads the last selected input device (defaults to keyboard).
func load_last_input_device() -> void:
	# Use the helper to safely load
	var load_data: Dictionary = Globals.safe_load_config(CONFIG_PATH)
	var config: ConfigFile = load_data["config"]
	var err: int = load_data["err"]

	if err == OK and config.has_section_key("input", "last_input_device"):
		var device: String = config.get_value("input", "last_input_device")
		Globals.current_input_device = device if device in ["keyboard", "gamepad"] else "keyboard"
	else:
		Globals.current_input_device = "keyboard"
