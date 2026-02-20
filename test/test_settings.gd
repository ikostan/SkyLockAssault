## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_settings.gd
## GdUnit4 tests for Settings input save/load.
## IMPORTANT: This suite must NOT use keys/buttons/axes that conflict with Settings defaults,
## because Settings.load_input_mappings() intentionally skips duplicates across ACTIONS.
extends GdUnitTestSuite

# ----------------------------
# Test-only constants
# ----------------------------

## Non-conflicting keyboard codes (not used by Settings.DEFAULT_KEYBOARD).
const TEST_KEY_1: int = KEY_F13
const TEST_KEY_2: int = KEY_F14
const TEST_KEY_3: int = KEY_F15
const TEST_KEY_4: int = KEY_F16

## Non-conflicting gamepad buttons.
## Our previous choice (JOY_BUTTON_X) conflicts with action "pause" in your project.
## Use a rarely-bound button instead.
const TEST_JOY_BUTTON: int = JOY_BUTTON_PADDLE1

## Non-conflicting gamepad axis (defaults use TRIGGERS and LEFT_X).
const TEST_JOY_AXIS: int = JOY_AXIS_RIGHT_X
const TEST_JOY_AXIS_VALUE: float = -1.0

## Files used by this suite (cleaned up in after()).
const PATH_TEST_SETTINGS: String = "user://test_settings.cfg"
const PATH_MULTI_TEST: String = "user://multi_test.cfg"
const PATH_JOY_TEST: String = "user://joy_test.cfg"
const PATH_OLD_FORMAT: String = "user://old_format.cfg"
const PATH_MALFORMED: String = "user://malformed.cfg"
const PATH_DEFAULT_TEST: String = "user://default_test.cfg"
const PATH_UNBOUND_TEST: String = "user://unbound_test.cfg"
const PATH_MULTI_ACTION: String = "user://multi_action.cfg"
const PATH_NO_SAVED: String = "user://no_saved.cfg"
const PATH_MIGRATION_TEST: String = "user://migration_test.cfg"
const PATH_NEW_FORMAT: String = "user://new_format.cfg"
const PATH_TYPE_TEST: String = "user://type_test.cfg"
const PATH_CORRUPT: String = "user://corrupt.cfg"


@warning_ignore("unused_parameter")
func before() -> void:
	# Ensure test actions exist (and start unbound).
	for action: String in ["test_action", "test_action1", "test_action2"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)


@warning_ignore("unused_parameter")
func after() -> void:
	# Remove test actions.
	for action: String in ["test_action", "test_action1", "test_action2"]:
		if InputMap.has_action(action):
			InputMap.erase_action(action)

	# Remove all files this suite may create.
	var paths: Array[String] = [
		PATH_TEST_SETTINGS,
		PATH_MULTI_TEST,
		PATH_JOY_TEST,
		PATH_OLD_FORMAT,
		PATH_MALFORMED,
		PATH_DEFAULT_TEST,
		PATH_UNBOUND_TEST,
		PATH_MULTI_ACTION,
		PATH_NO_SAVED,
		PATH_MIGRATION_TEST,
		PATH_NEW_FORMAT,
		PATH_TYPE_TEST,
		PATH_CORRUPT,
	]
	for p: String in paths:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func test_save_and_load_keyboard() -> void:
	var test_actions: Array[String] = ["test_action"]

	InputMap.action_erase_events("test_action")
	var new_event: InputEventKey = InputEventKey.new()
	new_event.physical_keycode = TEST_KEY_1
	InputMap.action_add_event("test_action", new_event)

	Settings.save_input_mappings(PATH_TEST_SETTINGS, test_actions)
	assert_bool(FileAccess.file_exists(PATH_TEST_SETTINGS)).is_true()

	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(PATH_TEST_SETTINGS, test_actions)

	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(1)
	if events.size() < 1:
		return
	assert_that(events[0] is InputEventKey).is_true()
	assert_int(events[0].physical_keycode).is_equal(TEST_KEY_1)


func test_save_and_load_joypad_button() -> void:
	var test_actions: Array[String] = ["test_action"]

	InputMap.action_erase_events("test_action")
	var new_event: InputEventJoypadButton = InputEventJoypadButton.new()
	new_event.button_index = TEST_JOY_BUTTON
	new_event.device = -1
	InputMap.action_add_event("test_action", new_event)

	Settings.save_input_mappings(PATH_JOY_TEST, test_actions)
	assert_bool(FileAccess.file_exists(PATH_JOY_TEST)).is_true()

	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(PATH_JOY_TEST, test_actions)

	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(1)
	if events.size() < 1:
		return
	assert_that(events[0] is InputEventJoypadButton).is_true()
	assert_int(events[0].button_index).is_equal(TEST_JOY_BUTTON)
	assert_int(events[0].device).is_equal(-1)


func test_save_and_load_joypad_motion() -> void:
	var test_actions: Array[String] = ["test_action"]

	InputMap.action_erase_events("test_action")
	var new_event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	new_event.axis = TEST_JOY_AXIS
	new_event.axis_value = TEST_JOY_AXIS_VALUE
	new_event.device = -1
	InputMap.action_add_event("test_action", new_event)

	Settings.save_input_mappings(PATH_JOY_TEST, test_actions)
	assert_bool(FileAccess.file_exists(PATH_JOY_TEST)).is_true()

	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(PATH_JOY_TEST, test_actions)

	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(1)
	if events.size() < 1:
		return
	assert_that(events[0] is InputEventJoypadMotion).is_true()
	assert_int(events[0].axis).is_equal(TEST_JOY_AXIS)
	assert_float(events[0].axis_value).is_equal(TEST_JOY_AXIS_VALUE)
	assert_int(events[0].device).is_equal(-1)


func test_multi_event_persistence() -> void:
	var test_actions: Array[String] = ["test_action"]

	InputMap.action_erase_events("test_action")

	var key_event: InputEventKey = InputEventKey.new()
	key_event.physical_keycode = TEST_KEY_1
	InputMap.action_add_event("test_action", key_event)

	var joy_event: InputEventJoypadButton = InputEventJoypadButton.new()
	joy_event.button_index = TEST_JOY_BUTTON
	joy_event.device = -1
	InputMap.action_add_event("test_action", joy_event)

	Settings.save_input_mappings(PATH_MULTI_TEST, test_actions)
	assert_bool(FileAccess.file_exists(PATH_MULTI_TEST)).is_true()

	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(PATH_MULTI_TEST, test_actions)

	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(2)
	if events.size() < 2:
		return

	# Validate content ignoring order (some loaders may reorder).
	var found_key: bool = false
	var found_joy: bool = false
	for ev: InputEvent in events:
		if ev is InputEventKey and ev.physical_keycode == TEST_KEY_1:
			found_key = true
		elif ev is InputEventJoypadButton and ev.button_index == TEST_JOY_BUTTON:
			found_joy = true

	assert_bool(found_key).is_true()
	assert_bool(found_joy).is_true()


func test_backward_compat_old_format() -> void:
	var test_actions: Array[String] = ["test_action"]

	# Old format: single int keycode (must not conflict with defaults).
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "test_action", TEST_KEY_3)
	config.save(PATH_OLD_FORMAT)

	assert_bool(FileAccess.file_exists(PATH_OLD_FORMAT)).is_true()

	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(PATH_OLD_FORMAT, test_actions)

	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(1)
	if events.size() < 1:
		return
	assert_that(events[0] is InputEventKey).is_true()
	assert_int(events[0].physical_keycode).is_equal(TEST_KEY_3)


func test_default_key_fallback() -> void:
	var test_actions: Array[String] = ["speed_up"]

	if FileAccess.file_exists(PATH_DEFAULT_TEST):
		DirAccess.remove_absolute(PATH_DEFAULT_TEST)

	InputMap.action_erase_events("speed_up")

	Settings.load_input_mappings(PATH_DEFAULT_TEST, test_actions)

	# Defaults for speed_up: KEY_W + right trigger axis.
	var events: Array[InputEvent] = InputMap.action_get_events("speed_up")
	assert_int(events.size()).is_equal(2)

	var key_found: bool = false
	var joy_found: bool = false
	for ev: InputEvent in events:
		if ev is InputEventKey:
			assert_int(ev.physical_keycode).is_equal(KEY_W)
			key_found = true
		elif ev is InputEventJoypadMotion:
			assert_int(ev.axis).is_equal(JOY_AXIS_RIGHT_Y)
			assert_float(ev.axis_value).is_equal(1.0)
			assert_int(ev.device).is_equal(-1)
			joy_found = true

	assert_bool(key_found).is_true()
	assert_bool(joy_found).is_true()


func test_unbound_action_persistence() -> void:
	var test_actions: Array[String] = ["test_action"]

	InputMap.action_erase_events("test_action")

	Settings.save_input_mappings(PATH_UNBOUND_TEST, test_actions)
	assert_bool(FileAccess.file_exists(PATH_UNBOUND_TEST)).is_true()

	var temp_event: InputEventKey = InputEventKey.new()
	temp_event.physical_keycode = TEST_KEY_2
	InputMap.action_add_event("test_action", temp_event)

	Settings.load_input_mappings(PATH_UNBOUND_TEST, test_actions)

	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(0)


func test_multi_action_persistence() -> void:
	var test_actions: Array[String] = ["test_action1", "test_action2"]

	InputMap.action_erase_events("test_action1")
	var event1: InputEventKey = InputEventKey.new()
	event1.physical_keycode = TEST_KEY_4
	InputMap.action_add_event("test_action1", event1)

	InputMap.action_erase_events("test_action2")

	Settings.save_input_mappings(PATH_MULTI_ACTION, test_actions)
	assert_bool(FileAccess.file_exists(PATH_MULTI_ACTION)).is_true()

	for action: String in test_actions:
		InputMap.action_erase_events(action)
	Settings.load_input_mappings(PATH_MULTI_ACTION, test_actions)

	var events1: Array[InputEvent] = InputMap.action_get_events("test_action1")
	assert_int(events1.size()).is_equal(1)
	if events1.size() < 1:
		return
	assert_that(events1[0] is InputEventKey).is_true()
	assert_int(events1[0].physical_keycode).is_equal(TEST_KEY_4)

	var events2: Array[InputEvent] = InputMap.action_get_events("test_action2")
	assert_int(events2.size()).is_equal(0)


func test_malformed_deserialization() -> void:
	var test_actions: Array[String] = ["test_action"]

	var config: ConfigFile = ConfigFile.new()
	var malformed_serials: Array[String] = [
		"joybtn:",
		"joybtn:abc",
		"joyaxis:1",
		"joyaxis:abc:1.0",
		"joyaxis:0:def",
		"key:",
		"key:0",
		"invalid:123",
	]
	config.set_value("input", "test_action", malformed_serials)
	config.save(PATH_MALFORMED)

	assert_bool(FileAccess.file_exists(PATH_MALFORMED)).is_true()

	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(PATH_MALFORMED, test_actions)

	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(0)


func test_preserve_default_joypad_no_saved() -> void:
	var test_actions: Array[String] = ["test_action"]

	InputMap.action_erase_events("test_action")
	var default_joy: InputEventJoypadButton = InputEventJoypadButton.new()
	default_joy.button_index = TEST_JOY_BUTTON
	default_joy.device = -1
	InputMap.action_add_event("test_action", default_joy)

	var config: ConfigFile = ConfigFile.new()
	config.save(PATH_NO_SAVED)

	Settings.load_input_mappings(PATH_NO_SAVED, test_actions)

	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(1)
	if events.size() < 1:
		return
	assert_that(events[0] is InputEventJoypadButton).is_true()
	assert_int(events[0].button_index).is_equal(TEST_JOY_BUTTON)


func test_migration_save_only_on_old() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "test_action", TEST_KEY_3)
	config.save(PATH_MIGRATION_TEST)

	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(PATH_MIGRATION_TEST, ["test_action"])

	assert_bool(Settings._needs_save).is_true()

	Settings.save_input_mappings(PATH_MIGRATION_TEST, ["test_action"])

	Settings._needs_save = false
	Settings.load_input_mappings(PATH_MIGRATION_TEST, ["test_action"])
	assert_bool(Settings._needs_save).is_false()


func test_no_migration_on_new() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "test_action", ["key:%d" % TEST_KEY_3])
	config.save(PATH_NEW_FORMAT)

	Settings.load_input_mappings(PATH_NEW_FORMAT, ["test_action"])
	assert_bool(Settings._needs_save).is_false()


func test_type_safe_new_format() -> void:
	var test_actions: Array[String] = ["test_action"]

	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "test_action", ["key:%d" % TEST_KEY_3])
	config.save(PATH_TYPE_TEST)

	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(PATH_TYPE_TEST, test_actions)

	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(1)
	if events.size() < 1:
		return
	assert_that(events[0] is InputEventKey).is_true()
	assert_int(events[0].physical_keycode).is_equal(TEST_KEY_3)


func test_load_error_handling() -> void:
	var file: FileAccess = FileAccess.open(PATH_CORRUPT, FileAccess.WRITE)
	file.store_string("[input\ninvalid_syntax")
	file.close()

	assert_bool(FileAccess.file_exists(PATH_CORRUPT)).is_true()

	InputMap.action_erase_events("test_action")

	assert_error(func() -> void:
		Settings.load_input_mappings(PATH_CORRUPT, ["test_action"])
	)

	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(0)
