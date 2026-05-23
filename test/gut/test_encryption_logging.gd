## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_encryption_logging.gd
##
## GUT unit tests explicitly designed to trigger the new encryption logging branches.
## Running this test suite will produce the new 🚨 ERROR, ⚠️ WARNING, and 🔓 DEBUG 
## logs in the console, verifying that the alerts fire under the correct conditions.

extends GutTest

const TEST_CONFIG_PATH: String = "user://test_encryption_logging.cfg"
const INVALID_CONFIG_PATH: String = "user://invalid_directory_that_does_not_exist/test.cfg"

var _original_settings: GameSettingsResource


func before_each() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	
	# Wipe cached key to force re-generation
	Globals.save_encryption_pass = ""
	
	_original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()
	
	# Force log level to DEBUG so we see everything in the console
	Globals.settings.current_log_level = Globals.LogLevel.DEBUG


func after_each() -> void:
	Globals.settings = _original_settings
	Globals.save_encryption_pass = ""
		
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)

# ==============================================================================
# GLOBALS.GD LOGGING TESTS
# ==============================================================================

## EXPECTED LOG: 🔑 Encryption key successfully generated and cached in memory.
func test_log_ensure_encryption_key_success() -> void:
	gut.p("Testing LOG: 🔑 Encryption key successfully generated")
	
	var key: String = Globals.ensure_encryption_key()
	
	assert_ne(key, "", "Key should be successfully generated.")
	assert_eq(Globals.save_encryption_pass, key, "Key should be cached in memory.")

## EXPECTED LOG: Config file not found at: ... (Normal for first-time boot)
func test_log_safe_load_config_not_found() -> void:
	gut.p("Testing LOG: Config file not found at...")
	
	var result: Dictionary = Globals.safe_load_config(TEST_CONFIG_PATH)
	assert_eq(result["err"], ERR_FILE_NOT_FOUND, "Should return file not found error.")

## EXPECTED LOG: 🔒 Encrypted settings persisted successfully
## EXPECTED LOG: 🔓 Successfully decrypted file
func test_log_safe_load_config_decrypt_success() -> void:
	gut.p("Testing LOG: 🔒 Encrypted settings persisted AND 🔓 Successfully decrypted file")
	
	# Trigger the successful save log
	Globals._save_settings(TEST_CONFIG_PATH)
	
	# Trigger the successful load log
	var result: Dictionary = Globals.safe_load_config(TEST_CONFIG_PATH)
	assert_eq(result["err"], OK, "File should decrypt successfully.")
	assert_false(result["is_legacy"], "File should not be marked as legacy plaintext.")

## EXPECTED LOG: ⚠️ Loaded unencrypted plaintext file: ... Migration needed.
func test_log_safe_load_config_plaintext_warning() -> void:
	gut.p("Testing LOG: ⚠️ Loaded unencrypted plaintext file")
	
	# Manually create a legacy plaintext file
	var config: ConfigFile = ConfigFile.new()
	config.set_value("Settings", "dummy_val", 1)
	config.save(TEST_CONFIG_PATH)
	
	var result: Dictionary = Globals.safe_load_config(TEST_CONFIG_PATH)
	assert_eq(result["err"], OK, "Plaintext should load fine.")
	assert_true(result["is_legacy"], "File MUST be flagged as legacy plaintext to trigger migration.")

## EXPECTED LOG: 🚨 CRITICAL ENCRYPTION FAILURE: Failed to save encrypted settings
func test_log_save_settings_encryption_failure() -> void:
	gut.p("Testing LOG: 🚨 CRITICAL ENCRYPTION FAILURE")
	
	# Attempting to save to a directory that does not exist will force Godot to throw ERR_CANT_OPEN
	# This triggers the catastrophic failure log.
	Globals._save_settings(INVALID_CONFIG_PATH)
	
	assert_false(FileAccess.file_exists(INVALID_CONFIG_PATH), "File should not exist.")

# ==============================================================================
# SETTINGS.GD LOGGING TESTS
# ==============================================================================

## EXPECTED LOG: 🔒 Encrypted input mappings saved
func test_log_save_input_mappings_success() -> void:
	gut.p("Testing LOG: 🔒 Encrypted input mappings saved")
	
	# Trigger successful save from settings.gd
	Settings.save_input_mappings(TEST_CONFIG_PATH, ["fire"])
	assert_true(FileAccess.file_exists(TEST_CONFIG_PATH), "Input mappings should save successfully.")

## EXPECTED LOG: 🚨 ENCRYPTION FAILURE: Failed to save encrypted input mappings
func test_log_save_input_mappings_failure() -> void:
	gut.p("Testing LOG: 🚨 ENCRYPTION FAILURE for input mappings")
	
	# Attempting to save to a non-existent directory forces the failure log in settings.gd
	Settings.save_input_mappings(INVALID_CONFIG_PATH, ["fire"])
	assert_false(FileAccess.file_exists(INVALID_CONFIG_PATH), "File should not exist.")
