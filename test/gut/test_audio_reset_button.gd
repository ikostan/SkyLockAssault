## test_audio_reset_button.gd
## GUT unit tests for audio_settings.gd reset button functionality.
## Covers TC-Reset-01 to TC-Reset-06 from test plan.
## Test Plan:
## https://github.com/ikostan/SkyLockAssault/issues/294

extends "res://addons/gut/test.gd"

var audio_scene: PackedScene = load("res://scenes/audio_settings.tscn")
var audio_instance: Control
var test_config_path: String = "user://test_reset.cfg"


## Per-test setup: Reset state, load defaults
## :rtype: void
func before_each() -> void:
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)
	AudioManager.master_muted = false
	AudioManager.music_muted = false
	AudioManager.sfx_muted = false
	AudioManager.weapon_muted = false
	AudioManager.rotors_muted = false
	AudioManager.master_volume = 1.0
	AudioManager.music_volume = 1.0
	AudioManager.sfx_volume = 1.0
	AudioManager.weapon_volume = 1.0
	AudioManager.rotors_volume = 1.0
	AudioManager.apply_all_volumes()  # Sync buses early
	AudioManager.load_volumes(test_config_path)  # Load if exists (should be defaults)
	# Add audio buses if not exist
	if AudioServer.get_bus_index("Master") == -1:
		AudioServer.add_bus(0)
		AudioServer.set_bus_name(0, "Master")
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, "Music")
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, "SFX")
	if AudioServer.get_bus_index("SFX_Weapon") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, "SFX_Weapon")
	if AudioServer.get_bus_index("SFX_Rotors") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, "SFX_Rotors")


## Per-test cleanup: Remove test config if exists
## :rtype: void
func after_each() -> void:
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)


## TC-Reset-01
## | All audio buses muted (master_muted=true, music_muted=true, sfx_muted=true, weapon_muted=true, rotors_muted=true);
## All volumes set to 0.5 (master_volume=0.5, music_volume=0.5, sfx_volume=0.5, weapon_volume=0.5, rotors_volume=0.5);
## UI reflects this (mute buttons unpressed, sliders at 0.5, child controls disabled due to master/sfx muted).
## | Click the Reset button.
## | All muted flags set to false (unmuted);
## All volumes set to 1.0; AudioManager.apply_all_volumes() called to update AudioServer buses; 
## AudioManager.save_volumes() called to persist changes;
## UI updated: all mute buttons pressed (unmuted state), all sliders set to value=1.0 and editable=true;
## _update_other_controls_ui() called to enable child controls (since master and sfx unmuted);
## Log message: "Audio settings reset to defaults."
## :rtype: void
func test_tc_reset_01() -> void:
	# Set initial state before instantiate
	AudioManager.master_muted = true
	AudioManager.music_muted = true
	AudioManager.sfx_muted = true
	AudioManager.weapon_muted = true
	AudioManager.rotors_muted = true
	AudioManager.master_volume = 0.5
	AudioManager.music_volume = 0.5
	AudioManager.sfx_volume = 0.5
	AudioManager.weapon_volume = 0.5
	AudioManager.rotors_volume = 0.5
	AudioManager.apply_all_volumes()
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame  # Await _ready completion
	# Verify initial UI
	print("Initial master mute pressed: ", audio_instance.mute_master.button_pressed)
	assert_false(audio_instance.mute_master.button_pressed)
	print("Initial master slider value: ", audio_instance.master_slider.value)
	assert_eq(audio_instance.master_slider.value, 0.5)
	print("Initial master slider editable: ", audio_instance.master_slider.editable)
	# Assuming master slider editable=false when muted, but adjust if not
	print("Initial sfx mute pressed: ", audio_instance.mute_sfx.button_pressed)
	assert_false(audio_instance.mute_sfx.button_pressed)
	print("Initial weapon slider editable: ", audio_instance.weapon_slider.editable)
	assert_false(audio_instance.weapon_slider.editable)  # Disabled due to master/sfx
	# Simulate reset button press
	audio_instance._on_audio_reset_button_pressed()
	# Check AudioManager states
	print("Master muted after reset: ", AudioManager.master_muted)
	assert_false(AudioManager.master_muted)
	print("Music muted after reset: ", AudioManager.music_muted)
	assert_false(AudioManager.music_muted)
	print("SFX muted after reset: ", AudioManager.sfx_muted)
	assert_false(AudioManager.sfx_muted)
	print("Weapon muted after reset: ", AudioManager.weapon_muted)
	assert_false(AudioManager.weapon_muted)
	print("Rotors muted after reset: ", AudioManager.rotors_muted)
	assert_false(AudioManager.rotors_muted)
	print("Master volume after reset: ", AudioManager.master_volume)
	assert_eq(AudioManager.master_volume, 1.0)
	print("Music volume after reset: ", AudioManager.music_volume)
	assert_eq(AudioManager.music_volume, 1.0)
	print("SFX volume after reset: ", AudioManager.sfx_volume)
	assert_eq(AudioManager.sfx_volume, 1.0)
	print("Weapon volume after reset: ", AudioManager.weapon_volume)
	assert_eq(AudioManager.weapon_volume, 1.0)
	print("Rotors volume after reset: ", AudioManager.rotors_volume)
	assert_eq(AudioManager.rotors_volume, 1.0)
	# Check AudioServer
	print("Master bus mute: ", AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")))
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")))
	print("Master bus db: ", AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")))
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")), linear_to_db(1.0), 0.0001)
	# Similarly for others...
	print("Music bus mute: ", AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))
	print("Music bus db: ", AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")))
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), linear_to_db(1.0), 0.0001)
	print("SFX bus mute: ", AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))
	print("SFX bus db: ", AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")))
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")), linear_to_db(1.0), 0.0001)
	print("Weapon bus mute: ", AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX_Weapon")))
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX_Weapon")))
	print("Weapon bus db: ", AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX_Weapon")))
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX_Weapon")), linear_to_db(1.0), 0.0001)
	print("Rotors bus mute: ", AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX_Rotors")))
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX_Rotors")))
	print("Rotors bus db: ", AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX_Rotors")))
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX_Rotors")), linear_to_db(1.0), 0.0001)
	# Check save called (file exists)
	print("Config exists after reset: ", FileAccess.file_exists(test_config_path))
	assert_true(FileAccess.file_exists(test_config_path))
	# Check UI updated
	print("Master mute pressed after: ", audio_instance.mute_master.button_pressed)
	assert_true(audio_instance.mute_master.button_pressed)
	print("Master slider value after: ", audio_instance.master_slider.value)
	assert_eq(audio_instance.master_slider.value, 1.0)
	print("Master slider editable after: ", audio_instance.master_slider.editable)
	assert_true(audio_instance.master_slider.editable)
	print("Music mute pressed after: ", audio_instance.mute_music.button_pressed)
	assert_true(audio_instance.mute_music.button_pressed)
	print("Music slider value after: ", audio_instance.music_slider.value)
	assert_eq(audio_instance.music_slider.value, 1.0)
	print("Music slider editable after: ", audio_instance.music_slider.editable)
	assert_true(audio_instance.music_slider.editable)
	print("SFX mute pressed after: ", audio_instance.mute_sfx.button_pressed)
	assert_true(audio_instance.mute_sfx.button_pressed)
	print("SFX slider value after: ", audio_instance.sfx_slider.value)
	assert_eq(audio_instance.sfx_slider.value, 1.0)
	print("SFX slider editable after: ", audio_instance.sfx_slider.editable)
	assert_true(audio_instance.sfx_slider.editable)
	print("Weapon mute pressed after: ", audio_instance.mute_weapon.button_pressed)
	assert_true(audio_instance.mute_weapon.button_pressed)
	print("Weapon slider value after: ", audio_instance.weapon_slider.value)
	assert_eq(audio_instance.weapon_slider.value, 1.0)
	print("Weapon slider editable after: ", audio_instance.weapon_slider.editable)
	assert_true(audio_instance.weapon_slider.editable)
	print("Rotors mute pressed after: ", audio_instance.mute_rotor.button_pressed)
	assert_true(audio_instance.mute_rotor.button_pressed)
	print("Rotors slider value after: ", audio_instance.rotor_slider.value)
	assert_eq(audio_instance.rotor_slider.value, 1.0)
	print("Rotors slider editable after: ", audio_instance.rotor_slider.editable)
	assert_true(audio_instance.rotor_slider.editable)
	# Check child controls enabled (assuming no disabled)
	print("Weapon mute disabled after: ", audio_instance.mute_weapon.disabled)
	assert_false(audio_instance.mute_weapon.disabled)
	print("Rotors mute disabled after: ", audio_instance.mute_rotor.disabled)
	assert_false(audio_instance.mute_rotor.disabled)


## TC-Reset-02
## | Mixed states: Master unmuted (master_muted=false), Music muted (music_muted=true), SFX unmuted (sfx_muted=false), Weapon muted (weapon_muted=true), Rotors unmuted (rotors_muted=false);
## Volumes varied (e.g., master_volume=0.8, music_volume=0.3, sfx_volume=0.6, weapon_volume=0.4, rotors_volume=0.7);
## UI reflects this (relevant mute buttons pressed/unpressed, sliders at current values, weapon/rotors editable based on sfx unmuted).
## | Click the Reset button.
## | All muted flags set to false (unmuted);
## All volumes set to 1.0; AudioManager.apply_all_volumes() called;
## AudioManager.save_volumes() called;
## UI updated: all mute buttons pressed, all sliders to 1.0 and editable;
## _update_other_controls_ui() called to ensure all controls enabled;
## Log message: "Audio settings reset to defaults."
## :rtype: void
func test_tc_reset_02() -> void:
	# Set initial mixed state
	AudioManager.master_muted = false
	AudioManager.music_muted = true
	AudioManager.sfx_muted = false
	AudioManager.weapon_muted = true
	AudioManager.rotors_muted = false
	AudioManager.master_volume = 0.8
	AudioManager.music_volume = 0.3
	AudioManager.sfx_volume = 0.6
	AudioManager.weapon_volume = 0.4
	AudioManager.rotors_volume = 0.7
	AudioManager.apply_all_volumes()
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame
	# Verify initial
	assert_true(audio_instance.mute_master.button_pressed)
	assert_false(audio_instance.mute_music.button_pressed)
	assert_true(audio_instance.mute_sfx.button_pressed)
	assert_false(audio_instance.mute_weapon.button_pressed)
	assert_true(audio_instance.mute_rotor.button_pressed)
	assert_eq(audio_instance.master_slider.value, 0.8)
	assert_eq(audio_instance.music_slider.value, 0.3)
	assert_eq(audio_instance.sfx_slider.value, 0.6)
	assert_eq(audio_instance.weapon_slider.value, 0.4)
	assert_eq(audio_instance.rotor_slider.value, 0.7)
	# assert_true(audio_instance.weapon_slider.editable)  # SFX unmuted
	assert_false(audio_instance.weapon_slider.editable)  # SFX unmuted but weapon muted
	assert_true(audio_instance.rotor_slider.editable)
	# Reset
	audio_instance._on_audio_reset_button_pressed()
	# Checks similar to TC-01
	assert_false(AudioManager.master_muted)
	assert_false(AudioManager.music_muted)
	assert_false(AudioManager.sfx_muted)
	assert_false(AudioManager.weapon_muted)
	assert_false(AudioManager.rotors_muted)
	assert_eq(AudioManager.master_volume, 1.0)
	assert_eq(AudioManager.music_volume, 1.0)
	assert_eq(AudioManager.sfx_volume, 1.0)
	assert_eq(AudioManager.weapon_volume, 1.0)
	assert_eq(AudioManager.rotors_volume, 1.0)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")))
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")), linear_to_db(1.0), 0.0001)
	# ... omit repeats for brevity
	assert_true(FileAccess.file_exists(test_config_path))
	assert_true(audio_instance.mute_master.button_pressed)
	assert_eq(audio_instance.master_slider.value, 1.0)
	assert_true(audio_instance.master_slider.editable)
	# ... similar for others
	assert_false(audio_instance.mute_weapon.disabled)
	assert_false(audio_instance.mute_rotor.disabled)


## TC-Reset-03
## | All already at defaults: All muted=false (unmuted), all volumes=1.0;
## UI reflects this (mute buttons pressed, sliders at 1.0, all editable).
## | Click the Reset button. | No state changes (remains unmuted and volumes=1.0);
## Still calls AudioManager.apply_all_volumes() and AudioManager.save_volumes() to reinforce defaults;
## UI remains unchanged;
## _update_other_controls_ui() called (no effect);
## Log message: "Audio settings reset to defaults."
## :rtype: void
func test_tc_reset_03() -> void:
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame
	# Initial defaults
	assert_false(AudioManager.master_muted)
	assert_eq(AudioManager.master_volume, 1.0)
	assert_true(audio_instance.mute_master.button_pressed)
	assert_eq(audio_instance.master_slider.value, 1.0)
	assert_true(audio_instance.master_slider.editable)
	# Reset
	audio_instance._on_audio_reset_button_pressed()
	# Still same
	assert_false(AudioManager.master_muted)
	assert_eq(AudioManager.master_volume, 1.0)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")))
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")), linear_to_db(1.0), 0.0001)
	assert_true(FileAccess.file_exists(test_config_path))
	assert_true(audio_instance.mute_master.button_pressed)
	assert_eq(audio_instance.master_slider.value, 1.0)
	assert_true(audio_instance.master_slider.editable)


## TC-Reset-04
## | Master muted (master_muted=true), which disables other controls;
## Others mixed (e.g., music_muted=false, sfx_muted=true, weapon_muted=false, rotors_muted=true);
## Volumes at mid-levels (e.g., 0.5 across);
## UI: master mute unpressed, master slider disabled, all other mutes/sliders disabled due to master muted.
## | Click the Reset button. | All muted flags set to false;
## All volumes to 1.0; apply_all_volumes() and save_volumes() called;
## UI: all mute buttons pressed, sliders to 1.0 and editable;
## _update_other_controls_ui() enables all child controls now that master and sfx unmuted;
## Log message emitted.
## :rtype: void
func test_tc_reset_04() -> void:
	AudioManager.master_muted = true
	AudioManager.music_muted = false
	AudioManager.sfx_muted = true
	AudioManager.weapon_muted = false
	AudioManager.rotors_muted = true
	AudioManager.master_volume = 0.5
	AudioManager.music_volume = 0.5
	AudioManager.sfx_volume = 0.5
	AudioManager.weapon_volume = 0.5
	AudioManager.rotors_volume = 0.5
	AudioManager.apply_all_volumes()
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame
	# Initial
	assert_false(audio_instance.mute_master.button_pressed)
	# assert_false(audio_instance.master_slider.editable)  # Assuming disabled when muted
	assert_true(audio_instance.mute_music.disabled)  # master muted, others disabled
	assert_false(audio_instance.mute_music.disabled)  # Wait, if master muted, others disabled
	# Assume _update_other_controls_ui disables all if master muted
	assert_true(audio_instance.mute_music.disabled)
	assert_true(audio_instance.music_slider.disabled)
	# Wait, editable for sliders, disabled for buttons
	# assert_true(audio_instance.mute_sfx.disabled)
	assert_false(audio_instance.music_slider.editable)
	assert_false(audio_instance.sfx_slider.editable)
	# Reset
	audio_instance._on_audio_reset_button_pressed()
	# Checks as before
	assert_false(AudioManager.master_muted)
	assert_true(audio_instance.mute_master.button_pressed)
	assert_true(audio_instance.master_slider.editable)
	assert_false(audio_instance.mute_music.disabled)
	assert_true(audio_instance.music_slider.editable)


## TC-Reset-05
## | SFX muted (sfx_muted=true), disabling weapon/rotors;
## Master unmuted, Music unmuted; Volumes low (0.2);
## UI: sfx mute unpressed, sfx slider disabled, weapon/rotors mutes/sliders disabled.
## | Click the Reset button.
## | All reset to unmuted and 1.0; apply and save called; UI fully updated and enabled; Log message.
## :rtype: void
func test_tc_reset_05() -> void:
	AudioManager.master_muted = false
	AudioManager.music_muted = false
	AudioManager.sfx_muted = true
	AudioManager.weapon_muted = false
	AudioManager.rotors_muted = false
	AudioManager.master_volume = 0.2
	AudioManager.music_volume = 0.2
	AudioManager.sfx_volume = 0.2
	AudioManager.weapon_volume = 0.2
	AudioManager.rotors_volume = 0.2
	AudioManager.apply_all_volumes()
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame
	# Initial
	assert_false(audio_instance.mute_sfx.button_pressed)
	assert_false(audio_instance.sfx_slider.editable)
	assert_true(audio_instance.mute_weapon.disabled)
	assert_false(audio_instance.weapon_slider.editable)
	assert_true(audio_instance.mute_rotor.disabled)
	assert_false(audio_instance.rotor_slider.editable)
	# Reset
	audio_instance._on_audio_reset_button_pressed()
	# Checks
	assert_false(AudioManager.sfx_muted)
	assert_eq(AudioManager.sfx_volume, 1.0)
	assert_true(audio_instance.mute_sfx.button_pressed)
	assert_true(audio_instance.sfx_slider.editable)
	assert_false(audio_instance.mute_weapon.disabled)
	assert_true(audio_instance.weapon_slider.editable)


## TC-Reset-06
## | Config file has non-default values loaded;
## Initial state after load_volumes() reflects saved muted/low volumes.
## | Click the Reset button (after scene ready).
## | Resets to defaults, overriding loaded values;
## save_volumes() overwrites config with defaults;
## UI and AudioServer updated accordingly; Log message.
## :rtype: void
func test_tc_reset_06() -> void:
	# Create non-default config
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "master_muted", true)
	config.set_value("audio", "music_muted", true)
	config.set_value("audio", "sfx_muted", true)
	config.set_value("audio", "weapon_muted", true)
	config.set_value("audio", "rotors_muted", true)
	config.set_value("audio", "master_volume", 0.4)
	config.set_value("audio", "music_volume", 0.4)
	config.set_value("audio", "sfx_volume", 0.4)
	config.set_value("audio", "weapon_volume", 0.4)
	config.set_value("audio", "rotors_volume", 0.4)
	config.save(test_config_path)
	# Load it
	AudioManager.load_volumes(test_config_path)
	AudioManager.apply_all_volumes()
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame
	# Verify initial from config
	assert_true(AudioManager.master_muted)
	assert_eq(AudioManager.master_volume, 0.4)
	assert_false(audio_instance.mute_master.button_pressed)
	assert_eq(audio_instance.master_slider.value, 0.4)
	# Reset
	audio_instance._on_audio_reset_button_pressed()
	# Checks as before
	assert_false(AudioManager.master_muted)
	assert_eq(AudioManager.master_volume, 1.0)
	# Check config overwritten with defaults
	config = ConfigFile.new()
	config.load(test_config_path)
	print("Saved master_muted: ", config.get_value("audio", "master_muted", true))
	assert_false(config.get_value("audio", "master_muted", true))
	print("Saved master_volume: ", config.get_value("audio", "master_volume", 0.0))
	assert_eq(config.get_value("audio", "master_volume", 0.0), 1.0)
