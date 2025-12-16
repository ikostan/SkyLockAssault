## Test Options Teardown Script
##
## Unit tests for options menu teardown logic, including flag and menu restoration.
##
## Uses GdUnitTestSuite for assertions and lifecycle hooks.
##
## :vartype orig_hidden_menu: Node
## :vartype orig_options_open: bool
## :vartype orig_options_instance: CanvasLayer
## :vartype orig_options_scene: PackedScene

extends GdUnitTestSuite

var orig_hidden_menu: Node
var orig_options_open: bool
var orig_options_instance: CanvasLayer
var orig_options_scene: PackedScene  # Extra for consistency

func before_test() -> void:
	## Saves and resets globals before each test.
	##
	## :rtype: void
	orig_hidden_menu = Globals.hidden_menu
	orig_options_open = Globals.options_open
	orig_options_instance = Globals.options_instance
	orig_options_scene = Globals.options_scene
	
	Globals.hidden_menu = null
	Globals.options_open = false
	Globals.options_instance = null
	# No mutation here, but reset if needed

func after_test() -> void:
	## Restores original globals after each test.
	##
	## :rtype: void
	Globals.hidden_menu = orig_hidden_menu
	Globals.options_open = orig_options_open
	Globals.options_instance = orig_options_instance
	Globals.options_scene = orig_options_scene

func test_options_open_cleared_on_exit() -> void:
	## Tests if options_open is set on load_options and cleared on exit_tree.
	##
	## :rtype: void
	# Mock hidden menu (null for this test)
	Globals.load_options(null)  # Triggers instantiation and add_child; sets flag
	
	await await_idle_frame()  # Await init
	
	assert_bool(Globals.options_open).is_true()  # Set in load_options
	
	# Simulate free (triggers _exit_tree)
	Globals.options_instance.queue_free()
	await await_idle_frame()  # Await exit
	
	assert_bool(Globals.options_open).is_false()  # Cleared in _exit_tree

func test_hidden_menu_restored_on_exit() -> void:
	## Tests if hidden_menu is restored on exit_tree.
	##
	## :rtype: void
	# Mock hidden menu
	var mock_hidden: Panel = auto_free(Panel.new())
	mock_hidden.visible = false
	
	Globals.load_options(mock_hidden)  # Loads options, hides mock, sets flag/refs
	
	await await_idle_frame()
	
	# Simulate free
	Globals.options_instance.queue_free()
	await await_idle_frame()
	
	assert_bool(mock_hidden.visible).is_true()  # Restored in _exit_tree
	assert_object(Globals.hidden_menu).is_null()  # Cleared

func test_unexpected_exit_resets_flag() -> void:
	## Tests if handler resets flag on unexpected exit (e.g., if normal teardown fails).
	##
	## Uses dummy node to isolate handler behavior without full menu load.
	##
	## :rtype: void
	# Spy on Globals
	var spy_globals: Node = spy(Globals)
	
	# Simulate stuck flag (as if teardown failed)
	Globals.options_open = true
	
	# Create dummy to simulate options_instance
	var dummy: CanvasLayer = auto_free(CanvasLayer.new())
	Globals.options_instance = dummy  # Set ref for cleanup
	
	add_child(dummy)  # Add to tree to enable exit signals
	
	# Connect handler (as in load_options)
	dummy.tree_exited.connect(Globals._on_options_exited_unexpectedly)
	
	# Simulate unexpected free
	dummy.queue_free()
	
	await await_idle_frame()
	
	# Assert flag reset by handler
	assert_bool(Globals.options_open).is_false()
	
	# Verify handler logged the reset (add period if in your handler string)
	verify(spy_globals, 1).log_message("Options instance exited unexpectedly—resetting flag.", Globals.LogLevel.WARNING)
