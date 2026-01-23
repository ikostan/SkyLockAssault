## test_preserve_other_sections.gd
## GUT unit tests for AudioManager save/load preserving other config sections.
## Covers TC-SL-06 to TC-SL-10 from test plan.
## Test Plan:
## https://github.com/ikostan/SkyLockAssault/issues/295

extends "res://addons/gut/test.gd"

var test_config_path: String = "user://settings.cfg"
var backup_path: String = "user://settings.backup.cfg"
var audio_scene: PackedScene = load("res://scenes/audio_settings.tscn")
var audio_instance: Control


## Per-test setup: Backup and delete real config, reset AudioManager, Globals.
## :rtype: void
func before_each() -> void:
	if FileAccess.file_exists(test_config_path):
		DirAccess.copy_absolute(test_config_path, backup_path)
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
	# Reset Globals settings
	Globals.current_log_level = Globals.LogLevel.INFO
	Globals.difficulty = 1.0
			

## Per-test cleanup: Free audio_instance safely.
## :rtype: void
func after_each() -> void:
	if is_instance_valid(audio_instance):
		if is_instance_valid(audio_instance.master_warning_dialog):
			audio_instance.master_warning_dialog.hide()
		if is_instance_valid(audio_instance.sfx_warning_dialog):
			audio_instance.sfx_warning_dialog.hide()
		remove_child(audio_instance)
		audio_instance.queue_free()
	audio_instance = null
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)
	await get_tree().process_frame


## TC-SL-06 | Config exists with "input" section (e.g., speed_up=["key:87"]); "Settings" (log_level=1, difficulty=1.5); No "audio". | Call AudioManager.save_volumes() with changes (e.g., sfx_volume=0.6) | "audio" section added with changes; "input" and "Settings" unchanged; Log "Saved volumes to config."
## :rtype: void
func test_tc_sl_06() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "speed_up", ["key:87"])
	config.set_value("Settings", "log_level", 1)
	config.set_value("Settings", "difficulty", 1.5)
	config.save(test_config_path)
	assert_true(FileAccess.file_exists(test_config_path))
	# Change AudioManager
	AudioManager.sfx_volume = 0.6
	AudioManager.save_volumes()
	# Verify config
	config = ConfigFile.new()
	config.load(test_config_path)
	var sections: Array = config.get_sections()
	assert_eq(sections.size(), 3)
	assert_true(config.has_section("audio"))
	assert_almost_eq(config.get_value("audio", "sfx_volume"), 0.6, 0.01)
	# Others unchanged
	assert_eq(config.get_value("input", "speed_up"), ["key:87"])
	assert_eq(config.get_value("Settings", "log_level"), 1)
	assert_eq(config.get_value("Settings", "difficulty"), 1.5)


## TC-SL-07 | Config with "input", "Settings", and "audio" (old audio values). | Call AudioManager.load_volumes() | Only audio vars updated from "audio" section; "input"/"Settings" ignored by AudioManager; Globals.current_log_level/difficulty unchanged; apply_all_volumes() called.
## :rtype: void
func test_tc_sl_07() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "speed_up", ["key:87"])
	config.set_value("Settings", "log_level", 1)
	config.set_value("Settings", "difficulty", 1.5)
	config.set_value("audio", "master_volume", 0.4)
	config.set_value("audio", "master_muted", true)
	config.save(test_config_path)
	# Set Globals to different values
	Globals.current_log_level = Globals.LogLevel.DEBUG
	Globals.difficulty = 2.0
	# Load audio only
	AudioManager.load_volumes()
	AudioManager.apply_all_volumes()
	# Audio updated
	assert_almost_eq(AudioManager.master_volume, 0.4, 0.01)
	assert_true(AudioManager.master_muted)
	# Globals unchanged (not loaded here)
	assert_eq(Globals.current_log_level, Globals.LogLevel.DEBUG)
	assert_eq(Globals.difficulty, 2.0)
	# Config unchanged
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_eq(config.get_value("input", "speed_up"), ["key:87"])
	assert_eq(config.get_value("Settings", "log_level"), 1)
	assert_eq(config.get_value("Settings", "difficulty"), 1.5)


## TC-SL-08 | Config with "input" and "Settings"; AudioManager changed. | Call AudioManager.save_volumes(); Then Globals._save_settings() | First save adds "audio", preserves others; Second adds/updates "Settings", preserves "audio"/"input"; No overwrites.
## :rtype: void
func test_tc_sl_08() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "speed_up", ["key:87"])
	config.set_value("Settings", "log_level", 1)
	config.set_value("Settings", "difficulty", 1.5)
	config.save(test_config_path)
	# Change AudioManager
	AudioManager.sfx_volume = 0.6
	AudioManager.save_volumes()
	# Verify after first save
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_almost_eq(config.get_value("audio", "sfx_volume"), 0.6, 0.01)
	assert_eq(config.get_value("input", "speed_up"), ["key:87"])
	assert_eq(config.get_value("Settings", "log_level"), 1)
	assert_eq(config.get_value("Settings", "difficulty"), 1.5)
	# Change Globals
	Globals.difficulty = 2.0
	Globals._save_settings()
	# Verify after second save
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_almost_eq(config.get_value("audio", "sfx_volume"), 0.6, 0.01)
	assert_eq(config.get_value("input", "speed_up"), ["key:87"])
	assert_eq(config.get_value("Settings", "log_level"), 1)
	assert_eq(config.get_value("Settings", "difficulty"), 2.0)


## TC-SL-09 | Config with all sections; Change audio via UI (e.g., toggle mute_sfx). | Simulate _on_mute_sfx_toggled(false); Await save | "audio" updated (sfx_muted=true); Other sections unchanged; Log "SFX mute button toggled to: false" and save.
## :rtype: void
func test_tc_sl_09() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "speed_up", ["key:87"])
	config.set_value("Settings", "log_level", 1)
	config.set_value("Settings", "difficulty", 1.5)
	config.set_value("audio", "sfx_muted", false)
	config.save(test_config_path)
	AudioManager.load_volumes()
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame
	# Simulate toggle to muted: set button_pressed = false (pressed=false means muted)
	audio_instance.mute_sfx.button_pressed = false
	await get_tree().process_frame
	# Verify audio updated
	assert_true(AudioManager.sfx_muted)
	# Config updated
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_true(config.get_value("audio", "sfx_muted"))
	# Others unchanged
	assert_eq(config.get_value("input", "speed_up"), ["key:87"])
	assert_eq(config.get_value("Settings", "log_level"), 1)
	assert_eq(config.get_value("Settings", "difficulty"), 1.5)


## TC-SL-10 | Config with all; Globals change log_level. | Call Globals._save_settings(); Then AudioManager.save_volumes() | "Settings" updated; Then "audio" preserved/updated without touching "Settings"; Sequence preserves all.
## :rtype: void
func test_tc_sl_10() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "speed_up", ["key:87"])
	config.set_value("Settings", "log_level", 1)
	config.set_value("Settings", "difficulty", 1.5)
	config.set_value("audio", "master_volume", 0.4)
	config.save(test_config_path)
	# Change Globals
	Globals.current_log_level = Globals.LogLevel.WARNING
	Globals._save_settings()
	# Verify after first save
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_eq(config.get_value("Settings", "log_level"), Globals.LogLevel.WARNING)
	assert_almost_eq(config.get_value("audio", "master_volume"), 0.4, 0.01)
	assert_eq(config.get_value("input", "speed_up"), ["key:87"])
	# Change AudioManager slightly
	AudioManager.master_volume = 0.5
	AudioManager.save_volumes()
	# Verify after second save
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_eq(config.get_value("Settings", "log_level"), Globals.LogLevel.WARNING)
	assert_almost_eq(config.get_value("audio", "master_volume"), 0.5, 0.01)
	assert_eq(config.get_value("input", "speed_up"), ["key:87"])
