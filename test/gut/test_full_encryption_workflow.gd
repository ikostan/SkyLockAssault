## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_full_encryption_workflow.gd
##
## GUT unit tests for the complete Settings Encryption Workflow.
## Covers Fresh Installs, Plaintext Fallbacks (Migrations), Mixed Systems,
## Restart behaviors, and Corrupted Files.

extends GutTest

const TEST_CONFIG_PATH: String = "user://test_encryption_workflow.cfg"
const SALT_PROPERTY: String = "game/security/save_salt"
const DUMMY_SALT: String = "test_workflow_salt_999"

var _original_salt_value: Variant = null
var _original_salt_existed: bool = false
var _original_settings: GameSettingsResource


## Per-test setup: Isolate the filesystem, backup ProjectSettings, and setup Globals.
## :rtype: void
func before_each() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	
	_original_salt_existed = ProjectSettings.has_setting(SALT_PROPERTY)
	if _original_salt_existed:
		_original_salt_value = ProjectSettings.get_setting(SALT_PROPERTY)
		
	# Ensure the salt is properly set so encryption is active by default in these tests
	ProjectSettings.set_setting(SALT_PROPERTY, DUMMY_SALT)
	
	# FIX: Clear the cached key in Globals so it is forced to recalculate using the DUMMY_SALT
	Globals.save_encryption_pass = ""
	
	_original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()
	Globals.settings.difficulty = 1.0  # Set a known default


## Per-test cleanup: Restore ProjectSettings and remove temporary files.
## :rtype: void
func after_each() -> void:
	Globals.settings = _original_settings
	
	if _original_salt_existed:
		ProjectSettings.set_setting(SALT_PROPERTY, _original_salt_value)
	else:
		ProjectSettings.clear(SALT_PROPERTY)
		
	# Clean up cached key to not pollute other tests
	Globals.save_encryption_pass = ""
		
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)


## Scenario 1: Fresh Install
## Save mappings → file is encrypted. Load → works correctly.
## :rtype: void
func test_scenario_1_fresh_install_encrypts_and_loads() -> void:
	gut.p("Scenario 1: Fresh install saves encrypted and loads correctly.")
	
	# 1. Save state
	Globals.settings.difficulty = 1.8
	Globals._save_settings(TEST_CONFIG_PATH)
	assert_true(FileAccess.file_exists(TEST_CONFIG_PATH), "File should be created.")
	
	# 2. Verify encryption (first character is NOT plaintext '[')
	var file: FileAccess = FileAccess.open(TEST_CONFIG_PATH, FileAccess.READ)
	var first_line: String = file.get_line()
	file.close()
	assert_false(first_line.begins_with("["), "File should be encrypted (no plaintext headers).")
	
	# 3. Modify memory to ensure load overwrites it
	Globals.settings.difficulty = 0.5
	
	# 4. Load state
	Globals._load_settings(TEST_CONFIG_PATH)
	assert_eq(Globals.settings.difficulty, 1.8, "Encrypted settings should load correctly.")


## Scenario 2: Existing Plaintext File
## Load → succeeds via fallback. _needs_save triggers rewrite. File becomes encrypted.
## :rtype: void
func test_scenario_2_plaintext_fallback_and_migration() -> void:
	gut.p("Scenario 2: Plaintext files load via fallback, and are rewritten as encrypted.")
	
	# 1. Create a legacy plaintext file manually
	var config: ConfigFile = ConfigFile.new()
	config.set_value("Settings", "difficulty", 1.3)
	config.save(TEST_CONFIG_PATH)  # Standard save, no encryption
	
	# Verify it is plaintext
	var file: FileAccess = FileAccess.open(TEST_CONFIG_PATH, FileAccess.READ)
	assert_true(file.get_line().begins_with("["), "File starts as plaintext.")
	file.close()
	
	# 2. Load settings (Fallback should catch this)
	Globals.settings.difficulty = 0.0 # Clear memory
	Globals._load_settings(TEST_CONFIG_PATH)
	assert_eq(Globals.settings.difficulty, 1.3, "Fallback should successfully load plaintext data.")
	
	# 3. Trigger a save (Simulating _needs_save or normal gameplay save)
	Globals._save_settings(TEST_CONFIG_PATH)
	
	# 4. Verify file is now encrypted
	file = FileAccess.open(TEST_CONFIG_PATH, FileAccess.READ)
	assert_false(file.get_line().begins_with("["), "File should now be converted to encrypted format.")
	file.close()


## Scenario 3: Mixed Systems (Critical)
## globals.gd writes settings. settings.gd writes input. Verify no data loss.
## :rtype: void
func test_scenario_3_mixed_systems_no_data_loss() -> void:
	gut.p("Scenario 3: Globals and Settings singletons can write to the same encrypted file without wiping each other.")
	
	# 1. Globals writes to the file first
	Globals.settings.difficulty = 1.9
	Globals._save_settings(TEST_CONFIG_PATH)
	
	# 2. Settings singleton (Input mappings) writes to the same file
	# We simulate the exact behavior of Settings.save_input_mappings() here
	var config: ConfigFile = ConfigFile.new()
	# FIX: Use ensure_encryption_key() to use the cached key identical to Globals
	var key: String = Globals.ensure_encryption_key() 
	config.load_encrypted_pass(TEST_CONFIG_PATH, key) # Must load existing first!
	config.set_value("input", "test_action", ["key:87"])
	config.save_encrypted_pass(TEST_CONFIG_PATH, key)
	
	# 3. Reload from Globals
	Globals.settings.difficulty = 0.0
	Globals._load_settings(TEST_CONFIG_PATH)
	
	# 4. Verify Globals data survived
	assert_eq(Globals.settings.difficulty, 1.9, "Globals settings must survive another system writing to the file.")
	
	# 5. Verify Settings data survived
	var verify_config: ConfigFile = ConfigFile.new()
	verify_config.load_encrypted_pass(TEST_CONFIG_PATH, key)
	var input_val: Variant = verify_config.get_value("input", "test_action", [])
	assert_eq(input_val, ["key:87"], "Input mappings must survive Globals writing to the file.")


## Scenario 4: Restart After Migration
## Load → encrypted path only. No fallback triggered.
## :rtype: void
func test_scenario_4_restart_after_migration() -> void:
	gut.p("Scenario 4: Restart simulation loads directly from encrypted file.")
	
	# 1. Create encrypted file (simulating post-migration state)
	Globals.settings.difficulty = 1.4
	Globals._save_settings(TEST_CONFIG_PATH)
	
	# 2. Wipe memory (simulating game exit and restart)
	Globals.settings = GameSettingsResource.new()
	
	# 3. Load settings
	Globals._load_settings(TEST_CONFIG_PATH)
	
	# 4. Verify
	assert_eq(Globals.settings.difficulty, 1.4, "Settings loaded successfully on restart.")


## Scenario 5: Corrupted File
## Load fails gracefully. No crash.
## :rtype: void
func test_scenario_5_corrupted_file_fails_gracefully() -> void:
	gut.p("Scenario 5: Corrupted encrypted file fails gracefully without crashing.")
	
	# 1. Write literal garbage bytes to the file to simulate corruption
	var file: FileAccess = FileAccess.open(TEST_CONFIG_PATH, FileAccess.WRITE)
	file.store_string("THIS_IS_CORRUPTED_GARBAGE_DATA_THAT_IS_NOT_ENCRYPTED_OR_PLAINTEXT_CFG")
	file.close()
	
	# 2. Attempt to load (this would crash Godot if not handled properly)
	Globals.settings.difficulty = 1.0 # Set default
	Globals._load_settings(TEST_CONFIG_PATH)
	
	# 3. Verify it failed gracefully and kept defaults
	assert_eq(Globals.settings.difficulty, 1.0, "Should handle corruption gracefully and retain default settings.")
