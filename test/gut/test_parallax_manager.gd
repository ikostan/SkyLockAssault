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
	Globals.settings.current_fuel = 100.0  # Ensure scroll is not gated by flameout reset
	
	_parallax_manager = ParallaxManager.new()
	add_child_autofree(_parallax_manager)
	_parallax_manager.set_process(false)  # Only run _process explicitly from tests
	
	# NEW: Inject the test settings into the manager
	_parallax_manager.setup(Globals.settings)


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
	_parallax_manager.update_speed(250.0, 500.0)
	
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


## test_flameout_resets_offset | State Management
## :rtype: void
func test_flameout_resets_offset() -> void:
	gut.p("Testing: current_fuel <= 0 resets scroll_offset to Vector2.ZERO.")
	Globals.settings.current_fuel = 0.0
	_parallax_manager._current_speed = 100.0
	_parallax_manager.scroll_offset = Vector2(42.0, 125.5)
	_parallax_manager._process(0.5)
	assert_eq(
		_parallax_manager.scroll_offset,
		Vector2.ZERO,
		"Offset must reset to ZERO when fuel is depleted."
	)


## test_flameout_recovery_resumes_scroll | State Management
## Tests the exact recovery path of the ParallaxManager after a flameout event.
## Verifies that pushing a positive fuel value via the global Observer pattern 
## successfully flips the internal `_out_of_fuel` boolean back to false, allowing 
## the `_process` loop to seamlessly resume parallax scrolling without needing a scene reload.
## :rtype: void
func test_flameout_recovery_resumes_scroll() -> void:
	gut.p("Testing: Refueling after a flameout clears the _out_of_fuel state and resumes scrolling.")
	
	# 1. Setup initial speed and force the flameout state
	_parallax_manager.prime_speed(100.0)
	_parallax_manager._on_fuel_depleted() # Simulates the global fuel_depleted signal
	
	# Verify the background is hard-stopped (Baseline Assertion)
	_parallax_manager._process(1.0)
	assert_eq(
		_parallax_manager.scroll_offset.y, 
		0.0, 
		"PRE-CONDITION: Scroll must be completely locked to ZERO during a flameout."
	)
	
	# 2. Simulate Refueling via the Observer Pattern
	# This mimics `main_scene.gd` or `player.gd` updating the global resource.
	# It triggers the specific `elif` branch in `_on_setting_changed` to clear `_out_of_fuel`.
	_parallax_manager._on_setting_changed("current_fuel", 50.0)
	
	# 3. Simulate the next physics frame post-refuel
	_parallax_manager._process(1.0)
	
	# 4. Verify the math resumed correctly
	# Expected math: speed(100.0) * delta(1.0) * diff(1.0) * multiplier(0.8) = 80.0
	var expected_offset: float = 100.0 * 1.0 * 1.0 * 0.8
	
	assert_almost_eq(
		_parallax_manager.scroll_offset.y, 
		expected_offset, 
		0.01, 
		"POST-CONDITION: Scroll offset must resume incrementing seamlessly once fuel is restored."
	)


# ==========================================
# SAFETY & EDGE CASE TESTS
# ==========================================

## test_process_safe_with_null_globals_after_setup | Safety Constraint
## :rtype: void
func test_process_safe_with_null_globals_after_setup() -> void:
	gut.p("Testing: ParallaxManager continues using cached state and does not crash if Globals drop.")
	
	# 1. Force a null state (simulating scene transition or engine shutdown)
	Globals.settings = null
	
	_parallax_manager.prime_speed(100.0)
	_parallax_manager.scroll_offset.y = 0.0
	
	# 2. Simulate processing frame
	var delta: float = 1.0
	_parallax_manager._process(delta)
	
	# 3. Verify the math used the cached difficulty (1.0 from before_each)
	# Expected math: speed(100.0) * delta(1.0) * cached_diff(1.0) * multiplier(0.8) = 80.0
	var expected_offset: float = 100.0 * 1.0 * 1.0 * 0.8
	
	assert_almost_eq(
		_parallax_manager.scroll_offset.y, 
		expected_offset, 
		0.01, 
		"Process must use cached difficulty and avoid null instance errors when Globals are missing."
	)


## test_process_uses_default_values_without_setup | Initialization
## :rtype: void
func test_process_uses_default_values_without_setup() -> void:
	gut.p("Testing: ParallaxManager uses safe default values (difficulty 1.0) if setup() is never called.")
	
	# 1. Create a fresh manager without calling setup()
	var uninitialized_manager: ParallaxManager = ParallaxManager.new()
	add_child_autofree(uninitialized_manager)
	uninitialized_manager.set_process(false)  # Only run _process explicitly from tests
	
	uninitialized_manager.prime_speed(100.0)
	uninitialized_manager.scroll_offset.y = 0.0
	
	# 2. Simulate processing frame
	var delta: float = 1.0
	uninitialized_manager._process(delta)
	
	# 3. Verify the math used the default initialized difficulty of 1.0
	# Expected math: speed(100.0) * delta(1.0) * default_diff(1.0) * multiplier(0.8) = 80.0
	var expected_offset: float = 100.0 * 1.0 * 1.0 * 0.8
	
	assert_almost_eq(
		uninitialized_manager.scroll_offset.y, 
		expected_offset, 
		0.01, 
		"Process must use its baseline difficulty of 1.0 if dependency injection never occurs."
	)
