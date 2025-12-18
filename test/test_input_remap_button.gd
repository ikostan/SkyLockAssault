# test_input_remap_button.gd (updated for new features: keyboard, joypad button, motion; tests display & remap)
# Uses GdUnit4 (assume installed; install via AssetLib if not).
# Run via GdUnit Inspector or command line.
extends GdUnitTestSuite

@warning_ignore("unused_parameter")
func before() -> void:
	# Global setup if needed (e.g., mock Globals/Settings if logging/save called)
	pass

@warning_ignore("unused_parameter")
func after() -> void:
	# Global cleanup
	pass

# Test keyboard label display (original, updated for Godot 4.4)
func test_keyboard_label_display() -> void:
	# Clean up if action exists
	if InputMap.has_action("test_action"):
		InputMap.erase_action("test_action")
	
	# Add action with KEY_SPACE (physical)
	InputMap.add_action("test_action")
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	InputMap.action_add_event("test_action", event)
	
	# Instance button, set action, ready
	var button: InputRemapButton = InputRemapButton.new()
	button.action = "test_action"
	button._ready()
	
	# Assert "Space"
	assert_str(button.text).is_equal("Space")
	
	# Cleanup
	button.free()
	InputMap.erase_action("test_action")

# Test joypad button label display
func test_joypad_button_label_display() -> void:
	if InputMap.has_action("test_action"):
		InputMap.erase_action("test_action")
	
	InputMap.add_action("test_action")
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_A
	event.device = -1
	InputMap.action_add_event("test_action", event)
	
	var button: InputRemapButton = InputRemapButton.new()
	button.action = "test_action"
	button._ready()
	
	assert_str(button.text).is_equal("A")
	
	button.free()
	InputMap.erase_action("test_action")

# Test joypad motion (axis) label display
func test_joypad_motion_label_display() -> void:
	if InputMap.has_action("test_action"):
		InputMap.erase_action("test_action")
	
	InputMap.add_action("test_action")
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = -1.0  # Left
	event.device = -1
	InputMap.action_add_event("test_action", event)
	
	var button: InputRemapButton = InputRemapButton.new()
	button.action = "test_action"
	button._ready()
	
	assert_str(button.text).is_equal("Left Stick Left")
	
	button.free()
	InputMap.erase_action("test_action")

# Test unbound display
func test_unbound_label_display() -> void:
	if InputMap.has_action("test_action"):
		InputMap.erase_action("test_action")
	
	InputMap.add_action("test_action")  # No events
	
	var button: InputRemapButton = InputRemapButton.new()
	button.action = "test_action"
	button._ready()
	
	assert_str(button.text).is_equal("Unbound")
	
	button.free()
	InputMap.erase_action("test_action")

# Test remapping keyboard (simulate input)
func test_remap_keyboard() -> void:
	if InputMap.has_action("test_action"):
		InputMap.erase_action("test_action")
	
	InputMap.add_action("test_action")  # Start empty
	
	var button: InputRemapButton = InputRemapButton.new()
	button.action = "test_action"
	button._ready()
	
	# Simulate press to start listening
	button._on_pressed()  # Sets listening=true, text="Press..."
	assert_bool(button.listening).is_true()
	
	# Simulate key input (e.g., KEY_D)
	var sim_event: InputEventKey = InputEventKey.new()
	sim_event.physical_keycode = KEY_D
	sim_event.pressed = true
	button._input(sim_event)
	
	# Assert remapped, text="D", not listening
	assert_str(button.text).is_equal("D")
	assert_bool(button.listening).is_false()
	
	# Verify event added
	var events: Array = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(1)
	assert_that(events[0] is InputEventKey).is_true()
	assert_int(events[0].physical_keycode).is_equal(KEY_D)
	
	button.free()
	InputMap.erase_action("test_action")

# Test remapping joypad button
func test_remap_joypad_button() -> void:
	if InputMap.has_action("test_action"):
		InputMap.erase_action("test_action")
	
	InputMap.add_action("test_action")
	
	var button: InputRemapButton = InputRemapButton.new()
	button.action = "test_action"
	button._ready()
	
	button._on_pressed()
	assert_bool(button.listening).is_true()
	
	var sim_event: InputEventJoypadButton = InputEventJoypadButton.new()
	sim_event.button_index = JOY_BUTTON_B
	sim_event.pressed = true
	button._input(sim_event)
	
	assert_str(button.text).is_equal("B")
	assert_bool(button.listening).is_false()
	
	var events: Array = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(1)
	assert_that(events[0] is InputEventJoypadButton).is_true()
	assert_int(events[0].button_index).is_equal(JOY_BUTTON_B)
	assert_int(events[0].device).is_equal(-1)
	
	button.free()
	InputMap.erase_action("test_action")

# Test remapping joypad motion (axis)
func test_remap_joypad_motion() -> void:
	if InputMap.has_action("test_action"):
		InputMap.erase_action("test_action")
	
	InputMap.add_action("test_action")
	
	var button: InputRemapButton = InputRemapButton.new()
	button.action = "test_action"
	button._ready()
	
	button._on_pressed()
	assert_bool(button.listening).is_true()
	
	var sim_event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	sim_event.axis = JOY_AXIS_LEFT_Y
	sim_event.axis_value = 1.0  # Down (abs > 0.5)
	button._input(sim_event)
	
	assert_str(button.text).is_equal("Left Stick Down")
	assert_bool(button.listening).is_false()
	
	var events: Array = InputMap.action_get_events("test_action")
	assert_int(events.size()).is_equal(1)
	assert_that(events[0] is InputEventJoypadMotion).is_true()
	assert_int(events[0].axis).is_equal(JOY_AXIS_LEFT_Y)
	assert_float(events[0].axis_value).is_equal(1.0)
	assert_int(events[0].device).is_equal(-1)
	
	button.free()
	InputMap.erase_action("test_action")

# Test fallback labels (unknown button/axis)
func test_fallback_labels() -> void:
	if InputMap.has_action("test_action"):
		InputMap.erase_action("test_action")
	
	InputMap.add_action("test_action")
	
	# Unknown button
	var btn_event: InputEventJoypadButton = InputEventJoypadButton.new()
	btn_event.button_index = 999  # Invalid
	InputMap.action_add_event("test_action", btn_event)
	
	var button: InputRemapButton = InputRemapButton.new()
	button.action = "test_action"
	button._ready()
	assert_str(button.text).is_equal("Button 999")
	
	# Unknown axis
	InputMap.action_erase_event("test_action", btn_event)
	var axis_event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	axis_event.axis = 999
	axis_event.axis_value = 1.0
	InputMap.action_add_event("test_action", axis_event)
	button.update_button_text()
	assert_str(button.text).is_equal("Axis 999 +")
	
	button.free()
	InputMap.erase_action("test_action")
