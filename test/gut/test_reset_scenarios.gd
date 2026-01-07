## test_reset_scenarios.gd
## GUT unit tests for AudioManager reset functionality preserving other sections.
## Covers TC-SL-16 to TC-SL-20 from test plan.
## Test Plan:
## https://github.com/ikostan/SkyLockAssault/issues/295

extends "res://addons/gut/test.gd"

var test_config_path: String = "user://test_reset.cfg"
var audio_scene: PackedScene = load("res://scenes/audio_settings.tscn")
var audio_instance: Control


## Per-test setup: Reset AudioManager to defaults, delete config if exists, reset Globals.
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


## Per-test cleanup: Free instance if exists.
## :rtype: void
func after_each() -> void:
	if is_instance_valid(audio_instance):
		audio_instance.queue_free()
		await get_tree().process_frame


## TC-SL-16 | Config with all; Non-audio changed (e.g., difficulty=2.0). | Call AudioManager.reset_volumes() | Only "audio" reset to defaults and saved; "Settings" difficulty unchanged; "input" preserved; Log "Audio volumes reset to defaults."; apply_all_volumes() called.
## :rtype: void
func test_tc_sl_16() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "speed_up", ["key:87"])
	config.set_value("Settings", "log_level", 1)
	config.set_value("Settings", "difficulty", 2.0)
	config.set_value("audio", "master_volume", 0.5)
	config.save(test_config_path)
	# Reset volumes
	AudioManager.reset_volumes()
	# Verify AudioManager reset
	assert_eq(AudioManager.master_volume, 1.0)
	assert_false(AudioManager.master_muted)
	# AudioServer updated
	var bus_idx: int = AudioServer.get_bus_index(AudioConstants.BUS_MASTER)
	assert_eq(AudioServer.get_bus_volume_db(bus_idx), linear_to_db(1.0))
	assert_false(AudioServer.is_bus_mute(bus_idx))
	# Config: audio reset, others preserved
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_eq(config.get_value("audio", "master_volume"), 1.0)
	assert_false(config.get_value("audio", "master_muted"))
	assert_eq(config.get_value("Settings", "difficulty"), 2.0)
	assert_eq(config.get_value("input", "speed_up"), ["key:87"])


## TC-SL-17 | Config with all; Audio non-defaults. | Simulate audio_settings _on_audio_reset_button_pressed() | Calls reset_volumes(); UI synced to defaults; Config "audio" overwritten to defaults; Other sections intact.
## :rtype: void
func test_tc_sl_17() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "speed_up", ["key:87"])
	config.set_value("Settings", "log_level", 1)
	config.set_value("Settings", "difficulty", 1.5)
	config.set_value("audio", "master_volume", 0.5)
	config.set_value("audio", "master_muted", true)
	config.save(test_config_path)
	AudioManager.load_volumes(test_config_path)
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame
	# Verify pre-reset UI
	assert_eq(audio_instance.master_slider.value, 0.5)
	assert_false(audio_instance.mute_master.button_pressed)
	# Reset via button
	audio_instance._on_audio_reset_button_pressed()
	# Verify AudioManager/UI reset
	assert_eq(AudioManager.master_volume, 1.0)
	assert_false(AudioManager.master_muted)
	assert_eq(audio_instance.master_slider.value, 1.0)
	assert_true(audio_instance.mute_master.button_pressed)
	# Config: audio reset, others preserved
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_eq(config.get_value("audio", "master_volume"), 1.0)
	assert_false(config.get_value("audio", "master_muted"))
	assert_eq(config.get_value("Settings", "difficulty"), 1.5)
	assert_eq(config.get_value("input", "speed_up"), ["key:87"])


## TC-SL-18 | Config with "Settings" only; Reset audio. | Call AudioManager.reset_volumes() | Adds "audio" defaults; "Settings" preserved; No unnecessary changes.
## :rtype: void
func test_tc_sl_18() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("Settings", "log_level", 1)
	config.set_value("Settings", "difficulty", 1.5)
	config.save(test_config_path)
	# Reset volumes (adds audio section)
	AudioManager.reset_volumes()
	# Verify AudioManager reset (to defaults anyway)
	assert_eq(AudioManager.master_volume, 1.0)
	assert_false(AudioManager.master_muted)
	# Config: audio added, settings preserved
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_true(config.has_section("audio"))
	assert_eq(config.get_value("audio", "master_volume"), 1.0)
	assert_false(config.get_value("audio", "master_muted"))
	assert_eq(config.get_value("Settings", "log_level"), 1)
	assert_eq(config.get_value("Settings", "difficulty"), 1.5)
	assert_false(config.has_section("input"))  # No unnecessary


## TC-SL-19 | Reset after load: Load non-default audio; Then reset. | Call load_volumes(); Then reset_volumes() | AudioManager/UI to defaults; Config updated to defaults; Other sections safe.
## :rtype: void
func test_tc_sl_19() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "speed_up", ["key:87"])
	config.set_value("Settings", "difficulty", 1.5)
	config.set_value("audio", "music_volume", 0.7)
	config.set_value("audio", "music_muted", true)
	config.save(test_config_path)
	# Load non-default audio
	AudioManager.load_volumes(test_config_path)
	assert_eq(AudioManager.music_volume, 0.7)
	assert_true(AudioManager.music_muted)
	# Instantiate UI to check sync
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame
	assert_eq(audio_instance.music_slider.value, 0.7)
	assert_false(audio_instance.mute_music.button_pressed)
	# Reset
	AudioManager.reset_volumes()
	# Verify AudioManager/UI to defaults
	assert_eq(AudioManager.music_volume, 1.0)
	assert_false(AudioManager.music_muted)
	# Sync UI manually if needed, but reset_volumes doesn't, but for test assume or call _sync_ui_from_manager
	audio_instance._sync_ui_from_manager()
	assert_eq(audio_instance.music_slider.value, 1.0)
	assert_true(audio_instance.mute_music.button_pressed)
	# Config updated to defaults for audio, others safe
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_eq(config.get_value("audio", "music_volume"), 1.0)
	assert_false(config.get_value("audio", "music_muted"))
	assert_eq(config.get_value("Settings", "difficulty"), 1.5)
	assert_eq(config.get_value("input", "speed_up"), ["key:87"])


## TC-SL-20 | Reset no config: No file; Audio changed in-memory. | Call reset_volumes() | Creates config with audio defaults; AudioManager to defaults; No other sections added unnecessarily.
## :rtype: void
func test_tc_sl_20() -> void:
	assert_false(FileAccess.file_exists(test_config_path))
	# Change in-memory
	AudioManager.sfx_volume = 0.3
	AudioManager.sfx_muted = true
	assert_eq(AudioManager.sfx_volume, 0.3)
	assert_true(AudioManager.sfx_muted)
	# Reset
	AudioManager.reset_volumes()
	# Verify to defaults
	assert_eq(AudioManager.sfx_volume, 1.0)
	assert_false(AudioManager.sfx_muted)
	# Config created with only audio defaults
	assert_true(FileAccess.file_exists(test_config_path))
	var config: ConfigFile = ConfigFile.new()
	config.load(test_config_path)
	var sections: Array = config.get_sections()
	assert_eq(sections.size(), 1)
	assert_eq(sections[0], "audio")
	assert_eq(config.get_value("audio", "sfx_volume"), 1.0)
	assert_false(config.get_value("audio", "sfx_muted"))
	assert_false(config.has_section("Settings"))
	assert_false(config.has_section("input"))
