## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_speed_resource.gd
##
## GUT unit tests for SpeedResource.
## Validates boundary enforcements, shifting limit invariants, and deterministic signal crossings.

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
