## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_deduplication_on_load.gd
## Additional GUT unit test to ensure duplicates in config are deduplicated on load.
## Scenario: Config has duplicate events (e.g., same key twice) → load dedups to unique events.
## Fails if InputMap has duplicates after load.
## :references: settings.gd load_input_mappings()

extends GutTest

const TEST_ACTION: String = "speed_up"
const TEST_CONFIG_PATH: String = "user://test_dedup_load.cfg"
const KEY_W_CODE: int = KEY_W

var config: ConfigFile = ConfigFile.new()

## Per-test: Delete temp config.
func before_each() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	InputMap.action_erase_events(TEST_ACTION)


## Per-test: Delete temp.
func after_each() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	# Restore fire bindings so subsequent tests see clean state.
	Settings.load_input_mappings(Settings.CONFIG_PATH, [TEST_ACTION])


## DEDUP-01 | Config with duplicate keys → load dedups | Unique events in InputMap
func test_dedup_01_load_config_duplicates() -> void:
	# Setup: Config with duplicates (e.g., "key:87" twice)
	config.set_value("input", TEST_ACTION, ["key:" + str(KEY_W_CODE), "key:" + str(KEY_W_CODE)])
	config.save(TEST_CONFIG_PATH)
	# Load
	Settings.load_input_mappings(TEST_CONFIG_PATH)
	# Assert: Only one event
	var events: Array[InputEvent] = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 1, "Duplicates should be deduplicated on load")
	assert_true(events[0] is InputEventKey and events[0].physical_keycode == KEY_W_CODE)
