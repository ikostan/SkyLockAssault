## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_input_remap_ec.gd
## Covers EC-02, EC-03, EC-08 from #351

extends "res://addons/gut/test.gd"

const InputRemapButton = preload("res://scripts/input_remap_button.gd")

var button: InputRemapButton
const TEST_ACTION: String = "test_action"


func before_each() -> void:
	if InputMap.has_action(TEST_ACTION):
		InputMap.erase_action(TEST_ACTION)
	InputMap.add_action(TEST_ACTION)
	button = InputRemapButton.new()
	button.action = TEST_ACTION
	button.current_device = InputRemapButton.DeviceType.KEYBOARD
	add_child_autofree(button)


func after_each() -> void:
	if InputMap.has_action(TEST_ACTION):
		InputMap.erase_action(TEST_ACTION)
	await get_tree().process_frame


## EC-02 | No device events | Remap triggered without input | Do nothing | UI unchanged
func test_ec_02_remap_cancelled_no_input() -> void:
	var prior_ev := InputEventKey.new()
	prior_ev.physical_keycode = KEY_A
	InputMap.action_add_event(TEST_ACTION, prior_ev)
	var prior_text := button.get_event_label(prior_ev)

	button.button_pressed = true
	button.pressed.emit()                 # start listening
	assert_true(button.listening)
	assert_eq(button.text, Globals.REMAP_PROMPT_TEXT)

	# Cancel by toggling button again (no input event)
	button.button_pressed = false
	button.pressed.emit()

	assert_false(button.listening)
	assert_eq(button.text, prior_text)
	assert_eq(InputMap.action_get_events(TEST_ACTION).size(), 1)


## EC-03 | Unsupported event | Unsupported controller type | Ignore | Don’t crash
func test_ec_03_unsupported_event_ignored() -> void:
	button.current_device = InputRemapButton.DeviceType.GAMEPAD
	button.button_pressed = true
	button.pressed.emit()

	# Mouse, keyboard, or other non-gamepad events
	var mouse_ev := InputEventMouseButton.new()
	mouse_ev.button_index = MOUSE_BUTTON_LEFT  # Valid button to avoid NONE warning

	var key_ev := InputEventKey.new()
	key_ev.keycode = KEY_A  # Optional, but set to valid

	var touch_ev := InputEventScreenTouch.new()
	touch_ev.index = 0  # Valid index

	for ev: InputEvent in [mouse_ev, key_ev, touch_ev]:
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().process_frame

	assert_true(button.listening)  # still listening
	assert_eq(InputMap.action_get_events(TEST_ACTION).size(), 0)  # no change


## EC-08 | Unexpected event flags | Random / invalid values | Ignored | No state change
func test_ec_08_unexpected_event_flags() -> void:
	button.current_device = InputRemapButton.DeviceType.GAMEPAD
	button.button_pressed = true
	button.pressed.emit()

	# Axis below deadzone
	var low_axis := InputEventJoypadMotion.new()
	low_axis.axis = JOY_AXIS_LEFT_X
	low_axis.axis_value = InputRemapButton.AXIS_DEADZONE_THRESHOLD - 0.001
	Input.parse_input_event(low_axis)
	await get_tree().process_frame

	# Button released flag
	var released_btn := InputEventJoypadButton.new()
	released_btn.button_index = JOY_BUTTON_A
	released_btn.pressed = false
	Input.parse_input_event(released_btn)
	await get_tree().process_frame

	assert_eq(InputMap.action_get_events(TEST_ACTION).size(), 0)
	assert_true(button.listening)
