## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_fuel_ui_gut.gd
## Unit tests for UI reactivity to fuel updates.
extends "res://addons/gut/test.gd"

## test_ui_updates_on_fuel_change_signal | Validate UI reacts to fuel updates
## Observes a local FuelResource (the source of truth since #1142), so no global state
## is touched and no listener outlives the test.
## :rtype: void
func test_ui_updates_on_fuel_change_signal() -> void:
	gut.p("Testing: UI Progressbar reflects resource value via signal.")
	var fuel_bar: ProgressBar = ProgressBar.new()
	add_child_autofree(fuel_bar)
	var fuel: FuelResource = FuelResource.new()
	
	# Connect UI to the fuel observer
	fuel.fuel_changed.connect(func(val: float) -> void:
		fuel_bar.value = val
	)
	
	fuel.current_fuel = 45.5
	assert_eq(fuel_bar.value, 45.5, "UI failed to update from fuel signal")
