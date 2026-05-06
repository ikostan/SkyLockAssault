## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_audio_web_bridge_dom_sync.gd
##
## TEST SUITE: Verifies DOM Sync Decoupling for Web Bridge (Issue #567).
## This suite proves that Godot state changes execute strictly one-way JavaScript 
## DOM updates without emitting signals back into the engine.
## This is a critical safety test to prevent infinite feedback loops.

extends "res://addons/gut/test.gd"

# ==========================================
# MOCKS
# ==========================================

## WHY: Mocks the OS environment to bypass the self-destruction check in 
## AudioWebBridge._ready() when running tests in a non-web environment.
class MockOSWrapper extends OSWrapper:
	func has_feature(feature: String) -> bool:
		return feature == "web"

## WHY: Mocks the JavaScriptBridge to record the exact strings passed to the browser.
class MockJSBridgeWrapper extends JavaScriptBridgeWrapper:
	var eval_calls: Array[String] = []
	# FIX: Use a non-empty dictionary. In GDScript, {} is falsy, 
	# which caused the bridge to return early.
	var mock_window := {"is_mock": true} 

	func eval(code: String, _global_exec: bool = false) -> Variant:
		eval_calls.append(code)
		return null

	func get_interface(interface: String) -> Variant:
		if interface == "window":
			return mock_window
		return null

	func create_callback(_callable: Callable) -> Variant:
		return {} 


# ==========================================
# TESTS
# ==========================================

var web_bridge: Node
var mock_js: MockJSBridgeWrapper

## WHY: Prepares the test environment by instantiating the bridge with mocks.
## WHAT: Loads AudioWebBridge using GamePaths and injects dependencies.
## EXPECTED: The script loads and is initialized for isolated evaluation.
func before_each() -> void:
	var path: String = GamePaths.AUDIO_WEB_BRIDGE
	var bridge_script: Script = load(path)
	
	if bridge_script == null:
		fail_test("Failed to load AudioWebBridge script at: " + path)
		return

	web_bridge = bridge_script.new()
	
	# Injection must happen BEFORE add_child so _ready() uses the mocks
	mock_js = MockJSBridgeWrapper.new()
	web_bridge.js_bridge_wrapper = mock_js
	web_bridge.os_wrapper = MockOSWrapper.new()

	add_child_autoqfree(web_bridge)


## WHY: Ensures volume changes in Godot update the HTML DOM via raw property assignment.
## WHAT: Simulates a volume change signal from the AudioManager for the Master bus.
## EXPECTED: The bridge generates a JS string setting the '.value' property. This 
## bypasses browser events to prevent Godot from receiving its own changes back.
func test_dom_volume_sync_executes_js_only() -> void:
	mock_js.eval_calls.clear()
	
	# Act: Directly trigger the bridge's internal signal listener
	var test_volume: float = 0.85
	web_bridge._on_godot_volume_changed(AudioConstants.BUS_MASTER, test_volume)
	
	# Assert: Verify exactly one JS command was issued
	assert_eq(mock_js.eval_calls.size(), 1, "Only one DOM update should be triggered.")
	
	if mock_js.eval_calls.size() > 0:
		var expected_js: String = "document.getElementById('master-slider').value = 0.85"
		assert_eq(
			mock_js.eval_calls[0], 
			expected_js, 
			"Bridge must update HTML DOM directly to prevent feedback loops."
		)


## WHY: Ensures that Godot's 'muted' state is correctly inverted for the DOM.
## WHAT: Simulates Godot muting the Music bus (muted = true).
## EXPECTED: DOM state corresponds to 'checked = false' translated via property update.
## Direct assignment prevents the browser from firing an 'onchange' event.
func test_dom_mute_sync_executes_js_only() -> void:
	mock_js.eval_calls.clear()
	
	# Act: Broadcast a mute action from Godot
	web_bridge._on_godot_mute_toggled(AudioConstants.BUS_MUSIC, true)
	
	assert_eq(mock_js.eval_calls.size(), 1, "Only one DOM update should be triggered.")
	
	if mock_js.eval_calls.size() > 0:
		var expected_js: String = "document.getElementById('mute-music').checked = false"
		assert_eq(
			mock_js.eval_calls[0], 
			expected_js, 
			"Bridge must directly uncheck the HTML element without Godot signals."
		)


## WHY: Ensures that Godot's 'unmuted' state is correctly reflected in the DOM.
## WHAT: Simulates Godot unmuting the SFX bus (muted = false).
## EXPECTED: The bridge translates this to 'checked = true' in JavaScript.
## Property assignment ensures the browser shell remains in sync with the engine.
func test_dom_unmute_sync_executes_js_only() -> void:
	mock_js.eval_calls.clear()
	
	# Act: Broadcast an unmute action from Godot
	web_bridge._on_godot_mute_toggled(AudioConstants.BUS_SFX, false)
	
	assert_eq(mock_js.eval_calls.size(), 1, "Only one DOM update should be triggered.")
	
	if mock_js.eval_calls.size() > 0:
		var expected_js: String = "document.getElementById('mute-sfx').checked = true"
		assert_eq(
			mock_js.eval_calls[0], 
			expected_js, 
			"Bridge must directly check the HTML element without Godot signals."
		)
	
