## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# input_remap_button.gd (full updated script - removes Godot 3.x methods, uses custom dicts only)
# Extends to handle joypad remapping and display (keys, buttons, axes).
# Use device = -1 for "all controllers".
# Handles listening, updating text, saving. Extends Button.
# Button text comes from InputEventCodec.get_event_label().
# Esc cancels keyboard listening, so Esc can't be bound by remapping (#1168).
# :vartype action: String
# :vartype action_event_index: int
# :vartype listening: bool

# gdlint:ignore = class-definitions-order
class_name InputRemapButton

extends Button

# Enum for clean Inspector dropdown + match
enum DeviceType {
	KEYBOARD,
	GAMEPAD,
}

# The axis deadzone is Settings.AXIS_DEADZONE_THRESHOLD, shared with gameplay.
# Value to normalize axis direction to (e.g., +1.0 or -1.0)
const AXIS_NORMALIZED_VALUE: float = 1.0

@export var current_device: DeviceType = DeviceType.KEYBOARD
@export var action: String = ""

var listening: bool = false


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
		# Safely check if Globals and settings are ready
		if is_instance_valid(Globals) and Globals.settings:
			# FIXED: Check the actual current_device to return the correct prompt
			text = (
				Globals.settings.remap_prompt_keyboard
				if current_device == DeviceType.KEYBOARD
				else Globals.settings.remap_prompt_gamepad
			)
		else:
			# Globals.log_message("'Globals.settings' resource is NULL", Globals.LogLevel.ERROR)
			push_error("ERROR: 'Globals.settings' resource is NULL")
			# Fallback prompt so the UI still reflects that we are listening
			text = (
				"Press a key (Esc to cancel)"
				if current_device == DeviceType.KEYBOARD
				else "Press a button"
			)
	else:
		update_button_text()


# In input_remap_button.gd (full updated _input function)
# Input: Handle remap for key/button/motion if listening.
# :param event: Input event.
# :type event: InputEvent
# :rtype: void
func _input(event: InputEvent) -> void:
	# Device-specific filtering
	if not listening or not _is_event_for_current_device(event):
		return

	# ── KEYBOARD CANCEL ── Esc stops listening before any binding logic (#1168).
	if _consume_escape(event):
		return

	var new_event: InputEvent = null

	# ── KEYBOARD HANDLING ──
	if event is InputEventKey and event.pressed:
		# Do not bind "pure" modifiers alone (Shift/Ctrl/Alt/Meta) if you want to support combinations.
		# This waits for the "main" key (like Tab) to be pressed while the modifier is held.
		if event.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
			return

		new_event = InputEventKey.new()
		new_event.physical_keycode = event.physical_keycode
		# CRITICAL: Transfer modifier states to the new event (including Meta for Meta-based shortcuts)
		new_event.shift_pressed = event.shift_pressed
		new_event.ctrl_pressed = event.ctrl_pressed
		new_event.alt_pressed = event.alt_pressed
		new_event.meta_pressed = event.meta_pressed

	# ── GAMEPAD HANDLING ──
	elif event is InputEventJoypadButton and event.pressed:
		new_event = InputEventJoypadButton.new()
		new_event.button_index = event.button_index
		new_event.device = -1
	elif (
		event is InputEventJoypadMotion
		and abs(event.axis_value) >= Settings.AXIS_DEADZONE_THRESHOLD
	):
		new_event = InputEventJoypadMotion.new()
		new_event.axis = event.axis
		new_event.axis_value = get_normalized_axis_direction(event.axis_value)
		new_event.device = -1

	if new_event == null:
		return

	# ── CONFLICT CHECK ──
	var conflicts: Array[String] = Settings.get_conflicting_actions(new_event, action)

	if (
		not conflicts.is_empty()
		and not InputEventCodec.events_match(new_event, get_matching_event())
	):
		var km_menu: Node = get_tree().get_first_node_in_group("key_mapping_menu")
		if is_instance_valid(km_menu) and km_menu.has_method("show_conflict_dialog"):
			km_menu.show_conflict_dialog(self, new_event.duplicate(), conflicts)
			get_viewport().set_input_as_handled()
			return  # Wait for user to confirm or cancel via dialog

	# ── APPLY MAPPING ── (Settings replaces this device's binding and emits bindings_changed)
	Settings.rebind(action, new_event)

	Globals.log_message(
		"Remapped '%s' to '%s'" % [action, InputEventCodec.get_event_label(new_event)],
		Globals.LogLevel.DEBUG
	)

	finish_remap()


## Stops listening without changing the binding (#1168).
##
## Restores the button text and resets the listening state. Doesn't touch [InputMap] and doesn't
## save. Marks the input as handled, so the Esc press that cancels doesn't also reach the menus or
## play the menu cancel sound.
func cancel_listening() -> void:
	update_button_text()
	button_pressed = false
	listening = false
	var viewport: Viewport = get_viewport()
	if viewport:
		viewport.set_input_as_handled()
	Globals.log_message("Remap of '%s' canceled." % action, Globals.LogLevel.DEBUG)


## Returns true if [param event] comes from the device this button remaps: a key for keyboard,
## a joypad button or axis for gamepad.
func _is_event_for_current_device(event: InputEvent) -> bool:
	if current_device == DeviceType.KEYBOARD:
		return event is InputEventKey
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


## Handles Esc while listening on keyboard (#1168). Returns true if [param event] was an Esc
## press, so the caller must not bind it.
##
## Cancels listening, unless the conflict dialog is waiting for this button: then Esc belongs to
## the dialog and the button keeps listening.
func _consume_escape(event: InputEvent) -> bool:
	if current_device != DeviceType.KEYBOARD or not _is_escape_press(event):
		return false
	if not _has_pending_conflict():
		cancel_listening()
	return true


## Returns true for a non-echo Esc press. Checks [member InputEventKey.physical_keycode], which
## binding uses, and falls back to [member InputEventKey.keycode] for synthetic events that only
## set the logical key.
## [param event]: The event to check.
static func _is_escape_press(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return false
	var key_event: InputEventKey = event
	return key_event.physical_keycode == KEY_ESCAPE or key_event.keycode == KEY_ESCAPE


## Returns true while the Key Mapping conflict dialog waits for a decision about this button.
func _has_pending_conflict() -> bool:
	if not is_inside_tree():
		return false
	var km_menu: Node = get_tree().get_first_node_in_group("key_mapping_menu")
	return is_instance_valid(km_menu) and km_menu.get("current_remap_button") == self


# New helper function: Normalizes axis value to a direction (+1.0 or -1.0)
# This keeps the logic clean and reusable if you add more axis features later.
# :param axis_value: The raw axis value from the event.
# :type axis_value: float
# :rtype: float
## Calculates the normalized axis direction based on the provided value.
##
## [param axis_value]: The raw float value of the input axis to evaluate.
## Returns the signed direction multiplied by the normalized value constant.
func get_normalized_axis_direction(axis_value: float) -> float:
	return sign(axis_value) * AXIS_NORMALIZED_VALUE


## Returns the first event bound to action for the current device.
##
## Keyboard buttons match an InputEventKey; gamepad buttons match an InputEventJoypadButton or
## InputEventJoypadMotion. Returns null when the action has no event for that device.
## Returns the matching InputEvent, or [code]null[/code] if none is found
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
## Finalizes the input remapping process and saves changes.
##
## Updates the button text, resets state flags, persists input mappings, and marks the input
## event as handled.
func finish_remap() -> void:
	update_button_text()
	button_pressed = false
	listening = false
	Settings.save_input_mappings()  # Save the changes
	get_viewport().set_input_as_handled()  # Prevent further input propagation


# Updated to display key, joypad button, or axis label
# :rtype: void
## Refresh the button text using the matching input event label.
##
## Retrieves the matching input event, formats the assigned label, removes non-breaking spaces,
## and assigns the resulting string to the button text.
func update_button_text() -> void:
	var ev: InputEvent = get_matching_event()
	text = InputEventCodec.get_event_label(ev).strip_edges() if ev else "Unbound"
	# Remove NBSP (common cause of “looks like a space” failures) + trim.
	text = text.replace("\u00A0", " ").strip_edges()
