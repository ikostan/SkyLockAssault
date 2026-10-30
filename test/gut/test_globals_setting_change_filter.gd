## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_globals_setting_change_filter.gd
##
## Issue #616: Globals._on_setting_changed must persist and log only persisted_schema keys.
## Runtime state on GameSettingsResource (fuel, speed, thresholds) must never trigger a
## settings.cfg write.
extends "res://addons/gut/test.gd"

const GlobalsScript = preload("res://scripts/core/globals.gd")

var _globals: Variant
var _original_schema: Dictionary


func before_each() -> void:
	_original_schema = GlobalsScript.persisted_schema
	GlobalsScript.persisted_schema = _original_schema.duplicate(true)
	# Outside the tree: no _ready(), no connection to the live Globals.settings.
	_globals = partial_double(GlobalsScript).new()
	autofree(_globals)
	stub(_globals, "_save_settings").to_do_nothing()
	stub(_globals, "log_message").to_do_nothing()
	_globals.settings = GameSettingsResource.new()


func after_each() -> void:
	GlobalsScript.persisted_schema = _original_schema


func test_each_persisted_key_saves_and_logs_once(
	prop: String = use_parameters(
		["current_log_level", "difficulty", "enable_debug_logging", "max_fuel", "show_fps"]
	)
) -> void:
	assert_true(GlobalsScript.persisted_schema.has(prop), "Parameter list matches the schema")
	_globals._on_setting_changed(prop, 1)
	assert_called_count(_globals._save_settings, 1)
	assert_called_count(_globals.log_message, 1)
	assert_called(
		_globals.log_message.bind("Setting '%s' updated to: 1" % prop, Globals.LogLevel.DEBUG)
	)


func test_runtime_properties_never_save_or_log(
	prop: String = use_parameters(
		[
			"current_fuel",
			"max_speed",
			"min_speed",
			"lateral_speed",
			"acceleration",
			"deceleration",
			"high_fuel_threshold",
			"no_fuel_threshold",
			"high_yellow_fraction",
		]
	)
) -> void:
	assert_false(GlobalsScript.persisted_schema.has(prop), "Parameter must be runtime-only")
	_globals._on_setting_changed(prop, 1.0)
	assert_not_called(_globals._save_settings)
	assert_not_called(_globals.log_message)


func test_unknown_setting_name_is_ignored() -> void:
	_globals._on_setting_changed("not_a_setting", true)
	assert_not_called(_globals._save_settings)
	assert_not_called(_globals.log_message)


func test_filter_follows_schema_extensions() -> void:
	# The filter is schema-driven: making a property persisted makes it save, with no
	# other code change.
	GlobalsScript.persisted_schema["max_speed"] = {"key": "max_speed", "types": [TYPE_FLOAT]}
	_globals._on_setting_changed("max_speed", 500.0)
	assert_called_count(_globals._save_settings, 1)


func test_resource_signals_end_to_end_save_only_for_persisted_changes() -> void:
	_globals.settings.setting_changed.connect(_globals._on_setting_changed)
	# Simulates one minute of fuel ticks plus speed changes during flight.
	for i: int in range(60):
		_globals.settings.current_fuel = 100.0 - i
	_globals.settings.max_speed = 600.0
	assert_not_called(_globals._save_settings)
	_globals.settings.difficulty = 1.5
	_globals.settings.show_fps = true
	assert_called_count(_globals._save_settings, 2)
	_globals.settings.setting_changed.disconnect(_globals._on_setting_changed)


func test_log_level_change_does_not_touch_js_bridge_on_native() -> void:
	if OS.has_feature("web"):
		pass_test("Native-only check")
		return
	var bridge: Variant = double(JavaScriptBridgeWrapper).new()
	stub(bridge, "eval").to_return(null)
	_globals.js_bridge_wrapper = bridge
	_globals._on_setting_changed("current_log_level", 0)
	assert_not_called(bridge, "eval")
	assert_called_count(_globals._save_settings, 1)
