## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_fuel_resource.gd
##
## GUT unit tests for FuelResource.
## Covers initialization, deterministic consumption, boundary enforcements, 
## invariants, deterministic signal crossing semantics, and fuel threshold
## validation (#1147).

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


# ==========================================
# 5. FUEL THRESHOLD VALIDATION (#1147)
# ==========================================

## Returns the four thresholds as [high, medium, low, no_fuel].
## :rtype: Array[float]
func _thresholds() -> Array[float]:
	return [
		fuel_res.high_fuel_threshold,
		fuel_res.medium_fuel_threshold,
		fuel_res.low_fuel_threshold,
		fuel_res.no_fuel_threshold,
	]


## test_default_thresholds_are_valid | Thresholds
func test_default_thresholds_are_valid() -> void:
	gut.p("Testing: The default thresholds form a valid set.")
	assert_eq(_thresholds(), [90.0, 50.0, 30.0, 15.0], "Defaults must stay 90/50/30/15.")
	assert_true(fuel_res.set_thresholds(90.0, 50.0, 30.0, 15.0), "The defaults must pass validation.")


## test_set_thresholds_lowers_all_exactly_from_defaults | Thresholds
## The #1147 bug: one by one, (20, 15, 10, 5) clamps high to 51 because medium is still 50.
func test_set_thresholds_lowers_all_exactly_from_defaults() -> void:
	gut.p("Testing: Lowering every threshold applies exactly from the defaults.")
	assert_true(fuel_res.set_thresholds(20.0, 15.0, 10.0, 5.0), "A valid lowered set must apply.")
	assert_eq(_thresholds(), [20.0, 15.0, 10.0, 5.0], "Lowered thresholds must apply as written.")


## test_set_thresholds_raises_all_exactly_from_defaults | Thresholds
func test_set_thresholds_raises_all_exactly_from_defaults() -> void:
	gut.p("Testing: Raising every threshold applies exactly from the defaults.")
	assert_true(fuel_res.set_thresholds(98.0, 80.0, 70.0, 60.0), "A valid raised set must apply.")
	assert_eq(_thresholds(), [98.0, 80.0, 70.0, 60.0], "Raised thresholds must apply as written.")


## test_set_thresholds_accepts_the_bounds | Thresholds
func test_set_thresholds_accepts_the_bounds() -> void:
	gut.p("Testing: 0, 100, and gaps of exactly 1 are allowed.")
	assert_true(fuel_res.set_thresholds(100.0, 2.0, 1.0, 0.0), "0, 100 and a gap of 1 must apply.")
	assert_eq(_thresholds(), [100.0, 2.0, 1.0, 0.0], "Boundary thresholds must apply as written.")


## test_set_thresholds_is_independent_of_current_values | Thresholds
func test_set_thresholds_is_independent_of_current_values() -> void:
	gut.p("Testing: The result doesn't depend on the previous thresholds.")
	assert_true(fuel_res.set_thresholds(98.0, 80.0, 70.0, 60.0))
	assert_true(fuel_res.set_thresholds(20.0, 15.0, 10.0, 5.0), "Lowering after raising must apply.")
	assert_eq(_thresholds(), [20.0, 15.0, 10.0, 5.0], "The second set must apply as written.")
	assert_true(fuel_res.set_thresholds(98.0, 80.0, 70.0, 60.0), "Raising after lowering must apply.")
	assert_eq(_thresholds(), [98.0, 80.0, 70.0, 60.0], "The third set must apply as written.")


## test_set_thresholds_rejects_invalid_sets | Thresholds
## Each invalid set must return false, warn, and leave every threshold unchanged.
func test_set_thresholds_rejects_invalid_sets(
	params: Array = use_parameters([
		["out of order", [50.0, 90.0, 30.0, 15.0]],
		["high equals medium", [50.0, 50.0, 30.0, 15.0]],
		["low equals no_fuel", [90.0, 50.0, 15.0, 15.0]],
		["too close", [90.0, 89.5, 30.0, 15.0]],
		["below 0", [90.0, 50.0, 30.0, -1.0]],
		["above 100", [101.0, 50.0, 30.0, 15.0]],
		["NaN", [90.0, NAN, 30.0, 15.0]],
		["infinite", [INF, 50.0, 30.0, 15.0]],
	])
) -> void:
	var label: String = params[0]
	var values: Array = params[1]
	gut.p("Testing: set_thresholds() rejects a set that is %s." % label)
	# Start from a custom set, so "unchanged" can't pass by matching the defaults.
	assert_true(fuel_res.set_thresholds(80.0, 60.0, 40.0, 20.0))
	
	var applied: bool = fuel_res.set_thresholds(values[0], values[1], values[2], values[3])
	
	assert_false(applied, "A set that is %s must be rejected." % label)
	assert_push_warning("FuelResource: rejected fuel thresholds")
	assert_eq(_thresholds(), [80.0, 60.0, 40.0, 20.0], "A rejected set must change nothing.")


## test_single_setters_keep_the_order | Thresholds
## The Inspector and existing callers still set thresholds one at a time.
func test_single_setters_keep_the_order() -> void:
	gut.p("Testing: Single-value setters clamp against their neighbours.")
	fuel_res.high_fuel_threshold = 10.0
	assert_eq(fuel_res.high_fuel_threshold, 51.0, "high must stay above medium + 1.")
	fuel_res.medium_fuel_threshold = 95.0
	assert_eq(fuel_res.medium_fuel_threshold, 50.0, "medium must stay below high - 1.")
	fuel_res.medium_fuel_threshold = 10.0
	assert_eq(fuel_res.medium_fuel_threshold, 31.0, "medium must stay above low + 1.")
	fuel_res.low_fuel_threshold = 40.0
	assert_eq(fuel_res.low_fuel_threshold, 30.0, "low must stay below medium - 1.")
	fuel_res.low_fuel_threshold = 5.0
	assert_eq(fuel_res.low_fuel_threshold, 16.0, "low must stay above no_fuel + 1.")
	fuel_res.no_fuel_threshold = 25.0
	assert_eq(fuel_res.no_fuel_threshold, 15.0, "no_fuel must stay below low - 1.")


## test_single_setters_respect_0_and_100 | Thresholds
func test_single_setters_respect_0_and_100() -> void:
	gut.p("Testing: Single-value setters can't leave the 0-100 range.")
	fuel_res.high_fuel_threshold = 150.0
	assert_eq(fuel_res.high_fuel_threshold, 100.0, "high must not exceed 100.")
	fuel_res.no_fuel_threshold = -5.0
	assert_eq(fuel_res.no_fuel_threshold, 0.0, "no_fuel must not go below 0.")
	fuel_res.high_fuel_threshold = 95.0
	fuel_res.no_fuel_threshold = 10.0
	assert_eq(_thresholds(), [95.0, 50.0, 30.0, 10.0], "In-range single writes must apply exactly.")
