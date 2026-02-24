## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_deduplication_on_device_switch.gd
## Additional GUT unit test to ensure device switch during remap doesn't duplicate.
## Scenario: Start remap, switch device, input → no cross-device dups or extras.
## Fails if duplicates or wrong device events.
## :references: key_mapping.gd update_all_remap_buttons(), input_remap_button.gd

extends GutTest

const InputRemapButton: Script = preload("res://scripts/input_remap_button.gd")
const TEST_ACTION: String = "speed_up"

var button: InputRemapButton


## Per-test: Setup button with listening.
func before_each() -> void:
	InputMap.action_erase_events(TEST_ACTION)
	if not InputMap.has_action(TEST_ACTION):
		InputMap.add_action(TEST_ACTION)
	button = InputRemapButton.new()
	button.action = TEST_ACTION
	button.current_device = InputRemapButton.DeviceType.KEYBOARD
	add_child_autofree(button)
	button.button_pressed = true
	button._on_pressed()


func after_each() -> void:
	InputMap.action_erase_events(TEST_ACTION)


## DEDUP-07 | Device switch mid-remap → input on new device, no dup on old | Correct event, no extras
func test_dedup_07_device_switch_mid_remap() -> void:
	# Switch to gamepad mid-listen
	button.current_device = InputRemapButton.DeviceType.GAMEPAD
	# Input gamepad event
	var gp_ev: InputEventJoypadButton = InputEventJoypadButton.new()
	gp_ev.button_index = JOY_BUTTON_A
	gp_ev.pressed = true
	button._input(gp_ev)
	var events: Array[InputEvent] = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 1, "Switch mid-remap should add only new, no dup")
	if events.size() > 0:
		assert_true(events[0] is InputEventJoypadButton, "Event should be InputEventJoypadButton, not keyboard event")
