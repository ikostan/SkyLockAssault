## Test script: test_options_teardown.gd
##
## GDUnit test suite for options menu teardown logic.
## Tests options_open flag clearing on exit_tree.
## Run via GDUnit inspector or command line.

extends GdUnitTestSuite

func before_test() -> void:
	## Resets options_open before each test.
	##
	## :rtype: void
	Globals.options_open = false

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
