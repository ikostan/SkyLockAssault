# test_difficulty.gd (extends GdUnitTestSuite)
# Unit tests for difficulty scaling in player.gd using GdUnit4.

extends GdUnitTestSuite

const TestHelpers = preload("res://test/test_helpers.gd")

var original_difficulty: float  # Snapshot holder

func before_test() -> void:
	original_difficulty = Globals.difficulty  # Snapshot before each test

func after_test() -> void:
	Globals.difficulty = original_difficulty  # Restore after each test


## Tests fuel depletion scaling with difficulty levels.
## @return: void
## Tests fuel depletion scaling with difficulty levels.
## @return: void
func test_fuel_depletion_with_difficulty() -> void:
	# Setup: Instance the full main scene and add to tree for _ready/@onready to resolve paths
	var main_scene: Variant = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)  # Enters scene tree, initializes @onready vars like fuel_bar
	
	# Get the player node from the scene
	var player_inst: Variant = main_scene.get_node("Player")
	
	# Save original difficulty for reset
	var original_difficulty: float = Globals.difficulty
	
	# Reset fuel before each sim for independent tests
	player_inst.fuel["fuel"] = 100.0
	Globals.difficulty = 1.0
	var normalized_speed: float = player_inst.speed["speed"] / player_inst.MAX_SPEED
	var dep_1: float = player_inst.base_fuel_drain * normalized_speed * Globals.difficulty
	player_inst._on_fuel_timer_timeout()
	assert_float(player_inst.fuel["fuel"]).is_equal_approx(100.0 - dep_1, 0.01)  # Larger delta for precision
	
	player_inst.fuel["fuel"] = 100.0
	Globals.difficulty = 2.0
	normalized_speed = player_inst.speed["speed"] / player_inst.MAX_SPEED  # Re-derive
	var dep_2: float = player_inst.base_fuel_drain * normalized_speed * Globals.difficulty
	player_inst._on_fuel_timer_timeout()
	assert_float(player_inst.fuel["fuel"]).is_equal_approx(100.0 - dep_2, 0.01)
	
	player_inst.fuel["fuel"] = 100.0
	Globals.difficulty = 0.5
	normalized_speed = player_inst.speed["speed"] / player_inst.MAX_SPEED
	var dep_05: float = player_inst.base_fuel_drain * normalized_speed * Globals.difficulty
	player_inst._on_fuel_timer_timeout()
	assert_float(player_inst.fuel["fuel"]).is_equal_approx(100.0 - dep_05, 0.01)
	
	# Reset original
	Globals.difficulty = original_difficulty
