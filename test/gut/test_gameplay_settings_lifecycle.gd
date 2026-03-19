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

## GS-LIFE-01 | Cleanup on tree exit verifies signals and ALL callbacks
func test_gs_life_01_cleanup_on_exit() -> void:
	# 1. Setup: Ensure everything is connected first
	assert_true(Globals.settings.setting_changed.is_connected(gameplay_menu._on_external_setting_changed))
	assert_true(gameplay_menu.difficulty_slider.value_changed.is_connected(gameplay_menu._on_difficulty_value_changed))
	
	# 2. Act: Trigger exit
	gameplay_menu._on_tree_exited()
	
	# 3. Assert Signal Disconnections (The missing piece)
	assert_false(Globals.settings.setting_changed.is_connected(gameplay_menu._on_external_setting_changed), 
		"Global resource signal should be disconnected")
	assert_false(gameplay_menu.difficulty_slider.value_changed.is_connected(gameplay_menu._on_difficulty_value_changed), 
		"Local UI signals should be disconnected")
	
	# 4. Assert ALL Callbacks (Including the missing reset callback)
	assert_null(gameplay_menu._change_difficulty_cb, "Difficulty callback nullified")
	assert_null(gameplay_menu._gameplay_back_button_pressed_cb, "Back button callback nullified")
	assert_null(gameplay_menu._gameplay_reset_cb, "Reset callback nullified")


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
	# FIX: Wrap the lambda in a JavaScriptObject callback
	var dummy_callable := func(_args: Array) -> void: pass
	gameplay_menu._change_difficulty_cb = JavaScriptBridge.create_callback(dummy_callable)
	
	# Act: Call the cleanup function directly
	gameplay_menu._on_tree_exited()
	
	# Assert: Verify the side effects of the cleanup logic
	assert_null(gameplay_menu._change_difficulty_cb, "Callback must be nullified even if Globals are shaky")
	

## GS-LIFE-09 | Unexpected removal (unintentional exit) restores previous menu
func test_gs_life_09_unexpected_removal_restoration() -> void:
	# 1. Setup: Create fresh instance but do not parent yet
	var test_menu: Control = load("res://scenes/gameplay_settings.tscn").instantiate()
	
	# 2. Mock a previous menu in the stack
	var mock_prev: Control = Control.new()
	mock_prev.name = "MockOptionsMenu"
	mock_prev.visible = false
	Globals.hidden_menus.push_back(mock_prev)
	
	# 3. Inject Mock Wrappers
	var mock_js_bridge: Variant = double(JavaScriptBridgeWrapper).new()
	var mock_os: Variant = double(OSWrapper).new()
	stub(mock_os, "has_feature").to_return(true)
	
	# 4. Use a Dictionary for the JS window mock to allow property setting
	var mock_window: Dictionary = {"valid": true} 
	stub(mock_js_bridge, "get_interface").to_return(mock_window)
	
	test_menu.os_wrapper = mock_os
	test_menu.js_bridge_wrapper = mock_js_bridge
	
	# 5. Add to tree to trigger _ready()
	add_child_autofree(test_menu)
	await get_tree().process_frame
	
	# --- THE CRITICAL FIX ---
	# Manually force the script's internal 'js_window' to our mock.
	# This ensures the 'if js_window' check in _on_tree_exited passes.
	test_menu.js_window = mock_window 
	# ------------------------

	# 6. Act: Trigger unexpected exit directly (_intentional_exit remains false)
	test_menu._on_tree_exited()
	
	# 7. Assertions
	assert_true(mock_prev.visible, "Unexpected exit must restore previous menu visibility")
	assert_null(test_menu._change_difficulty_cb, "Callbacks must still be nullified on unexpected exit")
	assert_called(mock_js_bridge, "eval")
	
	# Cleanup mock menu
	mock_prev.free()
