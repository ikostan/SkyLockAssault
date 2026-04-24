## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_volume_slider.gd
##
## TEST SUITE: Verifies the isolated logic of the VolumeSlider component.
## Covers initialization, programmatic update guards, and SFX interaction/rate-limiting guards.

extends "res://addons/gut/test.gd"

var _slider: VolumeSlider


func before_each() -> void:
	_slider = VolumeSlider.new()
	_slider.bus_name = AudioConstants.BUS_MASTER
	
	# FIX: Replicate the Inspector settings for a volume slider
	# Without this, HSlider defaults to step=1.0 and snaps all floats!
	_slider.max_value = 1.0
	_slider.step = 0.001
	
	# Add to the tree to ensure _ready() fires and UI state works
	add_child_autoqfree(_slider)


# ==========================================
# INITIALIZATION & PROGRAMMATIC GUARDS
# ==========================================

## WHY: Verifies that the component starts in a clean, predictable state.
## WHAT: Checks if the debounce timer is instantiated but not active.
## EXPECTED: Timer is not null and is currently stopped.
func test_initialization() -> void:
	assert_not_null(_slider.save_debounce_timer, "Debounce timer should be created on _ready")
	assert_true(_slider.save_debounce_timer.is_stopped(), "Timer should not be running immediately after initialization")


## WHY: Proves that programmatic updates (e.g., from Web Bridge or Init) are decoupled.
## WHAT: Updates the slider value using the set_value_programmatically() helper.
## EXPECTED: The value reflects the update, but the save timer remains stopped to prevent disk I/O spam.
func test_programmatic_change_blocks_debounce_timer() -> void:
	_slider.set_value_programmatically(0.5)
	
	assert_eq(_slider.value, 0.5, "Slider value should reflect the programmatic update")
	assert_true(
		_slider.save_debounce_timer.is_stopped(), 
		"Debounce timer MUST remain stopped during programmatic changes to prevent disk I/O spam"
	)


## WHY: Ensures that intentional user interaction correctly schedules a save operation.
## WHAT: Directly modifies the slider 'value' property to simulate a manual change event.
## EXPECTED: The save_debounce_timer is started to handle the persistence.
func test_manual_value_change_starts_debounce_timer() -> void:
	# Simulate a standard UI value change 
	_slider.value = 0.8
	
	assert_false(
		_slider.save_debounce_timer.is_stopped(), 
		"Debounce timer MUST start when a value is changed manually"
	)


## WHY: Confirms that non-interactive updates do not inadvertently flip interaction flags.
## WHAT: Performs a programmatic update and checks the internal _is_dragging state.
## EXPECTED: The _is_dragging flag remains false.
func test_programmatic_change_does_not_alter_drag_state() -> void:
	_slider.set_value_programmatically(0.2)
	assert_false(_slider._is_dragging, "Programmatic changes should not affect the _is_dragging state")


# ==========================================
# SFX UX GUARDS
# ==========================================

## WHY: Prevents audio spam when a slider event fires without a meaningful value change.
## WHAT: Attempts to trigger SFX logic using a value identical to the previous state.
## EXPECTED: Guard 1 blocks the playback; _last_sfx_time is not updated.
func test_sfx_guard_blocks_identical_values() -> void:
	# Setup: Set an initial value and simulate an interaction
	_slider.value = 0.5
	_slider._previous_value = 0.5
	_slider._is_dragging = true
	var initial_sfx_time: int = _slider._last_sfx_time
	
	# Act: Try to trigger SFX with the exact same value
	_slider._handle_slider_sfx(0.5)
	
	# Assert: The time shouldn't update because Guard 1 blocked it
	assert_eq(_slider._last_sfx_time, initial_sfx_time, "SFX must be blocked if the value hasn't actually changed.")


## WHY: Restricts SFX playback strictly to active user engagement.
## WHAT: Changes the value while the slider is neither being dragged nor focused.
## EXPECTED: Guard 2 blocks playback; _last_sfx_time remains at its initial value.
func test_sfx_guard_blocks_no_interaction() -> void:
	# Setup: New value, but NO interaction (not dragging, no focus)
	_slider.value = 0.5
	_slider._previous_value = 0.2
	_slider._is_dragging = false
	_slider.release_focus()
	var initial_sfx_time: int = _slider._last_sfx_time
	
	# Act: Try to trigger SFX
	_slider._handle_slider_sfx(0.5)
	
	# Assert: The time shouldn't update because Guard 2 blocked it
	assert_eq(_slider._last_sfx_time, initial_sfx_time, "SFX must be blocked if the user isn't actively interacting.")


## WHY: Validates the "Happy Path" for manual interaction audio feedback.
## WHAT: Simulates a manual drag interaction accompanied by a value delta.
## EXPECTED: All guards pass; _last_sfx_time is updated and _previous_value is committed.
func test_sfx_guard_allows_valid_interaction() -> void:
	# Setup: Different value AND active interaction
	_slider._previous_value = 0.2
	_slider._is_dragging = true
	_slider._last_sfx_time = 0 # Ensure no cooldown interference
	
	# Act: Trigger SFX
	_slider._handle_slider_sfx(0.5)
	
	# Assert: All guards passed, state was committed
	assert_ne(_slider._last_sfx_time, 0, "SFX time should update when a valid, manual value delta occurs.")
	assert_eq(_slider._previous_value, 0.5, "Previous value should be updated after successful SFX trigger.")


## WHY: Protects the user from ear-piercing noise during rapid mouse movements.
## WHAT: Attempts to trigger a second SFX trigger immediately after a successful one.
## EXPECTED: Guard 3 (Rate Limiter) blocks the second trigger based on SFX_COOLDOWN_MS.
func test_sfx_guard_enforces_rate_limiting() -> void:
	# Setup: Valid interaction, but we JUST played a sound
	_slider._previous_value = 0.2
	_slider._is_dragging = true
	
	# Force the last sfx time to be right now
	var current_time: int = Time.get_ticks_msec()
	_slider._last_sfx_time = current_time
	
	# Act: Try to trigger another sound immediately with a new value
	_slider._handle_slider_sfx(0.6)
	
	# Assert: It should have been blocked by the SFX_COOLDOWN_MS guard
	assert_eq(_slider._last_sfx_time, current_time, "Rate limiter MUST block sounds requested faster than the cooldown window.")
