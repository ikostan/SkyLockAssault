## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
# test_difficulty.gd (extends GdUnitTestSuite)
# Unit tests for difficulty scaling in player.gd using GdUnit4.

extends GdUnitTestSuite

const TestHelpers = preload("res://test/gdunit4/test_helpers.gd")

var original_difficulty: float  # Snapshot holder
# NEW: Added snapshot holders for global fuel state to prevent test leakage
var original_current_fuel: float
var original_max_fuel: float


func before_test() -> void:
	original_difficulty = Globals.settings.difficulty  # Snapshot before each test
	# NEW: Snapshot fuel state
	original_current_fuel = Globals.settings.current_fuel
	original_max_fuel = Globals.settings.max_fuel


func after_test() -> void:
	Globals.settings.difficulty = original_difficulty  # Restore after each test
	# NEW: Restore fuel state so other tests start clean
	Globals.settings.max_fuel = original_max_fuel
	Globals.settings.current_fuel = original_current_fuel


## Tests fuel depletion scaling with difficulty levels.
## @return: void
func test_fuel_depletion_with_difficulty() -> void:
	# Setup: Instance the full main scene and add to tree for _ready/@onready to resolve paths
	var main_scene: Variant = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)  # Enters scene tree, initializes @onready vars like fuel_bar
	
	# Get the player node from the scene
	var player_inst: Variant = main_scene.get_node("Player")
	
	# Save original difficulty for reset
	var original_difficulty: float = Globals.settings.difficulty
	# NEW: Derive the starting baseline dynamically to avoid clamping issues if max_fuel changed
	var start_fuel: float = Globals.settings.max_fuel
	
	# Reset fuel before each sim for independent tests
	# OLD: player_inst.fuel["fuel"] = 100.0
	# NEW: Reset the global fuel resource instead of the local dictionary using the dynamic baseline
	Globals.settings.current_fuel = start_fuel
	Globals.settings.difficulty = 1.0
	
	# NEW: Use Globals.settings.max_speed instead of the removed player_inst.MAX_SPEED
	var normalized_speed: float = player_inst.speed["speed"] / Globals.settings.max_speed
	
	# OLD: var dep_1: float = player_inst.base_fuel_drain * normalized_speed * Globals.settings.difficulty
	# NEW: Use the global base_consumption_rate instead of the removed local base_fuel_drain
	var dep_1: float = Globals.settings.base_consumption_rate * normalized_speed * Globals.settings.difficulty
	
	player_inst._on_fuel_timer_timeout()
	
	# OLD: assert_float(player_inst.fuel["fuel"]).is_equal_approx(100.0 - dep_1, 0.01)  # Larger delta for precision
	# NEW: Assert against the global fuel resource and dynamic baseline
	assert_float(Globals.settings.current_fuel).is_equal_approx(start_fuel - dep_1, 0.01)
	
	# OLD: player_inst.fuel["fuel"] = 100.0
	# NEW: Reset the global fuel resource for the second test
	Globals.settings.current_fuel = start_fuel
	Globals.settings.difficulty = 2.0
	
	# NEW: Use Globals.settings.max_speed instead of the removed player_inst.MAX_SPEED
	normalized_speed = player_inst.speed["speed"] / Globals.settings.max_speed
	
	# OLD: var dep_2: float = player_inst.base_fuel_drain * normalized_speed * Globals.settings.difficulty
	# NEW: Use the global base_consumption_rate instead of the removed local base_fuel_drain
	var dep_2: float = Globals.settings.base_consumption_rate * normalized_speed * Globals.settings.difficulty
	
	player_inst._on_fuel_timer_timeout()
	
	# OLD: assert_float(player_inst.fuel["fuel"]).is_equal_approx(100.0 - dep_2, 0.01)
	# NEW: Assert against the global fuel resource and dynamic baseline
	assert_float(Globals.settings.current_fuel).is_equal_approx(start_fuel - dep_2, 0.01)
	
	# OLD: player_inst.fuel["fuel"] = 100.0
	# NEW: Reset the global fuel resource for the third test
	Globals.settings.current_fuel = start_fuel
	Globals.settings.difficulty = 0.5
	
	# NEW: Use Globals.settings.max_speed instead of the removed player_inst.MAX_SPEED
	normalized_speed = player_inst.speed["speed"] / Globals.settings.max_speed
	
	# OLD: var dep_05: float = player_inst.base_fuel_drain * normalized_speed * Globals.settings.difficulty
	# NEW: Use the global base_consumption_rate instead of the removed local base_fuel_drain
	var dep_05: float = Globals.settings.base_consumption_rate * normalized_speed * Globals.settings.difficulty
	
	player_inst._on_fuel_timer_timeout()
	
	# OLD: assert_float(player_inst.fuel["fuel"]).is_equal_approx(100.0 - dep_05, 0.01)
	# NEW: Assert against the global fuel resource and dynamic baseline
	assert_float(Globals.settings.current_fuel).is_equal_approx(start_fuel - dep_05, 0.01)
