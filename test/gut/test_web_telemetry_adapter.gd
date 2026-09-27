## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## Unit tests for fuel telemetry using a real resource and an isolated browser bridge.
extends "res://addons/gut/test.gd"

const TelemetryAdapter = preload("res://scripts/system/web_telemetry_adapter.gd")


class RecordingBridge extends JavaScriptBridgeWrapper:

	var scripts: Array[String] = []

	func eval(code: String, _global_exec: bool = false) -> Variant:
		scripts.append(code)
		return null


var _adapter: Node
var _bridge: RecordingBridge
var _fuel: FuelResource


func before_each() -> void:
	_adapter = TelemetryAdapter.new()
	_bridge = RecordingBridge.new()
	_adapter.js_bridge_wrapper = _bridge
	var mock_os: Variant = double(OSWrapper).new()
	stub(mock_os, "has_feature").to_return(true).when_passed("web")
	_adapter.os_wrapper = mock_os
	_fuel = FuelResource.new()
	add_child_autofree(_adapter)


func _assert_published(expected: Array) -> void:
	var values: Array = []
	for code: String in _bridge.scripts:
		assert_true(code.begins_with("window.currentFuel = "), "Preserve the browser contract.")
		values.append(JSON.parse_string(code.trim_prefix("window.currentFuel = ")))
	assert_eq(values, expected, "Publish numeric fuel values in order, without extra writes.")


func test_web_adapter_waits_for_setup_without_publishing() -> void:
	assert_false(_adapter.is_queued_for_deletion())
	assert_called(_adapter.os_wrapper.has_feature.bind("web"))
	_assert_published([])


func test_native_adapter_is_freed_without_publishing() -> void:
	var native_adapter: Node = TelemetryAdapter.new()
	var mock_os: Variant = double(OSWrapper).new()
	stub(mock_os, "has_feature").to_return(false).when_passed("web")
	native_adapter.os_wrapper = mock_os
	native_adapter.js_bridge_wrapper = _bridge
	add_child_autoqfree(native_adapter)
	assert_true(native_adapter.is_queued_for_deletion())
	await get_tree().process_frame
	assert_false(is_instance_valid(native_adapter))
	_assert_published([])


func test_setup_immediately_publishes_existing_fractional_fuel() -> void:
	_fuel.current_fuel = 37.125
	_adapter.setup(_fuel)
	assert_true(_fuel.fuel_changed.is_connected(_adapter._on_fuel_changed))
	_assert_published([37.125])
	assert_eq(_fuel.current_fuel, 37.125, "Observing must not change fuel.")


func test_setup_publishes_zero_for_an_already_depleted_resource() -> void:
	_fuel.current_fuel = 0.0
	_adapter.setup(_fuel)
	_assert_published([0.0])


func test_resource_changes_publish_consumption_and_refueling_in_order() -> void:
	_adapter.setup(_fuel)
	_fuel.current_fuel = 75.5
	_fuel.current_fuel = 20.25
	_fuel.refuel(10.0)
	_assert_published([100.0, 75.5, 20.25, 30.25])


func test_duplicate_signal_emissions_do_not_repeat_browser_writes() -> void:
	_adapter.setup(_fuel)
	# Emit directly: the resource setter also deduplicates, which could mask a regression.
	for _index in range(3):
		_fuel.fuel_changed.emit(100.0)
	_fuel.current_fuel = 42.0
	for _index in range(3):
		_fuel.fuel_changed.emit(42.0)
	_assert_published([100.0, 42.0])


func test_returning_to_a_previous_value_is_not_suppressed() -> void:
	_adapter.setup(_fuel)
	_fuel.current_fuel = 25.0
	_fuel.current_fuel = 100.0
	_assert_published([100.0, 25.0, 100.0])


func test_small_fractional_changes_are_not_rounded_away() -> void:
	_fuel.current_fuel = 25.125
	_adapter.setup(_fuel)
	_fuel.current_fuel = 25.126
	_assert_published([25.125, 25.126])


func test_publishes_effective_clamped_values_at_both_boundaries() -> void:
	_adapter.setup(_fuel)
	_fuel.current_fuel = -10.0
	_fuel.current_fuel = -20.0
	_fuel.current_fuel = 200.0
	_fuel.current_fuel = 300.0
	_assert_published([100.0, 0.0, 100.0])


func test_lowering_capacity_publishes_the_new_effective_fuel() -> void:
	_adapter.setup(_fuel)
	_fuel.max_fuel = 40.0
	_assert_published([100.0, 40.0])


func test_null_setup_is_safe_without_an_existing_binding() -> void:
	_adapter.setup(null)
	_adapter.teardown()
	_assert_published([])


func test_null_setup_disconnects_previous_resource() -> void:
	_adapter.setup(_fuel)
	_adapter.setup(null)
	assert_false(_fuel.fuel_changed.is_connected(_adapter._on_fuel_changed))
	_fuel.current_fuel = 40.0
	_assert_published([100.0])


func test_rebinding_replaces_the_old_observer_and_primes_new_fuel() -> void:
	_adapter.setup(_fuel)
	var replacement := FuelResource.new()
	replacement.current_fuel = 15.5
	_adapter.setup(replacement)
	assert_false(_fuel.fuel_changed.is_connected(_adapter._on_fuel_changed))
	assert_true(replacement.fuel_changed.is_connected(_adapter._on_fuel_changed))
	_fuel.current_fuel = 1.0
	replacement.current_fuel = 10.0
	_assert_published([100.0, 15.5, 10.0])


func test_rebinding_equal_fuel_still_primes_the_new_connection() -> void:
	_adapter.setup(_fuel)
	var replacement := FuelResource.new()
	_adapter.setup(replacement)
	replacement.fuel_changed.emit(100.0)
	_assert_published([100.0, 100.0])


func test_repeated_setup_has_one_subscription_and_reprimes_each_time() -> void:
	_adapter.setup(_fuel)
	_adapter.setup(_fuel)
	assert_eq(_fuel.fuel_changed.get_connections().size(), 1)
	_fuel.current_fuel = 90.0
	_assert_published([100.0, 100.0, 90.0])


func test_teardown_is_repeatable_and_preserves_other_observers() -> void:
	var observed: Array[float] = []
	var other_observer := func(value: float) -> void: observed.append(value)
	_fuel.fuel_changed.connect(other_observer)
	_adapter.setup(_fuel)
	_adapter.teardown()
	_adapter.teardown()
	assert_false(_fuel.fuel_changed.is_connected(_adapter._on_fuel_changed))
	_fuel.current_fuel = 80.0
	assert_eq(observed, [80.0])
	_assert_published([100.0])
	_fuel.fuel_changed.disconnect(other_observer)


func test_teardown_tolerates_an_already_disconnected_signal() -> void:
	_adapter.setup(_fuel)
	_fuel.fuel_changed.disconnect(_adapter._on_fuel_changed)
	_adapter.teardown()
	_adapter.setup(_fuel)
	_assert_published([100.0, 100.0])


func test_setup_after_teardown_resets_duplicate_cache() -> void:
	_adapter.setup(_fuel)
	_adapter.teardown()
	_adapter.setup(_fuel)
	_fuel.fuel_changed.emit(100.0)
	_assert_published([100.0, 100.0])


func test_leaving_tree_disconnects_and_allows_binding_again() -> void:
	_adapter.setup(_fuel)
	remove_child(_adapter)
	assert_false(_fuel.fuel_changed.is_connected(_adapter._on_fuel_changed))
	_fuel.current_fuel = 55.0
	_assert_published([100.0])
	add_child(_adapter)
	_adapter.setup(_fuel)
	_assert_published([100.0, 55.0])

