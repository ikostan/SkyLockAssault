## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_globals.gd
## Unit tests for globals.gd saving/loading.
##
## Focuses on shared config preservation.

extends GdUnitTestSuite

var globals: Node
var test_path: String = "user://test_globals.cfg"  # Temp for isolation


func before_test() -> void:
	# Instantiate the script
	globals = auto_free(load("res://scripts/core/globals.gd").new())
	
	# FIX: Manually initialize the settings resource 
	# because _ready() hasn't run yet.
	globals.settings = GameSettingsResource.new()


func after_test() -> void:
	## Per-test cleanup: Remove test file.
	##
	## :rtype: void
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(test_path)


func test_save_settings_preserves_other_sections() -> void:
	## Tests settings save preserves unrelated sections (e.g., "audio").
	##
	## :rtype: void
	# Pre-create config with non-settings section using encryption
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "master_volume", 0.6)
	config.save_encrypted_pass(test_path, globals.save_encryption_pass)
	
	# Save settings
	globals.settings.difficulty = 1.2
	globals._save_settings(test_path)
	
	# Reload encrypted file and check both preserved
	config = ConfigFile.new()
	config.load_encrypted_pass(test_path, globals.save_encryption_pass)
	assert_float(config.get_value("Settings", "difficulty", 1.0)).is_equal(1.2)
	assert_float(config.get_value("audio", "master_volume", 1.0)).is_equal(0.6)


func test_load_settings_with_other_sections() -> void:
	## Tests load ignores/preserves other sections.
	##
	## :rtype: void
	# Pre-save mixed config using encryption
	var config: ConfigFile = ConfigFile.new()
	config.set_value("Settings", "difficulty", 0.8)
	config.set_value("audio", "master_volume", 0.4)
	config.save_encrypted_pass(test_path, globals.save_encryption_pass)
	
	# Load via globals
	globals._load_settings(test_path)
	assert_float(globals.settings.difficulty).is_equal(0.8)
	
	# Audio settings shouldn't be loaded into Globals.settings, but file should still have it
	config = ConfigFile.new()
	config.load_encrypted_pass(test_path, globals.save_encryption_pass)
	assert_float(config.get_value("audio", "master_volume", 1.0)).is_equal(0.4)
