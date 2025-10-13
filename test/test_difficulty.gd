# test_difficulty.gd (extends GdUnitTestSuite)
extends GdUnitTestSuite


func test_fuel_depletion_with_difficulty() -> void:
	# Setup: Instance player and mock globals
	var globals_mock: Variant = mock(Globals)
	do_return(1.0).on(globals_mock).get("difficulty")  # Normal
	var player_inst: Variant = auto_free(load("res://scenes/player.tscn").instantiate())
	
	# Simulate initial fuel
	player_inst.current_fuel = 100.0
	player_inst._on_fuel_timer_timeout()
	assert_float(player_inst.current_fuel).is_equal(99.5)  # Base 0.5 depletion
	
	# Change difficulty to Hard (2.0)
	do_return(2.0).on(globals_mock).get("difficulty")
	player_inst._on_fuel_timer_timeout()
	assert_float(player_inst.current_fuel).is_equal(98.5)  # Doubled depletion (1.0)
	
	# Change to Easy (0.5)
	do_return(0.5).on(globals_mock).get("difficulty")
	player_inst._on_fuel_timer_timeout()
	assert_float(player_inst.current_fuel).is_equal(98.25)  # Halved depletion (0.25)
