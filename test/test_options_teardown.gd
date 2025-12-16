## Test script: test_options_teardown.gd (updated)
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
