## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_parallax_manager.gd
##
## GUT unit tests for the ParallaxManager script.
## Validates observer pattern synchronization, scroll offset math, and fallback safety.
extends "res://addons/gut/test.gd"

var _parallax_manager: ParallaxManager
var _speed: SpeedResource
var _fuel: FuelResource
var _settings: GameSettingsResource


## Per-test setup: Instantiates isolated resources and the manager.
## :rtype: void
func before_each() -> void:
	# Isolate Speed
	_speed = SpeedResource.new()
	_speed.min_speed = 0.0
	_speed.max_speed = 1000.0
	_speed.current_speed = 100.0
	
	# Isolate Fuel
	_fuel = FuelResource.new()
	_fuel.max_fuel = 100.0
	_fuel.current_fuel = 100.0
	
	# Isolate Settings
	_settings = GameSettingsResource.new()
	_settings.difficulty = 1.0
	
	_parallax_manager = ParallaxManager.new()
	add_child_autofree(_parallax_manager)
	_parallax_manager.set_process(false)  # Only run _process explicitly from tests
	
	_parallax_manager.setup(_speed, _fuel, _settings)


# ==========================================
# OBSERVER INTEGRATION TESTS
# ==========================================

## test_speed_update_from_signal | Observer Integration
## :rtype: void
func test_speed_update_from_signal() -> void:
	gut.p("Testing: ParallaxManager correctly caches speed from the SpeedResource signal.")
	
	_speed.current_speed = 250.0
	
	assert_eq(
		_parallax_manager._current_speed, 
		250.0, 
		"Manager must update _current_speed when SpeedResource is mutated."
	)


## test_difficulty_updates_via_settings_resource_signal | Observer Integration
## :rtype: void
func test_difficulty_updates_via_settings_resource_signal() -> void:
	gut.p("Testing: ParallaxManager dynamically updates its difficulty multiplier via GameSettingsResource.")
	
	# Use 2.0 as it falls within the valid clamp(0.5, 2.0) bounds of GameSettingsResource
	_settings.difficulty = 2.0
	assert_eq(_parallax_manager._difficulty, 2.0, "Manager must update _difficulty when GameSettingsResource is mutated.")
	
	_speed.current_speed = 100.0
	_parallax_manager.scroll_offset.y = 0.0
	_parallax_manager._process(1.0)
	
	var expected_offset: float = 100.0 * 1.0 * 2.0 * 0.8
	assert_almost_eq(
		_parallax_manager.scroll_offset.y, 
		expected_offset, 
		0.01, 
		"Scroll offset math must use the newly emitted difficulty multiplier."
	)


# ==========================================
# PROCESS & MATH LOGIC TESTS
# ==========================================

## test_scroll_offset_math | Process Logic
## :rtype: void
func test_scroll_offset_math() -> void:
	gut.p("Testing: Process loop correctly calculates the scroll offset increment based on difficulty.")
	
	_settings.difficulty = 2.0
	_speed.current_speed = 100.0
	_parallax_manager.scroll_offset.y = 0.0
	
	var delta: float = 0.5
	_parallax_manager._process(delta)
	
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
	
	_speed.current_speed = 0.0
	var initial_offset: float = 125.5
	_parallax_manager.scroll_offset.y = initial_offset 
	
	_parallax_manager._process(1.0)
	
	assert_eq(
		_parallax_manager.scroll_offset.y, 
		initial_offset, 
		"Scroll offset must remain completely unchanged when speed is zero."
	)


## test_flameout_resets_offset | State Management
## :rtype: void
func test_flameout_resets_offset() -> void:
	gut.p("Testing: current_fuel <= 0 resets scroll_offset to Vector2.ZERO.")
	_speed.current_speed = 100.0
	_parallax_manager.scroll_offset = Vector2(42.0, 125.5)
	
	_fuel.current_fuel = 0.0
	_parallax_manager._process(0.5)
	
	assert_eq(
		_parallax_manager.scroll_offset,
		Vector2.ZERO,
		"Offset must reset to ZERO when fuel is depleted."
	)


## test_flameout_recovery_resumes_scroll | State Management
## :rtype: void
func test_flameout_recovery_resumes_scroll() -> void:
	gut.p("Testing: Refueling after a flameout clears the _out_of_fuel state and resumes scrolling.")
	
	_speed.current_speed = 100.0
	_fuel.current_fuel = 0.0
	
	_parallax_manager._process(1.0)
	assert_eq(
		_parallax_manager.scroll_offset.y, 
		0.0, 
		"PRE-CONDITION: Scroll must be completely locked to ZERO during a flameout."
	)
	
	_fuel.current_fuel = 50.0
	_parallax_manager._process(1.0)
	
	# Expected math: speed(100.0) * delta(1.0) * diff(1.0) * multiplier(0.8) = 80.0
	var expected_offset: float = 100.0 * 1.0 * 1.0 * 0.8
	
	assert_almost_eq(
		_parallax_manager.scroll_offset.y, 
		expected_offset, 
		0.01, 
		"POST-CONDITION: Scroll offset must resume incrementing seamlessly once fuel is restored."
	)


# ==========================================
# ISOLATION & LIFECYCLE TESTS
# ==========================================

## test_setup_initial_state_synchronization | Initialization
## :rtype: void
func test_setup_initial_state_synchronization() -> void:
	gut.p("Testing: Manager instantly synchronizes internal variables during setup().")
	
	var s = SpeedResource.new()
	s.min_speed = 0.0
	s.max_speed = 1000.0
	s.current_speed = 350.0
	
	var f = FuelResource.new()
	f.max_fuel = 100.0
	f.current_fuel = 0.0
	
	var st = GameSettingsResource.new()
	st.difficulty = 1.5
	
	var pm = ParallaxManager.new()
	pm.setup(s, f, st)
	
	assert_eq(pm._current_speed, 350.0, "Manager must pull initial speed.")
	assert_eq(pm._out_of_fuel, true, "Manager must pull initial fuel state.")
	assert_eq(pm._difficulty, 1.5, "Manager must pull initial difficulty.")
	pm.free()


## test_resource_replacement_disconnects_old_signals | Isolation
## :rtype: void
func test_resource_replacement_disconnects_old_signals() -> void:
	gut.p("Testing: Injecting new resources correctly severs connections to the old ones.")
	
	var speedA = SpeedResource.new()
	speedA.min_speed = 0.0
	speedA.max_speed = 500.0
	speedA.current_speed = 100.0
	_parallax_manager.setup(speedA, _fuel, _settings)
	
	var speedB = SpeedResource.new()
	speedB.min_speed = 0.0
	speedB.max_speed = 500.0
	speedB.current_speed = 200.0
	_parallax_manager.setup(speedB, _fuel, _settings)
	
	speedA.current_speed = 300.0
	assert_eq(
		_parallax_manager._current_speed, 
		200.0, 
		"Manager must ignore signals from previously injected resources."
	)
	
	speedB.current_speed = 400.0
	assert_eq(
		_parallax_manager._current_speed, 
		400.0, 
		"Manager must correctly observe the newly injected resource."
	)


## test_setup_idempotency_prevents_duplicate_connections | Safety Constraint
## :rtype: void
func test_setup_idempotency_prevents_duplicate_connections() -> void:
	gut.p("Testing: Running setup() multiple times is safe and prevents duplicate connections.")
	
	# Godot will throw an internal console error if we attempt to disconnect 
	# a non-connected signal or double-connect.
	_parallax_manager.setup(_speed, _fuel, _settings)
	_parallax_manager.setup(_speed, _fuel, _settings)
	_parallax_manager.setup(_speed, _fuel, _settings)
	
	_speed.current_speed = 123.0
	
	assert_eq(
		_parallax_manager._current_speed, 
		123.0, 
		"Signal processing must still function normally after idempotent setups."
	)


## test_setup_handles_null_resources_gracefully | Safety Constraint
## :rtype: void
func test_setup_handles_null_resources_gracefully() -> void:
	gut.p("Testing: ParallaxManager survives null resource injection without crashing.")
	
	var pm = ParallaxManager.new()
	pm._current_speed = 42.0
	pm._difficulty = 3.0
	pm._out_of_fuel = true
	
	pm.setup(null, null, null)
	
	assert_eq(pm._current_speed, 42.0, "Manager should retain previous state if speed is null.")
	assert_eq(pm._difficulty, 3.0, "Manager should retain previous state if settings are null.")
	assert_eq(pm._out_of_fuel, true, "Manager should retain previous state if fuel is null.")
	pm.free()


## test_process_uses_default_values_without_setup | Initialization
## :rtype: void
func test_process_uses_default_values_without_setup() -> void:
	gut.p("Testing: ParallaxManager uses safe default values (difficulty 1.0) if setup() is never called.")
	
	var uninitialized_manager: ParallaxManager = ParallaxManager.new()
	add_child_autofree(uninitialized_manager)
	uninitialized_manager.set_process(false)
	
	uninitialized_manager._current_speed = 100.0
	uninitialized_manager.scroll_offset.y = 0.0
	uninitialized_manager._process(1.0)
	
	# Expected math: speed(100.0) * delta(1.0) * default_diff(1.0) * multiplier(0.8) = 80.0
	var expected_offset: float = 100.0 * 1.0 * 1.0 * 0.8
	
	assert_almost_eq(
		uninitialized_manager.scroll_offset.y, 
		expected_offset, 
		0.01, 
		"Process must use its baseline difficulty of 1.0 if dependency injection never occurs."
	)


func test_fuel_depletion_resets_offset_before_next_frame() -> void:
	_parallax_manager.scroll_offset = Vector2(12.0, 240.0)

	_fuel.current_fuel = 0.0

	assert_eq(_parallax_manager.scroll_offset, Vector2.ZERO, "Depletion must stop scrolling immediately.")
	_parallax_manager.scroll_offset = Vector2(5.0, 10.0)
	_parallax_manager._process(0.0)
	assert_eq(_parallax_manager.scroll_offset, Vector2.ZERO, "The background must stay stopped while fuel is empty.")


func test_replacing_fuel_ignores_old_depletion_and_refueling() -> void:
	var replacement_fuel: FuelResource = FuelResource.new()
	replacement_fuel.current_fuel = 0.0
	_parallax_manager.setup(_speed, replacement_fuel, _settings)

	assert_true(_parallax_manager._out_of_fuel, "Replacement fuel must determine the initial state.")
	assert_false(_fuel.fuel_changed.is_connected(_parallax_manager._on_fuel_changed))
	assert_false(_fuel.fuel_depleted.is_connected(_parallax_manager._on_fuel_depleted))
	_fuel.current_fuel = 0.0
	_fuel.current_fuel = 50.0
	assert_true(_parallax_manager._out_of_fuel, "Old fuel changes must not resume scrolling.")

	replacement_fuel.current_fuel = 10.0
	assert_false(_parallax_manager._out_of_fuel, "Refueling the observed resource must resume scrolling.")
	_parallax_manager.scroll_offset = Vector2(4.0, 80.0)
	replacement_fuel.current_fuel = 0.0
	assert_eq(_parallax_manager.scroll_offset, Vector2.ZERO, "Only the observed fuel may trigger a flameout.")


func test_replacing_settings_ignores_old_difficulty_and_fuel_settings() -> void:
	var old_settings: GameSettingsResource = _settings
	var replacement_settings: GameSettingsResource = GameSettingsResource.new()
	replacement_settings.difficulty = 1.5
	_parallax_manager.setup(_speed, _fuel, replacement_settings)

	assert_false(old_settings.setting_changed.is_connected(_parallax_manager._on_setting_changed))
	assert_eq(_parallax_manager._difficulty, 1.5, "Setup must cache the replacement difficulty.")
	old_settings.difficulty = 2.0
	old_settings.current_fuel = 0.0
	assert_eq(_parallax_manager._difficulty, 1.5, "Old settings must not change the multiplier.")
	assert_false(_parallax_manager._out_of_fuel, "Settings fuel must not drive the background.")

	replacement_settings.difficulty = 0.5
	_parallax_manager.scroll_offset = Vector2.ZERO
	_parallax_manager._process(1.0)
	assert_almost_eq(_parallax_manager.scroll_offset.y, 40.0, 0.01, "Only the observed difficulty must affect scrolling.")


func test_null_setup_disconnects_observers_until_resources_are_reinjected() -> void:
	_parallax_manager.setup(null, null, null)

	assert_false(_speed.speed_updated.is_connected(_parallax_manager._on_speed_updated))
	assert_false(_fuel.fuel_changed.is_connected(_parallax_manager._on_fuel_changed))
	assert_false(_fuel.fuel_depleted.is_connected(_parallax_manager._on_fuel_depleted))
	assert_false(_settings.setting_changed.is_connected(_parallax_manager._on_setting_changed))
	_speed.current_speed = 300.0
	_fuel.current_fuel = 0.0
	_settings.difficulty = 2.0
	assert_eq(_parallax_manager._current_speed, 100.0, "Detached speed must not update the cache.")
	assert_false(_parallax_manager._out_of_fuel, "Detached fuel must not trigger flameout.")
	assert_eq(_parallax_manager._difficulty, 1.0, "Detached settings must not update the cache.")

	_parallax_manager.setup(_speed, _fuel, _settings)
	assert_eq(_parallax_manager._current_speed, 300.0, "Reinjection must read the current speed.")
	assert_true(_parallax_manager._out_of_fuel, "Reinjection must read the current fuel.")
	assert_eq(_parallax_manager._difficulty, 2.0, "Reinjection must read the current difficulty.")


func test_replacing_only_speed_keeps_other_observers_active() -> void:
	var replacement_speed: SpeedResource = SpeedResource.new()
	replacement_speed.min_speed = 0.0
	replacement_speed.current_speed = 0.0
	_parallax_manager.setup(replacement_speed, _fuel, _settings)

	assert_eq(_parallax_manager._current_speed, 0.0, "A stationary replacement must be cached immediately.")
	_speed.current_speed = 300.0
	assert_eq(_parallax_manager._current_speed, 0.0, "The replaced speed must not be observed.")
	_fuel.current_fuel = 0.0
	assert_true(_parallax_manager._out_of_fuel, "Unchanged fuel must remain observed.")
	_fuel.current_fuel = 20.0
	_settings.difficulty = 2.0
	replacement_speed.current_speed = 150.0
	_parallax_manager._process(1.0)
	assert_almost_eq(_parallax_manager.scroll_offset.y, 240.0, 0.01, "Unchanged settings and replacement speed must drive scrolling.")
