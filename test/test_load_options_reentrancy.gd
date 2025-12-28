## Test script: test_load_options_reentrancy.gd (updated for hidden_menus array)
extends GdUnitTestSuite

var orig_options_scene: PackedScene
var orig_options_instance: CanvasLayer
var orig_hidden_menus: Array[Node]  # Updated to array

func before_test() -> void:
	## Saves and resets globals before test.
	##
	## :rtype: void
	orig_options_scene = Globals.options_scene
	orig_options_instance = Globals.options_instance
	orig_hidden_menus = Globals.hidden_menus.duplicate()  # Copy array to backup
	
	Globals.options_instance = null
	Globals.hidden_menus = []  # Reset to empty array

func after_test() -> void:
	## Restores original globals after test.
	##
	## :rtype: void
	Globals.options_scene = orig_options_scene
	Globals.options_instance = orig_options_instance
	Globals.hidden_menus = orig_hidden_menus.duplicate()  # Restore copy

func test_load_options_guards_reentrancy() -> void:
	## Tests re-entrancy guard in load_options.
	##
	## :rtype: void
	# Mock menu
	var mock_menu: Panel = auto_free(Panel.new())
	mock_menu.visible = true
	
	# First call: Should attempt load (simulate without actual scene)
	Globals.options_scene = null  # Force failure path for test
	Globals.load_options(mock_menu)
	assert_bool(mock_menu.visible).is_true()  # Restored on failure (popped)
	assert_object(Globals.options_instance).is_null()
	assert_array(Globals.hidden_menus).is_empty()  # Cleaned up after pop
	
	# Simulate open instance
	Globals.options_instance = auto_free(CanvasLayer.new())  # Mock valid instance
	Globals.load_options(mock_menu)
	# Assert no change (guard fired)
	assert_bool(mock_menu.visible).is_true()  # Not hidden
	assert_array(Globals.hidden_menus).is_empty()  # No push since guarded
	# auto_free handles cleanup
