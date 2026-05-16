## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_encryption_failsafe.gd
##
## GUT unit tests for the Settings Encryption Failsafe.
## Updated for the GDScript Bytecode Injection architecture.
## Verifies that the hardcoded salt successfully encrypts the file.

extends GutTest

const TEST_CONFIG_PATH: String = "user://test_encryption_failsafe.cfg"

var _original_settings: GameSettingsResource
var _original_key: String

## Per-test setup: Isolate the filesystem and setup Globals.
func before_each() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	
	_original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()
	
	# Wipe the cached key to force re-evaluation
	_original_key = Globals.save_encryption_pass
	Globals.save_encryption_pass = ""


## Per-test cleanup: Restore Globals and remove temporary files.
func after_each() -> void:
	Globals.settings = _original_settings
	Globals.save_encryption_pass = _original_key
	
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)


## TEST 1: The New Architecture Validation
func test_bytecode_salt_generates_valid_key() -> void:
	gut.p("Testing: 'ensure_encryption_key' generates a valid hash from the bytecode salt.")
	
	var generated_key: String = Globals.ensure_encryption_key()
	
	assert_false(generated_key.is_empty(), "CRITICAL: The generated key should not be empty.")
	# SHA-256 hashes are exactly 64 characters long
	assert_eq(generated_key.length(), 64, "The generated key should be a valid SHA-256 hash string.")


## TEST 2: The Intended Scenario (Encryption Active)
func test_save_encrypts_file_with_valid_key() -> void:
	gut.p("Testing: Valid key successfully encrypts the settings file.")
	
	Globals._save_settings(TEST_CONFIG_PATH)
	
	assert_true(FileAccess.file_exists(TEST_CONFIG_PATH), "Settings file should have been created.")
	
	# Instead of reading as UTF-8 text and triggering console errors,
	# we safely check the binary magic number.
	var is_encrypted: bool = Globals.is_file_encrypted(TEST_CONFIG_PATH)
	assert_true(is_encrypted, "Encryption failed: The file does not have the encrypted file magic number.")
