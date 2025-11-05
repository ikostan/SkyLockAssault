extends GdUnitTestSuite

func before() -> void:
	# Setup test action in InputMap
	if not InputMap.has_action("test_action"):
		InputMap.add_action("test_action")
	InputMap.action_erase_events("test_action")
	var default_event: InputEventKey = InputEventKey.new()
	default_event.physical_keycode = KEY_W
	InputMap.action_add_event("test_action", default_event)

func after() -> void:
	# Cleanup
	InputMap.action_erase_events("test_action")
	var test_path: String = "user://test_settings.cfg"
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(test_path)

func test_save_and_load_input_mappings() -> void:
	var test_path: String = "user://test_settings.cfg"
	var test_actions: Array[String] = ["test_action"]
	
	# Remap to a new key (e.g., KEY_A)
	var events: Array[InputEvent] = InputMap.action_get_events("test_action")
	if events.size() > 0:
		InputMap.action_erase_event("test_action", events[0])
	var new_event: InputEventKey = InputEventKey.new()
	new_event.physical_keycode = KEY_A
	InputMap.action_add_event("test_action", new_event)
	
	# Save to test path with test actions
	Settings.save_input_mappings(test_path, test_actions)
	
	# Verify file was created
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	# Simulate reload: Erase current mapping and load from test file
	InputMap.action_erase_events("test_action")
	Settings.load_input_mappings(test_path, test_actions)
	
	# Verify loaded key is KEY_A
	events = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(1)
	assert_that(events[0] is InputEventKey).is_true()
	assert_int(events[0].physical_keycode).is_equal(KEY_A)

func test_multi_action_persistence() -> void:
	var test_path: String = "user://multi_test.cfg"
	var test_actions: Array[String] = ["test_action1", "test_action2"]
	
	# Setup actions
	for action in test_actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
	
	# Set keys: A for first, unbound for second
	var event1: InputEventKey = InputEventKey.new()
	event1.physical_keycode = KEY_A
	InputMap.action_add_event("test_action1", event1)
	# No event for test_action2 (tests unbound handling)
	
	# Save
	Settings.save_input_mappings(test_path, test_actions)
	
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	# Erase and load
	for action in test_actions:
		InputMap.action_erase_events(action)
	Settings.load_input_mappings(test_path, test_actions)
	
	# Verify
	var events1: Array[InputEvent] = InputMap.action_get_events("test_action1")
	assert_int(events1.size()).is_equal(1)
	assert_int(events1[0].physical_keycode).is_equal(KEY_A)
	
	var events2: Array[InputEvent] = InputMap.action_get_events("test_action2")
	assert_int(events2.size()).is_equal(0)  # Unbound
	
	# Cleanup
	for action in test_actions:
		InputMap.action_erase_events(action)
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(test_path)
