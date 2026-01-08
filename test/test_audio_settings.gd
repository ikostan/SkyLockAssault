## test_audio_settings.gd
## Unit tests for audio_settings.gd functionality.
##
## Covers initialization, back handling, and unexpected exits.
##
## Uses GdUnitTestSuite for assertions and hooks.

extends GdUnitTestSuite

var mock_js_bridge: Variant  # GdUnit mock for JavaScriptBridgeWrapper
var mock_os: Variant  # GdUnit mock for OSWrapper
var mock_js_window: Dictionary  # Mock for js_window


func before_test() -> void:
	## Per-test setup: Mock wrappers, reset Globals state.
	##
	## :rtype: void
	Globals.hidden_menus = []  # Reset stack
	
	# Mock OSWrapper
	mock_os = mock(OSWrapper)
	
	# Mock JavaScriptBridgeWrapper
	mock_js_bridge = mock(JavaScriptBridgeWrapper)
	do_return(null).on(mock_js_bridge).eval(GdUnitArgumentMatchers.any(), GdUnitArgumentMatchers.any())  # No-op for eval
	do_return(null).on(mock_js_bridge).create_callback(GdUnitArgumentMatchers.any())  # No-op for callbacks
	mock_js_window = {"backPressed": null}  # Non-empty dict to be truthy
	do_return(mock_js_window).on(mock_js_bridge).get_interface("window")
	

func after_test() -> void:
	## Per-test cleanup: Reset Globals and mocks.
	##
	## :rtype: void
	Globals.hidden_menus = []  # Clean up
	reset(mock_os)
	reset(mock_js_bridge)


func test_ready_non_web() -> void:
	## Tests _ready for non-web: connects signals and sets mode.
	##
	## :rtype: void
	do_return(false).on(mock_os).has_feature("web")
	var audio_menu: Control = auto_free(load("res://scenes/audio_settings.tscn").instantiate())
	audio_menu.os_wrapper = mock_os
	audio_menu.js_bridge_wrapper = mock_js_bridge
	add_child(audio_menu)  # Triggers _ready
	assert_bool(audio_menu.audio_back_button.pressed.is_connected(audio_menu._on_audio_back_button_pressed)).is_true()
	assert_bool(audio_menu.tree_exited.is_connected(audio_menu._on_tree_exited)).is_true()
	assert_int(audio_menu.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	verify(mock_js_bridge, 0).eval(GdUnitArgumentMatchers.by_type(TYPE_STRING), true)
	verify(mock_js_bridge, 0).get_interface("window")
	verify(mock_js_bridge, 0).create_callback(GdUnitArgumentMatchers.any())


func test_ready_web() -> void:
	## Tests _ready for web: connects signals, sets mode, handles overlays and callbacks.
	##
	## :rtype: void
	do_return(true).on(mock_os).has_feature("web")
	var audio_menu: Control = auto_free(load("res://scenes/audio_settings.tscn").instantiate())
	audio_menu.os_wrapper = mock_os
	audio_menu.js_bridge_wrapper = mock_js_bridge
	add_child(audio_menu)  # Triggers _ready
	assert_bool(audio_menu.audio_back_button.pressed.is_connected(audio_menu._on_audio_back_button_pressed)).is_true()
	assert_bool(audio_menu.tree_exited.is_connected(audio_menu._on_tree_exited)).is_true()
	assert_int(audio_menu.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	verify(mock_js_bridge, 1).eval(GdUnitArgumentMatchers.by_type(TYPE_STRING), true)  # For show overlays
	verify(mock_js_bridge, 1).get_interface("window")
	verify(mock_js_bridge, 12).create_callback(GdUnitArgumentMatchers.any())  # For backPressed


func test_back_button_pops_and_frees() -> void:
	## Tests back handler pops menu, shows prev, frees.
	##
	## :rtype: void
	do_return(false).on(mock_os).has_feature("web")
	var audio_menu: Control = auto_free(load("res://scenes/audio_settings.tscn").instantiate())
	audio_menu.os_wrapper = mock_os
	audio_menu.js_bridge_wrapper = mock_js_bridge
	add_child(audio_menu)
	var mock_prev: Control = auto_free(Control.new())
	mock_prev.visible = false
	Globals.hidden_menus.push_back(mock_prev)
	
	audio_menu._on_audio_back_button_pressed()
	
	assert_bool(Globals.hidden_menus.is_empty()).is_true()
	assert_bool(mock_prev.visible).is_true()
	# Assert queue_free called (via spy or check freed post-await)
	await await_idle_frame()
	assert_bool(not is_instance_valid(audio_menu)).is_true()  # Freed
	# Additional asserts for no double-pop: after full exit, hidden_menus still empty (no extra pop)
	assert_bool(Globals.hidden_menus.is_empty()).is_true()  # No double-pop occurred
	# If there was another menu, it wouldn't be shown; but since stack is empty, just confirm no extra show
	# (For extra assurance, could add a second mock_prev2 and assert it's not shown, but since pop only once, it's fine)


func test_tree_exited_restores_if_stuck() -> void:
	## Tests unexpected exit restores menu.
	##
	## :rtype: void
	do_return(false).on(mock_os).has_feature("web")
	var audio_menu: Control = auto_free(load("res://scenes/audio_settings.tscn").instantiate())
	audio_menu.os_wrapper = mock_os
	audio_menu.js_bridge_wrapper = mock_js_bridge
	add_child(audio_menu)
	var mock_prev: Control = auto_free(Control.new())
	mock_prev.visible = false
	Globals.hidden_menus.push_back(mock_prev)
	
	audio_menu.queue_free()
	await await_idle_frame()
	
	assert_bool(Globals.hidden_menus.is_empty()).is_true()
	assert_bool(mock_prev.visible).is_true()


func test_double_pop_prevented() -> void:
	## Tests that back press does not cause double-pop due to tree_exited.
	##
	## Simulates back press, awaits exit, asserts single pop and show.
	##
	## :rtype: void
	do_return(false).on(mock_os).has_feature("web")
	var audio_menu: Control = auto_free(load("res://scenes/audio_settings.tscn").instantiate())
	audio_menu.os_wrapper = mock_os
	audio_menu.js_bridge_wrapper = mock_js_bridge
	add_child(audio_menu)
	var mock_prev: Control = auto_free(Control.new())
	mock_prev.visible = false
	Globals.hidden_menus.push_back(mock_prev)
	
	# Simulate back press
	audio_menu._on_audio_back_button_pressed()
	
	# Await full exit (queue_free processes on next frame)
	await await_idle_frame()
	
	# Assert single pop: stack empty, prev shown
	assert_bool(Globals.hidden_menus.is_empty()).is_true()
	assert_bool(mock_prev.visible).is_true()
	
	# To confirm no extra show/pop: if we had a second menu underneath, it shouldn't be affected
	# For thoroughness, reset and add two menus
	Globals.hidden_menus = []  # Reset for sub-test
	var mock_prev2: Control = auto_free(Control.new())
	mock_prev2.visible = false
	Globals.hidden_menus.push_back(mock_prev2)
	mock_prev.visible = false  # Reset visibility
	Globals.hidden_menus.push_back(mock_prev)
	
	# Re-instantiate audio_menu for this sub-test
	audio_menu = auto_free(load("res://scenes/audio_settings.tscn").instantiate())
	audio_menu.os_wrapper = mock_os
	audio_menu.js_bridge_wrapper = mock_js_bridge
	add_child(audio_menu)
	
	# Simulate back press again
	audio_menu._on_audio_back_button_pressed()
	await await_idle_frame()
	
	# Assert only top popped: mock_prev shown, mock_prev2 still hidden and in stack
	assert_int(Globals.hidden_menus.size()).is_equal(1)
	assert_object(Globals.hidden_menus[0]).is_equal(mock_prev2)
	assert_bool(mock_prev.visible).is_true()
	assert_bool(mock_prev2.visible).is_false()  # Not shown, no double-pop
