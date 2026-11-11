## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## input_defaults.gd
## Default input layout: one keyboard and one gamepad binding per action, plus the
## gameplay/menu conflict groups.
##
## Single source for Settings (backfill, Reset, migrations). project.godot [input] must
## describe the same layout; test_input_layout_menu_gameplay_split.gd checks that they match.

extends RefCounted

## Actions used while flying. An input may be bound to only one of these.
## [code]pause[/code] is in both groups: it is pressed during flight and also closes menus.
const GAMEPLAY_ACTIONS: Array[String] = [
	"speed_up",
	"speed_down",
	"move_left",
	"move_right",
	"fire",
	"next_weapon",
	"pause",
]

## Actions used while a menu has focus. An input may be bound to only one of these.
## Menus and flight never take input at the same time, so a menu action may share an input
## with a gameplay action (A is both Fire and Accept on a gamepad).
const MENU_ACTIONS: Array[String] = [
	"pause",
	"ui_up",
	"ui_down",
	"ui_left",
	"ui_right",
	"ui_accept",
	"ui_focus_next",
	"ui_focus_prev",
]

## Default keyboard bindings: a physical keycode, or a dictionary for a key with modifiers.
const KEYBOARD: Dictionary = {
	"speed_up": KEY_W,
	"speed_down": KEY_S,
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
	"ui_focus_prev": {"keycode": KEY_TAB, "shift": true},
}

## Default gamepad bindings (Xbox layout). The whole plane flies on the left stick; menus
## navigate on the D-pad.
const GAMEPAD: Dictionary = {
	"speed_up": {"type": "axis", "axis": JOY_AXIS_LEFT_Y, "value": -1.0},
	"speed_down": {"type": "axis", "axis": JOY_AXIS_LEFT_Y, "value": 1.0},
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
	"ui_focus_next": {"type": "button", "button": JOY_BUTTON_RIGHT_SHOULDER},
	"ui_focus_prev": {"type": "button", "button": JOY_BUTTON_LEFT_SHOULDER},
}


## Builds the default event for an action on a specified device.
##
## Keys are physical and layout-independent. Joypad events use device -1 for all controllers.
##
## [param action]: Name of the input action.
## [param device]: Target device type, accepted values are [code]keyboard[/code] or
## [code]gamepad[/code].
## Returns a new input event, or [code]null[/code] if the action has no default for that
## device.
static func make_event(action: String, device: String) -> InputEvent:
	if device == "keyboard" and KEYBOARD.has(action):
		var def: Variant = KEYBOARD[action]
		var key := InputEventKey.new()
		if def is Dictionary:
			key.physical_keycode = def["keycode"]
			key.shift_pressed = def.get("shift", false)
			key.ctrl_pressed = def.get("ctrl", false)
		else:
			key.physical_keycode = def
		return key

	if device == "gamepad" and GAMEPAD.has(action):
		var def: Dictionary = GAMEPAD[action]
		match def.get("type"):
			"button":
				var button := InputEventJoypadButton.new()
				button.button_index = def["button"]
				button.device = -1
				return button
			"axis":
				var motion := InputEventJoypadMotion.new()
				motion.axis = def["axis"]
				motion.axis_value = def["value"]
				motion.device = -1
				return motion
	return null


## Return actions in all_actions that may not share an input with action.
##
## A gameplay action is scoped to GAMEPLAY_ACTIONS, a menu action to MENU_ACTIONS, and pause
## (in both groups) to their union. An empty or unknown action is scoped to all of all_actions.
##
## [param action]: The action whose conflict group is wanted.
## [param all_actions]: Every managed action, in the order results should keep.
## Returns the action names in that scope.
static func conflict_scope(action: String, all_actions: Array[String]) -> Array[String]:
	var in_gameplay: bool = action in GAMEPLAY_ACTIONS
	var in_menu: bool = action in MENU_ACTIONS
	if not in_gameplay and not in_menu:
		return all_actions.duplicate()

	var scope: Array[String] = []
	for other: String in all_actions:
		if (in_gameplay and other in GAMEPLAY_ACTIONS) or (in_menu and other in MENU_ACTIONS):
			scope.append(other)
	return scope
