## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_deduplication_on_remap.gd
## Additional GUT unit test to ensure remap doesn't add duplicates.
## Scenario: Remap to existing event → no add, or dedup.
## Fails if InputMap has duplicates after remap.
## :references: input_remap_button.gd _input()

extends GutTest

const InputRemapButton: Script = preload("res://scripts/input_remap_button.gd")
const TEST_ACTION: String = "speed_up"

var button: InputRemapButton


## Per-test: Setup button with existing event.
func before_each() -> void:
	InputMap.action_erase_events(TEST_ACTION)
	if not InputMap.has_action(TEST_ACTION):
		InputMap.add_action(TEST_ACTION)
	InputMap.add_action(TEST_ACTION)
	var existing_ev: InputEventKey = InputEventKey.new()
	existing_ev.physical_keycode = KEY_W
	InputMap.action_add_event(TEST_ACTION, existing_ev)
	button = InputRemapButton.new()
	button.action = TEST_ACTION
	button.current_device = InputRemapButton.DeviceType.KEYBOARD
	add_child_autofree(button)


## DEDUP-02 | Remap to same existing event → no duplicate | Size remains 1
func test_dedup_02_remap_to_existing() -> void:
	button.button_pressed = true
	button._on_pressed()
	var same_ev: InputEventKey = InputEventKey.new()
	same_ev.physical_keycode = KEY_W
	same_ev.pressed = true
	button._input(same_ev)
	var events: Array[InputEvent] = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 1, "Remap to same should not add duplicate")
