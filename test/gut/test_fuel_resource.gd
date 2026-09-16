## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_fuel_resource.gd
##
## GUT unit tests for FuelResource.
## Covers initialization, deterministic consumption, boundary enforcements, 
## invariants, and deterministic signal crossing semantics.

extends "res://addons/gut/test.gd"

var fuel_res: FuelResource
const TOLERANCE: float = 0.0001


func before_each() -> void:
	# Now instantiates the dedicated data container instead of GameSettingsResource
	fuel_res = FuelResource.new()
	watch_signals(fuel_res)


func after_each() -> void:
	fuel_res.free()


# ==========================================
# 1. INITIALIZATION TESTS (From Original)
# ==========================================

## test_fuel_initialization | Verify fuel initializes to max capacity
func test_fuel_initialization() -> void:
	gut.p("Testing: Fuel should default to max_capacity on init.")
	assert_eq(fuel_res.current_fuel, fuel_res.max_fuel, "Initial fuel must match max capacity")


# ==========================================
# 2. CONSUMPTION & REFUEL TESTS (From Original)
# ==========================================

## test_fuel_consumption_static_exact | Validate deterministic fuel consumption
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

## test_refuel_basic | Verify refuel increases fuel correctly
func test_refuel_basic() -> void:
	gut.p("Testing: Refuel logic adds to current stock.")
	fuel_res.current_fuel = 50.0
	fuel_res.refuel(20.0) 
	assert_eq(fuel_res.current_fuel, 70.0, "Refuel amount not correctly added")

## test_refuel_clamped_to_max | Ensure refuel does not exceed capacity
func test_refuel_clamped_to_max() -> void:
	gut.p("Testing: Refuel logic clamps at max_fuel.")
	fuel_res.current_fuel = 95.0
	fuel_res.refuel(20.0)
	assert_eq(fuel_res.current_fuel, 100.0, "Fuel exceeded max_capacity after refuel")


# ==========================================
# 3. BOUNDARY & INVARIANT TESTS (New Phase 1)
# ==========================================

func test_max_fuel_enforces_minimum() -> void:
	gut.p("Testing: max_fuel cannot drop below 1.0 to prevent division by zero.")
	fuel_res.max_fuel = -50.0
	assert_eq(fuel_res.max_fuel, 1.0, "max_fuel should clamp to a minimum of 1.0.")

func test_max_fuel_clamps_current_fuel() -> void:
	gut.p("Testing: Decreasing max_fuel below current_fuel automatically clamps current_fuel.")
	fuel_res.max_fuel = 100.0
	fuel_res.current_fuel = 100.0
	
	# Shrink the tank capacity
	fuel_res.max_fuel = 50.0
	
	assert_eq(fuel_res.current_fuel, 50.0, "current_fuel must shrink to fit the new max_fuel.")
	assert_signal_emitted_with_parameters(
		fuel_res, 
		"fuel_changed", 
		[50.0], 
		"Clamping current_fuel via max_fuel must emit fuel_changed."
	)

func test_current_fuel_clamps_to_bounds() -> void:
	gut.p("Testing: current_fuel cannot exceed [0.0, max_fuel].")
	fuel_res.max_fuel = 100.0
	
	fuel_res.current_fuel = 150.0
	assert_eq(fuel_res.current_fuel, 100.0, "current_fuel should clamp to max_fuel.")
	
	fuel_res.current_fuel = -20.0
	assert_eq(fuel_res.current_fuel, 0.0, "current_fuel should clamp to 0.0.")


# ==========================================
# 4. SIGNAL CROSSING SEMANTICS (New Phase 1)
# ==========================================

func test_fuel_changed_emitted_only_on_effective_change() -> void:
	gut.p("Testing: fuel_changed is strictly emitted only when the effective value mutates.")
	fuel_res.current_fuel = 50.0
	assert_signal_emitted(fuel_res, "fuel_changed", "Signal should emit on actual change.")
	
	# Clear signal watches to test unchanged behavior
	watch_signals(fuel_res) 
	
	# Assign the exact same value
	fuel_res.current_fuel = 50.0
	assert_signal_not_emitted(
		fuel_res, 
		"fuel_changed", 
		"Signal must not emit when value is identically reassigned."
	)
	
	# Assign an out-of-bounds value that results in no effective change after clamping
	fuel_res.max_fuel = 50.0
	watch_signals(fuel_res)
	fuel_res.current_fuel = 100.0 # Clamps down to 50.0
	assert_signal_not_emitted(
		fuel_res, 
		"fuel_changed", 
		"Signal must not emit when clamped value equals previous value."
	)

func test_fuel_depleted_crossing_semantics() -> void:
	gut.p("Testing: fuel_depleted strictly emits only when crossing from >0 to 0.")
	
	# 1. Normal crossing
	fuel_res.current_fuel = 10.0
	fuel_res.current_fuel = 0.0
	assert_signal_emitted(fuel_res, "fuel_depleted", "Crossing to 0.0 should emit fuel_depleted.")
	
	watch_signals(fuel_res)
	
	# 2. Spamming zero (should not emit duplicate signals)
	fuel_res.current_fuel = 0.0
	fuel_res.current_fuel = -10.0 # Clamps to 0.0
	assert_signal_not_emitted(
		fuel_res, 
		"fuel_depleted", 
		"Staying at 0.0 must not redundantly emit fuel_depleted."
	)
	
	# 3. Refueling and crossing again
	fuel_res.refuel(50.0)
	assert_signal_not_emitted(fuel_res, "fuel_depleted", "Refueling does not emit fuel_depleted.")
	
	fuel_res.current_fuel = 0.0
	assert_signal_emitted(fuel_res, "fuel_depleted", "Crossing to 0.0 again should emit fuel_depleted.")
