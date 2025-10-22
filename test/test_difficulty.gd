# test_difficulty.gd (extends GdUnitTestSuite)
extends GdUnitTestSuite

func test_fuel_depletion_with_difficulty() -> void:
	# Setup: Instance the full main scene and add to tree for _ready/@onready to resolve paths
	var main_scene: Variant = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)  # Enters scene tree, initializes @onready vars like fuel_bar
	
	# Get the player node from the scene
	var player_inst: Variant = main_scene.get_node("Player")
	
	# Save original difficulty for reset
	var original_difficulty: float = Globals.difficulty
	
	# Simulate initial fuel
	player_inst.current_fuel = 100.0
	
	# Normal (1.0)
	Globals.difficulty = 1.0
	player_inst._on_fuel_timer_timeout()
	assert_float(player_inst.current_fuel).is_equal(99.5)  # Base 0.5 depletion
	
	# Hard (2.0)
	Globals.difficulty = 2.0
	player_inst._on_fuel_timer_timeout()
	assert_float(player_inst.current_fuel).is_equal(98.5)  # Doubled depletion (1.0)
	
	# Easy (0.5)
	Globals.difficulty = 0.5
	player_inst._on_fuel_timer_timeout()
	assert_float(player_inst.current_fuel).is_equal(98.25)  # Halved depletion (0.25)
	
	# Reset original
	Globals.difficulty = original_difficulty
