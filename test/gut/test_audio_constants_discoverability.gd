## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_audio_constants_discoverability.gd
##
## Quality control suite validating that the base asset directory, bus structures,
## UI mappings, and filename maps are fully discoverable, statically typed, and verified.

extends "res://addons/gut/test.gd"

# ==========================================================================
# 1. DIRECTORY PATHS & STATIC CONSTANTS VERIFICATION
# ==========================================================================

## Verifies that the base SFX directory is properly exposed and present on the filesystem.
func test_sfx_dir_path_is_configured_and_exists() -> void:
	assert_true(
		"SFX_DIR_PATH" in AudioConstants, 
		"AudioConstants must expose SFX_DIR_PATH to satisfy developer configuration searchability."
	)
	
	var path: String = AudioConstants.SFX_DIR_PATH
	
	assert_ne(path, "", "SFX_DIR_PATH must not be an empty string.")
	assert_true(
		path.ends_with("/"), 
		"SFX_DIR_PATH must end with a trailing slash to prevent path concatenation errors."
	)
	
	var dir_exists := DirAccess.dir_exists_absolute(path)
	assert_true(
		dir_exists, 
		"The configured base directory path '%s' must physically exist in the project tree." % path
	)


## Verifies all audio bus string constants match expected names exactly.
func test_bus_name_constants() -> void:
	assert_eq(AudioConstants.BUS_MASTER, "Master", "BUS_MASTER mismatch.")
	assert_eq(AudioConstants.BUS_MUSIC, "Music", "BUS_MUSIC mismatch.")
	assert_eq(AudioConstants.BUS_SFX, "SFX", "BUS_SFX mismatch.")
	assert_eq(AudioConstants.BUS_SFX_ROTORS, "SFX_Rotors", "BUS_SFX_ROTORS mismatch.")
	assert_eq(AudioConstants.BUS_SFX_WEAPON, "SFX_Weapon", "BUS_SFX_WEAPON mismatch.")
	assert_eq(AudioConstants.BUS_SFX_MENU, "SFX_Menu", "BUS_SFX_MENU mismatch.")


# ==========================================================================
# 2. FILE RESOLUTION & REFERENCE INTEGRITY
# ==========================================================================

## Verifies that every asset mapped in SFX_ASSET_MAP is fully resolvable on the filesystem.
func test_sfx_asset_map_resolution_integrity() -> void:
	assert_true(
		"SFX_ASSET_MAP" in AudioConstants, 
		"AudioConstants must expose SFX_ASSET_MAP for dynamic path builds."
	)
	
	var base_dir: String = AudioConstants.SFX_DIR_PATH
	var asset_map: Dictionary = AudioConstants.SFX_ASSET_MAP
	
	assert_gt(
		asset_map.size(), 
		0, 
		"SFX_ASSET_MAP must contain at least one registered logical audio configuration."
	)
	
	# FIXED: Explicit static type definition on the loop iterator variable
	for sfx_key: String in asset_map.keys():
		var filename: String = asset_map[sfx_key]
		var full_path: String = base_dir + filename
		
		var file_exists := FileAccess.file_exists(full_path)
		assert_true(
			file_exists, 
			"Resolved physical file for key '%s' expected at '%s' is missing on disk." % [sfx_key, full_path]
		)


# ==========================================================================
# 3. BUS CONFIGURATION MATRIX QUALITY GATES
# ==========================================================================

## Validates that BUS_CONFIG contains all buses with their correct metadata structures.
func test_bus_config_matrix_integrity() -> void:
	var expected_buses: Array[String] = [
		AudioConstants.BUS_MASTER,
		AudioConstants.BUS_MUSIC,
		AudioConstants.BUS_SFX,
		AudioConstants.BUS_SFX_ROTORS,
		AudioConstants.BUS_SFX_WEAPON,
		AudioConstants.BUS_SFX_MENU
	]
	
	var config: Dictionary = AudioConstants.BUS_CONFIG
	
	for bus: String in expected_buses:
		assert_true(
			config.has(bus), 
			"BUS_CONFIG is missing registration entry for bus: %s" % bus
		)
		
		var bus_meta: Dictionary = config[bus]
		
		# Ensure structural fields exist
		assert_true(bus_meta.has("volume_var"), "Bus %s missing 'volume_var' mapping." % bus)
		assert_true(bus_meta.has("muted_var"), "Bus %s missing 'muted_var' mapping." % bus)
		assert_true(bus_meta.has("default_volume"), "Bus %s missing 'default_volume' mapping." % bus)
		assert_true(bus_meta.has("default_muted"), "Bus %s missing 'default_muted' mapping." % bus)
		
		# Strictly assert data types to prevent serialization mismatches
		assert_true(bus_meta["volume_var"] is String, "volume_var must be a String.")
		assert_true(bus_meta["muted_var"] is String, "muted_var must be a String.")
		assert_true(
			bus_meta["default_volume"] is float or bus_meta["default_volume"] is int, 
			"default_volume must be numeric."
		)
		assert_true(bus_meta["default_muted"] is bool, "default_muted must be a boolean.")


# ==========================================================================
# 4. REFERENTIAL INTEGRITY (UI ACTIONS TO PHYSICAL FILES)
# ==========================================================================

## Verifies that every input action in UI_SFX maps cleanly to a valid asset in SFX_ASSET_MAP.
## This acts as a compile-time block preventing silent audio deadlocks on actions.
func test_ui_sfx_referential_integrity() -> void:
	var ui_sfx: Dictionary = AudioConstants.UI_SFX
	var asset_map: Dictionary = AudioConstants.SFX_ASSET_MAP
	
	# Loop through all mapped actions with strict static type safety
	for action_name: String in ui_sfx.keys():
		var logical_sfx_key: String = ui_sfx[action_name]
		
		# Assert that the UI sound action refers to a defined asset mapping identifier
		assert_true(
			asset_map.has(logical_sfx_key),
			"UI Action '%s' maps to an unresolved logical key '%s' missing from SFX_ASSET_MAP." 
			% [action_name, logical_sfx_key]
		)
