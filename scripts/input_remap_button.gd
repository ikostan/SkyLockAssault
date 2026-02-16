## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
# input_remap_button.gd (full updated script - removes Godot 3.x methods, uses custom dicts only)
# Extends to handle joypad remapping and display (keys, buttons, axes).
# Use device = -1 for "all controllers".
# Handles listening, updating text, saving. Extends Button.
# :vartype action: String
# :vartype action_event_index: int
# :vartype KEY_LABELS: Dictionary
# :vartype JOY_BUTTON_LABELS: Dictionary
# :vartype JOY_AXIS_BASE_LABELS: Dictionary
# :vartype JOY_AXIS_LABELS: Dictionary
# :vartype listening: bool

# gdlint:ignore = class-definitions-order
class_name InputRemapButton

extends Button

# Enum for clean Inspector dropdown + match
enum DeviceType {
	KEYBOARD,
	GAMEPAD,
}

const KEY_LABELS: Dictionary = {
	Key.KEY_W: "W",
	Key.KEY_S: "S",
	Key.KEY_X: "X",
	Key.KEY_A: "A",
	Key.KEY_D: "D",
	Key.KEY_SPACE: "Space",
	Key.KEY_Q: "Q",
	Key.KEY_LEFT: "Left",
	Key.KEY_RIGHT: "Right",
	Key.KEY_UP: "Up",
	Key.KEY_DOWN: "Down",
	Key.KEY_ESCAPE: "Esc",
	Key.KEY_ENTER: "Enter",
	# Add more as needed for arrow keys, etc.
}

# Custom labels for joypad buttons (replaces removed Input.get_joy_button_string)
const JOY_BUTTON_LABELS: Dictionary = {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_GUIDE: "Guide",
	JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "Left Stick",
	JOY_BUTTON_RIGHT_STICK: "Right Stick",
	JOY_BUTTON_LEFT_SHOULDER: "L1",
	JOY_BUTTON_RIGHT_SHOULDER: "R1",
	JOY_BUTTON_DPAD_UP: "D-Pad Up",
	JOY_BUTTON_DPAD_DOWN: "D-Pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-Pad Left",
	JOY_BUTTON_DPAD_RIGHT: "D-Pad Right",
	JOY_BUTTON_MISC1: "Misc 1",
	JOY_BUTTON_PADDLE1: "Paddle 1",
	JOY_BUTTON_PADDLE2: "Paddle 2",
	JOY_BUTTON_PADDLE3: "Paddle 3",
	JOY_BUTTON_PADDLE4: "Paddle 4",
	JOY_BUTTON_TOUCHPAD: "Touchpad"
	# Add more from Godot docs if needed (e.g., for PS/Xbox specifics)
}

# Custom base labels for axes (replaces removed Input.get_joy_axis_string)
const JOY_AXIS_BASE_LABELS: Dictionary = {
	JOY_AXIS_LEFT_X: "Left Stick X",
	JOY_AXIS_LEFT_Y: "Left Stick Y",
	JOY_AXIS_RIGHT_X: "Right Stick X",
	JOY_AXIS_RIGHT_Y: "Right Stick Y",
	JOY_AXIS_TRIGGER_LEFT: "Left Trigger",
	JOY_AXIS_TRIGGER_RIGHT: "Right Trigger",
}

# Custom labels for common joypad axes/directions (for nice display)
const JOY_AXIS_LABELS: Dictionary = {
	JOY_AXIS_LEFT_X: {-1.0: "Left Stick Left", 1.0: "Left Stick Right"},
	JOY_AXIS_LEFT_Y: {-1.0: "Left Stick Up", 1.0: "Left Stick Down"},
	JOY_AXIS_RIGHT_X: {-1.0: "Right Stick Left", 1.0: "Right Stick Right"},
	JOY_AXIS_RIGHT_Y: {-1.0: "Right Stick Up", 1.0: "Right Stick Down"},
	JOY_AXIS_TRIGGER_LEFT: {1.0: "Left Trigger"},
	JOY_AXIS_TRIGGER_RIGHT: {1.0: "Right Trigger"}
}

# Add these new constants here for clarity and easy tweaking
# Minimum axis value to consider for remapping (avoids jitter)
const AXIS_DEADZONE_THRESHOLD: float = 0.5
# Value to normalize axis direction to (e.g., +1.0 or -1.0)
const AXIS_NORMALIZED_VALUE: float = 1.0

@export var current_device: DeviceType = DeviceType.KEYBOARD
@export var action: String = ""

var listening: bool = false

## Reference to KeyMappingMenu for conflict dialog.
@onready var key_mapping_menu: Node = get_tree().get_first_node_in_group("key_mapping_menu")


# Ready: Setup toggle, text, connect pressed.
# :rtype: void
func _ready() -> void:
	add_to_group("remap_buttons")
	toggle_mode = true
	update_button_text()
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)


## Handles button press to start remapping.
## Sets device-specific prompt text.
## :rtype: void
func _on_pressed() -> void:
	listening = button_pressed
	if listening:
		# Use tailored prompt based on current device (no layout expansion)
		text = (
			Globals.REMAP_PROMPT_KEYBOARD
			if current_device == DeviceType.KEYBOARD
			else Globals.REMAP_PROMPT_GAMEPAD
		)
	else:
		update_button_text()


# In input_remap_button.gd (full updated _input function)
# Input: Handle remap for key/button/motion if listening.
# :param event: Input event.
# :type event: InputEvent
# :rtype: void
func _input(event: InputEvent) -> void:
	if not listening:
		return

	# Device-specific filtering: Skip if event doesn't match current device
	if current_device == DeviceType.KEYBOARD and not event is InputEventKey:
		return

	if (
		current_device == DeviceType.GAMEPAD
		and not (event is InputEventJoypadButton or event is InputEventJoypadMotion)
	):
		return

	var new_event: InputEvent = null

	# Handle keyboard key press
	if event is InputEventKey and event.pressed:
		new_event = InputEventKey.new()
		new_event.physical_keycode = event.physical_keycode

	# Handle gamepad (joypad) button press
	elif event is InputEventJoypadButton and event.pressed:
		new_event = InputEventJoypadButton.new()
		new_event.button_index = event.button_index
		new_event.device = -1

	# Handle gamepad (joypad) axis motion (if moved past deadzone)
	elif event is InputEventJoypadMotion and abs(event.axis_value) > AXIS_DEADZONE_THRESHOLD:
		new_event = InputEventJoypadMotion.new()
		new_event.axis = event.axis
		new_event.axis_value = get_normalized_axis_direction(event.axis_value)
		new_event.device = -1

	if new_event == null:
		return

	# ── CONFLICT CHECK ───────────────────────────────────────────────
	# Checks if new_event is already used by another action.
	# :rtype: void
	var conflicts: Array[String] = Settings.get_conflicting_actions(new_event, action)

	# Skip dialog if this is the same binding we already have.
	if not conflicts.is_empty() and not Settings._events_match(new_event, get_matching_event()):
		# Fetch fresh every time (fixes ready-order null reference)
		var km_menu: Node = get_tree().get_first_node_in_group("key_mapping_menu")
		if is_instance_valid(km_menu) and km_menu.has_method("show_conflict_dialog"):
			km_menu.show_conflict_dialog(self, new_event.duplicate(), conflicts)
		else:
			Globals.log_message("key_mapping_menu missing or no show_conflict_dialog method", Globals.LogLevel.ERROR)
			# Fallback: still allow remap if dialog system fails
			erase_old_event()
			InputMap.action_add_event(action, new_event)
			Globals.log_message("Remapped (fallback - no dialog)", Globals.LogLevel.DEBUG)
			finish_remap()
		return

	# ── No conflict → normal remap ───────────────────────────────────
	erase_old_event()
	InputMap.action_add_event(action, new_event)
	Globals.log_message(
		"Remapped '%s' to '%s'" % [action, get_event_label(new_event)],
		Globals.LogLevel.DEBUG
	)
	finish_remap()


# New helper function: Normalizes axis value to a direction (+1.0 or -1.0)
# This keeps the logic clean and reusable if you add more axis features later.
# :param axis_value: The raw axis value from the event.
# :type axis_value: float
# :rtype: float
func get_normalized_axis_direction(axis_value: float) -> float:
	return sign(axis_value) * AXIS_NORMALIZED_VALUE


# Helper to erase old event at index
# Erase old event at index.
# :rtype: void
func erase_old_event() -> void:
	var old_ev: InputEvent = get_matching_event()
	if old_ev:
		InputMap.action_erase_event(action, old_ev)


## Gets matching event for current device.
## :rtype: InputEvent|null
func get_matching_event() -> InputEvent:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	for ev: InputEvent in events:
		if current_device == DeviceType.KEYBOARD and ev is InputEventKey:
			return ev

		if (
			current_device == DeviceType.GAMEPAD
			and (ev is InputEventJoypadButton or ev is InputEventJoypadMotion)
		):
			return ev
	return null


# In input_remap_button.gd, inside finish_remap() func (before Settings.save_input_mappings())
# Finish remap: update display, stop listening, save
# :rtype: void
func finish_remap() -> void:
	update_button_text()
	button_pressed = false
	listening = false
	Settings.save_input_mappings()  # Save the changes
	get_viewport().set_input_as_handled()  # Prevent further input propagation


# Updated to display key, joypad button, or axis label
# :rtype: void
func update_button_text() -> void:
	var ev: InputEvent = get_matching_event()
	text = get_event_label(ev) if ev else "Unbound"


# Get display label for any event type (uses custom dicts only)
# Get label for event (key/button/axis).
# :param event: Input event.
# :type event: InputEvent
# :rtype: String
func get_event_label(event: InputEvent) -> String:
	if event is InputEventKey:
		# FIX: Use physical_keycode for layout-agnostic labels (QWERTY-based).
		# This replaces the invalid 'key_label' and ensures consistency with your dict lookups.
		# OS.get_keycode_string() converts the enum (e.g., KEY_SPACE) to a string like "Space".
		return KEY_LABELS.get(event.physical_keycode, OS.get_keycode_string(event.physical_keycode))

	if event is InputEventJoypadButton:
		return JOY_BUTTON_LABELS.get(event.button_index, "Button " + str(event.button_index))

	if event is InputEventJoypadMotion:
		var axis_labels: Dictionary = JOY_AXIS_LABELS.get(event.axis, {})
		var dir_key: float = event.axis_value  # +1 or -1
		return axis_labels.get(
			dir_key,
			(
				JOY_AXIS_BASE_LABELS.get(event.axis, "Axis " + str(event.axis))
				+ (" +" if dir_key > 0 else " -")
			)
		)
	return "Unbound"
