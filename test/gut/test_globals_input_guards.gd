## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_globals_input_guards.gd
##
## Integration test suite validating that global ui_accept input intercepts
## are correctly bypassed for specific interactive UI controls to eliminate
## duplicate sound triggers and unintended activation noises.

## ==========================================================================
## ARCHITECTURAL CONTRACT
## ==========================================================================
## These tests verify the boundary between the global input interceptor 
## and individual interactive Controls that manage their own audio streams.
## Any Control responsible for triggering its own local confirmation or click 
## sounds must be bypassed by the global ui_accept handler to prevent 
## duplicate audio playback ("double-dipping").

extends "res://addons/gut/test.gd"

var _original_options_open: bool


func before_each() -> void:
	# Snapshot state and force active menu context for predictable test execution
	_original_options_open = Globals.options_open
	Globals.options_open = true
	
	# Purge any running streams from the shared singleton pool
	AudioManager.stop_all_sfx()
	if AudioManager.has_method("cleanup_for_test"):
		AudioManager.cleanup_for_test()


func after_each() -> void:
	Globals.options_open = _original_options_open
	
	var focus_owner := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus_owner):
		focus_owner.release_focus()
		
	AudioManager.stop_all_sfx()


# ==========================================================================
# TEST HELPERS
# ==========================================================================

## Centralized assertion helper to eliminate internal code duplication.
## Parameterized to support checking alternative input actions dynamically.
func _assert_focus_blocks_action(control: Control, failure_message: String, action_name: String = "ui_accept") -> void:
	# Setup layout tracking parameters
	await _setup_focused_control(control)
	
	# Assemble the target dynamic action payload
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = true
	
	# Route synthetic input payload straight to the intercept loop
	Globals._input(event)
	
	# Assert: Validation logic only. Lifecycle cleanup is deferred to after_each()
	assert_false(
		AudioManager.is_any_sfx_playing(),
		failure_message
	)


## Factory method to assemble an isolated ui_accept InputEventAction payload
func _create_ui_accept_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	return event


## Handles boilerplate instantiation, tree attachment, and frame-buffered focus allocation
func _setup_focused_control(control: Control) -> void:
	add_child_autofree(control)
	
	# Force passive controls (like Panel) to allow focus allocation for baseline testing
	if control.focus_mode == Control.FOCUS_NONE:
		control.focus_mode = Control.FOCUS_ALL
		
	control.grab_focus()
	
	# Godot requires exactly one frame step to recalculate and assign viewport focus owners
	await get_tree().process_frame
	
	assert_eq(get_viewport().gui_get_focus_owner(), control, "Precondition: Target control must hold active focus.")
	AudioManager.stop_all_sfx()


## CodeRabbit Refactor: Centralized assertion helper to eliminate internal 
## Arrange/Act/Assert code duplication across the separate test blocks.
func _assert_focus_blocks_ui_accept(control: Control, failure_message: String) -> void:
	await _setup_focused_control(control)
	Globals._input(_create_ui_accept_event())
	
	assert_false(
		AudioManager.is_any_sfx_playing(),
		failure_message
	)
	
	control.release_focus()
	AudioManager.stop_all_sfx()


# ==========================================================================
# TEST SCENARIOS
# ==========================================================================

## Issue #1 Verification: Toggling a mute button should bypass the global 
## ui_accept sound, delegating downstream audio feedback purely to its local pipeline.
func test_check_button_focus_skips_global_audio() -> void:
	await _assert_focus_blocks_ui_accept(
		CheckButton.new(), 
		"Fix Verification Failed: Global pipeline played generic audio over a focused CheckButton toggle switch."
	)


## Issue #2 Verification: Pressing Enter or Spacebar while a volume slider 
## holds focus must remain entirely silent.
func test_slider_focus_skips_global_audio() -> void:
	await _assert_focus_blocks_ui_accept(
		HSlider.new(), 
		"Fix Verification Failed: Slider emitted generic ui_accept audio when activated via keyboard/controller."
	)


## Issue #3 Verification: Hitting Enter on standard menu buttons must block 
## the global input hook from playing audio, preventing back-to-back double triggers.
func test_button_focus_skips_global_audio() -> void:
	await _assert_focus_blocks_action(
		Button.new(), 
		"Fix Verification Failed: Global hook double-dipped audio on a standard Button element."
	)


## Branch Coverage: Hitting Enter/Spacebar while focused on a LineEdit
## must bypass the global ui_accept sound intercept track.
func test_line_edit_focus_skips_global_audio() -> void:
	await _assert_focus_blocks_ui_accept(
		LineEdit.new(), 
		"Branch Coverage Failure: LineEdit leaked a generic global accept sound overlay."
	)


## Branch Coverage: Hitting Enter/Spacebar while focused on a TextEdit
## must bypass the global ui_accept sound intercept track.
func test_text_edit_focus_skips_global_audio() -> void:
	await _assert_focus_blocks_ui_accept(
		TextEdit.new(), 
		"Branch Coverage Failure: TextEdit leaked a generic global accept sound overlay."
	)


## Control Baseline Case: Ensure standard passive UI layout containers or non-interactive
## items still register the global fallback accept sound cleanly.
func test_passive_control_triggers_global_audio() -> void:
	var fallback_control := Panel.new()
	await _setup_focused_control(fallback_control)

	Globals._input(_create_ui_accept_event())

	assert_true(
		AudioManager.is_any_sfx_playing(),
		"Control Parity Failure: Global ui_accept tracking was blocked by an overly broad filter check."
	)


# ==========================================================================
# DIRECTIONAL NAVIGATION & STALE FOCUS COVERAGE
# ==========================================================================

## Helper method to assemble a navigation InputEventAction payload
func _create_nav_event(action_name: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = true
	return event


## Verification: Directional navigation sound effects must not be dropped
## when viewport focus is transiently empty/stale during a menu context.
func test_stale_focus_navigation_retains_audio_safeguard() -> void:
	# 1. Force a valid menu context but ensure focus owner is explicitly empty/stale
	Globals.options_open = true
	var focus_owner := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus_owner):
		focus_owner.release_focus()
	
	# Clear out any previous audio junk
	AudioManager.stop_all_sfx()
	
	# 2. Simulate a user hitting 'ui_down' during a focus transition fade
	Globals._input(_create_nav_event("ui_down"))
	
	# 3. Assert that the safeguard caught the transition and played the fallback audio
	assert_true(
		AudioManager.is_any_sfx_playing(),
		"Safeguard Failure: Navigation audio was unintentionally dropped due to a stale UI focus state."
	)
