## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_globals_button_hooks.gd
##
## Architectural test suite verifying the automatic stream connection guards
## inside the global Node instantiation tracking track.
extends "res://addons/gut/test.gd"


func before_each() -> void:
	AudioManager.stop_all_sfx()


func after_each() -> void:
	AudioManager.stop_all_sfx()
	await get_tree().process_frame


## Verifies that regular runtime UI buttons are automatically discovered
## and hooked up to the global accept audio sequence thread.
func test_standard_button_auto_connects_deferred() -> void:
	var standard_btn := Button.new()
	add_child_autofree(standard_btn)
	
	# Allow deferred connection assignment loop to commit
	await get_tree().process_frame
	
	# Verify implicit connection to the global execution target
	assert_true(
		standard_btn.pressed.is_connected(Globals._on_global_button_pressed),
		"Standard interactive button must auto-bind to global playback logic."
	)


## Verifies that flat buttons are intentionally bypassed to prevent
## overriding specialized spatial theme audio layers.
func test_flat_button_is_ignored_by_hook() -> void:
	var flat_btn := Button.new()
	flat_btn.flat = true
	add_child_autofree(flat_btn)
	await get_tree().process_frame
	
	assert_false(
		flat_btn.pressed.is_connected(Globals._on_global_button_pressed),
		"Flat UI theme buttons must be exempted from global audio routing."
	)


## Verifies that custom nodes using explicit structural meta flags
## suppress global button behavior cleanly.
func test_meta_flagged_button_is_ignored_by_hook() -> void:
	var isolated_btn := Button.new()
	isolated_btn.set_meta("no_global_sound", true)
	add_child_autofree(isolated_btn)
	await get_tree().process_frame
	
	assert_false(
		isolated_btn.pressed.is_connected(Globals._on_global_button_pressed),
		"Buttons carrying 'no_global_sound' metadata must remain isolated."
	)


## Verifies that structural internal elements of confirmation dialog blocks
## do not catch duplicate activation tracks.
func test_dialog_internal_buttons_are_ignored_by_hook() -> void:
	var confirmation_dialog := ConfirmationDialog.new()
	add_child_autofree(confirmation_dialog)
	
	# Grab a handle to native ok/cancel layout node branches
	var ok_btn := confirmation_dialog.get_ok_button()
	await get_tree().process_frame
	
	assert_false(
		ok_btn.pressed.is_connected(Globals._on_global_button_pressed),
		"Internal AcceptDialog/ConfirmationDialog buttons must bypass global hooks."
	)
