## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_settings_migration.gd
##
## Explicitly tests the plaintext-to-encrypted migration pipeline.
## Verifies lossless multi-writer safety during format upgrades.

extends GutTest

const TEST_CONFIG_PATH: String = "user://test_settings_migration.cfg"

func before_each() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	
	# Reset singletons/flags for a clean slate
	Settings._needs_save = false
	if Globals.has_meta(Settings.LEGACY_MIGRATION_KEY):
		Globals.remove_meta(Settings.LEGACY_MIGRATION_KEY)
	
	# Clear InputMap to test clean defaults loading
	for action: String in Settings.ACTIONS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action)


func after_each() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	await get_tree().process_frame


## Scenario 1: New Encrypted Install
## A fresh run should create an encrypted file.
func test_new_install_creates_encrypted_file() -> void:
	assert_false(FileAccess.file_exists(TEST_CONFIG_PATH), "File should not exist initially")
	
	Settings.save_input_mappings(TEST_CONFIG_PATH)
	assert_true(FileAccess.file_exists(TEST_CONFIG_PATH), "Save should create a new config file")
	
	# Assert using the file header helper to prevent intentional C++ crash logs in GUT
	assert_true(Settings._is_file_encrypted(TEST_CONFIG_PATH), "New file should be properly encrypted")
	
	var config := ConfigFile.new()
	var enc_err: int = config.load_encrypted_pass(TEST_CONFIG_PATH, Globals.save_encryption_pass)
	assert_eq(enc_err, OK, "Encrypted load_encrypted_pass() should succeed")


## Scenario 2: Fallback Loading of Legacy Plaintext
## If a user has an old plaintext file, Settings.load_input_mappings() should read it 
## successfully and flag it for migration.
func test_fallback_loading_of_legacy_plaintext() -> void:
	var legacy_cfg := ConfigFile.new()
	# Set to KEY_M (77) specifically to prove it loaded our custom plaintext data, not defaults
	legacy_cfg.set_value("input", "speed_up", ["key:77"])
	legacy_cfg.save(TEST_CONFIG_PATH)
	
	Settings.load_input_mappings(TEST_CONFIG_PATH)
	
	var events: Array[InputEvent] = InputMap.action_get_events("speed_up")
	assert_true(
		events.any(func(e: InputEvent) -> bool: return e is InputEventKey and e.physical_keycode == 77), 
		"Should successfully load legacy mapping via plaintext fallback"
	)
	
	assert_true(Settings._needs_save, "Settings should flag _needs_save after a plaintext fallback load")


## Scenario 3: Automatic Upgrade from Plaintext to Encrypted
## End-to-end test verifying that after loading a plaintext file, the subsequent save 
## rewrites it completely in the encrypted format.
func test_automatic_upgrade_from_plaintext_to_encrypted() -> void:
	var legacy_cfg := ConfigFile.new()
	legacy_cfg.set_value("input", "fire", ["key:77"])
	legacy_cfg.save(TEST_CONFIG_PATH)
	
	Settings.load_input_mappings(TEST_CONFIG_PATH)
	
	if Settings._needs_save:
		Settings.save_input_mappings(TEST_CONFIG_PATH)
		Settings._needs_save = false
		
	# Verify the file has been successfully migrated to encrypted
	assert_true(Settings._is_file_encrypted(TEST_CONFIG_PATH), "After migration, the file should be encrypted")
	
	var config := ConfigFile.new()
	var enc_err: int = config.load_encrypted_pass(TEST_CONFIG_PATH, Globals.save_encryption_pass)
	assert_eq(enc_err, OK, "After migration, the file should be successfully read as encrypted")


## Scenario 4: Lossless Multi-Writer Migration
## Verifies that migrating a plaintext file containing unrelated sections 
## (e.g. [audio], [Settings]) to an encrypted format preserves those sections perfectly.
func test_lossless_multi_writer_migration() -> void:
	# 1. Create a legacy plaintext file populated with multiple manager sections
	var legacy_cfg := ConfigFile.new()
	legacy_cfg.set_value("input", "speed_up", ["key:87"])
	legacy_cfg.set_value("audio", "master_volume", 0.75)
	legacy_cfg.set_value("Settings", "difficulty", 2.0)
	legacy_cfg.save(TEST_CONFIG_PATH)

	# 2. Trigger the load/save migration cycle via Settings
	Settings.load_input_mappings(TEST_CONFIG_PATH)
	if Settings._needs_save:
		Settings.save_input_mappings(TEST_CONFIG_PATH)
		Settings._needs_save = false

	# 3. Verify it is now encrypted
	assert_true(Settings._is_file_encrypted(TEST_CONFIG_PATH), "File should be encrypted after migration")

	# 4. Verify lossless data preservation via encrypted load
	var enc_cfg := ConfigFile.new()
	var err: int = enc_cfg.load_encrypted_pass(TEST_CONFIG_PATH, Globals.save_encryption_pass)
	assert_eq(err, OK, "Encrypted load should succeed")

	assert_eq(enc_cfg.get_value("audio", "master_volume"), 0.75, "Audio section must be preserved losslessly")
	assert_eq(enc_cfg.get_value("Settings", "difficulty"), 2.0, "Settings section must be preserved losslessly")
	
	var events: Array[InputEvent] = InputMap.action_get_events("speed_up")
	assert_true(
		events.any(func(e: InputEvent) -> bool: return e is InputEventKey and e.physical_keycode == 87), 
		"Input mapping must be preserved losslessly"
	)
