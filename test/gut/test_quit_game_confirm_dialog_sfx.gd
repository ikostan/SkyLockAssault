## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_quit_game_confirm_dialog_sfx.gd
## GUT unit tests for main menu quit dialog confirmation audio pathways.
# FIX: Swapped out explicit path inheritance for the global class name token to ensure test runner discovery
extends GutTest

# FIX: Load the PackedScene layout to build the required @onready subnode tree hierarchy
var MainMenuScene: PackedScene = load("res://scenes/main_menu.tscn")
var main_menu_instance: Control
var original_audio_script: Script
var original_fields := {}


## Suite setup: Double the AudioManager using an inherited script to preserve real node-wiring behavior.
## :rtype: void
func before_all() -> void:
	if is_instance_valid(AudioManager):
		original_audio_script = AudioManager.get_script()
		var script_path: String = original_audio_script.resource_path
		var mock_script := GDScript.new()
		
		# FIX (Sourcery-AI): Inherit directly from the production script so all real validation,
		# tree tracking, and filtering logic remain active. We only override play_sfx to spy on output.
		mock_script.source_code = """
extends "%s"

var sfx_calls: Array = []

# Override play_sfx matching the production signature to intercept audio calls safely
func play_sfx(sfx_name: String, bus_name: String = "SFX_Menu", pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	sfx_calls.append([sfx_name, bus_name])
""" % script_path
		
		mock_script.reload()
		AudioManager.set_script(mock_script)


## Suite cleanup: Safely restore original production script after all tests execute.
## :rtype: void
func after_all() -> void:
	if original_audio_script and is_instance_valid(AudioManager):
		AudioManager.set_script(original_audio_script)
		# FIX: Re-populate and rebuild the internal variable states wiped by set_script()
		if AudioManager.has_method("cleanup_for_test"):
			AudioManager.cleanup_for_test()


## Per-test setup: Instantiate target menu scene layout tree and clear call logs.
## :rtype: void
func before_each() -> void:
	# Instantiate the scene instead of using script.new() to initialize @onready child nodes
	main_menu_instance = MainMenuScene.instantiate() as Control
	
	# FIX: Turn on the safety guard to block get_tree().quit() from crashing the runner
	if "bypass_quit_for_testing" in main_menu_instance:
		main_menu_instance.set("bypass_quit_for_testing", true)
		
	add_child_autofree(main_menu_instance)
	
	if AudioManager.get("sfx_calls") != null:
		AudioManager.set("sfx_calls", [])
		
	await get_tree().process_frame


## Per-test cleanup: Release active control focuses cleanly.
## :rtype: void
func after_each() -> void:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus_owner):
		focus_owner.release_focus()
	await get_tree().process_frame


## Helper assertions for tracking explicit mock array triggers
func _assert_sfx_called(key: String) -> void:
	var found := false
	var calls: Array = AudioManager.get("sfx_calls")
	for c: Array in calls:
		if c[0] == key:
			found = true
			break
	assert_true(found, "Expected play_sfx to be called with: " + key)


func _assert_sfx_call_count(count: int) -> void:
	var actual_count: int = AudioManager.get("sfx_calls").size()
	assert_eq(actual_count, count, "Expected play_sfx to be called %d times. Got %d." % [count, actual_count])


func _assert_sfx_not_called(key: String) -> void:
	var found := false
	var calls: Array = AudioManager.get("sfx_calls")
	for c: Array in calls:
		if c[0] == key:
			found = true
			break
	assert_false(found, "Expected play_sfx NOT to be called with: " + key)


## Assert that calling the localized _on_quit_dialog_confirmed sequence triggers an accept chime.
## :rtype: void
func test_dialog_confirmation_audio() -> void:
	if main_menu_instance.has_method("_on_quit_dialog_confirmed"):
		main_menu_instance._on_quit_dialog_confirmed()
		
	_assert_sfx_called("ui_accept")
	_assert_sfx_call_count(1)


## Assert that invoking the localized _on_quit_dialog_canceled sequence triggers a cancellation sound.
## :rtype: void
func test_dialog_cancellation_audio() -> void:
	if main_menu_instance.has_method("_on_quit_dialog_canceled"):
		main_menu_instance._on_quit_dialog_canceled()
		
	_assert_sfx_called("ui_cancel")
	_assert_sfx_call_count(1)


## Assert that standard menu buttons do not trigger global confirmation requests on ui_accept.
## :rtype: void
func test_flat_button_anti_trigger_protection() -> void:
	var start_button: Button = Button.new()
	start_button.flat = true
	main_menu_instance.add_child(start_button)
	
	# FIX: Explicitly drive the button through the global connection hook to mimic tree entry
	# OLD: Globals._on_node_added(start_button)
	AudioManager._on_node_added(start_button)
	await get_tree().process_frame
	
	# FIX: Directly emit the pressed signal to verify the global hook was successfully blocked
	start_button.pressed.emit()
	await get_tree().process_frame
		
	# Global accept confirmation must remain untouched to respect native inspector themes
	_assert_sfx_not_called("ui_accept")
