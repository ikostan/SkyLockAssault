## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_encryption_failsafe.gd
##
## GUT unit tests for the Settings Encryption Failsafe.
## Covers the specific edge case where the CI/CD pipeline injects a salt,
## but Godot's headless exporter strips it due to un-registered ProjectSettings.
## Verifies that missing salts trigger plaintext fallback, and valid salts encrypt.

extends GutTest

const TEST_CONFIG_PATH: String = "user://test_encryption_failsafe.cfg"
const SALT_PROPERTY: String = "game/security/save_salt"

var _original_salt_value: Variant = null
var _original_salt_existed: bool = false
var _original_settings: GameSettingsResource

## Per-test setup: Isolate the filesystem, backup ProjectSettings, and setup Globals.
func before_each() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	
	_original_salt_existed = ProjectSettings.has_setting(SALT_PROPERTY)
	if _original_salt_existed:
		_original_salt_value = ProjectSettings.get_setting(SALT_PROPERTY)
	
	_original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()
	
	# FIX: Wipe the cached key to force re-evaluation for the failsafe tests
	Globals.save_encryption_pass = ""


## Per-test cleanup: Restore ProjectSettings and remove temporary files.
func after_each() -> void:
	Globals.settings = _original_settings
	
	if _original_salt_existed:
		ProjectSettings.set_setting(SALT_PROPERTY, _original_salt_value)
	else:
		ProjectSettings.clear(SALT_PROPERTY)
		
	# FIX: Clean up cached key so it doesn't bleed into other GUT scripts
	Globals.save_encryption_pass = ""
		
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)


## TEST 1: The Root Cause Validation
func test_ci_salt_property_is_registered_in_engine() -> void:
	gut.p("Testing: 'game/security/save_salt' must be a registered Project Setting to survive CI export.")
	
	var property_list: Array[Dictionary] = ProjectSettings.get_property_list()
	var property_found: bool = false
	
	for prop: Dictionary in property_list:
		if prop["name"] == SALT_PROPERTY:
			property_found = true
			break
			
	assert_true(property_found, "CRITICAL: The salt property is not registered in the Godot Editor. The CI pipeline will strip it during export!")


## TEST 2: The Bug Scenario (Missing Salt)
func test_failsafe_saves_plaintext_when_salt_is_missing() -> void:
	gut.p("Testing: Missing salt triggers failsafe and saves file as plaintext.")
	
	ProjectSettings.set_setting(SALT_PROPERTY, "")
	
	Globals._save_settings(TEST_CONFIG_PATH)
	
	assert_true(FileAccess.file_exists(TEST_CONFIG_PATH), "Settings file should have been created.")
	
	var file: FileAccess = FileAccess.open(TEST_CONFIG_PATH, FileAccess.READ)
	assert_not_null(file, "Should be able to open the file.")
	
	var first_line: String = file.get_line()
	file.close()
	
	assert_true(first_line.begins_with("["), "Failsafe failed: File should be readable plaintext starting with '[' when salt is missing.")


## TEST 3: The Intended Scenario (Salt Present)
func test_save_encrypts_file_when_salt_is_present() -> void:
	gut.p("Testing: Valid salt successfully encrypts the settings file.")
	
	ProjectSettings.set_setting(SALT_PROPERTY, "valid_test_salt_12345")
	
	Globals._save_settings(TEST_CONFIG_PATH)
	
	assert_true(FileAccess.file_exists(TEST_CONFIG_PATH), "Settings file should have been created.")
	
	var file: FileAccess = FileAccess.open(TEST_CONFIG_PATH, FileAccess.READ)
	assert_not_null(file, "Should be able to open the file.")
	
	var first_line: String = file.get_line()
	file.close()
	
	assert_false(first_line.begins_with("["), "Encryption failed: File is still readable plaintext despite having a valid salt.")
