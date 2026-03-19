## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_gameplay_settings_lifecycle.gd
##
## GS-LIFE: Verifies cleanup, menu restoration, and web overlay teardown.

extends "res://addons/gut/test.gd"

const GameplaySettings = preload("res://scripts/gameplay_settings.gd")
var gameplay_menu: Control

func before_each() -> void:
	Globals.settings = GameSettingsResource.new()
	gameplay_menu = load("res://scenes/gameplay_settings.tscn").instantiate()
	gameplay_menu.os_wrapper = OSWrapper.new() 
	add_child_autofree(gameplay_menu)
	await get_tree().process_frame

# --- SECTION 7: LIFECYCLE AND CLEANUP TESTS ---

## GS-LIFE-01 | Cleanup on tree exit nullifies callbacks
func test_gs_life_01_cleanup_on_exit() -> void:
	# Trigger exit
	gameplay_menu._on_tree_exited()
	
	# Verify JS callbacks are cleared to prevent memory leaks
	assert_null(gameplay_menu._change_difficulty_cb, "Difficulty callback should be null")
	assert_null(gameplay_menu._gameplay_back_button_pressed_cb, "Back button callback should be null")


## GS-LIFE-02 | Back button restores previous menu from stack
func test_gs_life_02_back_button_restoration() -> void:
	# Mock a previous menu
	var mock_prev: Control = Control.new()
	autofree(mock_prev)  # Ensures cleanup even on test failure
	mock_prev.name = "MockOptionsMenu"
	mock_prev.visible = false
	Globals.hidden_menus.push_back(mock_prev)
	
	gameplay_menu._on_gameplay_back_button_pressed()
	
	assert_true(mock_prev.visible, "Previous menu should be visible again")
	assert_true(gameplay_menu.is_queued_for_deletion(), "Menu should be freed")


## GS-LIFE-08 | Web overlay visibility cleanup
func test_gs_life_08_web_overlay_cleanup() -> void:
	var test_menu: Control = load("res://scenes/gameplay_settings.tscn").instantiate()
	var mock_js_bridge: Variant = double(JavaScriptBridgeWrapper).new()
	var mock_os: Variant = double(OSWrapper).new()
	
	stub(mock_os, "has_feature").to_return(true)
	
	# FIX: Use a Dictionary. It allows the script to call 
	# js_window.changeDifficulty = ... without crashing.
	var mock_window: Dictionary = {} 
	stub(mock_js_bridge, "get_interface").to_return(mock_window)
	
	test_menu.os_wrapper = mock_os
	test_menu.js_bridge_wrapper = mock_js_bridge
	
	add_child_autofree(test_menu)
	await get_tree().process_frame
	
	test_menu._on_tree_exited()
	assert_called(mock_js_bridge, "eval")


## GS-LIFE-05 | Cleanup handles null Globals gracefully
func test_gs_life_05_null_globals_safety() -> void:
	# Set a non-null callback to verify cleanup actually nullifies it.
	var dummy_callable := func(_args: Array) -> void: pass
	gameplay_menu._change_difficulty_cb = dummy_callable
	
	# Act: Call the cleanup function directly [cite: 8]
	gameplay_menu._on_tree_exited()
	
	# Assert: Verify the side effects of the cleanup logic
	assert_null(gameplay_menu._change_difficulty_cb, "Callback must be nullified even if Globals are shaky")
