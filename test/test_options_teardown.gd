## Test script: test_options_teardown.gd (updated)
extends GdUnitTestSuite

func before_test() -> void:
	## Resets state before each test.
	##
	## :rtype: void
	Globals.options_open = false
	Globals.hidden_menu = null
	Globals.options_instance = null

func test_options_open_cleared_on_exit() -> void:
	## Tests if options_open is set on ready and cleared on exit_tree.
	##
	## :rtype: void
	# Instance options menu
	var options_inst: CanvasLayer = auto_free(load("res://scenes/options_menu.tscn").instantiate())
	add_child(options_inst)  # Triggers _ready
	await await_idle_frame()  # Await init
	
	assert_bool(Globals.options_open).is_true()  # Set in _ready
	
	# Simulate free (triggers _exit_tree)
	remove_child(options_inst)
	options_inst.queue_free()
	await await_idle_frame()  # Await exit
	
	assert_bool(Globals.options_open).is_false()  # Cleared in _exit_tree

func test_hidden_menu_restored_on_exit() -> void:
	## Tests if hidden_menu is restored on exit_tree.
	##
	## :rtype: void
	# Mock hidden menu
	var mock_hidden: Panel = auto_free(Panel.new())
	mock_hidden.visible = false
	Globals.hidden_menu = mock_hidden
	
	# Instance options menu
	var options_inst: CanvasLayer = auto_free(load("res://scenes/options_menu.tscn").instantiate())
	add_child(options_inst)  # Triggers _ready
	await await_idle_frame()
	
	# Simulate free
	remove_child(options_inst)
	options_inst.queue_free()
	await await_idle_frame()
	
	assert_bool(mock_hidden.visible).is_true()  # Restored in _exit_tree
	assert_object(Globals.hidden_menu).is_null()  # Cleared
