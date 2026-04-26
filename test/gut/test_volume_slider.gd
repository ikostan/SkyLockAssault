## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_volume_slider.gd
##
## TEST SUITE: Verifies the isolated logic of the VolumeSlider component.
## Covers initialization, programmatic update guards, and SFX interaction/rate-limiting guards.

extends "res://addons/gut/test.gd"

# ==========================================
# MOCKS
# ==========================================

class MockAudioManager extends Node:
	var played_sfx: Array[String] = []
	
	func play_sfx(sfx_name: String, _bus_name: String = "", _pitch_scale: float = 1.0, _volume_db: float = 0.0) -> void:
		played_sfx.append(sfx_name)

# ==========================================
# TESTS
# ==========================================

var _slider: VolumeSlider

# Snapshot variables for state isolation
var _orig_config_path: String
var _orig_master_volume: float
const _TEST_CONFIG_PATH: String = "user://test_volume_slider.cfg"


func before_each() -> void:
	# Snapshot global state to prevent cross-suite leakage
	_orig_config_path = AudioManager.current_config_path
	_orig_master_volume = AudioManager.master_volume
	
	# Isolate the config path so any rogue debounce saves hit a throwaway file
	AudioManager.current_config_path = _TEST_CONFIG_PATH

	_slider = VolumeSlider.new()
	_slider.bus_name = AudioConstants.BUS_MASTER
	
	# FIX: Replicate the Inspector settings for a volume slider
	# Without this, HSlider defaults to step=1.0 and snaps all floats!
	_slider.max_value = 1.0
	_slider.step = 0.001
	
	# Add to the tree to ensure _ready() fires and UI state works
	add_child_autoqfree(_slider)


func after_each() -> void:
	# Restore global state
	AudioManager.current_config_path = _orig_config_path
	AudioManager.master_volume = _orig_master_volume
	
	# Clean up any test config generated if the debounce timer fired during CI lag
	if FileAccess.file_exists(_TEST_CONFIG_PATH):
		DirAccess.remove_absolute(_TEST_CONFIG_PATH)


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
	assert_false(_slider.is_user_dragging(), "Programmatic changes should not affect the _is_dragging state")


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
	var initial_sfx_time: int = _slider.get_last_sfx_time()
	
	# Act: Try to trigger the full pipeline with the exact same value
	_slider._on_value_changed(0.5)
	
	# Assert: The time shouldn't update because the early return blocked it
	assert_eq(_slider.get_last_sfx_time(), initial_sfx_time, "SFX must be blocked if the value hasn't actually changed.")


## WHY: Validates the "Happy Path" for manual interaction audio feedback.
## WHAT: Simulates a manual drag interaction accompanied by a value delta.
## EXPECTED: All guards pass; _last_sfx_time is updated and _previous_value is committed.
func test_sfx_guard_allows_valid_interaction() -> void:
	# 1. Setup the manual mock to block real audio I/O
	var mock_am: MockAudioManager = MockAudioManager.new()
	
	# Swap out the real AudioManager in the scene tree
	var root := get_tree().root
	var real_am := root.get_node("AudioManager")
	root.remove_child(real_am)
	root.add_child(mock_am)
	mock_am.name = "AudioManager"
	
	# 2. Setup slider interaction variables
	_slider._previous_value = 0.2
	_slider._is_dragging = true
	_slider._last_sfx_time = 0 # Ensure no cooldown interference
	
	# 3. Act: Trigger the full pipeline
	_slider._on_value_changed(0.5)
	
	# 4. Assert local state
	assert_ne(_slider.get_last_sfx_time(), 0, "SFX time should update when a valid, manual value delta occurs.")
	assert_eq(_slider.get_previous_value(), 0.5, "Previous value should be updated after successful SFX trigger.")
	
	# 5. Assert the mock received the play_sfx call, proving the guards passed
	assert_eq(mock_am.played_sfx.size(), 1, "play_sfx should be called exactly once.")
	assert_eq(mock_am.played_sfx[0], AudioConstants.SFX_SLIDER, "The correct SFX constant should be played.")
	
	# 6. Cleanup: Safely restore the original AudioManager
	root.remove_child(mock_am)
	root.add_child(real_am)
	mock_am.free()
	# Setup: Set an initial value and simulate an interaction
	_slider.value = 0.5
	_slider._previous_value = 0.5
	_slider._is_dragging = true
	var initial_sfx_time: int = _slider.get_last_sfx_time()
	
	# Act: Try to trigger SFX with the exact same value
	_slider._handle_slider_sfx(0.5)
	
	# Assert: The time shouldn't update because Guard 1 blocked it
	assert_eq(_slider.get_last_sfx_time(), initial_sfx_time, "SFX must be blocked if the value hasn't actually changed.")


## WHY: Restricts SFX playback strictly to active user engagement.
## WHAT: Changes the value while the slider is neither being dragged nor focused.
## EXPECTED: Guard 2 blocks playback; _last_sfx_time remains at its initial value.
func test_sfx_guard_blocks_no_interaction() -> void:
	# Setup: New value, but NO interaction (not dragging, no focus)
	_slider.value = 0.5
	_slider._previous_value = 0.2
	_slider._is_dragging = false
	_slider.release_focus()
	var initial_sfx_time: int = _slider.get_last_sfx_time()
	
	# Act: Try to trigger SFX
	_slider._handle_slider_sfx(0.5)
	
	# Assert: The time shouldn't update because Guard 2 blocked it
	assert_eq(_slider.get_last_sfx_time(), initial_sfx_time, "SFX must be blocked if the user isn't actively interacting.")


## WHY: Protects the user from ear-piercing noise during rapid mouse movements.
## WHAT: Attempts to trigger a second SFX trigger immediately after a successful one.
## EXPECTED: Guard 3 (Rate Limiter) blocks the second trigger based on SFX_COOLDOWN_MS.
func test_sfx_guard_enforces_rate_limiting() -> void:
	# Setup: Valid interaction, but we JUST played a sound
	_slider._previous_value = 0.2
	_slider._is_dragging = true
	
	# Force the last sfx time into the future to guarantee a deterministic block
	# regardless of CI thread pauses or garbage collection spikes.
	var future_time: int = Time.get_ticks_msec() + _slider.SFX_COOLDOWN_MS + 1000
	_slider._last_sfx_time = future_time
	
	# Act: Try to trigger another sound immediately with a new value
	_slider._handle_slider_sfx(0.6)
	
	# Assert: It should have been blocked by the SFX_COOLDOWN_MS guard
	assert_eq(
		_slider.get_last_sfx_time(), 
		future_time, 
		"Rate limiter MUST block sounds requested faster than the cooldown window."
	)


# ==========================================
# INVALID BUS GUARDS (Bug Risk)
# ==========================================

## WHY: Ensures the game doesn't crash and fully locks out inputs if an audio bus name is typoed.
## WHAT: Initializes a new slider with a fake bus name.
## EXPECTED: The slider detects the -1 index, logs the error to Globals, disables itself, drops focus/mouse handling, and aborts safely.
func test_invalid_bus_disables_slider() -> void:
	var bad_slider: VolumeSlider = VolumeSlider.new()
	bad_slider.bus_name = "NonExistentBus123"
	
	# Add to tree to trigger _ready()
	add_child_autoqfree(bad_slider)
	
	assert_false(bad_slider.editable, "Slider must disable itself if the audio bus is invalid.")
	assert_eq(bad_slider.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Slider must ignore mouse events if invalid.")
	assert_eq(bad_slider.focus_mode, Control.FOCUS_NONE, "Slider must drop keyboard/controller focus if invalid.")
	assert_null(bad_slider.save_debounce_timer, "Initialization should abort early, leaving the timer null.")


## WHY: Prevents external scripts from forcing updates on a broken slider.
## WHAT: Attempts to programmatically set the value of an invalid slider.
## EXPECTED: The guard clause blocks the update, leaving state trackers at their default values.
func test_invalid_bus_blocks_programmatic_updates() -> void:
	var bad_slider: VolumeSlider = VolumeSlider.new()
	bad_slider.bus_name = "AnotherFakeBus"
	add_child_autoqfree(bad_slider)
	
	# Act: Try to force a value update
	bad_slider.set_value_programmatically(0.8)
	
	# Assert: The values should remain at their uninitialized defaults
	assert_eq(bad_slider._previous_value, -1.0, "The delta tracker should not update for an invalid bus.")
	assert_eq(bad_slider.value, 0.0, "The visual slider value should not update for an invalid bus.")


## WHY: Guarantees no SFX or volume updates can occur from user interaction on a dead slider.
## WHAT: Verifies the signal connections are bypassed during a failed initialization.
## EXPECTED: value_changed and gui_input signals are never connected to their respective handlers.
func test_invalid_bus_prevents_signal_connections() -> void:
	var bad_slider: VolumeSlider = VolumeSlider.new()
	bad_slider.bus_name = "GhostBus"
	add_child_autoqfree(bad_slider)
	
	assert_false(bad_slider.value_changed.is_connected(bad_slider._on_value_changed), "Value changed signal must remain disconnected.")
	assert_false(bad_slider.gui_input.is_connected(bad_slider._on_gui_input), "GUI input signal must remain disconnected.")
