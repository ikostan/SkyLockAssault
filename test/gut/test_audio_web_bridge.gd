## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_audio_web_bridge.gd
##
## GdUnit4 unit tests for the AudioWebBridge Autoload.
## Validates web environment initialization, DOM synchronization, and JS signal routing.

extends GdUnitTestSuite

const AudioWebBridge = preload("res://scripts/audio_web_bridge.gd")

func before_test() -> void:
	# Reset AudioManager to a known clean state before each test
	AudioManager._init_to_defaults()
	AudioManager.apply_all_volumes()

func after_test() -> void:
	# Clean up any stray states
	AudioManager._init_to_defaults()


# ==========================================
# HELPER FUNCTIONS
# ==========================================

## Creates and returns an AudioWebBridge instance that believes it is running 
## in a valid web browser. Use this for testing API and JS->Godot logic (TC-AWB-04 to 14).
func _create_active_bridge() -> Node:
	var bridge := auto_free(AudioWebBridge.new())
	
	# 1. Mock OSWrapper to return true for "web"
	var mock_os := mock(OSWrapper)
	do_return(true).on(mock_os).has_feature("web")
	bridge.os_wrapper = mock_os
	
	# 2. Mock JavaScriptBridgeWrapper and Window
	var mock_js_bridge := mock(JavaScriptBridgeWrapper)
	var mock_window := {} # Dictionary acts as the JS window object
	do_return(mock_window).on(mock_js_bridge).get_interface("window")
	
	# Stub the create_callback to just return a dummy string indicating success
	# do_return("mock_callback").on(mock_js_bridge).create_callback(any_class(Callable))
	do_return("mock_callback").on(mock_js_bridge).create_callback(any())
	
	bridge.js_bridge_wrapper = mock_js_bridge
	
	# Add to tree to trigger _ready()
	add_child(bridge)
	return bridge

# ==========================================
# INITIALIZATION TESTS
# ==========================================

func test_tc_awb_01_init_not_web() -> void:
	## Category: Initialization
	## Scenario: OSWrapper.has_feature("web") returns false.
	## Expected Result: Node calls queue_free() and early returns.
	var bridge := AudioWebBridge.new()
	var mock_os := mock(OSWrapper)
	
	do_return(false).on(mock_os).has_feature("web")
	bridge.os_wrapper = mock_os
	add_child(bridge)
	
	assert_bool(bridge.is_queued_for_deletion()).is_true()


func test_tc_awb_02_init_no_js_window() -> void:
	## Category: Initialization
	## Scenario: Web feature is true, but get_interface("window") returns null.
	## Expected Result: Logs an error: "Failed to get JS window interface" and early returns.
	var bridge := auto_free(AudioWebBridge.new())
	var mock_os := mock(OSWrapper)
	var mock_js_bridge := mock(JavaScriptBridgeWrapper)
	
	do_return(true).on(mock_os).has_feature("web")
	do_return(null).on(mock_js_bridge).get_interface("window")
	
	bridge.os_wrapper = mock_os
	bridge.js_bridge_wrapper = mock_js_bridge
	add_child(bridge)
	
	assert_bool(bridge.is_queued_for_deletion()).is_false()
	assert_that(bridge.js_window).is_null()
	assert_that(bridge._audio_back_button_pressed_cb).is_null() # Proves callbacks were skipped


func test_tc_awb_03_init_valid_environment() -> void:
	## Category: Initialization
	## Scenario: Valid web environment and valid JS window interface.
	## Expected Result: Callbacks registered globally, connects to AudioManager signals, logs success.
	var bridge := _create_active_bridge()
	
	assert_that(bridge._audio_back_button_pressed_cb).is_equal("mock_callback")
	assert_bool(AudioManager.volume_changed.is_connected(bridge._on_godot_volume_changed)).is_true()
	assert_bool(AudioManager.mute_toggled.is_connected(bridge._on_godot_mute_toggled)).is_true()

# ==========================================
# PUBLIC API TESTS
# ==========================================

func test_tc_awb_04_toggle_dom_visibility_false() -> void:
	## Category: Public API
	## Scenario: Call toggle_dom_visibility(false).
	## Expected Result: Calls js_bridge_wrapper.eval() to set style.display = 'none' for all 14 element IDs.
	var bridge := _create_active_bridge()
	bridge.toggle_dom_visibility(false)
	
	# Verify eval was executed exactly 14 times (once for each element)
	verify(bridge.js_bridge_wrapper, 14).eval(any_string())
	verify(bridge.js_bridge_wrapper, 1).eval("document.getElementById('master-slider').style.display = 'none';")


func test_tc_awb_05_toggle_dom_visibility_true() -> void:
	## Category: Public API
	## Scenario: Call toggle_dom_visibility(true).
	## Expected Result: Sets style.display = 'block' for all IDs and triggers _sync_all_dom_values().
	var bridge := _create_active_bridge()
	bridge.toggle_dom_visibility(true)
	
	# 14 UI elements toggled to 'block' + 6 Bus Volumes Synced + 6 Bus Mutes Synced = 26 evals
	verify(bridge.js_bridge_wrapper, 26).eval(any_string())
	verify(bridge.js_bridge_wrapper, 1).eval("document.getElementById('master-slider').style.display = 'block';")

# ==========================================
# GODOT -> JS TESTS
# ==========================================

func test_tc_awb_06_godot_to_js_volume_changed() -> void:
	## Category: Godot -> JS
	## Scenario: AudioManager emits volume_changed (e.g., Music, 0.5).
	## Expected Result: Executes eval("document.getElementById('music-slider').value = 0.5").
	var bridge := _create_active_bridge()
	
	AudioManager.volume_changed.emit(AudioConstants.BUS_MUSIC, 0.5)
	verify(bridge.js_bridge_wrapper, 1).eval("document.getElementById('music-slider').value = 0.5")


func test_tc_awb_07_godot_to_js_mute_toggled() -> void:
	## Category: Godot -> JS
	## Scenario: AudioManager emits mute_toggled (e.g., SFX, true).
	## Expected Result: Executes eval("document.getElementById('mute-sfx').checked = false") (inverted).
	var bridge := _create_active_bridge()
	
	AudioManager.mute_toggled.emit(AudioConstants.BUS_SFX, true)
	verify(bridge.js_bridge_wrapper, 1).eval("document.getElementById('mute-sfx').checked = false")

# ==========================================
# JS -> GODOT TESTS
# ==========================================

func test_tc_awb_08_js_to_godot_invalid_volume_args() -> void:
	## Category: JS -> Godot
	## Scenario: JS sends invalid volume args via _on_change_master_volume_js (e.g., empty, string).
	## Expected Result: _validate_volume_args returns -1.0, logs error, returns early.
	var bridge := _create_active_bridge()
	
	# Passing an empty array to trigger the invalid args check natively
	assert_float(bridge._validate_volume_args([])).is_equal(-1.0)


func test_tc_awb_09_js_to_godot_valid_volume_change() -> void:
	## Category: JS -> Godot
	## Scenario: JS sends valid volume change (e.g., Master, 0.75).
	## Expected Result: Value is clamped (0.0 to 1.0). Calls AudioManager.set_volume, apply, save.
	var bridge := _create_active_bridge()
	var spy_bridge := spy(bridge) # Use spy to bypass strict web TYPE_OBJECT requirement during tests
	
	do_return(0.75).on(spy_bridge)._validate_volume_args(any_array())
	spy_bridge._on_change_master_volume_js([])
	
	assert_float(AudioManager.master_volume).is_equal(0.75)


func test_tc_awb_10_js_to_godot_blocked_by_parent_mute() -> void:
	## Category: JS -> Godot
	## Scenario: JS attempts to change a sub-bus (e.g., Music) while AudioManager.master_muted is true.
	## Expected Result: Returns early. Blocks the sub-bus adjustment.
	var bridge := _create_active_bridge()
	var spy_bridge := spy(bridge)
	do_return(0.5).on(spy_bridge)._validate_volume_args(any_array())
	
	AudioManager.master_muted = true
	var initial_music_vol := AudioManager.music_volume
	
	spy_bridge._on_change_music_volume_js([])
	
	assert_float(AudioManager.music_volume).is_equal(initial_music_vol) # Remains unchanged


func test_tc_awb_11_js_to_godot_valid_mute_toggle() -> void:
	## Category: JS -> Godot
	## Scenario: JS sends valid mute toggle (e.g., [[true]] -> HTML checked).
	## Expected Result: Converts HTML checked state to Godot mute state (inverted). Updates AudioManager.
	var bridge := _create_active_bridge()
	var spy_bridge := spy(bridge)
	
	do_return(true).on(spy_bridge)._validate_mute_args(any_array()) # HTML true = checked = unmuted
	spy_bridge._on_toggle_mute_master_js([])
	
	assert_bool(AudioManager.master_muted).is_false()


func test_tc_awb_12_js_to_godot_invalid_mute_args() -> void:
	## Category: JS -> Godot
	## Scenario: JS sends invalid mute args (e.g., empty).
	## Expected Result: _validate_mute_args returns null, logs error, returns early.
	var bridge := _create_active_bridge()
	
	assert_that(bridge._validate_mute_args([])).is_null()


func test_tc_awb_13_js_to_godot_back_button() -> void:
	## Category: JS -> Godot
	## Scenario: Browser triggers _on_audio_back_button_pressed_js.
	## Expected Result: Emits the web_back_requested signal.
	var bridge := _create_active_bridge()
	
	bridge._on_audio_back_button_pressed_js([])
	assert_signal(bridge).is_emitted("web_back_requested")


func test_tc_awb_14_js_to_godot_reset_button() -> void:
	## Category: JS -> Godot
	## Scenario: Browser triggers _on_audio_reset_js.
	## Expected Result: Emits the web_reset_requested signal.
	var bridge := _create_active_bridge()
	
	bridge._on_audio_reset_js([])
	assert_signal(bridge).is_emitted("web_reset_requested")
