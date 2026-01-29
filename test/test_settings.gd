## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_settings.gd (updated for new features: multi-event, joypad button/motion, backward compat, defaults)
## Uses GdUnit4 (assume installed; install via AssetLib if not).
## Run via GdUnit Inspector or command line.
extends GdUnitTestSuite

@warning_ignore("unused_parameter")
func before() -> void:
	# Global setup: Ensure test actions exist (erase events)
	for action: String in ["test_action", "test_action1", "test_action2"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)

@warning_ignore("unused_parameter")
func after() -> void:
	# Global cleanup: Erase test actions and files
	for action: String in ["test_action", "test_action1", "test_action2"]:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	for path: String in ["user://test_settings.cfg", "user://multi_test.cfg", "user://joy_test.cfg", "user://old_format.cfg", "user://malformed.cfg"]:
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
	assert_that(events[0] is InputEventJoypadMotion).is_true()
	assert_int(events[0].axis).is_equal(JOY_AXIS_LEFT_X)
	assert_float(events[0].axis_value).is_equal(-1.0)
	assert_int(events[0].device).is_equal(-1)

# Test multi-event per action (key + joypad)
func test_multi_event_persistence() -> void:
	var test_path: String = "user://multi_test.cfg"
	var test_actions: Array[String] = ["test_action"]
	
	# Add multiple events
	InputMap.action_erase_events("test_action")
	var key_event: InputEventKey = InputEventKey.new()
	key_event.physical_keycode = KEY_A
	InputMap.action_add_event("test_action", key_event)
	var joy_event: InputEventJoypadButton = InputEventJoypadButton.new()
	joy_event.button_index = JOY_BUTTON_B
	joy_event.device = -1
	InputMap.action_add_event("test_action", joy_event)
	
	# Save
	Settings.save_input_mappings(test_path, test_actions)
	
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	# Erase and load
	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(test_path, test_actions)
	
	# Verify both loaded
	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(2)
	assert_that(events[0] is InputEventKey).is_true()
	assert_int(events[0].physical_keycode).is_equal(KEY_A)
	assert_that(events[1] is InputEventJoypadButton).is_true()
	assert_int(events[1].button_index).is_equal(JOY_BUTTON_B)

# Test backward compatibility (old int keycode format)
func test_backward_compat_old_format() -> void:
	var test_path: String = "user://old_format.cfg"
	var test_actions: Array[String] = ["test_action"]
	
	# Manually create old-format cfg (int keycode)
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "test_action", KEY_Q)  # Old: single int
	config.save(test_path)
	
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	# Load (should convert to array ["key:81"])
	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(test_path, test_actions)
	
	# Verify KEY_Q loaded
	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(1)
	assert_that(events[0] is InputEventKey).is_true()
	assert_int(events[0].physical_keycode).is_equal(KEY_Q)

# Test default fallback when no file
func test_default_key_fallback() -> void:
	var test_path: String = "user://default_test.cfg"
	var test_actions: Array[String] = ["speed_up"]
	
	# No file—load should add defaults where missing (but speed_up empty initially)
	InputMap.action_erase_events("speed_up")
	Settings.load_input_mappings(test_path, test_actions)
	
	# Verify defaults added (key and joy for speed_up)
	var events: Array[InputEvent] = InputMap.action_get_events("speed_up")
	assert_int(events.size()).is_equal(2)
	
	var key_found: bool = false
	var joy_found: bool = false
	for ev: InputEvent in events:
		if ev is InputEventKey:
			assert_int(ev.physical_keycode).is_equal(KEY_W)
			key_found = true
		elif ev is InputEventJoypadMotion:
			assert_int(ev.axis).is_equal(JOY_AXIS_TRIGGER_RIGHT)
			assert_float(ev.axis_value).is_equal(1.0)
			assert_int(ev.device).is_equal(-1)
			joy_found = true
	assert_bool(key_found).is_true()
	assert_bool(joy_found).is_true()

# Test unbound persistence (empty array saved/loaded)
func test_unbound_action_persistence() -> void:
	var test_path: String = "user://unbound_test.cfg"
	var test_actions: Array[String] = ["test_action"]
	
	# Set unbound (erase events)
	InputMap.action_erase_events("test_action")
	
	# Save (should save empty array)
	Settings.save_input_mappings(test_path, test_actions)
	
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	# Add temp event, then load (should erase to unbound)
	var temp_event: InputEventKey = InputEventKey.new()
	temp_event.physical_keycode = KEY_B
	InputMap.action_add_event("test_action", temp_event)
	Settings.load_input_mappings(test_path, test_actions)
	
	# Verify empty
	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(0)

# Test multi-action persistence
func test_multi_action_persistence() -> void:
	var test_path: String = "user://multi_action.cfg"
	var test_actions: Array[String] = ["test_action1", "test_action2"]
	
	# Set action1 with key, action2 unbound
	InputMap.action_erase_events("test_action1")
	var event1: InputEventKey = InputEventKey.new()
	event1.physical_keycode = KEY_A
	InputMap.action_add_event("test_action1", event1)
	InputMap.action_erase_events("test_action2")  # Unbound
	
	# Save
	Settings.save_input_mappings(test_path, test_actions)
	
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	# Erase and load
	for action: String in test_actions:
		InputMap.action_erase_events(action)
	Settings.load_input_mappings(test_path, test_actions)
	
	# Verify action1 has KEY_A, action2 empty (unbound)
	var events1: Array[InputEvent] = InputMap.action_get_events("test_action1")
	assert_int(events1.size()).is_equal(1)
	assert_int(events1[0].physical_keycode).is_equal(KEY_A)
	
	var events2: Array[InputEvent] = InputMap.action_get_events("test_action2")
	assert_int(events2.size()).is_equal(0)

# Test malformed deserialization (skips invalid, no events added)
func test_malformed_deserialization() -> void:
	var test_path: String = "user://malformed.cfg"
	var test_actions: Array[String] = ["test_action"]
	
	# Manually create cfg with malformed serials
	var config: ConfigFile = ConfigFile.new()
	var malformed_serials: Array[String] = [
		"joybtn:",  # Insufficient parts (missing btn)
		"joybtn:abc",  # Invalid btn index
		"joybtn:1:def",  # Invalid dev
		"joyaxis:1",  # Insufficient parts (missing aval)
		"joyaxis:abc:1.0",  # Invalid axis
		"joyaxis:0:def",  # Invalid aval
		"joyaxis:0:1.0:ghi",  # Invalid dev
		"key:",  # Missing kc
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
	assert_that(events[0] is InputEventJoypadButton).is_true()
	assert_int(events[0].button_index).is_equal(JOY_BUTTON_A)

# Test migration save only on old-format config
func test_migration_save_only_on_old() -> void:
	var test_path: String = "user://migration_test.cfg"
	
	# Create old-format cfg
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "test_action", KEY_Q)  # Old int
	config.save(test_path)
	
	# Load (should detect old, set flag)
	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(test_path, ["test_action"])
	
	# Simulate _ready() save logic—check if flag triggers save
	assert_bool(Settings._needs_migration).is_true()  # Flag set
	Settings.save_input_mappings(test_path, ["test_action"])  # Would save in new format
	
	# Reload to verify upgraded, no flag next time
	Settings._needs_migration = false  # Reset
	Settings.load_input_mappings(test_path, ["test_action"])
	assert_bool(Settings._needs_migration).is_false()  # No old format now

# Test no save on new-format or no config
func test_no_migration_on_new() -> void:
	var test_path: String = "user://new_format.cfg"
	
	# Create new-format cfg
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "test_action", ["key:81"])  # New array
	config.save(test_path)
	
	Settings.load_input_mappings(test_path, ["test_action"])
	assert_bool(Settings._needs_migration).is_false()  # No flag


# Test type-safe load for new-format array
func test_type_safe_new_format() -> void:
	var test_path: String = "user://type_test.cfg"
	var test_actions: Array[String] = ["test_action"]
	
	# Create new-format cfg with Array[String]
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "test_action", ["key:81"])
	config.save(test_path)
	
	# Load and verify no type error
	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(test_path, test_actions)
	
	# Verify loaded correctly
	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(1)
	assert_that(events[0] is InputEventKey).is_true()
	assert_int(events[0].physical_keycode).is_equal(KEY_Q)


# Test load error handling (e.g., corrupt file)
func test_load_error_handling() -> void:
	var test_path: String = "user://corrupt.cfg"
	# Create corrupt file (invalid ConfigFile syntax—write raw text)
	var file: FileAccess = FileAccess.open(test_path, FileAccess.WRITE)
	file.store_string("[input\ninvalid_syntax")  # Malformed section
	file.close()
	
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	# Erase events before testing
	InputMap.action_erase_events("test_action")
	
	# Expect a runtime error during load
	assert_error(func() -> void:
		Settings.load_input_mappings(test_path, ["test_action"])
	)
	
	# Verify no events added (load skipped due to error handling)
	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(0)
	
	# Clean up
	DirAccess.remove_absolute(test_path)
