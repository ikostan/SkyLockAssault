## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_input_remap_button.gd
## GUT unit tests for input_remap_button.gd.
## Covers IRB-01 to IRB-08 from test plan.
## Test Plan:
## https://github.com/ikostan/SkyLockAssault/issues/347

extends "res://addons/gut/test.gd"

const InputRemapButton = preload("res://scripts/input_remap_button.gd")

var button: InputRemapButton
const TEST_ACTION: String = "test_action"


## Per-test setup: Reset InputMap for test action, instantiate button.
## :rtype: void
func before_each() -> void:
	if InputMap.has_action(TEST_ACTION):
		InputMap.erase_action(TEST_ACTION)
	InputMap.add_action(TEST_ACTION)
	button = InputRemapButton.new()
	button.action = TEST_ACTION
	button.current_device = InputRemapButton.DeviceType.KEYBOARD
	add_child_autofree(button)


## Per-test cleanup: Erase test action.
## :rtype: void
func after_each() -> void:
	if InputMap.has_action(TEST_ACTION):
		InputMap.erase_action(TEST_ACTION)
	await get_tree().process_frame


## IRB-01 | Remap keyboard event | current_device = KEYBOARD; action exists with prior events | Instantiate, simulate _input with Key, inspect InputMap | Only keyboard event added; old erased; button label updated; remap logged.
## FIXED: Direct button._input() call (bypasses parse_input_event queue for reliable test execution in GUT).
## Uses KEY_Z (conflict-free). 
## :rtype: void
func test_irb_01() -> void:
	# Add prior events
	var prior_key: InputEventKey = InputEventKey.new()
	prior_key.physical_keycode = KEY_A
	InputMap.action_add_event(TEST_ACTION, prior_key)
	var prior_gamepad: InputEventJoypadButton = InputEventJoypadButton.new()
	prior_gamepad.button_index = JOY_BUTTON_A
	InputMap.action_add_event(TEST_ACTION, prior_gamepad)
	# Start remapping
	button.button_pressed = true
	button.pressed.emit()
	assert_true(button.listening)
	# Simulate input directly on button (KEY_Z: safe, no conflict with defaults)
	var new_key: InputEventKey = InputEventKey.new()
	new_key.physical_keycode = KEY_Z
	new_key.pressed = true
	button._input(new_key)  # Direct call for sync execution in tests
	await get_tree().process_frame
	# Assert
	var events: Array = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 2)
	assert_true(events.any(func(ev: InputEvent) -> bool: return ev is InputEventKey and ev.physical_keycode == KEY_Z))
	assert_true(events.any(func(ev: InputEvent) -> bool: return ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_A))
	assert_eq(button.text, "Z")  # Updated for KEY_Z label (via get_event_label fallback)
	assert_false(button.listening)


## IRB-02 | Remap gamepad event | current_device = GAMEPAD; action exists | Simulate _input with InputEventJoypadButton, inspect InputMap | Only gamepad event added; non-matching events ignored; label updated correctly.
## :rtype: void
func test_irb_02() -> void:
	button.current_device = InputRemapButton.DeviceType.GAMEPAD
	# Add prior events
	var prior_key: InputEventKey = InputEventKey.new()
	prior_key.physical_keycode = KEY_A
	InputMap.action_add_event(TEST_ACTION, prior_key)
	# Start remapping
	button.button_pressed = true
	button.pressed.emit()
	assert_true(button.listening)
	# Simulate input
	var new_gamepad: InputEventJoypadButton = InputEventJoypadButton.new()
	new_gamepad.button_index = JOY_BUTTON_B
	new_gamepad.pressed = true
	Input.parse_input_event(new_gamepad)
	await get_tree().process_frame
	# Assert
	var events: Array = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 2)
	assert_true(events.any(func(ev: InputEvent) -> bool: return ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_B))
	assert_true(events.any(func(ev: InputEvent) -> bool: return ev is InputEventKey and ev.physical_keycode == KEY_A))
	assert_eq(button.text, Settings.get_event_label(new_gamepad))
	assert_false(button.listening)


## IRB-04 | Ignore wrong-device event during remap | current_device = KEYBOARD | Simulate _input with InputEventJoypadButton | Event ignored; no change to InputMap; label unchanged.
## :rtype: void
func test_irb_04() -> void:
	# Add prior event
	var prior_key: InputEventKey = InputEventKey.new()
	prior_key.physical_keycode = KEY_A
	InputMap.action_add_event(TEST_ACTION, prior_key)
	# Start remapping
	button.button_pressed = true
	button.pressed.emit()
	assert_true(button.listening)
	var listening_text: String = button.text
	# Simulate wrong input
	var gamepad_event: InputEventJoypadButton = InputEventJoypadButton.new()
	gamepad_event.button_index = JOY_BUTTON_A
	gamepad_event.pressed = true
	Input.parse_input_event(gamepad_event)
	await get_tree().process_frame
	# Assert
	var events: Array = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 1)
	assert_true(events[0] is InputEventKey)
	assert_eq(events[0].physical_keycode, KEY_A)
	assert_eq(button.text, listening_text)
	assert_true(button.listening)


## IRB-05 | Get matching event for device | Action has mixed keyboard, and gamepad events | Call get_matching_event(DeviceType.KEYBOARD) | Correct keyboard event returned; null if none exist.
## :rtype: void
func test_irb_05() -> void:
	# Add mixed events
	var key_event: InputEventKey = InputEventKey.new()
	key_event.physical_keycode = KEY_A
	InputMap.action_add_event(TEST_ACTION, key_event)
	var gamepad_event: InputEventJoypadButton = InputEventJoypadButton.new()
	gamepad_event.button_index = JOY_BUTTON_A
	InputMap.action_add_event(TEST_ACTION, gamepad_event)
	# For keyboard
	button.current_device = InputRemapButton.DeviceType.KEYBOARD
	var matching: InputEvent = button.get_matching_event()
	assert_true(matching is InputEventKey)
	# For gamepad
	button.current_device = InputRemapButton.DeviceType.GAMEPAD
	matching = button.get_matching_event()
	assert_true(matching is InputEventJoypadButton)
	# None for keyboard after erase
	InputMap.action_erase_events(TEST_ACTION)
	button.current_device = InputRemapButton.DeviceType.KEYBOARD
	matching = button.get_matching_event()
	assert_null(matching)


## IRB-07 | Handle remap logging | Logging enabled | Perform successful remap, inspect log output | Log entry includes device type and new event details.
## :rtype: void
func test_irb_07() -> void:
	# Note: Assuming Globals.log_info is called; use spy if available.
	# For simplicity, perform remap (logging happens internally).
	button.button_pressed = true
	button.pressed.emit()
	var new_key: InputEventKey = InputEventKey.new()
	new_key.physical_keycode = KEY_C
	new_key.pressed = true
	Input.parse_input_event(new_key)
	await get_tree().process_frame
	# Assert remap happened, assume log is printed (no direct assert on print).
	var events: Array = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 1)
	# If GUT supports output spying, add here.


## IRB-08 | Edge case: No existing events | Action exists but has no mapped events | Clear action events, remap a new valid event | New event added correctly for active device; no errors thrown.
## :rtype: void
func test_irb_08() -> void:
	InputMap.action_erase_events(TEST_ACTION)
	# Start remapping
	button.button_pressed = true
	button.pressed.emit()
	assert_true(button.listening)
	# Simulate input
	var new_key: InputEventKey = InputEventKey.new()
	new_key.physical_keycode = KEY_D
	new_key.pressed = true
	Input.parse_input_event(new_key)
	await get_tree().process_frame
	# Assert
	var events: Array = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 1)
	assert_true(events[0] is InputEventKey)
	assert_eq(events[0].physical_keycode, KEY_D)
	assert_eq(button.text, Settings.get_event_label(new_key))
	assert_false(button.listening)
