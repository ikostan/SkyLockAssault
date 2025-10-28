# test_difficulty_integration.gd (extends GdUnitTestSuite)
extends GdUnitTestSuite

func test_difficulty_scales_fuel_and_weapon() -> void:
	# Setup: Load main_scene for full context (PlayerStatsPanel for fuel_bar path)
	var main_scene: Variant = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)  # Add to tree for _ready() (init timers, paths)
	# Await frame to ensure @onready vars set (fixes null in tests/CI)
	await await_idle_frame()
	
	# Get player and weapon (correct path per screenshot: under CharacterBody2D)
	var player: Node2D = main_scene.get_node("Player")
	# Assert found
	assert_object(player).is_not_null()  
	# Updated: Full path
	var weapon: Node2D = player.get_node("CharacterBody2D/Weapon")
	# Assert found
	assert_object(weapon).is_not_null()
	
	var original_difficulty: float = Globals.difficulty
	Globals.difficulty = 2.0

	# Simulate fuel depletion
	player.current_fuel = 100.0
	player._on_fuel_timer_timeout()
	# Base 0.5 * 2.0 = 1.0 depletion
	assert_float(player.current_fuel).is_equal(99.0)

	# Simulate fire
	weapon._fire()
	# Base 0.5 * 2.0 = 1.0
	assert_float(weapon.timer.wait_time).is_equal(1.0)

	Globals.difficulty = original_difficulty
