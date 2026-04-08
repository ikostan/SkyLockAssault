## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_fuel_resource.gd
## GUT unit tests for Fuel System core logic in GameSettingsResource.
##
## Covers initialization, deterministic consumption, and clamping.
extends "res://addons/gut/test.gd"

var fuel_res: GameSettingsResource
const TOLERANCE: float = 0.0001


## Per-test setup: Instantiate a fresh resource.
## :rtype: void
func before_each() -> void:
	fuel_res = GameSettingsResource.new()
	
	# OLD: 
	# fuel_res.max_fuel = 100.0
	# fuel_res.current_fuel = 100.0
	# fuel_res.base_consumption_rate = 1.0
	
	# NEW: Removed the manual property assignments. This ensures test_fuel_initialization()
	# genuinely verifies the default values hardcoded within the GameSettingsResource script.

# --- 1. Initialization Tests ---

## test_fuel_initialization | Verify fuel initializes to max capacity
## :rtype: void
func test_fuel_initialization() -> void:
	gut.p("Testing: Fuel should default to max_capacity on init.")
	assert_eq(fuel_res.current_fuel, fuel_res.max_fuel, "Initial fuel must match max capacity")

# --- 2. Consumption & Clamping Tests ---

## test_fuel_consumption_static_exact | Validate deterministic fuel consumption
## :rtype: void
func test_fuel_consumption_static_exact() -> void:
	gut.p("Testing: Deterministic fuel drain over fixed delta steps.")
	var start_fuel: float = fuel_res.current_fuel
	var delta: float = 0.1
	var steps: int = 10
	var rate: float = fuel_res.base_consumption_rate
	
	for i in range(steps):
		# Manual subtraction to simulate the physics/timer logic
		fuel_res.current_fuel -= rate * delta
		
	var expected: float = start_fuel - (rate * delta * steps)
	assert_almost_eq(fuel_res.current_fuel, expected, TOLERANCE, "Fuel drain calculation mismatch")

## test_fuel_not_negative | Ensure fuel is clamped at zero
## :rtype: void
func test_fuel_not_negative() -> void:
	gut.p("Testing: Fuel setter must clamp values to 0.0.")
	fuel_res.current_fuel = 0.5
	fuel_res.current_fuel -= 10.0 # Force negative via subtraction
	assert_eq(fuel_res.current_fuel, 0.0, "Fuel should never be negative")

# --- 3. Refuel Tests ---

## test_refuel_basic | Verify refuel increases fuel correctly
## :rtype: void
func test_refuel_basic() -> void:
	gut.p("Testing: Refuel logic adds to current stock.")
	fuel_res.current_fuel = 50.0
	fuel_res.refuel(20.0) 
	assert_eq(fuel_res.current_fuel, 70.0, "Refuel amount not correctly added")

## test_refuel_clamped_to_max | Ensure refuel does not exceed capacity
## :rtype: void
func test_refuel_clamped_to_max() -> void:
	gut.p("Testing: Refuel logic clamps at max_fuel.")
	fuel_res.current_fuel = 95.0
	fuel_res.refuel(20.0)
	assert_eq(fuel_res.current_fuel, 100.0, "Fuel exceeded max_capacity after refuel")
