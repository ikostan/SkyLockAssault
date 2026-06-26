## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_quit_game_confirm_dialog_sfx.gd
## GUT unit tests for main menu quit dialog confirmation audio pathways.

extends "res://addons/gut/test.gd"

# FIX: Load the PackedScene layout to build the required @onready subnode tree hierarchy
var MainMenuScene: PackedScene = load("res://scenes/main_menu.tscn")
var main_menu_instance: Control
var original_audio_script: Script
var original_fields := {}

## Suite setup: Double the AudioManager using a decoupled script to bypass lifecycle destruction guards.
## :rtype: void
func before_all() -> void:
	if is_instance_valid(AudioManager):
		original_audio_script = AudioManager.get_script()
		var mock_script := GDScript.new()
		mock_script.source_code = """
extends Node
var sfx_calls: Array = []
func play_sfx(key: String, extra: Variant = null) -> void:
	sfx_calls.append([key, extra])
"""
		mock_script.reload()
		AudioManager.set_script(mock_script)


## Suite cleanup: Safely restore original production script after all tests execute.
## :rtype: void
func after_all() -> void:
	if original_audio_script and is_instance_valid(AudioManager):
		AudioManager.set_script(original_audio_script)


## Per-test setup: Instantiate target menu scene layout tree and clear call logs.
## :rtype: void
func before_each() -> void:
	# FIX: Instantiate the scene instead of using script.new() to initialize @onready child nodes
	main_menu_instance = MainMenuScene.instantiate() as Control
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
	start_button.grab_focus()
	await get_tree().process_frame
	
	var event: InputEventAction = InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	
	if main_menu_instance.has_method("_input"):
		main_menu_instance._input(event)
	if main_menu_instance.has_method("_unhandled_input"):
		main_menu_instance._unhandled_input(event)
		
	# Global accept confirmation must remain untouched to respect native inspector themes
	_assert_sfx_not_called("ui_accept")
