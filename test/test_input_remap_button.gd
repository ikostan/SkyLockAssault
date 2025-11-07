extends GdUnitTestSuite

func test_label_display_web_safe() -> void:
	# Clean up if action already exists (for test isolation)
	if InputMap.has_action("test_action"):
		InputMap.erase_action("test_action")
	
	# Setup action with physical KEY_SPACE
	InputMap.add_action("test_action")
	var event: = InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	InputMap.action_add_event("test_action", event)
	
	# Instance button (no add_child if not needed; test isolated)
	var button: = InputRemapButton.new()
	button.action = "test_action"
	button._ready()  # Manual call
	
	# Assert text is "Space" (from fallback or dict)
	assert_str(button.text).is_equal("Space")
	
	# Cleanup
	button.queue_free()
	InputMap.erase_action("test_action")
