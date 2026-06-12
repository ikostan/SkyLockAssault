## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_ui_audio_persistence.gd
##
## TEST SUITE: Verifies UI/Menu Volume, Mute, and AudioServer Persistence (Issue #707, #708, #709, #712).

extends "res://addons/gut/test.gd"

# Test Suite Constants to avoid magic numbers
const TEST_TOLERANCE: float = 0.001
const DEFAULT_VOLUME: float = 1.0
const DEFAULT_MUTE_STATE: bool = false

var test_config_path: String = "user://test_ui_audio_persistence.cfg"
var _orig_config_path: String
var _bus_created_by_test: bool = false


## Per-test setup: Snapshot the original configuration path, clear any stale test files, 
## reset AudioManager to default values, and initialize the Menu bus if absent.
## :rtype: void
func before_each() -> void:
	_orig_config_path = AudioManager.current_config_path
	
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)
		
	AudioManager._init_to_defaults()
	AudioManager.apply_all_volumes()
	
	# Dynamically register the Menu bus for headless environments and flag for cleanup
	if AudioServer.get_bus_index(AudioConstants.BUS_SFX_MENU) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, AudioConstants.BUS_SFX_MENU)
		_bus_created_by_test = true


## Per-test cleanup: Delete the temporary configuration file, restore global paths, and tear down test buses.
## :rtype: void
func after_each() -> void:
	# 1. TELL THE MANAGER TO FORGET THE BUSES
	# You need a method in AudioManager like `reset_bus_indices()` 
	# that clears any cached bus indices (e.g., set variables to -1).
	if AudioManager.has_method("reset_bus_indices"):
		AudioManager.reset_bus_indices()
	
	# 2. Now it is safe to remove the bus from the server
	if _bus_created_by_test:
		var bus_idx: int = AudioServer.get_bus_index(AudioConstants.BUS_SFX_MENU)
		if bus_idx != -1:
			AudioServer.remove_bus(bus_idx)
		_bus_created_by_test = false

	# 3. Standard cleanup
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)
		
	AudioManager.current_config_path = _orig_config_path
	await get_tree().process_frame


## TC-Persistence-01 | Verifies that programmatic changes to the Menu/UI volume persist across save/load cycles
## and correctly propagate down to the AudioServer buses.
## :rtype: void
func test_ui_menu_volume_persistence() -> void:
	# 1. Configure a dedicated test settings file path.
	AudioManager.current_config_path = test_config_path
	
	# 2. Set the Menu/UI volume to a known value.
	AudioManager.set_volume(AudioConstants.BUS_SFX_MENU, 0.75)
	
	# 3. Save the current audio configuration.
	AudioManager.save_volumes()
	
	# 4. Deliberately overwrite the in-memory value with a different value.
	AudioManager.set_volume(AudioConstants.BUS_SFX_MENU, 0.10)
	
	# 5. Verify the overwrite succeeded.
	assert_almost_eq(
		AudioManager.get_volume(AudioConstants.BUS_SFX_MENU),
		0.10,
		TEST_TOLERANCE,
		"In-memory volume should be successfully mutated to 0.10"
	)
	
	# 6. Reload audio settings from disk.
	AudioManager.load_volumes()
	
	# 7. Verify the value was restored from the saved configuration.
	assert_almost_eq(
		AudioManager.get_volume(AudioConstants.BUS_SFX_MENU),
		0.75,
		TEST_TOLERANCE,
		"Volume should be successfully restored to 0.75 from disk"
	)
	
	# 8. Verify the value was applied to the corresponding AudioServer bus.
	var bus_idx: int = AudioServer.get_bus_index(AudioConstants.BUS_SFX_MENU)
	assert_ne(bus_idx, -1, "The Menu/UI audio bus must exist on the AudioServer")
	
	var expected_db: float = linear_to_db(0.75)
	assert_almost_eq(
		AudioServer.get_bus_volume_db(bus_idx),
		expected_db,
		TEST_TOLERANCE,
		"The AudioServer bus volume must accurately reflect the loaded volume in decibels"
	)


## TC-Persistence-02 | Verifies that programmatic changes to the Menu/UI mute state persist across save/load cycles
## and correctly propagate down to the AudioServer buses.
## :rtype: void
func test_ui_menu_mute_persistence() -> void:
	# 1. Configure a dedicated test settings file path.
	AudioManager.current_config_path = test_config_path
	
	# 2. Set the Menu/UI bus mute state to true.
	AudioManager.set_muted(AudioConstants.BUS_SFX_MENU, true)
	
	# 3. Save the current audio settings.
	AudioManager.save_volumes()
	
	# 4. Deliberately overwrite the in-memory mute state.
	AudioManager.set_muted(AudioConstants.BUS_SFX_MENU, false)
	
	# 5. Verify the overwrite was successful.
	assert_false(
		AudioManager.get_muted(AudioConstants.BUS_SFX_MENU),
		"In-memory mute state should be successfully mutated to false"
	)
	
	# 6. Reload audio settings from disk.
	AudioManager.load_volumes()
	
	# 7. Verify the mute state was restored from the configuration file.
	assert_true(
		AudioManager.get_muted(AudioConstants.BUS_SFX_MENU),
		"Mute state should be successfully restored to true from disk"
	)
	
	# 8. Verify the value was applied to the corresponding AudioServer bus.
	var bus_idx: int = AudioServer.get_bus_index(AudioConstants.BUS_SFX_MENU) 
	assert_ne(bus_idx, -1, "The Menu/UI audio bus must exist on the AudioServer") 
	
	assert_true(
		AudioServer.is_bus_mute(bus_idx),
		"The AudioServer bus mute state must accurately reflect the loaded true state"
	)


## TC-Persistence-03 | Verifies that reloading settings from disk accurately re-applies the restored volume
## down to the AudioServer bus level, ensuring complete synchronization between AudioManager and AudioServer.
## :rtype: void
func test_ui_menu_volume_restoration_applies_to_audioserver() -> void:
	# 1. Configure a dedicated test settings file path.
	AudioManager.current_config_path = test_config_path
	
	# 2. Set the Menu/UI bus volume to a known value.
	AudioManager.set_volume(AudioConstants.BUS_SFX_MENU, 0.60)
	
	# 3. Save the current audio settings.
	AudioManager.save_volumes()
	
	# 4. Change the in-memory volume to a different value.
	AudioManager.set_volume(AudioConstants.BUS_SFX_MENU, 0.20)
	
	# 5. Reload settings from disk.
	AudioManager.load_volumes()
	
	# 6. Obtain the Menu/UI bus index.
	var bus_index: int = AudioServer.get_bus_index(AudioConstants.BUS_SFX_MENU)
	assert_ne(bus_index, -1, "The Menu/UI audio bus must exist on the AudioServer")
	
	# 7. Verify AudioManager volume equals 0.60.
	assert_almost_eq(
		AudioManager.get_volume(AudioConstants.BUS_SFX_MENU),
		0.60,
		TEST_TOLERANCE,
		"AudioManager's internal runtime state must restore back to 0.60"
	)
	
	# 8. Verify the corresponding AudioServer bus volume reflects the loaded value.
	var expected_db: float = linear_to_db(0.60)
	assert_almost_eq(
		AudioServer.get_bus_volume_db(bus_index),
		expected_db,
		TEST_TOLERANCE,
		"The actual AudioServer bus volume must automatically resync to the 0.60 linear equivalent in decibels"
	)


## TC-Persistence-04 | Verifies that reloading settings from disk accurately re-applies the restored mute state
## down to the AudioServer bus level, ensuring complete configuration-to-runtime synchronization.
## :rtype: void
func test_ui_menu_mute_restoration_applies_to_audioserver() -> void:
	# 1. Configure a dedicated test settings file path.
	AudioManager.current_config_path = test_config_path
	
	# 2. Set the Menu/UI bus mute state to true.
	AudioManager.set_muted(AudioConstants.BUS_SFX_MENU, true)
	
	# 3. Save the current audio settings.
	AudioManager.save_volumes()
	
	# 4. Change the mute state back to false.
	AudioManager.set_muted(AudioConstants.BUS_SFX_MENU, false)
	
	# 5. Reload settings from disk.
	AudioManager.load_volumes()
	
	# 6. Obtain the Menu/UI bus index.
	var bus_index: int = AudioServer.get_bus_index(AudioConstants.BUS_SFX_MENU)
	assert_ne(bus_index, -1, "The Menu/UI audio bus must exist on the AudioServer")
	
	# 7. Verify AudioManager mute state equals true.
	assert_true(
		AudioManager.get_muted(AudioConstants.BUS_SFX_MENU),
		"AudioManager's internal runtime state must restore back to being muted (true)"
	)
	
	# 8. Verify the corresponding AudioServer bus mute state reflects the loaded value.
	assert_true(
		AudioServer.is_bus_mute(bus_index),
		"The actual AudioServer bus mute state must automatically resync to muted (true)"
	)


## TC-Persistence-05 | Verifies that loading an empty or incomplete configuration file safely initializes 
## the Menu/UI audio settings to their default values without generating engine errors.
## :rtype: void
func test_ui_menu_missing_configuration_defaults() -> void:
	# 1. Configure a dedicated test settings file path.
	AudioManager.current_config_path = test_config_path
	
	# 2. Create an empty or incomplete settings file.
	var config: ConfigFile = ConfigFile.new()
	
	# FIX: Save using encryption to prevent C++ core errors during AudioManager.load_volumes
	var save_err: int = config.save_encrypted_pass(test_config_path, Globals.save_encryption_pass)
	assert_eq(save_err, OK, "Failed to create encrypted test config fixture.")
	
	# 3. Load audio settings.
	AudioManager.load_volumes()
	
	# 4. Verify the Menu/UI bus configuration is initialized using default values.
	var expected_default_volume: float = DEFAULT_VOLUME
	var expected_default_mute: bool = DEFAULT_MUTE_STATE
	
	# 5. Assert default volume is correctly assigned.
	assert_almost_eq(
		AudioManager.get_volume(AudioConstants.BUS_SFX_MENU),
		expected_default_volume,
		TEST_TOLERANCE,
		"Menu volume must fallback and initialize to its default value of 1.0 when missing from config"
	)
	
	# 6. Assert default mute state is correctly assigned.
	assert_eq(
		AudioManager.get_muted(AudioConstants.BUS_SFX_MENU),
		expected_default_mute,
		"Menu mute state must fallback and initialize to its default value of false when missing from config"
	)
