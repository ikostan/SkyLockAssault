## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## Regression coverage for the table-driven Globals settings persistence contract.
extends "res://addons/gut/test.gd"

const GlobalsScript = preload("res://scripts/core/globals.gd")
const TEST_PATH: String = "user://test_globals_settings_serialization.cfg"
const TEST_KEY: String = "settings-schema-unit-test-key"
# Keep the compatibility oracle independent of persisted_schema, including the log_level alias.
const DISK_VALUES: Dictionary = {
	"log_level": 3,
	"difficulty": 1.75,
	"enable_debug_logging": true,
	"max_fuel": 240.5,
	"show_fps": true,
}

var _globals: Variant
var _config: ConfigFile
var _original_schema: Dictionary


func before_each() -> void:
	_original_schema = GlobalsScript.persisted_schema
	GlobalsScript.persisted_schema = _original_schema.duplicate(true)
	# No _ready(), singleton replacement, or connection to the user's live settings.
	_globals = partial_double(GlobalsScript).new()
	autofree(_globals)
	_globals.settings = GameSettingsResource.new()
	_globals.settings.current_log_level = 2
	_globals.settings.difficulty = 1.25
	_globals.settings.max_fuel = 175.0
	_config = ConfigFile.new()
	stub(_globals, "safe_load_config").to_return(
		{"config": _config, "err": OK, "is_legacy": false}
	)
	stub(_globals, "log_message").to_do_nothing()
	stub(_globals, "ensure_encryption_key").to_return(TEST_KEY)
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func after_each() -> void:
	GlobalsScript.persisted_schema = _original_schema
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func _populate_config(values: Dictionary) -> void:
	for key: String in values:
		_config.set_value("Settings", key, values[key])


func _snapshot() -> Dictionary:
	return {
		"log_level": _globals.settings.current_log_level,
		"difficulty": _globals.settings.difficulty,
		"enable_debug_logging": _globals.settings.enable_debug_logging,
		"max_fuel": _globals.settings.max_fuel,
		"show_fps": _globals.settings.show_fps,
	}


func _read_saved_config() -> ConfigFile:
	var saved := ConfigFile.new()
	assert_eq(saved.load_encrypted_pass(TEST_PATH, TEST_KEY), OK)
	return saved


func test_load_applies_every_legacy_disk_key() -> void:
	_populate_config(DISK_VALUES)
	_globals._load_settings(TEST_PATH)
	assert_eq(_snapshot(), DISK_VALUES)
	assert_false(_globals._is_loading_settings)


func test_load_accepts_each_log_level_including_boundaries(
	level: int = use_parameters([0, 1, 2, 3, 4])
) -> void:
	_config.set_value("Settings", "log_level", level)
	_globals._load_settings(TEST_PATH)
	assert_eq(_globals.settings.current_log_level, level)


func test_load_rejects_out_of_range_log_levels_without_clamping(
	level: int = use_parameters([-1, 5, -100, 100])
) -> void:
	_config.set_value("Settings", "log_level", level)
	watch_signals(_globals.settings)
	_globals._load_settings(TEST_PATH)
	assert_eq(_globals.settings.current_log_level, 2, "Keep the current value, not a boundary")
	assert_signal_not_emitted(_globals.settings, "setting_changed")
	assert_false(_globals._is_loading_settings)


func test_load_casts_legacy_integers_for_both_float_properties() -> void:
	_populate_config({"difficulty": 2, "max_fuel": 225})
	_globals._load_settings(TEST_PATH)
	assert_eq(_globals.settings.difficulty, 2.0)
	assert_eq(typeof(_globals.settings.difficulty), TYPE_FLOAT)
	assert_eq(_globals.settings.max_fuel, 225.0)
	assert_eq(typeof(_globals.settings.max_fuel), TYPE_FLOAT)


func test_load_accepts_both_boolean_values(value: bool = use_parameters([false, true])) -> void:
	_globals.settings.enable_debug_logging = not value
	_globals.settings.show_fps = not value
	_populate_config({"enable_debug_logging": value, "show_fps": value})
	_globals._load_settings(TEST_PATH)
	assert_eq(_globals.settings.enable_debug_logging, value)
	assert_eq(_globals.settings.show_fps, value)


func test_load_rejects_wrong_types_before_resource_setters_can_coerce_them(
	case: Array = use_parameters([
		["log_level", 4.0], ["log_level", "4"], ["log_level", true],
		["difficulty", "2.0"], ["difficulty", true], ["difficulty", [1.5]],
		["max_fuel", "250"], ["max_fuel", false], ["max_fuel", {"value": 250}],
		["enable_debug_logging", 1], ["enable_debug_logging", 0],
		["enable_debug_logging", 1.0], ["enable_debug_logging", "true"],
		["show_fps", 1], ["show_fps", 0], ["show_fps", 0.0],
		["show_fps", "false"], ["show_fps", []],
	])
) -> void:
	# Seed true as well, so falsy but invalid values cannot silently turn flags off.
	_globals.settings.enable_debug_logging = true
	_globals.settings.show_fps = true
	var before := _snapshot()
	_config.set_value("Settings", case[0], case[1])
	watch_signals(_globals.settings)
	_globals._load_settings(TEST_PATH)
	assert_eq(_snapshot(), before, "Invalid value must preserve the existing settings")
	assert_signal_not_emitted(_globals.settings, "setting_changed")


func test_load_missing_section_preserves_current_values() -> void:
	var before := _snapshot()
	_config.set_value("audio", "difficulty", 2.0)
	_globals._load_settings(TEST_PATH)
	assert_eq(_snapshot(), before)


func test_load_partial_config_changes_only_present_keys() -> void:
	var expected := _snapshot()
	expected["show_fps"] = true
	_config.set_value("Settings", "show_fps", true)
	_globals._load_settings(TEST_PATH)
	assert_eq(_snapshot(), expected)


func test_invalid_entries_do_not_prevent_later_valid_entries_loading() -> void:
	_populate_config({
		"log_level": 5, "difficulty": "bad", "enable_debug_logging": true,
		"max_fuel": [], "show_fps": true,
	})
	_globals._load_settings(TEST_PATH)
	assert_eq(_snapshot(), {
		"log_level": 2, "difficulty": 1.25, "enable_debug_logging": true,
		"max_fuel": 175.0, "show_fps": true,
	})
	assert_false(_globals._is_loading_settings)


func test_load_ignores_unknown_keys_resource_names_and_wrong_section_case() -> void:
	var before := _snapshot()
	_populate_config({"current_log_level": 4, "current_fuel": 0.0, "future_option": true})
	_config.set_value("settings", "difficulty", 2.0)
	_globals._load_settings(TEST_PATH)
	assert_eq(_snapshot(), before)
	assert_eq(_globals.settings.current_fuel, 100.0)


func test_load_still_uses_resource_validation_for_unbounded_schema_fields(
	case: Array = use_parameters([[-10.0, 0.0, 0.5, 1.0], [8.0, 400.5, 2.0, 400.5]])
) -> void:
	_populate_config({"difficulty": case[0], "max_fuel": case[1]})
	_globals._load_settings(TEST_PATH)
	assert_eq(_globals.settings.difficulty, case[2])
	assert_eq(_globals.settings.max_fuel, case[3])


func test_bulk_load_suppresses_observer_saves_and_restores_observer_afterward() -> void:
	stub(_globals, "_save_settings").to_do_nothing()
	_globals.settings.setting_changed.connect(_globals._on_setting_changed)
	var guards: Array[bool] = []
	_globals.settings.setting_changed.connect(
		func(_name: String, _value: Variant) -> void:
			guards.append(_globals._is_loading_settings)
	)
	_populate_config(DISK_VALUES)
	_globals._load_settings(TEST_PATH)
	assert_eq(guards.size(), 5, "Exercise every persisted setter")
	assert_false(guards.has(false), "Guard must cover the entire schema loop")
	assert_not_called(_globals._save_settings)
	# Only the completion message is allowed; observer mutation logs are suppressed.
	assert_called_count(_globals.log_message, 1)
	assert_false(_globals._is_loading_settings)
	_globals.settings.show_fps = false
	assert_called_count(_globals._save_settings, 1)


func test_load_schema_extension_honors_alias_cast_and_optional_bounds(
	case: Array = use_parameters([[100, 100.0], [900, 900.0], [99, 713.0], [901, 713.0]])
) -> void:
	# An existing non-persisted property becomes persistable with only a schema entry.
	GlobalsScript.persisted_schema["max_speed"] = {
		"key": "speed_limit", "types": [TYPE_INT, TYPE_FLOAT],
		"cast": TYPE_FLOAT, "min": 100.0, "max": 900.0,
	}
	_config.set_value("Settings", "speed_limit", case[0])
	_globals._load_settings(TEST_PATH)
	assert_eq(_globals.settings.max_speed, case[1])


func test_load_missing_resource_property_is_skipped_without_aborting() -> void:
	GlobalsScript.persisted_schema = {
		"removed_property": {"key": "old_option", "types": [TYPE_INT]},
	}
	GlobalsScript.persisted_schema.merge(_original_schema)
	_populate_config(DISK_VALUES)
	_config.set_value("Settings", "old_option", 42)
	_globals._load_settings(TEST_PATH)
	assert_eq(_snapshot(), DISK_VALUES)
	assert_false(_globals._is_loading_settings)
	assert_called(_globals.log_message.bind(
		"Schema error: 'removed_property' is not a GameSettingsResource property.",
		Globals.LogLevel.ERROR
	))


func test_failed_load_does_not_apply_config_or_save(
	error: int = use_parameters([ERR_FILE_NOT_FOUND, ERR_PARSE_ERROR, ERR_FILE_CANT_OPEN])
) -> void:
	var before := _snapshot()
	_populate_config(DISK_VALUES)
	stub(_globals, "safe_load_config").to_return(
		{"config": _config, "err": error, "is_legacy": false}
	)
	stub(_globals, "_save_settings").to_do_nothing()
	_globals._load_settings(TEST_PATH)
	assert_eq(_snapshot(), before)
	assert_not_called(_globals._save_settings)
	assert_false(_globals._is_loading_settings)


func test_save_writes_all_compatible_keys_and_excludes_runtime_properties() -> void:
	var expected := _snapshot()
	_globals._save_settings(TEST_PATH)
	var saved := _read_saved_config()
	assert_eq(saved.get_sections(), PackedStringArray(["Settings"]))
	assert_eq(saved.get_section_keys("Settings").size(), 5)
	for key: String in expected:
		assert_eq(saved.get_value("Settings", key), expected[key], key)
	assert_false(saved.has_section_key("Settings", "current_log_level"))
	assert_false(saved.has_section_key("Settings", "current_fuel"))


func test_save_preserves_other_managers_and_unknown_settings() -> void:
	_config.set_value("audio", "master_volume", 0.375)
	_config.set_value("audio", "mute", true)
	_config.set_value("input", "fire", ["key:77", "joybtn:0:-1"])
	_config.set_value("input", "pause", [])
	_config.set_value("future_section", "options", {"enabled": true})
	_config.set_value("Settings", "future_option", "keep me")
	_config.set_value("Settings", "difficulty", 0.5)
	_globals._save_settings(TEST_PATH)
	var saved := _read_saved_config()
	assert_eq(saved.get_value("audio", "master_volume"), 0.375)
	assert_eq(saved.get_value("audio", "mute"), true)
	assert_eq(saved.get_value("input", "fire"), ["key:77", "joybtn:0:-1"])
	assert_eq(saved.get_value("input", "pause"), [], "Explicitly unbound inputs survive")
	assert_eq(saved.get_value("future_section", "options"), {"enabled": true})
	assert_eq(saved.get_value("Settings", "future_option"), "keep me")
	assert_eq(saved.get_value("Settings", "difficulty"), 1.25)


func test_save_schema_extension_uses_disk_alias() -> void:
	GlobalsScript.persisted_schema["max_speed"] = {"key": "speed_limit", "types": [TYPE_FLOAT]}
	_globals.settings.max_speed = 850.5
	_globals._save_settings(TEST_PATH)
	var saved := _read_saved_config()
	assert_eq(saved.get_value("Settings", "speed_limit"), 850.5)
	assert_false(saved.has_section_key("Settings", "max_speed"))


func test_save_missing_resource_property_does_not_erase_existing_key() -> void:
	GlobalsScript.persisted_schema = {
		"removed_property": {"key": "old_option", "types": [TYPE_INT]},
	}
	GlobalsScript.persisted_schema.merge(_original_schema)
	_config.set_value("Settings", "old_option", 42)
	_globals._save_settings(TEST_PATH)
	var saved := _read_saved_config()
	assert_eq(saved.get_value("Settings", "old_option"), 42, "A null get must not erase data")
	assert_eq(saved.get_value("Settings", "show_fps"), false, "Later properties still save")


func test_save_preserves_loading_guard(loading: bool = use_parameters([false, true])) -> void:
	_globals._is_loading_settings = loading
	_globals._save_settings(TEST_PATH)
	assert_eq(_globals._is_loading_settings, loading)
	assert_eq(_read_saved_config().get_value("Settings", "difficulty"), 1.25)


func test_encrypted_save_load_round_trip() -> void:
	# Exercise real ConfigFile boundaries in addition to the in-memory loading cases.
	# GUT validates the typed return even when delegating to the real implementation.
	stub(_globals, "safe_load_config").to_return({}).to_call_super()
	_globals.settings.current_log_level = 3
	_globals.settings.difficulty = 1.75
	_globals.settings.enable_debug_logging = true
	_globals.settings.max_fuel = 240.5
	_globals.settings.show_fps = true
	_globals._save_settings(TEST_PATH)
	_globals.settings = GameSettingsResource.new()
	_globals._load_settings(TEST_PATH)
	assert_eq(_snapshot(), DISK_VALUES)


func test_plaintext_migration_applies_schema_and_preserves_other_sections() -> void:
	_populate_config(DISK_VALUES)
	_config.set_value("Settings", "log_level", 5)  # Reject, then persist the retained value.
	_config.set_value("input", "fire", [])
	_config.set_value("audio", "master_volume", 0.25)
	assert_eq(_config.save(TEST_PATH), OK)
	# GUT validates the typed return even when delegating to the real implementation.
	stub(_globals, "safe_load_config").to_return({}).to_call_super()
	_globals._load_settings(TEST_PATH)
	var saved := _read_saved_config()
	var expected: Dictionary = DISK_VALUES.duplicate()
	expected["log_level"] = 2
	assert_eq(_snapshot(), expected)
	for key: String in expected:
		assert_eq(saved.get_value("Settings", key), expected[key], key)
	assert_eq(saved.get_value("input", "fire"), [])
	assert_eq(saved.get_value("audio", "master_volume"), 0.25)
	assert_called_count(_globals._save_settings, 1)
	assert_called(_globals._save_settings.bind(TEST_PATH))
	assert_false(_globals._is_loading_settings)
