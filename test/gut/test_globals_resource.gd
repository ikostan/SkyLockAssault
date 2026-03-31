## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_globals_resource.gd
## GUT unit tests for Globals singleton migration to Resource-based settings.

extends GutTest

const TEST_RESOURCE_PATH: String = "user://test_settings.tres"

func before_each() -> void:
	if FileAccess.file_exists(TEST_RESOURCE_PATH):
		DirAccess.remove_absolute(TEST_RESOURCE_PATH)
	
	# REMOVE the double_scene line. It is causing the crash in Image 7.
	# If you need to stop log spam, just do this:
	Globals.settings.current_log_level = Globals.LogLevel.NONE

func after_each() -> void:
	if FileAccess.file_exists(TEST_RESOURCE_PATH):
		DirAccess.remove_absolute(TEST_RESOURCE_PATH)

# --- 1. Logging Resource Tests ---

func test_logging_default_level() -> void:
	gut.p("Testing: Log level should default to INFO (1).")
	
	# FIX: Load the actual resource file instead of creating a blank .new()
	Globals.settings = load("res://config_resources/default_settings.tres") 
	
	assert_eq(Globals.settings.current_log_level, 1, "Default log level must be INFO (1)")


func test_logging_persistence() -> void:
	gut.p("Testing: Persistence writes to config file.")
	Globals.settings.current_log_level = 0 # DEBUG
	Globals._save_settings(TEST_RESOURCE_PATH)
	
	assert_true(FileAccess.file_exists(TEST_RESOURCE_PATH), "Config file should exist")
	
	var config := ConfigFile.new()
	var err := config.load(TEST_RESOURCE_PATH)
	assert_eq(err, OK, "ConfigFile should load successfully")
	
	# Matches the key used in globals.gd line 241 
	assert_eq(config.get_value("Settings", "log_level"), 0, "Saved value check")

# --- 2. Gameplay Resource Tests ---

func test_difficulty_clamping() -> void:
	gut.p("Testing: Difficulty should respect valid range (0.5 to 2.0).")
	# Setup a ConfigFile with an invalid high value
	var config := ConfigFile.new()
	config.set_value("Settings", "difficulty", 5.0)
	config.save(TEST_RESOURCE_PATH)
	
	# Load it via Globals logic
	Globals._load_settings(TEST_RESOURCE_PATH)
	
	# Assert it was clamped by the setter in GameSettingsResource
	assert_eq(Globals.settings.difficulty, 2.0, "Difficulty should clamp to max (2.0)")

# --- 3. UI & Scenes Resource Tests ---

func test_scene_resource_validity() -> void:
	gut.p("Testing: PackedScenes in Resource are valid and preloaded.")
	# Verifies that migrating paths to Resources doesn't break preloading
	assert_not_null(Globals.settings.key_mapping_scene, "Key mapping scene must be assigned in Resource")
	assert_true(Globals.settings.key_mapping_scene is PackedScene, "Key mapping should be a PackedScene")

func test_remap_prompt_strings() -> void:
	gut.p("Testing: Remap prompt strings are correctly retrieved from Resource.")
	# Verifies migration of hard-coded constants [cite: 3]
	assert_eq(Globals.settings.remap_prompt_keyboard, "Press a key...", "Keyboard prompt mismatch")
	assert_string_contains(Globals.settings.remap_prompt_gamepad, "gamepad", "Gamepad prompt should mention device")

# --- 4. Edge Case: Corrupted Resource ---

func test_corrupted_resource_fallback() -> void:
	gut.p("Testing: Corrupted resource file falls back to defaults (Defensive Test).")
	# Create a dummy file that isn't a valid Resource
	var f: FileAccess = FileAccess.open(TEST_RESOURCE_PATH, FileAccess.WRITE)
	f.store_string("not a resource file")
	f.close()
	
	Globals._load_settings(TEST_RESOURCE_PATH)
	# Should fall back to your 'preload' default in globals.gd
	assert_not_null(Globals.settings, "Globals should never have a null settings reference")
	
