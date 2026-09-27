## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_web_telemetry_adapter.gd
## GUT unit tests for the WebTelemetryAdapter.

extends "res://addons/gut/test.gd"

# --- Inner Classes for Mocking ---
class MockOSWrapper extends OSWrapper:
	var simulate_web: bool = true
	func has_feature(feature: String) -> bool:
		if feature == "web":
			return simulate_web
		return false

class MockJSBridge extends JavaScriptBridgeWrapper:
	var last_eval: String = ""
	var eval_count: int = 0
	
	func eval(code: String, global_exec: bool = false) -> Variant:
		last_eval = code
		eval_count += 1
		return null
# ---------------------------------

var adapter: Node
var fuel_res: FuelResource
var os_mock: MockOSWrapper
var js_mock: MockJSBridge

func before_each() -> void:
	fuel_res = FuelResource.new()
	adapter = load("res://scripts/system/web_telemetry_adapter.gd").new()
	
	os_mock = MockOSWrapper.new()
	js_mock = MockJSBridge.new()
	
	# Inject mocks BEFORE adding to tree so _ready() behaves properly
	adapter.os_wrapper = os_mock
	adapter.js_bridge_wrapper = js_mock
	
	add_child_autoqfree(adapter)


func test_adapter_primes_initial_value() -> void:
	gut.p("Testing: setup() primes the initial value to the DOM.")
	fuel_res.current_fuel = 88.5
	adapter.setup(fuel_res)
	
	assert_eq(js_mock.last_eval, "window.currentFuel = 88.5")
	assert_eq(js_mock.eval_count, 1)


func test_adapter_pushes_updates() -> void:
	gut.p("Testing: adapter pushes new values on fuel change.")
	adapter.setup(fuel_res)
	var initial_count: int = js_mock.eval_count
	
	fuel_res.current_fuel = 50.5
	assert_eq(js_mock.last_eval, "window.currentFuel = 50.5")
	assert_eq(js_mock.eval_count, initial_count + 1)


func test_adapter_ignores_redundant_updates() -> void:
	gut.p("Testing: redundant values are ignored by the internal cache.")
	fuel_res.current_fuel = 60.0
	adapter.setup(fuel_res)
	var initial_count: int = js_mock.eval_count
	
	# Simulate a redundant change 
	adapter._on_fuel_changed(60.0) 
	
	assert_eq(js_mock.eval_count, initial_count, "Should not increment eval count for unchanged values.")


func test_adapter_self_destructs_off_web() -> void:
	gut.p("Testing: adapter frees itself on non-web platforms.")
	
	var desktop_adapter: Node = load("res://scripts/system/web_telemetry_adapter.gd").new()
	var desktop_os_mock: MockOSWrapper = MockOSWrapper.new()
	desktop_os_mock.simulate_web = false # Simulate Windows/Linux/Mac
	
	desktop_adapter.os_wrapper = desktop_os_mock
	add_child_autoqfree(desktop_adapter)
	
	assert_true(desktop_adapter.is_queued_for_deletion(), "Adapter must self-destruct if not on web.")
