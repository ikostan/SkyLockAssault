## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_speed_resource.gd
##
## GUT unit tests for SpeedResource.
## Validates boundary enforcements, shifting limit invariants, deterministic signal crossings,
## and setting both speed limits as a pair (#1148).

extends "res://addons/gut/test.gd"

var speed_res: SpeedResource

func before_each() -> void:
	speed_res = SpeedResource.new()

func after_each() -> void:
	pass


# ==========================================
# BOUNDARY & INVARIANT TESTS
# ==========================================

func test_speed_boundaries_cannot_invert() -> void:
	gut.p("Testing: min_speed and max_speed preserve the min <= max invariant.")
	speed_res.max_speed = 500.0
	speed_res.min_speed = 100.0
	
	# Attempt to push min above max
	speed_res.min_speed = 800.0
	assert_eq(speed_res.min_speed, 500.0, "min_speed must clamp to max_speed.")
	
	# Attempt to push max below min
	speed_res.max_speed = 50.0
	assert_eq(speed_res.max_speed, 500.0, "max_speed must clamp to the current min_speed.")


func test_boundary_shift_clamps_current_speed() -> void:
	gut.p("Testing: Shifting boundaries forces current_speed to remain within [min, max].")
	speed_res.max_speed = 500.0
	speed_res.min_speed = 100.0
	speed_res.current_speed = 300.0
	
	watch_signals(speed_res)
	
	# Shift max boundary down
	speed_res.max_speed = 200.0
	assert_eq(speed_res.current_speed, 200.0, "current_speed must shrink to fit new max_speed.")
	# FIX: Reverted to single brackets [200.0]
	assert_signal_emitted_with_parameters(speed_res, "speed_updated", [200.0])
	
	# Reset max boundary to give min_speed room to shift upwards
	speed_res.max_speed = 500.0 
	
	# Shift min boundary up (current_speed is currently 200.0)
	speed_res.min_speed = 250.0
	assert_eq(speed_res.current_speed, 250.0, "current_speed must increase to fit new min_speed.")
	# FIX: Reverted to single brackets [250.0]
	assert_signal_emitted_with_parameters(speed_res, "speed_updated", [250.0])


# ==========================================
# SIGNAL CROSSING SEMANTICS
# ==========================================

func test_speed_updated_emits_only_on_effective_change() -> void:
	gut.p("Testing: speed_updated strictly emits only on effective state change.")
	speed_res.max_speed = 500.0
	speed_res.min_speed = 100.0
	speed_res.current_speed = 300.0
	
	watch_signals(speed_res)
	
	# Exact reassignment
	speed_res.current_speed = 300.0
	assert_signal_emit_count(speed_res, "speed_updated", 0, "Reassigning the same value must not emit.")
	
	# Out of bounds reassignment resulting in the same clamped value
	speed_res.current_speed = 500.0
	# The above line caused 1 valid emission.
	
	speed_res.current_speed = 800.0 # Clamps to 500.0
	assert_signal_emit_count(speed_res, "speed_updated", 1, "Value clamping to unchanged effective state must not emit again.")


func test_speed_low_crossing_semantics() -> void:
	gut.p("Testing: speed_low strictly emits only when crossing the dynamic threshold downward.")
	speed_res.max_speed = 500.0
	speed_res.min_speed = 100.0
	speed_res.low_yellow_fraction = 0.25 # Threshold is 200.0
	
	speed_res.current_speed = 300.0
	watch_signals(speed_res)
	
	# 1. Cross the threshold
	speed_res.current_speed = 150.0
	assert_signal_emit_count(speed_res, "speed_low", 1, "Crossing below threshold must emit speed_low.")
	
	# 2. Mutate while already below threshold
	speed_res.current_speed = 120.0
	assert_signal_emit_count(speed_res, "speed_low", 1, "Mutating below threshold must not re-emit.")
	
	# 3. Climb back out and re-cross
	speed_res.current_speed = 300.0
	assert_signal_emit_count(speed_res, "speed_low", 1, "Climbing above threshold must not emit.")
	
	speed_res.current_speed = 200.0 # Exactly hitting the threshold
	assert_signal_emit_count(speed_res, "speed_low", 2, "Hitting threshold exactly from above must emit.")


func test_speed_maxed_crossing_semantics() -> void:
	gut.p("Testing: speed_maxed strictly emits only when crossing to exactly max_speed.")
	speed_res.max_speed = 500.0
	speed_res.min_speed = 100.0
	speed_res.current_speed = 300.0
	
	watch_signals(speed_res)
	
	# 1. Hit max speed
	speed_res.current_speed = 600.0 # Clamps to 500.0
	assert_signal_emit_count(speed_res, "speed_maxed", 1, "Hitting max_speed must emit.")
	
	# 2. Stay at max speed
	speed_res.current_speed = 800.0 # Clamps to 500.0
	assert_signal_emit_count(speed_res, "speed_maxed", 1, "Staying at max_speed must not re-emit.")


func test_speed_boundaries_cannot_be_negative() -> void:
	gut.p("Testing: min_speed and max_speed strictly enforce non-negative limits.")
	speed_res.max_speed = 500.0
	speed_res.min_speed = 100.0

	# Attempt to push min_speed below 0
	speed_res.min_speed = -50.0
	assert_eq(speed_res.min_speed, 0.0, "min_speed must clamp to a hard floor of 0.0.")

	# Attempt to push max_speed below 1.0 (after dropping min_speed to give it room)
	speed_res.min_speed = 0.0
	speed_res.max_speed = -10.0
	assert_eq(speed_res.max_speed, 1.0, "max_speed must clamp to a hard floor of 1.0.")


# ==========================================
# SPEED LIMITS AS A PAIR (#1148)
# ==========================================

## test_set_speed_limits_raises_both_exactly | Speed Limits
## The #1148 bug: one at a time, min 900 clamps to the old max 713 before max is raised.
func test_set_speed_limits_raises_both_exactly() -> void:
	gut.p("Testing: Raising both limits applies exactly from the defaults.")
	assert_true(speed_res.set_speed_limits(900.0, 1000.0), "A valid raised pair must apply.")
	assert_eq(speed_res.min_speed, 900.0, "min_speed must apply as written.")
	assert_eq(speed_res.max_speed, 1000.0, "max_speed must apply as written.")


## test_set_speed_limits_lowers_both_exactly | Speed Limits
func test_set_speed_limits_lowers_both_exactly() -> void:
	gut.p("Testing: Lowering both limits applies exactly, after raising them.")
	assert_true(speed_res.set_speed_limits(900.0, 1000.0))
	assert_true(speed_res.set_speed_limits(10.0, 50.0), "A valid lowered pair must apply.")
	assert_eq(speed_res.min_speed, 10.0, "min_speed must apply as written.")
	assert_eq(speed_res.max_speed, 50.0, "max_speed must apply as written.")


## test_set_speed_limits_accepts_the_bounds | Speed Limits
func test_set_speed_limits_accepts_the_bounds() -> void:
	gut.p("Testing: min 0, max 1, and min == max are allowed.")
	assert_true(speed_res.set_speed_limits(0.0, 1.0), "min 0 with max 1 must apply.")
	assert_eq([speed_res.min_speed, speed_res.max_speed], [0.0, 1.0])
	assert_true(speed_res.set_speed_limits(500.0, 500.0), "Equal limits must apply.")
	assert_eq([speed_res.min_speed, speed_res.max_speed], [500.0, 500.0])


## test_set_speed_limits_clamps_current_speed_up | Speed Limits
func test_set_speed_limits_clamps_current_speed_up() -> void:
	gut.p("Testing: current_speed rises into a raised range.")
	speed_res.current_speed = 250.0
	watch_signals(speed_res)
	
	assert_true(speed_res.set_speed_limits(900.0, 1000.0))
	
	assert_eq(speed_res.current_speed, 900.0, "current_speed must rise to the new min_speed.")
	assert_signal_emit_count(speed_res, "speed_updated", 1, "The clamp must notify once.")
	assert_signal_emitted_with_parameters(speed_res, "speed_updated", [900.0])


## test_set_speed_limits_clamps_current_speed_down | Speed Limits
func test_set_speed_limits_clamps_current_speed_down() -> void:
	gut.p("Testing: current_speed drops into a lowered range.")
	speed_res.current_speed = 600.0
	
	assert_true(speed_res.set_speed_limits(10.0, 50.0))
	
	assert_eq(speed_res.current_speed, 50.0, "current_speed must drop to the new max_speed.")


## test_set_speed_limits_keeps_current_speed_inside_range | Speed Limits
func test_set_speed_limits_keeps_current_speed_inside_range() -> void:
	gut.p("Testing: current_speed already inside the new range is left alone.")
	speed_res.current_speed = 300.0
	watch_signals(speed_res)
	
	assert_true(speed_res.set_speed_limits(200.0, 400.0))
	
	assert_eq(speed_res.current_speed, 300.0, "current_speed must stay where it was.")
	assert_signal_not_emitted(speed_res, "speed_updated", "An unchanged speed must not notify.")


## test_set_speed_limits_rejects_invalid_pairs | Speed Limits
## Each invalid pair must return false, warn, and leave both limits and the speed unchanged.
func test_set_speed_limits_rejects_invalid_pairs(
	params: Array = use_parameters([
		["min above max", [900.0, 800.0]],
		["negative min", [-1.0, 500.0]],
		["max below 1", [0.0, 0.5]],
		["NaN min", [NAN, 500.0]],
		["NaN max", [100.0, NAN]],
		["infinite max", [100.0, INF]],
	])
) -> void:
	var label: String = params[0]
	var pair: Array = params[1]
	gut.p("Testing: set_speed_limits() rejects a pair with %s." % label)
	# Start from a custom pair, so "unchanged" can't pass by matching the defaults.
	assert_true(speed_res.set_speed_limits(120.0, 640.0))
	speed_res.current_speed = 300.0
	
	var applied: bool = speed_res.set_speed_limits(pair[0], pair[1])
	
	assert_false(applied, "A pair with %s must be rejected." % label)
	assert_push_warning("SpeedResource: rejected speed limits")
	assert_eq([speed_res.min_speed, speed_res.max_speed], [120.0, 640.0], "Limits must not change.")
	assert_eq(speed_res.current_speed, 300.0, "A rejected pair must not move current_speed.")


## test_single_limit_setters_still_clamp | Speed Limits
## Inspector edits and the zero-fuel path still set one limit at a time.
func test_single_limit_setters_still_clamp() -> void:
	gut.p("Testing: min_speed and max_speed setters keep clamping after the backing-field change.")
	speed_res.min_speed = 5000.0
	assert_eq(speed_res.min_speed, 713.0, "min_speed must clamp to max_speed.")
	speed_res.min_speed = 95.0
	speed_res.max_speed = 0.0
	assert_eq(speed_res.max_speed, 95.0, "max_speed must not drop below min_speed.")
	speed_res.min_speed = 0.0
	speed_res.max_speed = 0.0
	assert_eq(speed_res.max_speed, 1.0, "max_speed must not drop below 1.")
