## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## Regression tests for removing the legacy fuel special case in Globals.
extends "res://addons/gut/test.gd"

const GlobalsScript = preload("res://scripts/core/globals.gd")

var _globals: Variant


func before_each() -> void:
	# Keep this instance outside the tree so _ready does not load or connect global settings.
	_globals = partial_double(GlobalsScript).new()
	autofree(_globals)
	stub(_globals, "_save_settings").to_do_nothing()
	stub(_globals, "log_message").to_do_nothing()
	_globals.settings = GameSettingsResource.new()


func test_legacy_fuel_notification_uses_normal_settings_persistence() -> void:
	_globals._on_setting_changed("current_fuel", 42.5)
	assert_called_count(_globals._save_settings, 1)
	assert_called(
		_globals.log_message.bind("Setting 'current_fuel' updated to: 42.5", Globals.LogLevel.DEBUG)
	)


func test_bulk_loading_still_suppresses_fuel_side_effects() -> void:
	_globals._is_loading_settings = true
	_globals._on_setting_changed("current_fuel", 0.0)
	assert_not_called(_globals._save_settings)
	assert_not_called(_globals.log_message)


func test_fuel_notifications_resume_after_bulk_loading() -> void:
	_globals._is_loading_settings = true
	_globals._on_setting_changed("current_fuel", 20.0)
	_globals._is_loading_settings = false
	_globals._on_setting_changed("current_fuel", 10.0)
	assert_called_count(_globals._save_settings, 1)
	assert_called_count(_globals.log_message, 1)
	assert_called(
		_globals.log_message.bind("Setting 'current_fuel' updated to: 10.0", Globals.LogLevel.DEBUG)
	)
