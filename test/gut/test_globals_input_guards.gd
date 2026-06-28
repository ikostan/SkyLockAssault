## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_globals_input_guards.gd
##
## Integration test suite validating that global ui_accept input intercepts
## are correctly bypassed for specific interactive UI controls to eliminate
## duplicate sound triggers and unintended activation noises.
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
	# Restore global state configuration
	Globals.options_open = _original_options_open
	
	# Release viewport focus gracefully to avoid dragging cross-suite residue
	var focus_owner := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus_owner):
		focus_owner.release_focus()
		
	AudioManager.stop_all_sfx()
	await get_tree().process_frame


## Helper method to assemble an isolated ui_accept InputEventAction payload
func _simulate_ui_accept_press() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	return event


# ==========================================================================
# TEST SCENARIOS
# ==========================================================================

## Issue #1 Verification: Toggling a mute button should bypass the global 
## ui_accept sound, delegating downstream audio feedback purely to its local pipeline.
func test_ui_accept_on_check_button_bypasses_global_audio() -> void:
	# 1. ARRANGE: Instantiate a toggleable check control and hold active viewport focus
	var mute_btn := CheckButton.new()
	add_child_autofree(mute_btn)
	mute_btn.grab_focus()
	await get_tree().process_frame
	
	assert_eq(get_viewport().gui_get_focus_owner(), mute_btn, "Precondition: CheckButton must hold active focus.")
	AudioManager.stop_all_sfx() # Ensure clean state after focus allocations

	# 2. ACT: Pass a raw ui_accept event directly into the global input hook
	var event := _simulate_ui_accept_press()
	Globals._input(event)
	await get_tree().process_frame

	# 3. ASSERT: The global catch must return early, preventing generic stream allocation
	assert_false(
		AudioManager.is_any_sfx_playing(),
		"Fix Verification Failed: Global pipeline played generic audio over a focused CheckButton toggle switch."
	)


## Issue #2 Verification: Pressing Enter or Spacebar while a volume slider 
## holds focus must remain entirely silent.
func test_ui_accept_on_slider_bypasses_global_audio() -> void:
	# 1. ARRANGE: Instantiate a standard slider component and grab focus
	var slider := HSlider.new()
	add_child_autofree(slider)
	slider.grab_focus()
	await get_tree().process_frame
	
	assert_eq(get_viewport().gui_get_focus_owner(), slider, "Precondition: Slider must hold active focus.")
	AudioManager.stop_all_sfx()

	# 2. ACT: Fire the ui_accept input event
	var event := _simulate_ui_accept_press()
	Globals._input(event)
	await get_tree().process_frame

	# 3. ASSERT: No sounds must leak out from the global interceptor layer
	assert_false(
		AudioManager.is_any_sfx_playing(),
		"Fix Verification Failed: Slider emitted generic ui_accept audio when activated via keyboard/controller."
	)


## Issue #3 Verification: Hitting Enter on standard menu buttons must block 
## the global input hook from playing audio, preventing back-to-back double triggers.
func test_ui_accept_on_base_button_bypasses_global_audio() -> void:
	# 1. ARRANGE: Instantiate a base menu button control and give it focus
	var menu_btn := Button.new()
	add_child_autofree(menu_btn)
	menu_btn.grab_focus()
	await get_tree().process_frame
	
	assert_eq(get_viewport().gui_get_focus_owner(), menu_btn, "Precondition: Base Button must hold active focus.")
	AudioManager.stop_all_sfx()

	# 2. ACT: Fire the ui_accept input action
	var event := _simulate_ui_accept_press()
	Globals._input(event)
	await get_tree().process_frame

	# 3. ASSERT: The global interceptor must remain completely silent, 
	# leaving sound production strictly to the connected button signal thread.
	assert_false(
		AudioManager.is_any_sfx_playing(),
		"Fix Verification Failed: Global hook double-dipped audio on a standard Button element before its pressed signal settled."
	)


## Control Baseline Case: Ensure that standard UI nodes (like text boxes or items without
## custom audio configurations) still register the global accept sound cleanly.
func test_ui_accept_on_non_button_control_triggers_global_audio() -> void:
	# 1. ARRANGE: Create a focus-fallback control that isn't exempted by the context guards
	var fallback_control := ItemList.new()
	add_child_autofree(fallback_control)
	fallback_control.grab_focus()
	await get_tree().process_frame
	
	assert_eq(get_viewport().gui_get_focus_owner(), fallback_control, "Precondition: Fallback control must be focused.")
	AudioManager.stop_all_sfx()

	# 2. ACT: Pass the ui_accept event execution
	var event := _simulate_ui_accept_press()
	Globals._input(event)
	await get_tree().process_frame

	# 3. ASSERT: The global loop should map and execute the standard ui_accept audio resource path
	assert_true(
		AudioManager.is_any_sfx_playing(),
		"Control Parity Failure: Global ui_accept tracking was blocked by an overly broad filter check."
	)
