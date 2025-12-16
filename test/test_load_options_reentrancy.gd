## Test script: test_load_options_reentrancy.gd
##
## GDUnit test suite for load_options re-entrancy guard.
## Tests prevention of multiple options loads.
## Run via GDUnit inspector or command line.

extends GdUnitTestSuite

func test_load_options_guards_reentrancy() -> void:
	## Tests re-entrancy guard in load_options.
	##
	## :rtype: void
	# Mock menu
	var mock_menu: Panel = auto_free(Panel.new())
	mock_menu.visible = true
	
	# First call: Should load (simulate without actual scene)
	Globals.options_scene = null  # Force failure path for test
	Globals.load_options(mock_menu)
	assert_bool(mock_menu.visible).is_true()  # Restored on failure
	assert_object(Globals.options_instance).is_null()
	
	# Simulate open instance
	Globals.options_instance = CanvasLayer.new()  # Mock valid instance
	Globals.load_options(mock_menu)
	# Assert no change (guard fired)
	assert_bool(mock_menu.visible).is_true()  # Not hidden
	Globals.options_instance.queue_free()  # Cleanup mock
