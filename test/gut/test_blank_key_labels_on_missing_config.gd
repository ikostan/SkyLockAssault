## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_blank_key_labels_on_missing_config.gd
## GUT unit tests to reproduce the "blank key label" UI bug:
## When config is missing (fresh install / migration) or an action entry is missing,
## Settings.load_input_mappings() keeps project-default InputMap events.
## If the project-default InputEventKey has physical_keycode == 0 (but keycode set),
## InputRemapButton.get_event_label() returns "" and the Key Mapping menu shows an empty value.
##
## Keyboard tests are expected to FAIL until a fix is implemented.
## Gamepad tests are EXPECTED TO PASS (they are regression guards) because the blank-label bug
## is specific to keyboard physical_keycode usage.
##
## References:
## - res://scripts/settings.gd (load_input_mappings, _add_missing_defaults)
## - res://scripts/input_remap_button.gd (get_event_label)

extends GutTest

const InputRemapButton := preload("res://scripts/input_remap_button.gd")

const TEST_CONFIG_MISSING_PATH: String = "user://test_blank_missing.cfg"
const TEST_CONFIG_PARTIAL_PATH: String = "user://test_blank_partial.cfg"

const TEST_ACTION: String = "test_blank_action"
const OTHER_ACTION: String = "test_other_action"

const KEY_DEFAULT: int = KEY_W


## Per-test setup: ensure actions exist and temp files are removed.
## :rtype: void
func before_each() -> void:
	# Remove temp config files (if any).
	if FileAccess.file_exists(TEST_CONFIG_MISSING_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_MISSING_PATH)
	if FileAccess.file_exists(TEST_CONFIG_PARTIAL_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PARTIAL_PATH)

	# Reset actions for isolation.
	if InputMap.has_action(TEST_ACTION):
		InputMap.erase_action(TEST_ACTION)
	if InputMap.has_action(OTHER_ACTION):
		InputMap.erase_action(OTHER_ACTION)

	InputMap.add_action(TEST_ACTION)
	InputMap.add_action(OTHER_ACTION)

	# Simulate a "project default" keyboard event that has keycode set but physical_keycode = 0.
	# This is the condition that leads to an empty label in InputRemapButton.get_event_label().
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = KEY_DEFAULT
	ev.physical_keycode = 0
	InputMap.action_add_event(TEST_ACTION, ev)


## Per-test cleanup.
## :rtype: void
func after_each() -> void:
	if InputMap.has_action(TEST_ACTION):
		InputMap.erase_action(TEST_ACTION)
	if InputMap.has_action(OTHER_ACTION):
		InputMap.erase_action(OTHER_ACTION)

	if FileAccess.file_exists(TEST_CONFIG_MISSING_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_MISSING_PATH)
	if FileAccess.file_exists(TEST_CONFIG_PARTIAL_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PARTIAL_PATH)

	await get_tree().process_frame


## Helper: create a remap button for an action and return the displayed label for the current device.
## :param action: Input action name.
## :param device: Device type to use.
## :type action: String
## :type device: int
## :rtype: String
func _get_label_for(action: String, device: int) -> String:
	var button: InputRemapButton = InputRemapButton.new()
	button.action = action
	button.current_device = device
	add_child_autofree(button)

	var ev: InputEvent = button.get_matching_event()
	if ev == null:
		return "Unbound"
	return Settings.get_event_label(ev)


## Helper: create and save a config file that contains a single joypad mapping for OTHER_ACTION,
## leaving TEST_ACTION missing.
## :param path: Target config path.
## :type path: String
## :rtype: void
func _write_partial_config_with_other_action_gamepad(path: String) -> void:
	var cfg: ConfigFile = ConfigFile.new()

	# Note: Settings.deserialize_event expects formats like "joy:btn:<index>" / "joy:axis:..."
	# We mirror the same scheme used elsewhere in the project tests.
	cfg.set_value("input", OTHER_ACTION, ["joy:btn:%d" % JOY_BUTTON_A])

	var err: int = cfg.save(path)
	assert_eq(err, OK, "Precondition failed: could not write test config.")


## BLANK-01 | Missing config file (fresh install / migration) keeps project defaults.
## Expected behavior (post-fix): label should NOT be empty for keyboard.
## Current behavior (pre-fix): label is "" because physical_keycode == 0.
## :rtype: void
func test_blank_01_missing_config_keeps_project_default_physical_0_keyboard_label_is_not_empty() -> void:
	# Act: load with a missing file, restricted to TEST_ACTION.
	Settings.load_input_mappings(TEST_CONFIG_MISSING_PATH, [TEST_ACTION])

	# Assert: this should be "W" (or any non-empty string), but currently is "".
	var label: String = _get_label_for(TEST_ACTION, InputRemapButton.DeviceType.KEYBOARD)
	assert_ne(label, "", "Keyboard label must not be empty when config is missing; should fall back to a real key name.")


## BLANK-02 | Config exists but action key is missing (migration / new action added).
## Expected behavior (post-fix): label should NOT be empty for keyboard.
## Current behavior (pre-fix): label is "" because physical_keycode == 0 is treated as 'has_keyboard'.
## :rtype: void
func test_blank_02_action_key_missing_keeps_project_default_physical_0_keyboard_label_is_not_empty() -> void:
	# Arrange: write config with some other action, but NOT TEST_ACTION.
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("input", OTHER_ACTION, ["key:%d" % KEY_DEFAULT])
	var err: int = cfg.save(TEST_CONFIG_PARTIAL_PATH)
	assert_eq(err, OK, "Precondition failed: could not write test config.")

	# Act: load config restricted to TEST_ACTION only. This simulates "action missing in local storage".
	Settings.load_input_mappings(TEST_CONFIG_PARTIAL_PATH, [TEST_ACTION])

	# Assert: should not be blank, but currently is "".
	var label: String = _get_label_for(TEST_ACTION, InputRemapButton.DeviceType.KEYBOARD)
	assert_ne(label, "", "Keyboard label must not be empty when action key is missing; should fall back to a real key name.")


## GAMEPAD-01 | Missing config: project-default joypad mapping should show non-empty label.
## This is expected to PASS (regression guard).
## :rtype: void
func test_gamepad_01_missing_config_project_default_joypad_label_is_not_empty() -> void:
	# Arrange: replace keyboard default with a joypad default.
	InputMap.action_erase_events(TEST_ACTION)
	var gev: InputEventJoypadButton = InputEventJoypadButton.new()
	gev.button_index = JOY_BUTTON_A
	gev.device = 0
	InputMap.action_add_event(TEST_ACTION, gev)

	# Act
	Settings.load_input_mappings(TEST_CONFIG_MISSING_PATH, [TEST_ACTION])

	# Assert
	var label: String = _get_label_for(TEST_ACTION, InputRemapButton.DeviceType.GAMEPAD)
	assert_ne(label, "", "Gamepad label must not be empty when config is missing.")


## GAMEPAD-02 | Action key missing in config: project-default joypad mapping should show non-empty label.
## This is expected to PASS (regression guard).
## :rtype: void
func test_gamepad_02_action_key_missing_project_default_joypad_label_is_not_empty() -> void:
	# Arrange: ensure project-default is joypad.
	InputMap.action_erase_events(TEST_ACTION)
	var gev: InputEventJoypadButton = InputEventJoypadButton.new()
	gev.button_index = JOY_BUTTON_A
	gev.device = 0
	InputMap.action_add_event(TEST_ACTION, gev)

	# Write config that does NOT include TEST_ACTION (simulates new action after migration).
	_write_partial_config_with_other_action_gamepad(TEST_CONFIG_PARTIAL_PATH)

	# Act: load restricted to TEST_ACTION.
	Settings.load_input_mappings(TEST_CONFIG_PARTIAL_PATH, [TEST_ACTION])

	# Assert
	var label: String = _get_label_for(TEST_ACTION, InputRemapButton.DeviceType.GAMEPAD)
	assert_ne(label, "", "Gamepad label must not be empty when action key is missing.")


## GAMEPAD-03 | Mixed defaults: keyboard physical_keycode==0 + joypad present.
## Ensure GAMEPAD device selects joypad mapping (not keyboard), and label is non-empty.
## This is expected to PASS (regression guard).
## :rtype: void
func test_gamepad_03_mixed_defaults_gamepad_selects_joypad_event_and_label_is_not_empty() -> void:
	# Arrange: keep the keyboard event (physical_keycode == 0) from before_each,
	# and add a joypad event as well.
	var gev: InputEventJoypadButton = InputEventJoypadButton.new()
	gev.button_index = JOY_BUTTON_A
	gev.device = 0
	InputMap.action_add_event(TEST_ACTION, gev)

	# Act: missing config => keep project defaults.
	Settings.load_input_mappings(TEST_CONFIG_MISSING_PATH, [TEST_ACTION])

	# Assert: GAMEPAD should match joypad event and have non-empty label.
	var label: String = _get_label_for(TEST_ACTION, InputRemapButton.DeviceType.GAMEPAD)
	assert_ne(label, "", "Gamepad label must not be empty; GAMEPAD device should pick joypad mapping even if keyboard is blankable.")
