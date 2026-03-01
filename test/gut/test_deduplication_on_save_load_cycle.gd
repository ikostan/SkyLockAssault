## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_deduplication_on_save_load_cycle.gd
## Additional GUT unit test to ensure save-load cycle doesn't introduce duplicates.
## Scenario: Add duplicate manually, save, load → dedup on load.
## Fails if duplicates persist after cycle.
## :references: settings.gd save_input_mappings(), load_input_mappings()

extends GutTest

const TEST_ACTION: String = "speed_up"
const TEST_CONFIG_PATH: String = "user://test_dedup_cycle.cfg"


## Per-test: Setup with duplicate in InputMap.
func before_each() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	InputMap.action_erase_events(TEST_ACTION)
	InputMap.add_action(TEST_ACTION)
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = KEY_W
	InputMap.action_add_event(TEST_ACTION, ev)
	InputMap.action_add_event(TEST_ACTION, ev.duplicate())  # Dup


## Per-test: Cleanup.
func after_each() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)


## DEDUP-08 | Save with dups, load → dedup | Size 1 after load
func test_dedup_08_save_load_cycle() -> void:
	Settings.save_input_mappings(TEST_CONFIG_PATH)
	InputMap.action_erase_events(TEST_ACTION)
	Settings.load_input_mappings(TEST_CONFIG_PATH)
	var events: Array[InputEvent] = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 1, "Save-load should deduplicate")
