## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_combined_multi_manager_loads.gd
## GUT unit tests for combined/multi-manager config loads/saves.
## Covers TC-SL-11 to TC-SL-15 from test plan.
## Test Plan: https://github.com/ikostan/SkyLockAssault/issues/295

extends "res://addons/gut/test.gd"

var test_config_path: String = "user://test_combined.cfg"


## Per-test setup: Reset AudioManager, Globals, InputMap; delete config.
## :rtype: void
func before_each() -> void:
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)
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
	# Reset Globals
	Globals.current_log_level = Globals.LogLevel.INFO
	Globals.difficulty = 1.0
	# Reset InputMap to defaults
	for action: String in Settings.ACTIONS:
		InputMap.action_erase_events(action)
		var default_key: int = Settings.DEFAULT_KEYBOARD[action]
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = default_key
		InputMap.action_add_event(action, ev)
	Settings._needs_migration = false  # Reset migration flag


## TC-SL-11 | Config with all sections (non-default audio, inputs, settings). | Call AudioManager.load_volumes(); Then Settings.load_input_mappings(); Then Globals._load_settings() | Each loads their section without affecting others; AudioManager gets "audio"; Settings gets "input"; Globals gets "Settings"; All apply correctly; No cross-overwrites.
## Updated for per-device unbound: partial input ["key:87"] loads keyboard only (gamepad unbound).
## :rtype: void
func test_tc_sl_11() -> void:
	var config: ConfigFile = ConfigFile.new()
	# Audio
	config.set_value("audio", "master_volume", 0.5)
	config.set_value("audio", "master_muted", true)
	# Inputs: Partial (keyboard only) - tests new per-device unbound (no auto-gamepad)
	config.set_value("input", "speed_up", ["key:87"])
	# Settings
	config.set_value("Settings", "log_level", Globals.LogLevel.WARNING)
	config.set_value("Settings", "difficulty", 1.5)
	config.save(test_config_path)
	# Load sequence
	AudioManager.load_volumes(test_config_path)
	Settings.load_input_mappings(test_config_path)
	Globals._load_settings(test_config_path)
	# Verify Audio
	assert_almost_eq(AudioManager.master_volume, 0.5, 0.01)
	assert_true(AudioManager.master_muted)
	# Verify Inputs: Only saved key (no gamepad - per-device unbound)
	var events: Array[InputEvent] = InputMap.action_get_events("speed_up")
	assert_eq(events.size(), 1)
	assert_true(events[0] is InputEventKey)
	assert_eq(events[0].physical_keycode, 87)
	# Verify Globals
	assert_eq(Globals.current_log_level, Globals.LogLevel.WARNING)
	assert_eq(Globals.difficulty, 1.5)
	# Config unchanged (no saves)
	var loaded_config: ConfigFile = ConfigFile.new()
	loaded_config.load(test_config_path)
	assert_almost_eq(loaded_config.get_value("audio", "master_volume"), 0.5, 0.01)
	assert_eq(loaded_config.get_value("input", "speed_up"), ["key:87"])
	assert_eq(loaded_config.get_value("Settings", "log_level"), Globals.LogLevel.WARNING)


## TC-SL-12 | Config with "audio" and "Settings"; Invalid in "Settings" (e.g., log_level="invalid"). | Call Globals._load_settings(); Then AudioManager.load_volumes() | Globals falls back to default log_level; Audio loads normally; No errors propagate; Logs warnings if applicable.
## :rtype: void
func test_tc_sl_12() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "music_volume", 0.7)
	config.set_value("Settings", "log_level", "invalid")  # Invalid type/string
	config.set_value("Settings", "difficulty", 1.5)
	config.save(test_config_path)
	# Initial Globals
	Globals.current_log_level = Globals.LogLevel.DEBUG
	# Load Globals first (should fallback for invalid log_level)
	Globals._load_settings(test_config_path)
	assert_eq(Globals.current_log_level, Globals.LogLevel.DEBUG)  # Keeps current or default? Code likely skips invalid, keeps current
	assert_eq(Globals.difficulty, 1.5)
	# Then load Audio
	AudioManager.load_volumes(test_config_path)
	assert_almost_eq(AudioManager.music_volume, 0.7, 0.01)
	# Config unchanged
	var loaded_config: ConfigFile = ConfigFile.new()
	loaded_config.load(test_config_path)
	assert_eq(loaded_config.get_value("Settings", "log_level"), "invalid")


## TC-SL-13 | Config with old-format inputs (int keycodes); No audio. | Call Settings.load_input_mappings() (sets _needs_migration=true, saves upgraded); Then AudioManager.save_volumes() | Inputs upgraded and saved; Then audio added without re-overwriting inputs; Config has upgraded "input" and new "audio".
## :rtype: void
func test_tc_sl_13() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "speed_up", 87)  # Old int format
	config.save(test_config_path)
	# Load inputs (should set _needs_migration)
	Settings.load_input_mappings(test_config_path)
	# Manually save if migration needed (since _ready() not re-called in test)
	if Settings._needs_migration:
		Settings.save_input_mappings(test_config_path)
		Settings._needs_migration = false
	# Verify migrated in InputMap
	var events: Array = InputMap.action_get_events("speed_up")
	assert_eq(events.size(), 2)
	assert_true(events[0] is InputEventKey)
	assert_eq(events[0].physical_keycode, 87)
	assert_true(events[1] is InputEventJoypadMotion)
	assert_eq(events[1].axis, JOY_AXIS_TRIGGER_RIGHT)
	assert_eq(events[1].axis_value, 1.0)
	assert_eq(events[1].device, -1)
	# Config upgraded
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_eq(config.get_value("input", "speed_up"), ["key:87", "joyaxis:5:1.0:-1"])  # Upgraded to array string with added gamepad default
	# Now save audio changes
	AudioManager.master_volume = 0.5
	AudioManager.save_volumes(test_config_path)
	# Verify config has audio added, inputs preserved
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_almost_eq(config.get_value("audio", "master_volume"), 0.5, 0.01)
	assert_eq(config.get_value("input", "speed_up"), ["key:87", "joyaxis:5:1.0:-1"])


## TC-SL-14 | Multiple saves: Config with all; Change audio, save; Change settings, save; Change inputs, save. | Sequence of saves from different managers | Each save loads existing, updates own section, saves; All sections preserved across calls; No data loss.
## :rtype: void
func test_tc_sl_14() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "speed_up", ["key:87"])
	config.set_value("Settings", "log_level", 1)
	config.set_value("Settings", "difficulty", 1.5)
	config.set_value("audio", "master_volume", 0.4)
	config.save(test_config_path)
	# Change audio and save
	AudioManager.master_volume = 0.5
	AudioManager.save_volumes(test_config_path)
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_almost_eq(config.get_value("audio", "master_volume"), 0.5, 0.01)
	assert_eq(config.get_value("Settings", "difficulty"), 1.5)
	assert_eq(config.get_value("input", "speed_up"), ["key:87"])
	# Change settings and save
	Globals.difficulty = 2.0
	Globals._save_settings(test_config_path)
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_almost_eq(config.get_value("audio", "master_volume"), 0.5, 0.01)
	assert_eq(config.get_value("Settings", "difficulty"), 2.0)
	assert_eq(config.get_value("input", "speed_up"), ["key:87"])
	# Change inputs and save (e.g., replace event to simulate remap)
	InputMap.action_erase_events("speed_up")
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = KEY_UP
	InputMap.action_add_event("speed_up", ev)
	Settings.save_input_mappings(test_config_path)
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_almost_eq(config.get_value("audio", "master_volume"), 0.5, 0.01)
	assert_eq(config.get_value("Settings", "difficulty"), 2.0)
	var serials: Array = config.get_value("input", "speed_up")
	assert_eq(serials.size(), 1)
	assert_eq(serials[0], "key:4194320")


## TC-SL-15 | Concurrent-like: Simulate rapid saves from audio then globals. | Call AudioManager.save_volumes(); Immediately Globals._save_settings() | No race (Godot single-threaded), but verify final config has both updates; No overwrites.
## :rtype: void
func test_tc_sl_15() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "speed_up", ["key:87"])
	config.set_value("Settings", "log_level", 1)
	config.set_value("Settings", "difficulty", 1.5)
	config.set_value("audio", "master_volume", 0.4)
	config.save(test_config_path)
	# Change audio and save
	AudioManager.master_volume = 0.5
	AudioManager.save_volumes(test_config_path)
	# Immediately change and save globals
	Globals.difficulty = 2.0
	Globals._save_settings(test_config_path)
	# Verify final config
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_almost_eq(config.get_value("audio", "master_volume"), 0.5, 0.01)
	assert_eq(config.get_value("Settings", "difficulty"), 2.0)
	assert_eq(config.get_value("input", "speed_up"), ["key:87"])
	assert_eq(config.get_value("Settings", "log_level"), 1)
