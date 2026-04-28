## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
# test_settings_persistence.gd (extends GdUnitTestSuite)
extends GdUnitTestSuite


func test_settings_persistence() -> void:
	## Tests persistence with isolated path.
	##
	## :rtype: void
	var test_path: String = "user://test_settings.cfg"
	
	# Setup: Create and save test config using encryption
	var config: ConfigFile = ConfigFile.new()
	config.set_value("Settings", "difficulty", 1.5)
	
	# FIX: Save using encrypted pass so Globals._load_settings doesn't throw a C++ core error
	var err: int = config.save_encrypted_pass(test_path, Globals.save_encryption_pass)
	if err != OK:
		fail("Failed to save test config: " + str(err))
	
	Globals._load_settings(test_path)
	assert_float(Globals.settings.difficulty).is_equal(1.5)  # Loaded
	
	Globals.settings.difficulty = 2.0
	Globals._save_settings(test_path)
	
	# Reload to verify save
	Globals._load_settings(test_path)
	assert_float(Globals.settings.difficulty).is_equal(2.0)  # Saved and loaded


func after_test() -> void:
	## Cleans test file.
	##
	## :rtype: void
	var test_path: String = "user://test_settings.cfg"
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(test_path)
