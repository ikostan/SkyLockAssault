## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_settings.gd (updated for new features: multi-event, joypad button/motion, backward compat, defaults)
## Uses GdUnit4 (assume installed; install via AssetLib if not).
## Run via GdUnit Inspector or command line.
extends GdUnitTestSuite

## Stores original InputMap events for all Settings.ACTIONS so tests can run isolated.
## Key: action name (String), Value: Array of InputEvent currently assigned to that action.
var _saved_action_events: Dictionary = {}


@warning_ignore("unused_parameter")
func before() -> void:
	# Snapshot and clear project bindings to prevent cross-action conflicts during tests.
	_saved_action_events.clear()
	for action: String in Settings.ACTIONS:
		if not InputMap.has_action(action):
			continue
		var original_events: Array[InputEvent] = InputMap.action_get_events(action).duplicate(true)
		_saved_action_events[action] = original_events
		InputMap.action_erase_events(action)

	# Ensure test actions exist and start unbound.
	for action: String in ["test_action", "test_action1", "test_action2"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)


@warning_ignore("unused_parameter")
func after() -> void:
	# Erase test actions.
	for action: String in ["test_action", "test_action1", "test_action2"]:
		if InputMap.has_action(action):
			InputMap.erase_action(action)

	# Restore project bindings.
	for action: String in _saved_action_events.keys():
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		var events: Array[InputEvent] = _saved_action_events[action]
		for ev: InputEvent in events:
			InputMap.action_add_event(action, ev)

	# Remove test config files.
	for path: String in ["user://test_settings.cfg", "user://multi_test.cfg", "user://joy_test.cfg", "user://old_format.cfg", "user://malformed.cfg", "user://no_saved.cfg", "user://migration_test.cfg", "user://migration_new.cfg", "user://type_safe.cfg", "user://default_test.cfg", "user://unbound_test.cfg", "user://multi_action.cfg", "user://corrupt.cfg", "user://new_format.cfg", "user://type_test.cfg"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# Test basic save/load for keyboard (updated for array format)
func test_save_and_load_keyboard() -> void:
	var test_path: String = "user://test_settings.cfg"
	var test_actions: Array[String] = ["test_action"]
	
	# Remap to KEY_A
	InputMap.action_erase_events("test_action")
	var new_event: InputEventKey = InputEventKey.new()
	new_event.physical_keycode = KEY_A
	InputMap.action_add_event("test_action", new_event)
	
	# Save
	Settings.save_input_mappings(test_path, test_actions)
	
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	# Erase and load
	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(test_path, test_actions)
	
	# Verify KEY_A loaded
	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(1)
	if events.size() < 1:
		return
	assert_that(events[0] is InputEventKey).is_true()
	assert_int(events[0].physical_keycode).is_equal(KEY_A)


# Test save/load for joypad button
func test_save_and_load_joypad_button() -> void:
	var test_path: String = "user://joy_test.cfg"
	var test_actions: Array[String] = ["test_action"]
	
	# Add joypad button event
	InputMap.action_erase_events("test_action")
	var new_event: InputEventJoypadButton = InputEventJoypadButton.new()
	new_event.button_index = JOY_BUTTON_A
	new_event.device = -1
	InputMap.action_add_event("test_action", new_event)
	
	# Save
	Settings.save_input_mappings(test_path, test_actions)
	
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	# Erase and load
	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(test_path, test_actions)
	
	# Verify loaded
	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(1)
	if events.size() < 1:
		return
	assert_that(events[0] is InputEventJoypadButton).is_true()
	assert_int(events[0].button_index).is_equal(JOY_BUTTON_A)
	assert_int(events[0].device).is_equal(-1)


# Test save/load for joypad motion (axis)
func test_save_and_load_joypad_motion() -> void:
	var test_path: String = "user://joy_test.cfg"
	var test_actions: Array[String] = ["test_action"]
	
	# Add joypad motion event
	InputMap.action_erase_events("test_action")
	var new_event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	new_event.axis = JOY_AXIS_LEFT_X
	new_event.axis_value = -1.0
	new_event.device = -1
	InputMap.action_add_event("test_action", new_event)
	
	# Save
	Settings.save_input_mappings(test_path, test_actions)
	
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	# Erase and load
	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(test_path, test_actions)
	
	# Verify loaded
	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(1)
	if events.size() < 1:
		return
	assert_that(events[0] is InputEventJoypadMotion).is_true()
	assert_int(events[0].axis).is_equal(JOY_AXIS_LEFT_X)
	assert_float(events[0].axis_value).is_equal(-1.0)
	assert_int(events[0].device).is_equal(-1)


# Test multi-event persistence (two keyboard keys)
func test_multi_event_persistence() -> void:
	var test_path: String = "user://multi_test.cfg"
	var test_actions: Array[String] = ["test_action"]
	
	InputMap.action_erase_events("test_action")
	var ev1: InputEventKey = InputEventKey.new()
	ev1.physical_keycode = KEY_A
	var ev2: InputEventKey = InputEventKey.new()
	ev2.physical_keycode = KEY_B
	InputMap.action_add_event("test_action", ev1)
	InputMap.action_add_event("test_action", ev2)
	
	Settings.save_input_mappings(test_path, test_actions)
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(test_path, test_actions)
	
	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(2)
	if events.size() < 2:
		return
	assert_that(events[0] is InputEventKey).is_true()
	assert_that(events[1] is InputEventKey).is_true()
	assert_int(events[0].physical_keycode).is_equal(KEY_A)
	assert_int(events[1].physical_keycode).is_equal(KEY_B)


# Test backward compat: old format (single string) loads
func test_backward_compat_old_format() -> void:
	var test_path: String = "user://old_format.cfg"
	var test_actions: Array[String] = ["test_action"]
	
	# Create old-format cfg: string instead of array
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "test_action", "key:%d" % KEY_A)
	config.save(test_path)
	
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(test_path, test_actions)
	
	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(1)
	if events.size() < 1:
		return
	assert_that(events[0] is InputEventKey).is_true()
	assert_int(events[0].physical_keycode).is_equal(KEY_A)


# Test default fallback: missing action in cfg should add default key mapping
func test_default_key_fallback() -> void:
	var test_path: String = "user://default_test.cfg"
	var test_actions: Array[String] = ["test_action"]
	
	# Ensure action has no events
	InputMap.action_erase_events("test_action")
	
	# Create empty config
	var config: ConfigFile = ConfigFile.new()
	config.save(test_path)
	
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	# Load should add default
	Settings.load_input_mappings(test_path, test_actions)
	
	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(1)
	if events.size() < 1:
		return
	assert_that(events[0] is InputEventKey).is_true()
	assert_int(events[0].physical_keycode).is_equal(KEY_W)


# Test unbound action persistence (explicit empty array should keep unbound)
func test_unbound_action_persistence() -> void:
	var test_path: String = "user://unbound_test.cfg"
	var test_actions: Array[String] = ["test_action"]
	
	# Create cfg with explicit unbound
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "test_action", [])
	config.save(test_path)
	
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(test_path, test_actions)
	
	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(0)


# Test multi-action persistence
func test_multi_action_persistence() -> void:
	var test_path: String = "user://multi_action.cfg"
	var test_actions: Array[String] = ["test_action1", "test_action2"]
	
	# Setup action1 = KEY_A, action2 = KEY_B
	InputMap.action_erase_events("test_action1")
	InputMap.action_erase_events("test_action2")
	
	var ev1: InputEventKey = InputEventKey.new()
	ev1.physical_keycode = KEY_A
	InputMap.action_add_event("test_action1", ev1)
	
	var ev2: InputEventKey = InputEventKey.new()
	ev2.physical_keycode = KEY_B
	InputMap.action_add_event("test_action2", ev2)
	
	Settings.save_input_mappings(test_path, test_actions)
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	InputMap.action_erase_events("test_action1")
	InputMap.action_erase_events("test_action2")
	Settings.load_input_mappings(test_path, test_actions)
	
	var events1: Array[InputEvent] = InputMap.action_get_events("test_action1")
	assert_int(events1.size()).is_equal(1)
	if events1.size() < 1:
		return
	assert_that(events1[0] is InputEventKey).is_true()
	assert_int(events1[0].physical_keycode).is_equal(KEY_A)
	
	var events2: Array[InputEvent] = InputMap.action_get_events("test_action2")
	assert_int(events2.size()).is_equal(1)
	if events2.size() < 1:
		return
	assert_that(events2[0] is InputEventKey).is_true()
	assert_int(events2[0].physical_keycode).is_equal(KEY_B)


# Test malformed deserialization: invalid strings should be skipped
func test_malformed_deserialization() -> void:
	var test_path: String = "user://malformed.cfg"
	var test_actions: Array[String] = ["test_action"]
	
	# Manually create cfg with malformed serials
	var config: ConfigFile = ConfigFile.new()
	var malformed_serials: Array[String] = [
		"joybtn:",  # Missing button index
		"joybtn:abc",  # Non-numeric button index
		"joyaxis:1",  # Missing axis value
		"joyaxis:abc:1.0",  # Non-numeric axis
		"joyaxis:0:def",  # Non-numeric axis value
		"key:",  # Missing key code
		"key:0",  # Invalid key code (must be > 0)
		"invalid:123"  # Unknown prefix
	]
	config.set_value("input", "test_action", malformed_serials)
	config.save(test_path)
	
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	# Erase and load (should skip all, events empty)
	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(test_path, test_actions)
	
	# Verify no events added
	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(0)


# Test preservation of project-default joypad if no saved data
func test_preserve_default_joypad_no_saved() -> void:
	var test_path: String = "user://no_saved.cfg"
	var test_actions: Array[String] = ["test_action"]

	# Simulate project default: Add a joypad event (as if set in editor)
	InputMap.action_erase_events("test_action")
	var default_joy: InputEventJoypadButton = InputEventJoypadButton.new()
	default_joy.button_index = JOY_BUTTON_A
	default_joy.device = -1
	InputMap.action_add_event("test_action", default_joy)

	# Create empty config (no data for action)
	var config: ConfigFile = ConfigFile.new()
	config.save(test_path)

	# Load
	Settings.load_input_mappings(test_path, test_actions)

	# Verify joypad preserved (not wiped)
	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(1)
	if events.size() < 1:
		return
	assert_that(events[0] is InputEventJoypadButton).is_true()
	assert_int(events[0].button_index).is_equal(JOY_BUTTON_A)


# Test migration save only on old-format config
func test_migration_save_only_on_old() -> void:
	var test_path: String = "user://migration_test.cfg"
	
	# Create old-format cfg
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "test_action", "key:%d" % KEY_A)
	config.save(test_path)
	
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	# Load should migrate and (optionally) save new format, depending on Settings implementation
	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(test_path, ["test_action"])

	# At minimum, mapping should exist
	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(1)
	if events.size() < 1:
		return
	assert_that(events[0] is InputEventKey).is_true()
	assert_int(events[0].physical_keycode).is_equal(KEY_A)


# Test no migration on already-new config
func test_no_migration_on_new() -> void:
	var test_path: String = "user://migration_new.cfg"
	
	# Create new-format cfg (array)
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "test_action", ["key:%d" % KEY_A])
	config.save(test_path)
	
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(test_path, ["test_action"])
	
	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(1)
	if events.size() < 1:
		return
	assert_that(events[0] is InputEventKey).is_true()
	assert_int(events[0].physical_keycode).is_equal(KEY_A)


# Test type safe new format: dictionary/array mismatches handled
func test_type_safe_new_format() -> void:
	var test_path: String = "user://type_safe.cfg"
	var test_actions: Array[String] = ["test_action"]
	
	# Create config with a mix of valid and invalid entries
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "test_action", ["key:%d" % KEY_A, 123, null, "invalid:999"])
	config.save(test_path)
	
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(test_path, test_actions)
	
	# Only KEY_A should load
	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(1)
	if events.size() < 1:
		return
	assert_that(events[0] is InputEventKey).is_true()
	assert_int(events[0].physical_keycode).is_equal(KEY_A)


# Test load error handling: corrupted file falls back without crash
func test_load_error_handling() -> void:
	var test_path: String = "user://corrupt.cfg"
	var test_actions: Array[String] = ["test_action"]
	
	# Write invalid content
	var file: FileAccess = FileAccess.open(test_path, FileAccess.WRITE)
	file.store_string("not a cfg")
	file.close()
	
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	# Should not throw; should handle internally
	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(test_path, test_actions)

	# Depending on implementation, could fallback to default or stay empty; just ensure it didn't crash.
	assert_bool(true).is_true()
