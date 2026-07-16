## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_audio_constants_discoverability.gd
##
## Quality control suite validating that the audio bus structures,
## UI mappings, and filename dictionary formats match production standards.

extends "res://addons/gut/test.gd"

# ==========================================================================
# 1. BUS NAME CONSTANTS VERIFICATION
# ==========================================================================

## Verifies all audio bus string constants match expected names exactly.
func test_bus_name_constants() -> void:
	assert_eq(AudioConstants.BUS_MASTER, "Master", "BUS_MASTER mismatch.")
	assert_eq(AudioConstants.BUS_MUSIC, "Music", "BUS_MUSIC mismatch.")
	assert_eq(AudioConstants.BUS_SFX, "SFX", "BUS_SFX mismatch.")
	assert_eq(AudioConstants.BUS_SFX_ROTORS, "SFX_Rotors", "BUS_SFX_ROTORS mismatch.")
	assert_eq(AudioConstants.BUS_SFX_WEAPON, "SFX_Weapon", "BUS_SFX_WEAPON mismatch.")
	assert_eq(AudioConstants.BUS_SFX_MENU, "SFX_Menu", "BUS_SFX_MENU mismatch.")


# ==========================================================================
# 2. DICTIONARY STRUCTURE INTEGRITY
# ==========================================================================

## Verifies that SFX_ASSET_MAP is a populated dictionary containing valid string mappings
## without relying on or exposing internal engine folder layout paths.
func test_sfx_asset_map_structural_integrity() -> void:
	assert_true(
		"SFX_ASSET_MAP" in AudioConstants, 
		"AudioConstants must expose SFX_ASSET_MAP for dynamic path builds."
	)
	
	var asset_map: Dictionary = AudioConstants.SFX_ASSET_MAP
	
	assert_gt(
		asset_map.size(), 
		0, 
		"SFX_ASSET_MAP must contain at least one registered logical audio configuration."
	)
	
	# Statically typed loop checking schema validity without poking the file system
	for sfx_key: String in asset_map.keys():
		assert_true(asset_map[sfx_key] is String, "Mapping value for '%s' must be a String." % sfx_key)
		assert_true(not asset_map[sfx_key].is_empty(), "Mapping value for '%s' must not be empty." % sfx_key)


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
# 4. REFERENTIAL INTEGRITY (UI ACTIONS TO LOGICAL KEY MAPS)
# ==========================================================================

## Verifies that every input action in UI_SFX maps cleanly to a valid asset in SFX_ASSET_MAP.
func test_ui_sfx_referential_integrity() -> void:
	var ui_sfx: Dictionary = AudioConstants.UI_SFX
	var asset_map: Dictionary = AudioConstants.SFX_ASSET_MAP
	
	for action_name: String in ui_sfx.keys():
		var logical_sfx_key: String = ui_sfx[action_name]
		
		assert_true(
			asset_map.has(logical_sfx_key),
			"UI Action '%s' maps to an unresolved logical key '%s' missing from SFX_ASSET_MAP." 
			% [action_name, logical_sfx_key]
		)
