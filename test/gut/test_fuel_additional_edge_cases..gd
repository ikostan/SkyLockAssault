## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_fuel_additional_edge_cases.gd
## GUT unit tests covering fuel consumption scaling and negative refuel edge cases.

extends "res://addons/gut/test.gd"

var main_scene: Node
var player_root: Node2D

## Per-test setup: Instantiate a fresh environment and resource.
## :rtype: void
func before_each() -> void:
	# NEW: Reset global settings to a fresh instance to prevent state leakage between tests.
	Globals.settings = GameSettingsResource.new()
	
	# OLD: main_scene = autofree(load("res://scenes/main_scene.tscn").instantiate())
	# OLD: add_child(main_scene)
	# OLD: player_root = main_scene.get_node("Player")
	# NEW: Instantiating the scene here caused orphans in tests that didn't even use it.
	# Scene instantiation is now moved directly into the specific test that needs it.


## test_fuel_consumption_with_scaling | Integration | Verify speed increases fuel consumption
## :rtype: void
func test_fuel_consumption_with_scaling() -> void:
	gut.p("Testing: Fuel consumption scales up when moving at a higher speed.")
	
	# NEW: Instantiate the main scene locally and use GUT's add_child_autoqfree(). 
	# This ensures the scene and all its dynamically generated Sprite2D children are safely queued for deletion.
	main_scene = load("res://scenes/main_scene.tscn").instantiate()
	add_child_autoqfree(main_scene)
	player_root = main_scene.get_node("Player")
	
	# NEW: Establish a clean baseline for fuel and difficulty.
	Globals.settings.current_fuel = 100.0
	Globals.settings.difficulty = 1.0
	
	# NEW: Simulate consumption at normal (minimum) speed.
	player_root.speed["speed"] = player_root.MIN_SPEED
	player_root._on_fuel_timer_timeout()
	var base_depletion: float = 100.0 - Globals.settings.current_fuel
	
	# NEW: Reset the fuel tank for the second measurement.
	Globals.settings.current_fuel = 100.0
	
	# NEW: Simulate consumption at an increased-consumption state (maximum speed).
	player_root.speed["speed"] = player_root.MAX_SPEED
	player_root._on_fuel_timer_timeout()
	var high_speed_depletion: float = 100.0 - Globals.settings.current_fuel
	
	# NEW: Assert that the high-speed state drained strictly more fuel than the base-speed state.
	assert_gt(high_speed_depletion, base_depletion, "High speed state must consume more fuel than base speed.")


## test_refuel_negative_input | Resource | Validate handling of invalid refuel input
## :rtype: void
func test_refuel_negative_input() -> void:
	gut.p("Testing: Refueling with a negative value should be ignored.")
	
	# NEW: Set an initial baseline fuel level.
	var initial_fuel: float = 50.0
	Globals.settings.current_fuel = initial_fuel
	
	# NEW: Attempt to apply a negative refuel amount (-10.0) which should be caught by the refuel logic.
	Globals.settings.refuel(-10.0)
	
	# NEW: Assert the fuel level remained completely unchanged and did not accidentally subtract fuel.
	assert_eq(Globals.settings.current_fuel, initial_fuel, "Negative refuel inputs must not drain the current fuel.")
