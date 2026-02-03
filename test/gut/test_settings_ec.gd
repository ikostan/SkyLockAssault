## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_settings_ec.gd
## Covers EC-01, EC-04, EC-05, EC-06, EC-07 from #351

extends "res://addons/gut/test.gd"

const TEST_ACTION: String = "speed_up"
var test_config_path: String = "user://test_settings_ec.cfg"
var invalid_path: String = "res://invalid/unwritable.cfg"  # Simulate permission/disk-full
var original_input_map: Dictionary = {}


func before_all() -> void:
	for act: String in InputMap.get_actions():
		original_input_map[act] = InputMap.action_get_events(act)


func after_all() -> void:
	for act in InputMap.get_actions():
		InputMap.action_erase_events(act)
	for act: String in original_input_map:
		if not InputMap.has_action(act):
			InputMap.add_action(act)
		for ev: InputEvent in original_input_map[act]:
			InputMap.action_add_event(act, ev)


func before_each() -> void:
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)
	for act in Settings.ACTIONS:
		if InputMap.has_action(act):
			InputMap.action_erase_events(act)
		else:
			InputMap.add_action(act)
	Settings.load_input_mappings(test_config_path)  # ensure clean defaults


func after_each() -> void:
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)


## EC-01 | Invalid config values | Corrupted entry in file | Use defaults | Log warning
func test_ec_01_invalid_config_values() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", TEST_ACTION, ["key:abc", "joybtn:999:foo", "unknown:xxx", 999, "joyaxis:0:1.0:bar"])
	cfg.set_value("input", "move_left", ["key:65"])  # valid
	cfg.save(test_config_path)

	Settings.load_input_mappings(test_config_path)

	var events := InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 2)
	assert_true(events.any(func(e: InputEvent) -> bool: return e is InputEventKey and e.physical_keycode == Settings.DEFAULT_KEYBOARD[TEST_ACTION]))
	assert_true(events.any(func(e: InputEvent) -> bool: return e is InputEventJoypadMotion and e.axis == Settings.DEFAULT_GAMEPAD[TEST_ACTION]["axis"] and e.axis_value == Settings.DEFAULT_GAMEPAD[TEST_ACTION]["value"]))


## EC-04 | Legacy config formats | Mixed old/new types | Backfill defaults, preserve valid
func test_ec_04_legacy_mixed_formats() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", TEST_ACTION, 87)                    # old int
	cfg.set_value("input", "speed_down", "key:88")             # old string key
	cfg.set_value("input", "fire", ["joybtn:0:-1"])            # new format
	cfg.set_value("input", "move_left", ["key:65", "key:66"])  # valid new
	cfg.save(test_config_path)
	Settings.load_input_mappings(test_config_path)

	# speed_up should have migrated from old int
	var events := InputMap.action_get_events(TEST_ACTION)
	assert_true(events.any(func(e: InputEvent) -> bool:
		return e is InputEventKey and e.physical_keycode == 87
	))
	# defaults backfilled where missing
	assert_true(InputMap.action_get_events("pause").any(func(e: InputEvent) -> bool: return e is InputEventKey))


## EC-05 | Config unreadable | Corrupt JSON/parse error | Load defaults | Log error
func test_ec_05_corrupt_parse_error() -> void:
	# Simulate corrupt cfg file
	var f := FileAccess.open(test_config_path, FileAccess.WRITE)
	f.store_string("{invalid cfg data\n[broken")
	f.close()

	Settings.load_input_mappings(test_config_path)  # should still fall back to defaults

	var events := InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 2)
	assert_true(events.any(func(e: InputEvent) -> bool: return e is InputEventKey and e.physical_keycode == Settings.DEFAULT_KEYBOARD[TEST_ACTION]))
	assert_true(events.any(func(e: InputEvent) -> bool: return e is InputEventJoypadMotion and e.axis == Settings.DEFAULT_GAMEPAD[TEST_ACTION]["axis"] and e.axis_value == Settings.DEFAULT_GAMEPAD[TEST_ACTION]["value"]))


## EC-06 | Save fails | Disk full / permission denied | Report error, no crash
func test_ec_06_save_fails_gracefully() -> void:
	# Force failure path
	Settings.save_input_mappings(invalid_path)

	# No crash occurred, InputMap is still valid
	assert_true(InputMap.has_action(TEST_ACTION))
	# File was not created
	assert_false(FileAccess.file_exists(invalid_path))


## EC-07 | Partial config types | Extra unknown keys | Only known entries loaded
func test_ec_07_extra_unknown_keys_ignored() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", TEST_ACTION, ["key:87"])
	cfg.set_value("input", "non_existent_action", ["key:999"])  # not in ACTIONS
	cfg.set_value("other_section", "foo", "bar")
	cfg.save(test_config_path)

	Settings.load_input_mappings(test_config_path)
	Settings.save_input_mappings(test_config_path)  # round-trip

	cfg = ConfigFile.new()
	cfg.load(test_config_path)
	assert_true(cfg.has_section("other_section"))  # preserved
	assert_false(InputMap.has_action("non_existent_action"))  # ignored
