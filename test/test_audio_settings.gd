## test_audio_settings.gd
## Unit tests for audio_settings.gd functionality.
##
## Covers initialization, back handling, and unexpected exits.
##
## Uses GdUnitTestSuite for assertions and hooks.

extends GdUnitTestSuite

var audio_menu: Control


func before_test() -> void:
	## Per-test setup: Instantiate fresh menu, reset Globals state.
	##
	## :rtype: void
	Globals.hidden_menus = []  # Reset stack
	audio_menu = auto_free(load("res://scenes/audio_settings.tscn").instantiate())
	add_child(audio_menu)  # Enter tree to trigger _ready


func after_test() -> void:
	## Per-test cleanup: Free menu, reset Globals.
	##
	## :rtype: void
	if is_instance_valid(audio_menu):
		audio_menu.queue_free()
	Globals.hidden_menus = []  # Clean up


func test_ready_connects_signals() -> void:
	## Tests _ready connects signals and sets mode.
	##
	## :rtype: void
	assert_bool(audio_menu.audio_back_button.pressed.is_connected(audio_menu._on_audio_back_button_pressed)).is_true()
	assert_bool(audio_menu.tree_exited.is_connected(audio_menu._on_tree_exited)).is_true()
	assert_int(audio_menu.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
# Mock web feature for full coverage (requires spy/mock on OS/JavaScriptBridge)


func test_back_button_pops_and_frees() -> void:
	## Tests back handler pops menu, shows prev, frees.
	##
	## :rtype: void
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
	if is_instance_valid(audio_menu):
		audio_menu.queue_free()
	audio_menu = auto_free(load("res://scenes/audio_settings.tscn").instantiate())
	add_child(audio_menu)
	
	# Simulate back press again
	audio_menu._on_audio_back_button_pressed()
	await await_idle_frame()
	
	# Assert only top popped: mock_prev shown, mock_prev2 still hidden and in stack
	assert_int(Globals.hidden_menus.size()).is_equal(1)
	assert_object(Globals.hidden_menus[0]).is_equal(mock_prev2)
	assert_bool(mock_prev.visible).is_true()
	assert_bool(mock_prev2.visible).is_false()  # Not shown, no double-pop
