## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_fuel_additional_edge_cases.gd
## GUT unit tests covering fuel consumption scaling and negative refuel edge cases.

extends "res://addons/gut/test.gd"

var main_scene: Node
var player_root: Node2D
# NEW: Declare the member variable to prevent "Identifier not found" script errors
var _previous_settings: GameSettingsResource

## Per-test setup: Instantiate a fresh environment and resource.
## :rtype: void
func before_each() -> void:
	_previous_settings = Globals.settings
	# NEW: Reset global settings to a fresh instance to prevent state leakage between tests.
	Globals.settings = GameSettingsResource.new()

func after_each() -> void:
	Globals.settings = _previous_settings


## test_fuel_consumption_with_scaling | Integration | Verify speed increases fuel consumption
## :rtype: void
func test_fuel_consumption_with_scaling() -> void:
	gut.p("Testing: Fuel consumption scales up when moving at a higher speed.")
	
	# NEW: Instantiate the main scene locally and use GUT's add_child_autoqfree().
	# This ensures the scene and all its dynamically generated Sprite2D children are safely queued for deletion.
	main_scene = load(GamePaths.MAIN_SCENE).instantiate()
	add_child_autoqfree(main_scene)
	player_root = main_scene.get_node("Player")
	player_root.fuel_timer.stop()
	# Fuel state lives on the player's FuelResource, not on Globals.settings (#1142).
	var fuel: FuelResource = player_root.fuel_resource
	
	# NEW: Establish a clean baseline for fuel and difficulty.
	fuel.current_fuel = 100.0
	Globals.settings.difficulty = 1.0
	
	# CHANGED: Use current_speed instead of speed["speed"]
	player_root.current_speed = Globals.settings.min_speed
	player_root._on_fuel_timer_timeout()
	var base_depletion: float = 100.0 - fuel.current_fuel
	
	# NEW: Reset the fuel tank for the second measurement.
	fuel.current_fuel = 100.0
	
	# CHANGED: Use current_speed instead of speed["speed"]
	player_root.current_speed = Globals.settings.max_speed
	player_root._on_fuel_timer_timeout()
	var high_speed_depletion: float = 100.0 - fuel.current_fuel
	
	# NEW: Assert that the high-speed state drained strictly more fuel than the base-speed state.
	assert_gt(high_speed_depletion, base_depletion, "High speed state must consume more fuel than base speed.")


## test_refuel_negative_input | FuelResource | Validate handling of invalid refuel input
## :rtype: void
func test_refuel_negative_input() -> void:
	gut.p("Testing: Refueling with a negative value should be ignored.")
	var fuel: FuelResource = FuelResource.new()
	
	# NEW: Set an initial baseline fuel level.
	var initial_fuel: float = 50.0
	fuel.current_fuel = initial_fuel
	
	# NEW: Attempt to apply a negative refuel amount (-10.0) which should be caught by the refuel logic.
	fuel.refuel(-10.0)
	
	# NEW: Assert the fuel level remained completely unchanged and did not accidentally subtract fuel.
	assert_eq(fuel.current_fuel, initial_fuel, "Negative refuel inputs must not drain the current fuel.")
