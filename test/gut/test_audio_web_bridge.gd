## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_audio_web_bridge.gd
##
## GUT unit tests for the AudioWebBridge Autoload.
## Validates web environment initialization, DOM synchronization, and JS signal routing.

extends "res://addons/gut/test.gd"

const AudioWebBridge = preload(GamePaths.AUDIO_WEB_BRIDGE)

func before_each() -> void:
	# Reset AudioManager to a known clean state before each test
	AudioManager._init_to_defaults()
	AudioManager.apply_all_volumes()

func after_each() -> void:
	# Clean up any stray states
	AudioManager._init_to_defaults()


# ==========================================
# HELPER FUNCTIONS
# ==========================================

## Creates and returns an AudioWebBridge instance that believes it is running 
## in a valid web browser. Use this for testing API and JS->Godot logic (TC-AWB-04 to 14).
func _create_active_bridge() -> Node:
	var bridge: Node = AudioWebBridge.new()
	
	# 1. Mock OSWrapper to return true for "web"
	var mock_os: Variant = double(OSWrapper).new()
	stub(mock_os, "has_feature").to_return(true)
	bridge.os_wrapper = mock_os
	
	# 2. Mock JavaScriptBridgeWrapper and Window
	var mock_js_bridge: Variant = double(JavaScriptBridgeWrapper).new()
	
	# FIX: An empty dictionary {} evaluates to false in Godot 4!
	# We must include a dummy key so 'if not js_window:' evaluates to true.
	var mock_window: Dictionary = {"is_valid_mock": true} 
	stub(mock_js_bridge, "get_interface").to_return(mock_window)
	
	# Stub the create_callback to just return a dummy string indicating success
	stub(mock_js_bridge, "create_callback").to_return("mock_callback")
	
	bridge.js_bridge_wrapper = mock_js_bridge
	
	# Add to tree to trigger _ready() and auto-free at end of test
	add_child_autofree(bridge)
	return bridge

## Creates a partial_double (spy) of the bridge for intercepting specific internal methods
func _create_spy_bridge() -> Variant:
	var bridge: Variant = partial_double(AudioWebBridge).new()
	
	var mock_os: Variant = double(OSWrapper).new()
	stub(mock_os, "has_feature").to_return(true)
	bridge.os_wrapper = mock_os
	
	var mock_js_bridge: Variant = double(JavaScriptBridgeWrapper).new()
	
	# FIX: Make the mock truthy
	var mock_window: Dictionary = {"is_valid_mock": true} 
	stub(mock_js_bridge, "get_interface").to_return(mock_window)
	stub(mock_js_bridge, "create_callback").to_return("mock_callback")
	bridge.js_bridge_wrapper = mock_js_bridge
	
	add_child_autofree(bridge)
	return bridge

# ==========================================
# INITIALIZATION TESTS
# ==========================================

func test_tc_awb_01_init_not_web() -> void:
	## Category: Initialization
	## Scenario: OSWrapper.has_feature("web") returns false.
	## Expected Result: Node calls queue_free() and early returns.
	var bridge: Node = AudioWebBridge.new()
	var mock_os: Variant = double(OSWrapper).new()
	
	stub(mock_os, "has_feature").to_return(false)
	bridge.os_wrapper = mock_os
	add_child_autofree(bridge)
	
	assert_true(bridge.is_queued_for_deletion())


func test_tc_awb_02_init_no_js_window() -> void:
	## Category: Initialization
	## Scenario: Web feature is true, but get_interface("window") returns null.
	## Expected Result: Logs an error: "Failed to get JS window interface" and early returns.
	var bridge: Node = AudioWebBridge.new()
	var mock_os: Variant = double(OSWrapper).new()
	var mock_js_bridge: Variant = double(JavaScriptBridgeWrapper).new()
	
	stub(mock_os, "has_feature").to_return(true)
	stub(mock_js_bridge, "get_interface").to_return(null)
	
	bridge.os_wrapper = mock_os
	bridge.js_bridge_wrapper = mock_js_bridge
	add_child_autofree(bridge)
	
	assert_false(bridge.is_queued_for_deletion())
	assert_null(bridge.js_window)
	assert_null(bridge._audio_back_button_pressed_cb)


func test_tc_awb_03_init_valid_environment() -> void:
	## Category: Initialization
	## Scenario: Valid web environment and valid JS window interface.
	## Expected Result: Callbacks registered globally, connects to AudioManager signals, logs success.
	var bridge: Node = _create_active_bridge()
	
	assert_eq(bridge._audio_back_button_pressed_cb, "mock_callback")
	assert_true(AudioManager.volume_changed.is_connected(bridge._on_godot_volume_changed))
	assert_true(AudioManager.mute_toggled.is_connected(bridge._on_godot_mute_toggled))

# ==========================================
# PUBLIC API TESTS
# ==========================================

func test_tc_awb_04_toggle_dom_visibility_false() -> void:
	## Category: Public API
	## Scenario: Call toggle_dom_visibility(false).
	## Expected Result: Calls js_bridge_wrapper.eval() to set style.display = 'none' for all 14 element IDs.
	var bridge: Node = _create_active_bridge()
	bridge.toggle_dom_visibility(false)
	
	# Verify eval was executed exactly 14 times
	assert_called_count(bridge.js_bridge_wrapper.eval, 14)
	assert_called(bridge.js_bridge_wrapper.eval.bind("document.getElementById('master-slider').style.display = 'none';", false))


func test_tc_awb_05_toggle_dom_visibility_true() -> void:
	## Category: Public API
	## Scenario: Call toggle_dom_visibility(true).
	## Expected Result: Sets style.display = 'block' for all IDs and triggers _sync_all_dom_values().
	var bridge: Node = _create_active_bridge()
	bridge.toggle_dom_visibility(true)
	
	# 14 UI elements toggled to 'block' + 6 Bus Volumes Synced + 6 Bus Mutes Synced = 26 evals
	assert_called_count(bridge.js_bridge_wrapper.eval, 26)
	assert_called(bridge.js_bridge_wrapper.eval.bind("document.getElementById('master-slider').style.display = 'block';", false))

# ==========================================
# GODOT -> JS TESTS
# ==========================================

func test_tc_awb_06_godot_to_js_volume_changed() -> void:
	## Category: Godot -> JS
	## Scenario: AudioManager emits volume_changed (e.g., Music, 0.5).
	## Expected Result: Executes eval("document.getElementById('music-slider').value = 0.5").
	var bridge: Node = _create_active_bridge()
	
	AudioManager.volume_changed.emit(AudioConstants.BUS_MUSIC, 0.5)
	assert_called(bridge.js_bridge_wrapper.eval.bind("document.getElementById('music-slider').value = 0.5", false))


func test_tc_awb_07_godot_to_js_mute_toggled() -> void:
	## Category: Godot -> JS
	## Scenario: AudioManager emits mute_toggled (e.g., SFX, true).
	## Expected Result: Executes eval("document.getElementById('mute-sfx').checked = false") (inverted).
	var bridge: Node = _create_active_bridge()
	
	AudioManager.mute_toggled.emit(AudioConstants.BUS_SFX, true)
	assert_called(bridge.js_bridge_wrapper.eval.bind("document.getElementById('mute-sfx').checked = false", false))

# ==========================================
# JS -> GODOT TESTS
# ==========================================

func test_tc_awb_08_js_to_godot_invalid_volume_args() -> void:
	## Category: JS -> Godot
	## Scenario: JS sends invalid volume args via _on_change_master_volume_js (e.g., empty, string).
	## Expected Result: _validate_volume_args returns -1.0, logs error, returns early.
	var bridge: Node = _create_active_bridge()
	
	# Passing an empty array to trigger the invalid args check natively
	assert_eq(bridge._validate_volume_args([]), -1.0)


func test_tc_awb_09_js_to_godot_valid_volume_change() -> void:
	## Category: JS -> Godot
	## Scenario: JS sends valid volume change (e.g., Master, 0.75).
	## Expected Result: Value is clamped (0.0 to 1.0). Calls AudioManager.set_volume, apply, save.
	var bridge: Variant = _create_spy_bridge()
	
	stub(bridge, "_validate_volume_args").to_return(0.75)
	bridge._on_change_master_volume_js([])
	
	assert_eq(AudioManager.master_volume, 0.75)


func test_tc_awb_10_js_to_godot_blocked_by_parent_mute() -> void:
	## Category: JS -> Godot
	## Scenario: JS attempts to change a sub-bus (e.g., Music) while AudioManager.master_muted is true.
	## Expected Result: Returns early. Blocks the sub-bus adjustment.
	var bridge: Variant = _create_spy_bridge()
	stub(bridge, "_validate_volume_args").to_return(0.5)
	
	AudioManager.master_muted = true
	var initial_music_vol: float = AudioManager.music_volume
	
	bridge._on_change_music_volume_js([])
	
	assert_eq(AudioManager.music_volume, initial_music_vol) # Remains unchanged


func test_tc_awb_11_js_to_godot_valid_mute_toggle() -> void:
	## Category: JS -> Godot
	## Scenario: JS sends valid mute toggle (e.g., [[true]] -> HTML checked).
	## Expected Result: Converts HTML checked state to Godot mute state (inverted). Updates AudioManager.
	var bridge: Variant = _create_spy_bridge()
	
	stub(bridge, "_validate_mute_args").to_return(true) # HTML true = checked = unmuted
	bridge._on_toggle_mute_master_js([])
	
	assert_false(AudioManager.master_muted)


func test_tc_awb_12_js_to_godot_invalid_mute_args() -> void:
	## Category: JS -> Godot
	## Scenario: JS sends invalid mute args (e.g., empty).
	## Expected Result: _validate_mute_args returns null, logs error, returns early.
	var bridge: Node = _create_active_bridge()
	
	assert_null(bridge._validate_mute_args([]))


func test_tc_awb_13_js_to_godot_back_button() -> void:
	## Category: JS -> Godot
	## Scenario: Browser triggers _on_audio_back_button_pressed_js.
	## Expected Result: Emits the web_back_requested signal.
	var bridge: Node = _create_active_bridge()
	
	watch_signals(bridge)
	bridge._on_audio_back_button_pressed_js([])
	assert_signal_emitted(bridge, "web_back_requested")


func test_tc_awb_14_js_to_godot_reset_button() -> void:
	## Category: JS -> Godot
	## Scenario: Browser triggers _on_audio_reset_js.
	## Expected Result: Emits the web_reset_requested signal.
	var bridge: Node = _create_active_bridge()
	
	watch_signals(bridge)
	bridge._on_audio_reset_js([])
	assert_signal_emitted(bridge, "web_reset_requested")
