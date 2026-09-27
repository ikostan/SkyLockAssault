## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## web_telemetry_adapter.gd
## Dedicated telemetry adapter for WebGL E2E testing synchronization.
## Acts as a strict observer of FuelResource to push DOM updates to window.currentFuel.

extends Node

var os_wrapper: OSWrapper = OSWrapper.new()
var js_bridge_wrapper: JavaScriptBridgeWrapper = JavaScriptBridgeWrapper.new()

var _fuel_resource: Resource = null
var _last_fuel_value: float = -1.0


func _ready() -> void:
	# Self-destruct immediately if not running in a Web environment.
	# This ensures zero overhead on native desktop/console builds.
	if not os_wrapper.has_feature("web"):
		queue_free()
		return


## Safely binds the adapter to a specific FuelResource instance.
func setup(resource: Resource) -> void:
	# Clear any existing connections first to prevent memory leaks
	teardown()

	if not is_instance_valid(resource):
		return

	_fuel_resource = resource
	if not _fuel_resource.is_connected("fuel_changed", _on_fuel_changed):
		_fuel_resource.connect("fuel_changed", _on_fuel_changed)
		
		# Prime the DOM with the current value immediately upon connection
		_on_fuel_changed(_fuel_resource.current_fuel)


## Safely unbinds the adapter from the currently observed FuelResource.
func teardown() -> void:
	if (
		is_instance_valid(_fuel_resource)
		and _fuel_resource.is_connected("fuel_changed", _on_fuel_changed)
	):
		_fuel_resource.disconnect("fuel_changed", _on_fuel_changed)
	_fuel_resource = null
	_last_fuel_value = -1.0  # Reset cache


func _exit_tree() -> void:
	teardown()


## Signal listener for FuelResource updates.
## Pushes the effective value to the browser's DOM for Playwright assertions.
func _on_fuel_changed(new_value: float) -> void:
	# Guard: Unchanged fuel values do not produce redundant browser telemetry updates.
	if new_value == _last_fuel_value:
		return

	_last_fuel_value = new_value
	js_bridge_wrapper.eval("window.currentFuel = " + JSON.stringify(new_value))
