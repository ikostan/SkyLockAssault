## Test script: test_options_teardown.gd
##
## GDUnit test suite for options menu teardown logic.
## Tests options_open flag clearing on exit_tree.
## Run via GDUnit inspector or command line.

extends GdUnitTestSuite

func test_options_open_cleared_on_exit() -> void:
	# Mock Globals
	var mock_globals: Dictionary = {
		"options_open": false,
		"log_message": func(msg: String, lvl: int) -> void: pass  # No-op
	}
	
	# Instance options menu
	var options_inst: CanvasLayer = auto_free(load("res://scenes/options_menu.tscn").instantiate())
	add_child(options_inst)  # Triggers _ready
	await await_idle_frame()  # Await init
	
	assert_bool(mock_globals["options_open"]).is_true()  # Set in _ready
	
	# Simulate free (triggers _exit_tree)
	remove_child(options_inst)
	options_inst.queue_free()
	await await_idle_frame()  # Await exit
	
	assert_bool(mock_globals["options_open"]).is_false()  # Cleared in _exit_tree
