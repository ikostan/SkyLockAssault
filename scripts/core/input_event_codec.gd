## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## input_event_codec.gd
## Static helpers for one InputEvent at a time: the string saved in settings.cfg, the label
## shown in menus, whether two events are the same binding, and which device an event is from.
##
## Moved out of settings.gd unchanged (#1101), so Settings keeps only the bindings and
## settings state it owns.

class_name InputEventCodec
extends RefCounted

## Modifier tokens [method serialize_event] can write after the keycode in a
## [code]key:[/code] string. Any other token makes [method deserialize_event] return null.
const KEY_MODIFIER_TOKENS: PackedStringArray = ["shift", "ctrl", "alt", "meta"]


## Serializes an InputEvent to string for ConfigFile storage.
##
## Handles Key without device, JoypadButton, and JoypadMotion with device, preserving modifiers
## like shift, ctrl, alt, and meta.
##
## [param ev]: The InputEvent instance to serialize, supporting Key, JoypadButton, and
## JoypadMotion.
## Returns a serialized string representation of the event or an empty string if unsupported.
static func serialize_event(ev: InputEvent) -> String:
	if ev is InputEventKey:
		# Godot's built-in actions and editor-made bindings can set only keycode, leaving
		# physical_keycode 0; "key:0" would be rejected on load. See [method _key_identity]:
		# a logical printable key is written as "lkey:" so it is restored as a keycode and
		# keeps following the keyboard layout, instead of becoming a physical position.
		var identity: Vector2i = _key_identity(ev)
		var s: String = ("lkey:" if identity.y == 1 else "key:") + str(identity.x)
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


## Deserializes a string back to an InputEvent.
##
## Handles serialized strings starting with key, lkey, joybtn, or joyaxis to restore the
## corresponding input event.
##
## [param serialized]: The serialized string starting with key, lkey, joybtn, or joyaxis.
## [code]key:[/code] restores a physical keycode, [code]lkey:[/code] a logical keycode.
## Returns the deserialized InputEvent, or null if the string is invalid.
## A key string accepts the modifiers in [constant KEY_MODIFIER_TOKENS] in any order; an
## unknown, empty or repeated token makes the whole string invalid.
static func deserialize_event(serialized: String) -> InputEvent:
	var event_to_return: InputEvent = null

	# 1. Reject invalid prefixes immediately
	if not (
		serialized.begins_with("key:")
		or serialized.begins_with("lkey:")
		or serialized.begins_with("joybtn:")
		or serialized.begins_with("joyaxis:")
	):
		return null

	var parts: PackedStringArray = serialized.split(":", true)
	if parts.size() < 2:
		return null

	match parts[0]:
		"key", "lkey":
			if parts.size() >= 2 and parts[1].is_valid_int():
				# serialize_event only writes known modifiers, each at most once, so any
				# other token means the saved binding is corrupt or hand-edited (#1090).
				var modifiers: PackedStringArray = parts.slice(2)
				for token: String in modifiers:
					var problem: String = ""
					if token not in KEY_MODIFIER_TOKENS:
						problem = "unknown modifier token '%s'" % token
					elif modifiers.count(token) > 1:
						problem = "duplicate modifier token '%s'" % token
					if not problem.is_empty():
						Globals.log_message(
							"Rejecting key event with %s: %s" % [problem, serialized],
							Globals.LogLevel.WARNING
						)
						return null

				var code := parts[1].to_int()

				# OPINION: Explicitly reject 0 to prevent "silent drops"
				# as suggested by Sourcery.
				if code == 0:
					Globals.log_message(
						"Ignoring key event with keycode 0", Globals.LogLevel.WARNING
					)
					return null

				var ev := InputEventKey.new()
				if parts[0] == "lkey":
					ev.keycode = code  # Logical: follows the keyboard layout.
				else:
					ev.physical_keycode = code
				ev.shift_pressed = "shift" in modifiers
				ev.ctrl_pressed = "ctrl" in modifiers
				ev.alt_pressed = "alt" in modifiers
				ev.meta_pressed = "meta" in modifiers
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


## Returns true if two events are exactly the same binding.
##
## Key events match on [code]physical_keycode[/code] and all four modifiers (Shift, Ctrl, Alt,
## Meta). Joypad buttons match on button index and device; joypad axes match on axis,
## direction value and device. Events of different classes never match.
##
## [param a]: First event to compare. [code]null[/code] never matches.
## [param b]: Second event to compare. [code]null[/code] never matches.
## Returns [code]true[/code] if both events describe the same binding.
static func events_match(a: InputEvent, b: InputEvent) -> bool:
	if a == null or b == null:
		return false
	if a.get_class() != b.get_class():
		return false

	if a is InputEventKey:
		# Compare what serialize_event would store (see _key_identity), plus modifiers so
		# Tab and Shift+Tab stay distinct. A logical and a physical printable key never match:
		# which physical key a logical one lands on depends on the keyboard layout.
		return (
			_key_identity(a) == _key_identity(b)
			and a.shift_pressed == b.shift_pressed
			and a.ctrl_pressed == b.ctrl_pressed
			and a.alt_pressed == b.alt_pressed
			and a.meta_pressed == b.meta_pressed
		)

	if a is InputEventJoypadButton:
		return a.button_index == b.button_index and a.device == b.device
	if a is InputEventJoypadMotion:
		return a.axis == b.axis and a.axis_value == b.axis_value and a.device == b.device
	return false


## Returns how a key event is identified: [code]x[/code] is the code and [code]y[/code] is 1
## for a logical (layout-following) key or 0 for a physical (position) key.
##
## [code]physical_keycode[/code] wins when set. A keycode-only event is physical too when its
## keycode is a special key (arrows, Enter, Tab, Escape, F-keys, numpad...), because Godot uses
## the same value for both and those keys do not move between layouts. Only a keycode-only
## printable key (letters, digits, symbols) is logical.
##
## [param ev]: The key event.
## Returns [code]Vector2i(code, is_logical)[/code].
static func _key_identity(ev: InputEventKey) -> Vector2i:
	if ev.physical_keycode != 0:
		return Vector2i(int(ev.physical_keycode), 0)
	var code: int = int(ev.keycode)
	if code == 0 or code & KEY_SPECIAL:
		return Vector2i(code, 0)
	return Vector2i(code, 1)


## Return keyboard or gamepad based on the type of the event.
##
## [param event]: The input event to check for device type.
## Returns a string representing the device type such as keyboard or gamepad.
static func get_event_device_type(event: InputEvent) -> String:
	if event is InputEventKey:
		return "keyboard"
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return "gamepad"
	return "unknown"


## Returns a human-readable label for an InputEvent.
##
## Keys use [method OS.get_keycode_string] with Ctrl, Alt, Shift and Meta prefixes, preferring
## [code]physical_keycode[/code] and falling back to [code]keycode[/code]. Joypad buttons
## always use Xbox-style names (A, B, X, Y, LB, RB, ...) regardless of controller brand.
## Joypad axes use stick and trigger names such as "Left Stick (Right)" or "Left Trigger (+)".
##
## [param ev]: The event to label.
## Returns the label, "Unbound" for a key with no keycode, or "Unknown" for other events.
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
