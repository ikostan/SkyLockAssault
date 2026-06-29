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
	# Micro-optimization: Removed 'await get_tree().process_frame' 
	# unless cross-suite focus pollution explicitly requires it.


# ==========================================================================
# TEST HELPERS
# ==========================================================================

## Factory method to assemble an isolated ui_accept InputEventAction payload
func _create_ui_accept_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	return event


## Handles boilerplate instantiation, tree attachment, and frame-buffered focus allocation
func _setup_focused_control(control: Control) -> void:
	add_child_autofree(control)
	
	# Godot 4 Fix: Force passive controls (like Panel) to allow focus allocation for baseline testing
	if control.focus_mode == Control.FOCUS_NONE:
		control.focus_mode = Control.FOCUS_ALL
		
	control.grab_focus()
	
	# Godot requires exactly one frame step to recalculate and assign viewport focus owners
	await get_tree().process_frame
	
	assert_eq(get_viewport().gui_get_focus_owner(), control, "Precondition: Target control must hold active focus.")
	AudioManager.stop_all_sfx()


# ==========================================================================
# TEST SCENARIOS
# ==========================================================================

## Issue #1 Verification: Toggling a mute button should bypass the global 
## ui_accept sound, delegating downstream audio feedback purely to its local pipeline.
func test_check_button_focus_skips_global_audio() -> void:
	var mute_btn := CheckButton.new()
	await _setup_focused_control(mute_btn)

	# Feed the event directly into Globals._input().
	# GUT does not cleanly pump synthetic InputEventActions through the engine's main OS window
	# pipeline, so this exercises the target script's entry point directly and deterministically.
	Globals._input(_create_ui_accept_event())

	assert_false(
		AudioManager.is_any_sfx_playing(),
		"Fix Verification Failed: Global pipeline played generic audio over a focused CheckButton toggle switch."
	)


## Issue #2 Verification: Pressing Enter or Spacebar while a volume slider 
## holds focus must remain entirely silent.
func test_slider_focus_skips_global_audio() -> void:
	var slider := HSlider.new()
	await _setup_focused_control(slider)

	Globals._input(_create_ui_accept_event())

	assert_false(
		AudioManager.is_any_sfx_playing(),
		"Fix Verification Failed: Slider emitted generic ui_accept audio when activated via keyboard/controller."
	)


## Issue #3 Verification: Hitting Enter on standard menu buttons must block 
## the global input hook from playing audio, preventing back-to-back double triggers.
func test_button_focus_skips_global_audio() -> void:
	var menu_btn := Button.new()
	await _setup_focused_control(menu_btn)

	Globals._input(_create_ui_accept_event())

	assert_false(
		AudioManager.is_any_sfx_playing(),
		"Fix Verification Failed: Global hook double-dipped audio on a standard Button element."
	)


## Regression Guard: Ensure the input block checks the abstract BaseButton class,
## preventing audio leakage on alternative button implementations like TextureButtons.
func test_texture_button_focus_skips_global_audio() -> void:
	var texture_btn := TextureButton.new()
	await _setup_focused_control(texture_btn)

	Globals._input(_create_ui_accept_event())

	assert_false(
		AudioManager.is_any_sfx_playing(),
		"Regression Failure: Input guard failed to catch TextureButton (likely checking for Button instead of BaseButton)."
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
