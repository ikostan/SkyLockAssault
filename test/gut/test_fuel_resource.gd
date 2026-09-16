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
	fuel_res = FuelResource.new()


func after_each() -> void:
	pass


# ==========================================
# 1. INITIALIZATION TESTS (From Original)
# ==========================================

func test_fuel_initialization() -> void:
	gut.p("Testing: Fuel should default to max_capacity on init.")
	assert_eq(fuel_res.current_fuel, fuel_res.max_fuel, "Initial fuel must match max capacity")


# ==========================================
# 2. CONSUMPTION & REFUEL TESTS (From Original)
# ==========================================

func test_fuel_consumption_static_exact() -> void:
	gut.p("Testing: Deterministic fuel drain over fixed delta steps.")
	var start_fuel: float = fuel_res.current_fuel
	var delta: float = 0.1
	var steps: int = 10
	var rate: float = fuel_res.base_consumption_rate
	
	for i in range(steps):
		fuel_res.current_fuel -= rate * delta
		
	var expected: float = start_fuel - (rate * delta * steps)
	assert_almost_eq(fuel_res.current_fuel, expected, TOLERANCE, "Fuel drain calculation mismatch")

func test_refuel_basic() -> void:
	gut.p("Testing: Refuel logic adds to current stock.")
	fuel_res.current_fuel = 50.0
	fuel_res.refuel(20.0) 
	assert_eq(fuel_res.current_fuel, 70.0, "Refuel amount not correctly added")

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
	
	watch_signals(fuel_res)
	
	# Shrink the tank capacity
	fuel_res.max_fuel = 50.0
	
	assert_eq(fuel_res.current_fuel, 50.0, "current_fuel must shrink to fit the new max_fuel.")
	
	# FIX: Removed the 4th String argument so GUT doesn't crash
	assert_signal_emitted_with_parameters(fuel_res, "fuel_changed", [50.0])

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
	
	watch_signals(fuel_res) 
	
	fuel_res.current_fuel = 50.0
	
	# FIX: Use emit counts to verify no new signals fired after watching
	assert_signal_emit_count(fuel_res, "fuel_changed", 0, "Signal must not emit when identically reassigned.")
	
	fuel_res.max_fuel = 50.0
	fuel_res.current_fuel = 100.0 # Clamps down to 50.0
	
	assert_signal_emit_count(fuel_res, "fuel_changed", 0, "Signal must not emit when clamped value equals previous value.")

func test_fuel_depleted_crossing_semantics() -> void:
	gut.p("Testing: fuel_depleted strictly emits only when crossing from >0 to 0.")
	
	fuel_res.current_fuel = 10.0
	watch_signals(fuel_res)
	
	# 1. Normal crossing
	fuel_res.current_fuel = 0.0
	
	# FIX: Track total running count instead of attempting to clear history
	assert_signal_emit_count(fuel_res, "fuel_depleted", 1, "Crossing to 0.0 should emit fuel_depleted exactly once.")
	
	# 2. Spamming zero
	fuel_res.current_fuel = 0.0
	fuel_res.current_fuel = -10.0 # Clamps to 0.0
	assert_signal_emit_count(fuel_res, "fuel_depleted", 1, "Staying at 0.0 must not redundantly emit fuel_depleted.")
	
	# 3. Refueling and crossing again
	fuel_res.refuel(50.0)
	assert_signal_emit_count(fuel_res, "fuel_depleted", 1, "Refueling does not emit fuel_depleted.")
	
	fuel_res.current_fuel = 0.0
	assert_signal_emit_count(fuel_res, "fuel_depleted", 2, "Crossing to 0.0 again should emit fuel_depleted a second time.")
