## test_basic_save_load_without_other_settings.gd
## GUT unit tests for AudioManager save/load functionality without other settings.
## Covers TC-SL-01 to TC-SL-05 from test plan.
## Test Plan:
## https://github.com/ikostan/SkyLockAssault/issues/295

extends "res://addons/gut/test.gd"

var test_config_path: String = "user://test_basic_sl.cfg"


## Per-test setup: Reset AudioManager to defaults, delete config if exists.
## :rtype: void
func before_each() -> void:
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)
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


## TC-SL-01 | Config file does not exist; AudioManager volumes/mutes at defaults (all 1.0, false); No other settings. | Call AudioManager.save_volumes() | Config file created with only "audio" section; All audio keys set to defaults; No other sections (e.g., no "input" or "Settings"); Log "Saved volumes to config."
## :rtype: void
func test_tc_sl_01() -> void:
	assert_false(FileAccess.file_exists(test_config_path))
	AudioManager.current_config_path = test_config_path
	AudioManager.save_volumes()
	assert_true(FileAccess.file_exists(test_config_path))
	var config: ConfigFile = ConfigFile.new()
	config.load(test_config_path)
	var sections: Array = config.get_sections()
	assert_eq(sections.size(), 1)
	assert_eq(sections[0], "audio")
	var keys: Array = config.get_section_keys("audio")
	assert_eq(keys.size(), 10)  # 5 volumes + 5 mutes
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		var config_data: Dictionary = AudioConstants.BUS_CONFIG[bus]
		assert_almost_eq(config.get_value("audio", config_data["volume_var"]), 1.0, 0.01)
		assert_eq(config.get_value("audio", config_data["muted_var"]), false)
	assert_false(config.has_section("input"))
	assert_false(config.has_section("Settings"))


## TC-SL-02 | Config file exists with only "audio" section (non-defaults: master_volume=0.5, master_muted=true); AudioManager at defaults. | Call AudioManager.load_volumes() | AudioManager updates to config values (master_volume=0.5, master_muted=true); apply_all_volumes() called; Log "Loaded volumes from config."; Config unchanged.
## :rtype: void
func test_tc_sl_02() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "master_volume", 0.5)
	config.set_value("audio", "master_muted", true)
	config.save(test_config_path)
	assert_true(FileAccess.file_exists(test_config_path))
	# Verify initial defaults
	assert_almost_eq(AudioManager.master_volume, 1.0, 0.01)
	assert_false(AudioManager.master_muted)
	AudioManager.load_volumes(test_config_path)
	AudioManager.apply_all_volumes()
	# Verify updated
	assert_almost_eq(AudioManager.master_volume, 0.5, 0.01)
	assert_true(AudioManager.master_muted)
	# Check AudioServer (apply_all_volumes called)
	var bus_idx: int = AudioServer.get_bus_index(AudioConstants.BUS_MASTER)
	assert_almost_eq(AudioServer.get_bus_volume_db(bus_idx), linear_to_db(0.5), 0.1)
	assert_true(AudioServer.is_bus_mute(bus_idx))
	# Config unchanged
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_almost_eq(config.get_value("audio", "master_volume"), 0.5, 0.01)
	assert_true(config.get_value("audio", "master_muted"))
	assert_eq(config.get_sections().size(), 1)


## TC-SL-03 | Config file does not exist; AudioManager changed (e.g., music_volume=0.7, music_muted=true). | Call AudioManager.save_volumes(); Then load_volumes() | Config created with changes; After load, AudioManager matches saved; AudioServer buses updated; Logs for save/load.
## :rtype: void
func test_tc_sl_03() -> void:
	assert_false(FileAccess.file_exists(test_config_path))
	# Change AudioManager
	AudioManager.music_volume = 0.7
	AudioManager.music_muted = true
	AudioManager.current_config_path = test_config_path
	AudioManager.save_volumes()
	assert_true(FileAccess.file_exists(test_config_path))
	# Reset to defaults to simulate reload
	AudioManager._init_to_defaults()
	assert_almost_eq(AudioManager.music_volume, 1.0, 0.01)
	assert_false(AudioManager.music_muted)
	AudioManager.load_volumes(test_config_path)
	AudioManager.apply_all_volumes()
	# Verify matches saved
	assert_almost_eq(AudioManager.music_volume, 0.7, 0.01)
	assert_true(AudioManager.music_muted)
	# AudioServer updated
	var bus_idx: int = AudioServer.get_bus_index(AudioConstants.BUS_MUSIC)
	assert_almost_eq(AudioServer.get_bus_volume_db(bus_idx), linear_to_db(0.7), 0.1)
	assert_true(AudioServer.is_bus_mute(bus_idx))
	# Config has changes
	var config: ConfigFile = ConfigFile.new()
	config.load(test_config_path)
	assert_almost_eq(config.get_value("audio", "music_volume"), 0.7, 0.01)
	assert_true(config.get_value("audio", "music_muted"))


## TC-SL-04 | Config file exists with invalid "audio" key types (e.g., master_volume="string"); AudioManager at defaults. | Call AudioManager.load_volumes() | Skips invalid keys, keeps defaults; Log warnings if applicable; No crash; apply_all_volumes() with defaults.
## :rtype: void
func test_tc_sl_04() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "master_volume", "invalid_string")  # Wrong type
	config.set_value("audio", "master_muted", 42)  # Wrong type for bool
	config.save(test_config_path)
	assert_true(FileAccess.file_exists(test_config_path))
	AudioManager.load_volumes(test_config_path)
	AudioManager.apply_all_volumes()
	# Verify keeps defaults
	assert_almost_eq(AudioManager.master_volume, 1.0, 0.01)
	assert_false(AudioManager.master_muted)
	# AudioServer at defaults
	var bus_idx: int = AudioServer.get_bus_index(AudioConstants.BUS_MASTER)
	assert_almost_eq(AudioServer.get_bus_volume_db(bus_idx), linear_to_db(1.0), 0.1)
	assert_false(AudioServer.is_bus_mute(bus_idx))


## TC-SL-05 | Config file exists but empty; AudioManager at non-defaults. | Call AudioManager.load_volumes() | No changes to AudioManager (keeps non-defaults, as get_value falls back); apply_all_volumes() with current; Log if needed.
## :rtype: void
func test_tc_sl_05() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.save(test_config_path)  # Empty config
	assert_true(FileAccess.file_exists(test_config_path))
	# Set non-defaults
	AudioManager.sfx_volume = 0.3
	AudioManager.sfx_muted = true
	AudioManager.load_volumes(test_config_path)
	AudioManager.apply_all_volumes()
	# Keeps non-defaults
	assert_almost_eq(AudioManager.sfx_volume, 0.3, 0.01)
	assert_true(AudioManager.sfx_muted)
	# AudioServer updated with current
	var bus_idx: int = AudioServer.get_bus_index(AudioConstants.BUS_SFX)
	assert_almost_eq(AudioServer.get_bus_volume_db(bus_idx), linear_to_db(0.3), 0.1)
	assert_true(AudioServer.is_bus_mute(bus_idx))
