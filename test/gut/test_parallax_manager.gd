## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_parallax_manager.gd
##
## GUT unit tests for the ParallaxManager script.
## Validates observer pattern synchronization, scroll offset math, and fallback safety.
extends "res://addons/gut/test.gd"

var _parallax_manager: ParallaxManager
var _original_settings: GameSettingsResource


## Per-test setup: Isolates the global resource state and instantiates the manager.
## :rtype: void
func before_each() -> void:
	_original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()
	Globals.settings.difficulty = 1.0
	
	_parallax_manager = ParallaxManager.new()
	add_child_autofree(_parallax_manager)


## Post-test cleanup: Restores global state to prevent test leakage.
## :rtype: void
func after_each() -> void:
	Globals.settings = _original_settings


# ==========================================
# OBSERVER INTEGRATION TESTS
# ==========================================

## test_speed_update_from_signal | Observer Integration
## :rtype: void
func test_speed_update_from_signal() -> void:
	gut.p("Testing: ParallaxManager correctly caches speed from the player's signal.")
	
	# Simulate the Player broadcasting a new speed of 250.0
	_parallax_manager._on_player_speed_changed(250.0, 500.0)
	
	assert_eq(
		_parallax_manager._current_speed, 
		250.0, 
		"Manager must update _current_speed when signal callback is invoked."
	)


# ==========================================
# PROCESS & MATH LOGIC TESTS
# ==========================================

## test_scroll_offset_math | Process Logic
## :rtype: void
func test_scroll_offset_math() -> void:
	gut.p("Testing: Process loop correctly calculates the scroll offset increment based on difficulty.")
	
	# 1. Setup specific variables for predictable math
	Globals.settings.difficulty = 2.0
	_parallax_manager._current_speed = 100.0
	_parallax_manager.scroll_offset.y = 0.0
	
	# 2. Simulate one physics frame
	var delta: float = 0.5
	_parallax_manager._process(delta)
	
	# 3. Verify the math
	# Expected math: speed(100.0) * delta(0.5) * diff(2.0) * multiplier(0.8) = 80.0
	var expected_offset: float = 100.0 * 0.5 * 2.0 * 0.8
	
	assert_almost_eq(
		_parallax_manager.scroll_offset.y, 
		expected_offset, 
		0.01, 
		"Scroll offset must accurately reflect the delta, speed, and difficulty multiplier."
	)


## test_zero_speed_stops_scroll | State Management
## :rtype: void
func test_zero_speed_stops_scroll() -> void:
	gut.p("Testing: A speed of 0.0 results in a halted background scroll.")
	
	# 1. Setup flameout/halt state
	_parallax_manager._current_speed = 0.0
	var initial_offset: float = 125.5
	_parallax_manager.scroll_offset.y = initial_offset 
	
	# 2. Simulate processing frame
	_parallax_manager._process(1.0)
	
	# 3. Verify no movement
	assert_eq(
		_parallax_manager.scroll_offset.y, 
		initial_offset, 
		"Scroll offset must remain completely unchanged when speed is zero."
	)


# ==========================================
# SAFETY & EDGE CASE TESTS
# ==========================================

## test_process_safe_without_globals | Safety Constraint
## :rtype: void
func test_process_safe_without_globals() -> void:
	gut.p("Testing: ParallaxManager defaults to difficulty 1.0 if Globals.settings is missing.")
	
	# 1. Force a null state (simulating scene transition or engine shutdown)
	Globals.settings = null
	
	_parallax_manager._current_speed = 100.0
	_parallax_manager.scroll_offset.y = 0.0
	
	# 2. Simulate processing frame
	var delta: float = 1.0
	_parallax_manager._process(delta)
	
	# 3. Verify the math defaulted safely
	# Expected math: speed(100.0) * delta(1.0) * diff(1.0 fallback) * multiplier(0.8) = 80.0
	var expected_offset: float = 100.0 * 1.0 * 1.0 * 0.8
	
	assert_almost_eq(
		_parallax_manager.scroll_offset.y, 
		expected_offset, 
		0.01, 
		"Process must fall back to a 1.0 difficulty multiplier without throwing null instance errors."
	)
