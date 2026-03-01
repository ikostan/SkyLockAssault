## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_deduplication_on_rapid_remap.gd
## Additional GUT unit test to ensure rapid remaps don't create duplicates.
## Scenario: Multiple quick remaps to same/different → no dups.
## Fails if InputMap has duplicates after series.
## :references: input_remap_button.gd _input()

extends GutTest

const InputRemapButton: Script = preload("res://scripts/input_remap_button.gd")
const TEST_ACTION: String = "speed_up"

var button: InputRemapButton


## Per-test: Setup button.
func before_each() -> void:
	InputMap.action_erase_events(TEST_ACTION)
	if not InputMap.has_action(TEST_ACTION):
		InputMap.add_action(TEST_ACTION)
	button = InputRemapButton.new()
	button.action = TEST_ACTION
	button.current_device = InputRemapButton.DeviceType.KEYBOARD
	add_child_autofree(button)


func after_each() -> void:
	InputMap.action_erase_events(TEST_ACTION)


## DEDUP-06 | Rapid remaps to same event → dedup, size 1
func test_dedup_06_rapid_remap_same() -> void:
	for i in range(5):
		button.button_pressed = true
		button._on_pressed()
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = KEY_W
		ev.pressed = true
		button._input(ev)
		await get_tree().process_frame
	var events: Array[InputEvent] = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 1, "Rapid same remaps should not create duplicates")
