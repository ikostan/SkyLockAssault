## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_error_edge_cases.gd
## GUT unit tests for AudioManager error/edge cases in save/load.
## Covers TC-SL-21 to TC-SL-25 from test plan.
## Test Plan:
## https://github.com/ikostan/SkyLockAssault/issues/295

extends "res://addons/gut/test.gd"

var test_config_path: String = "user://test_edge.cfg"
var invalid_path: String = "res://invalid/unwritable.cfg"  # Simulate unwritable
var corrupted_path: String = "user://corrupted.cfg"


## Per-test setup: Reset AudioManager to defaults, delete test files.
## :rtype: void
func before_each() -> void:
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)
	if FileAccess.file_exists(corrupted_path):
		DirAccess.remove_absolute(corrupted_path)
	AudioManager.current_config_path = test_config_path
	AudioManager._init_to_defaults()
	AudioManager.apply_all_volumes()
	# Add audio buses if not exist
	if AudioServer.get_bus_index(AudioConstants.BUS_MASTER) == -1:
		AudioServer.add_bus(0)
		AudioServer.set_bus_name(0, AudioConstants.BUS_MASTER)
	if AudioServer.get_bus_index(AudioConstants.BUS_MUSIC) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, AudioConstants.BUS_MUSIC)
	if AudioServer.get_bus_index(AudioConstants.BUS_SFX) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, AudioConstants.BUS_SFX)
	if AudioServer.get_bus_index(AudioConstants.BUS_SFX_WEAPON) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, AudioConstants.BUS_SFX_WEAPON)
	if AudioServer.get_bus_index(AudioConstants.BUS_SFX_ROTORS) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, AudioConstants.BUS_SFX_ROTORS)
	# Reset migration flag
	Settings._needs_migration = false


## TC-SL-21 | Config path invalid/unwritable (simulate via temp path or mock). | Call AudioManager.save_volumes() | Error logged (e.g., "Failed to save config"); No crash; AudioManager unchanged.
## :rtype: void
func test_tc_sl_21() -> void:
	AudioManager.master_volume = 0.5  # Change to check unchanged
	AudioManager.current_config_path = invalid_path
	AudioManager.save_volumes()  # Should fail silently with log
	assert_false(FileAccess.file_exists(invalid_path))
	assert_eq(AudioManager.master_volume, 0.5)  # Unchanged


## TC-SL-23 | Config with unknown sections/keys (e.g., "random" section). | Call save_volumes() or other saves | Unknown preserved (since load/set/save doesn't touch them); No deletion.
## :rtype: void
func test_tc_sl_23() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("random", "unknown_key", "value")
	config.set_value("audio", "master_volume", 0.5)
	config.save(test_config_path)
	# Save audio (should preserve random)
	AudioManager.master_volume = 0.6
	AudioManager.save_volumes()
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_eq(config.get_value("audio", "master_volume"), 0.6)
	assert_eq(config.get_value("random", "unknown_key"), "value")
	# Similar for other saves
	Globals.difficulty = 2.0
	Globals._save_settings()
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_eq(config.get_value("random", "unknown_key"), "value")


## TC-SL-24 | No config; Load all. | Call load_volumes(), load_input_mappings(), _load_settings() | Each handles NOT_FOUND gracefully; Defaults used; Logs info/warnings as per code.
## :rtype: void
func test_tc_sl_24() -> void:
	assert_false(FileAccess.file_exists(test_config_path))
	# Change to non-defaults to check keep on NOT_FOUND
	AudioManager.master_volume = 0.5
	Globals.difficulty = 2.0
	# Load all
	AudioManager.load_volumes()
	Settings.load_input_mappings(test_config_path)
	Globals._load_settings(test_config_path)
	# Verify keeps current (per updated code: skips on NOT_FOUND)
	assert_eq(AudioManager.master_volume, 0.5)
	assert_eq(Globals.difficulty, 2.0)


## TC-SL-25 | Migration needed (old inputs); Save audio after. | Load inputs (migrate and save); Then save_volumes() | Migration saves upgraded inputs; Audio save preserves them; No re-migration.
## :rtype: void
func test_tc_sl_25() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "speed_up", 87)  # Old int
	config.save(test_config_path)
	# Load inputs (migrate)
	Settings.load_input_mappings(test_config_path)
	# Manually save if migration (since no _ready in test)
	if Settings._needs_migration:
		Settings.save_input_mappings(test_config_path)
		Settings._needs_migration = false
	# Verify upgraded
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_eq(config.get_value("input", "speed_up"), ["key:87", "joyaxis:5:1.0:-1"])
	# Save audio after
	AudioManager.master_volume = 0.5
	AudioManager.save_volumes(test_config_path)
	# Verify preserves upgraded inputs
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_eq(config.get_value("input", "speed_up"), ["key:87", "joyaxis:5:1.0:-1"])
	assert_eq(config.get_value("audio", "master_volume"), 0.5)
	# No re-migration
	assert_false(Settings._needs_migration)
