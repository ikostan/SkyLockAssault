## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_fuel_ui_gut.gd
## Unit tests for UI reactivity to fuel updates.
extends "res://addons/gut/test.gd"

## test_ui_updates_on_fuel_change_signal | Validate UI reacts to fuel updates
## :rtype: void
func test_ui_updates_on_fuel_change_signal() -> void:
	gut.p("Testing: UI Progressbar reflects resource value via signal.")
	var fuel_bar: ProgressBar = ProgressBar.new()
	add_child_autofree(fuel_bar)
	
	# Connect UI to the settings observer
	Globals.settings.setting_changed.connect(func(name: String, val: Variant) -> void:
		if name == "current_fuel":
			fuel_bar.value = float(val)
	)
	
	Globals.settings.current_fuel = 45.5
	assert_eq(fuel_bar.value, 45.5, "UI failed to update from fuel signal")
