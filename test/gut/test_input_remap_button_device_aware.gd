## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_input_remap_button_device_aware.gd
## GUT unit tests for input_remap_button.gd device-aware event handling.
## Covers IRB-01 to IRB-10 from test plan.
## Test Plan:
## https://github.com/ikostan/SkyLockAssault/issues/348

extends "res://addons/gut/test.gd"

const InputRemapButton: Script = preload("res://scripts/input_remap_button.gd")

var button: InputRemapButton
const TEST_ACTION: String = "test_action"
var test_config_path: String = "user://test_remap.cfg"


## Per-test setup: Reset InputMap for test action, instantiate button.
## :rtype: void
func before_each() -> void:
	if FileAccess.file_exists(test_config_path):
		var err: Error = DirAccess.remove_absolute(test_config_path)
		assert_eq(err, OK)
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
	if FileAccess.file_exists(test_config_path):
		var err: Error = DirAccess.remove_absolute(test_config_path)
		assert_eq(err, OK)
	await get_tree().process_frame


## IRB-01 | Validate keyboard display text | Default keyboard mapping | Trigger update_button_text() with keyboard event | UI shows correct key label | Non-keyboard events produce no change | ✔ | Active tab = InputRemap
## :rtype: void
func test_irb_01() -> void:
	var key_event: InputEventKey = InputEventKey.new()
	key_event.physical_keycode = KEY_A
	InputMap.action_add_event(TEST_ACTION, key_event)
	button.update_button_text()
	assert_eq(button.text, "A")  # From KEY_LABELS fallback OS.get_keycode_string(KEY_A) = "A"
	# Non-keyboard: add gamepad
	var gamepad_event: InputEventJoypadButton = InputEventJoypadButton.new()
	gamepad_event.button_index = JOY_BUTTON_A
	InputMap.action_add_event(TEST_ACTION, gamepad_event)
	var prior_text: String = button.text
	button.update_button_text()  # Still keyboard device
	assert_eq(button.text, prior_text)  # No change
	assert_eq(button.text, "A")


## IRB-02a | Validate gamepad display text | Default gamepad mapping | Trigger update_button_text() with gamepad button | UI shows correct button label | Test missing button mapping | ✔ | Active tab = InputRemap
## :rtype: void
func test_irb_02a() -> void:
	button.current_device = InputRemapButton.DeviceType.GAMEPAD
	var button_event: InputEventJoypadButton = InputEventJoypadButton.new()
	button_event.button_index = JOY_BUTTON_A
	InputMap.action_add_event(TEST_ACTION, button_event)
	button.update_button_text()
	assert_eq(button.text, "A")  # From JOY_BUTTON_LABELS
	# Missing mapping
	InputMap.action_erase_events(TEST_ACTION)
	button.update_button_text()
	assert_eq(button.text, "Unbound")  # Actual unassigned text


## IRB-02b | Validate axis label | Gamepad axis event | Trigger update_button_text() with axis event | UI shows axis string (e.g., “Axis X”) | Very small motions ignored (deadzone) | ✔ | Deadzone threshold defined
## :rtype: void
func test_irb_02b() -> void:
	button.current_device = InputRemapButton.DeviceType.GAMEPAD
	var axis_event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	axis_event.axis = JOY_AXIS_LEFT_X
	axis_event.axis_value = 1.0
	InputMap.action_add_event(TEST_ACTION, axis_event)
	button.update_button_text()
	assert_eq(button.text, "Left Stick (Right)")  # From JOY_AXIS_LABELS


## IRB-03 | Remap keyboard binding | Keyboard mapping enabled | Press new key | Mapping updates to new key; old removed | When no key pressed, mapping unchanged | ✔ | Remapping mode active
## :rtype: void
func test_irb_03() -> void:
	# Prior key
	var prior_key: InputEventKey = InputEventKey.new()
	prior_key.physical_keycode = KEY_A
	InputMap.action_add_event(TEST_ACTION, prior_key)
	# New key
	var new_key: InputEventKey = InputEventKey.new()
	new_key.physical_keycode = KEY_B
	new_key.pressed = true
	button.button_pressed = true
	button.pressed.emit()
	assert_true(button.listening)
	Input.parse_input_event(new_key)
	await get_tree().process_frame
	var events: Array[InputEvent] = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 1)
	assert_eq(events[0].physical_keycode, KEY_B)
	assert_false(button.listening)
	# No press: cancel by toggling button_pressed
	button.button_pressed = true  # Restart listening
	button.pressed.emit()
	assert_true(button.listening)
	button.button_pressed = false  # Cancel
	button.pressed.emit()
	assert_false(button.listening)
	events = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 1)
	assert_eq(events[0].physical_keycode, KEY_B)  # Unchanged


## IRB-04 | Remap gamepad button | Gamepad mapping enabled | Press joystick button | Adds correct mapping for button | Wrong-device events ignored | ✔ | Remap mode with gamepad
## :rtype: void
func test_irb_04() -> void:
	button.current_device = InputRemapButton.DeviceType.GAMEPAD
	# Prior button
	var prior_button: InputEventJoypadButton = InputEventJoypadButton.new()
	prior_button.button_index = JOY_BUTTON_A
	InputMap.action_add_event(TEST_ACTION, prior_button)
	# New button
	var new_button: InputEventJoypadButton = InputEventJoypadButton.new()
	new_button.button_index = JOY_BUTTON_B
	new_button.pressed = true
	button.button_pressed = true
	button.pressed.emit()
	assert_true(button.listening)
	Input.parse_input_event(new_button)
	await get_tree().process_frame
	var events: Array[InputEvent] = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 1)
	assert_eq(events[0].button_index, JOY_BUTTON_B)
	assert_false(button.listening)
	# Wrong device: keyboard during gamepad listen
	button.button_pressed = true
	button.pressed.emit()
	assert_true(button.listening)
	var key_event: InputEventKey = InputEventKey.new()
	key_event.physical_keycode = KEY_A
	key_event.pressed = true
	Input.parse_input_event(key_event)
	await get_tree().process_frame
	events = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 1)  # No add
	assert_eq(events[0].button_index, JOY_BUTTON_B)  # Unchanged
	assert_true(button.listening)  # Continues


## IRB-05 | Validate deadzone threshold | Gamepad remap mode | Inject axis event below deadzone | No mapping change; above adds mapping | Normalized to ±1.0 | ✔ | Deadzone = 0.5
## :rtype: void
func test_irb_05() -> void:
	button.current_device = InputRemapButton.DeviceType.GAMEPAD
	var deadzone_threshold: float = InputRemapButton.AXIS_DEADZONE_THRESHOLD
	button.button_pressed = true
	button.pressed.emit()
	assert_true(button.listening)
	# Below threshold
	var low_axis: InputEventJoypadMotion = InputEventJoypadMotion.new()
	low_axis.axis = JOY_AXIS_LEFT_X
	low_axis.axis_value = deadzone_threshold - 0.01
	Input.parse_input_event(low_axis)
	await get_tree().process_frame
	var events: Array[InputEvent] = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 0)
	assert_true(button.listening)
	# Beyond threshold
	var axis: InputEventJoypadMotion = InputEventJoypadMotion.new()
	axis.axis = JOY_AXIS_LEFT_X
	axis.axis_value = deadzone_threshold + 0.01
	Input.parse_input_event(axis)
	await get_tree().process_frame
	events = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 1)
	assert_eq(events[0].axis, JOY_AXIS_LEFT_X)
	assert_eq(events[0].axis_value, 1.0)  # Normalized
	assert_false(button.listening)


## IRB-06 | Reject wrong-device input | Current mode = gamepad | Inject keyboard event | No change to mapping or UI | Logs ignored events | ✔ | Cross-device event queue
## :rtype: void
func test_irb_06() -> void:
	button.current_device = InputRemapButton.DeviceType.GAMEPAD
	button.button_pressed = true
	button.pressed.emit()
	assert_true(button.listening)
	var key_event: InputEventKey = InputEventKey.new()
	key_event.physical_keycode = KEY_A
	key_event.pressed = true
	Input.parse_input_event(key_event)
	await get_tree().process_frame
	var events: Array[InputEvent] = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 0)  # No change
	assert_true(button.listening)  # Continues


## IRB-07 | Validate unassigned display state | No current mapping | UI shows “Unbound” | Works for all devices | UI doesn’t crash | ✔ | Fresh start or cleared mapping
## :rtype: void
func test_irb_07() -> void:
	button.update_button_text()
	assert_eq(button.text, "Unbound")
	button.current_device = InputRemapButton.DeviceType.GAMEPAD
	button.update_button_text()
	assert_eq(button.text, "Unbound")
	# No crash: call on empty
	InputMap.action_erase_events(TEST_ACTION)
	button.update_button_text()
	assert_eq(button.text, "Unbound")


## IRB-08 | Persistence save & load | After remap | Save settings → reload | Settings persist correctly | Save fails gracefully | ✔ | File storage available
## :rtype: void
func test_irb_08() -> void:
	InputMap.action_erase_events(TEST_ACTION)
	button.current_device = InputRemapButton.DeviceType.KEYBOARD  # Ensure device matches event type.
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


## IRB-09 | Tab switching behavior | Multiple UI tabs | Switch between tabs | Keyboard tab shows keyboard; gamepad tab shows gamepad | Rapid switch doesn’t crash UI | ✔ | Both tabs tested
## :rtype: void
func test_irb_09() -> void:
	# Add events for both
	var key_event: InputEventKey = InputEventKey.new()
	key_event.physical_keycode = KEY_A
	InputMap.action_add_event(TEST_ACTION, key_event)
	var button_event: InputEventJoypadButton = InputEventJoypadButton.new()
	button_event.button_index = JOY_BUTTON_A
	InputMap.action_add_event(TEST_ACTION, button_event)
	# Keyboard tab
	button.current_device = InputRemapButton.DeviceType.KEYBOARD
	button.update_button_text()
	assert_eq(button.text, "A")
	# Switch to gamepad
	button.current_device = InputRemapButton.DeviceType.GAMEPAD
	button.update_button_text()
	assert_eq(button.text, "A")
	# Rapid switch: repeat multiple times
	for i: int in range(5):
		button.current_device = InputRemapButton.DeviceType.KEYBOARD if i % 2 == 0 else InputRemapButton.DeviceType.GAMEPAD
		button.update_button_text()
	assert_not_null(button.text)  # No crash


## IRB-10 | Invalid event filtering | Invalid or null input | Send malformed event | No mapping applied; logged error | Crash-safe handling | ✔ | Error handling enabled
## :rtype: void
func test_irb_10() -> void:
	button.button_pressed = true
	button.pressed.emit()
	assert_true(button.listening)
	# Malformed: e.g., InputEventMouseButton as proxy for invalid
	var invalid_event: InputEventMouseButton = InputEventMouseButton.new()
	invalid_event.button_index = MOUSE_BUTTON_LEFT
	invalid_event.pressed = true
	Input.parse_input_event(invalid_event)
	await get_tree().process_frame
	var events: Array[InputEvent] = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 0)  # No apply
	assert_true(button.listening)  # Continues
