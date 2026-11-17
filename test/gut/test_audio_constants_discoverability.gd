## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_audio_constants_discoverability.gd
##
## Quality control suite validating that the audio bus structures,
## UI mappings, and filename dictionary formats match production standards.

extends "res://addons/gut/test.gd"

const PlayerScene: PackedScene = preload("res://scenes/Player.tscn")
const AdvancedSettingsScript: GDScript = preload("res://scripts/ui/menus/advanced_settings.gd")

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
	assert_eq(AudioConstants.BUS_SFX_ROTOR_LEFT, "SFX_Rotor_Left", "BUS_SFX_ROTOR_LEFT mismatch.")
	assert_eq(
		AudioConstants.BUS_SFX_ROTOR_RIGHT, "SFX_Rotor_Right", "BUS_SFX_ROTOR_RIGHT mismatch."
	)


## AudioConstants is a class_name script with constants only, not an autoload (#1149).
func test_audio_constants_is_not_an_autoload() -> void:
	assert_false(
		ProjectSettings.has_setting("autoload/AudioConstants"),
		"project.godot must not list AudioConstants as an autoload."
	)
	assert_null(
		get_tree().root.get_node_or_null("AudioConstants"),
		"No AudioConstants node should exist under /root."
	)


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


## The check sound has one constant and one map entry (#1149). It used to play only
## through the .wav fallback, with SFX_MUTE_TOGGLE as a second name for the same file.
func test_check_sound_is_mapped_once() -> void:
	var asset_map: Dictionary = AudioConstants.SFX_ASSET_MAP
	assert_true(
		asset_map.has(AudioConstants.SFX_CHECK),
		"SFX_CHECK must have its own SFX_ASSET_MAP entry instead of relying on the fallback."
	)
	assert_eq(asset_map.get(AudioConstants.SFX_CHECK, ""), "check.wav", "SFX_CHECK must map to check.wav.")
	assert_true(
		ResourceLoader.exists(AudioConstants.SFX_DIR_PATH + "check.wav"),
		"The file mapped by SFX_CHECK must exist."
	)
	assert_false(asset_map.has("mute_toggle"), "The unused 'mute_toggle' alias must be gone.")


## Every sound file has exactly one logical name, so one sound can't drift into
## several IDs again (#1149).
func test_each_sfx_file_has_one_logical_id() -> void:
	var owners: Dictionary = {}
	for sfx_key: String in AudioConstants.SFX_ASSET_MAP:
		var file_name: String = AudioConstants.SFX_ASSET_MAP[sfx_key]
		assert_false(
			owners.has(file_name),
			"'%s' is mapped by both '%s' and '%s'." % [file_name, owners.get(file_name, ""), sfx_key]
		)
		owners[file_name] = sfx_key


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


# ==========================================================================
# 5. RUNTIME & SYSTEMIC INTEGRATION VERIFICATION
# ==========================================================================

## GUT Lifecycle hook: Runs automatically after every single test method.
## Guarantees the AudioManager is restored to a pristine state even if assertions fail.
func after_each() -> void:
	AudioManager.cleanup_for_test()


## Validates that every asset defined in the central map physically exists on disk
## AND successfully loads as a valid, uncorrupted AudioStream.
func test_all_mapped_assets_load_as_valid_audiostream() -> void:
	for key: String in AudioConstants.SFX_ASSET_MAP:
		var file_name: String = AudioConstants.SFX_ASSET_MAP[key]
		var full_path: String = AudioConstants.SFX_DIR_PATH + file_name
		
		# 1. Assert physical file existence on disk
		assert_true(ResourceLoader.exists(full_path), 
			"SFX mapping key '%s' points to a missing file on disk: %s" % [key, full_path])
		
		# 2. Force load the resource and verify it compiles to a valid AudioStream instance
		var stream: Resource = load(full_path)
		assert_not_null(stream, "Failed to load audio resource at: %s" % full_path)
		assert_true(stream is AudioStream, "Resource at %s is not a valid AudioStream." % full_path)


## Validates that the fallback menu mixing bus actually exists in the AudioServer.
func test_fallback_bus_exists_in_audio_server() -> void:
	var bus_idx: int = AudioServer.get_bus_index(AudioConstants.BUS_SFX_MENU)
	assert_gt(bus_idx, -1, 
		"Fallback mixing bus '%s' must exist in default_bus_layout.tres" % AudioConstants.BUS_SFX_MENU)


## Validates that the mixer routing in default_bus_layout.tres matches the mute/volume
## hierarchy the Audio Settings UI and AudioWebBridge enforce (Issue #1045):
## SFX sub-buses (Weapon, Rotors, Menu) must send to SFX, so muting or lowering SFX
## also silences or attenuates them. The rotor playback buses must feed SFX_Rotors,
## otherwise rotor audio would bypass the Rotors and SFX controls entirely.
func test_bus_routing_matches_ui_hierarchy() -> void:
	var expected_sends: Dictionary = {
		AudioConstants.BUS_MUSIC: AudioConstants.BUS_MASTER,
		AudioConstants.BUS_SFX: AudioConstants.BUS_MASTER,
		AudioConstants.BUS_SFX_WEAPON: AudioConstants.BUS_SFX,
		AudioConstants.BUS_SFX_ROTORS: AudioConstants.BUS_SFX,
		AudioConstants.BUS_SFX_MENU: AudioConstants.BUS_SFX,
		AudioConstants.BUS_SFX_ROTOR_LEFT: AudioConstants.BUS_SFX_ROTORS,
		AudioConstants.BUS_SFX_ROTOR_RIGHT: AudioConstants.BUS_SFX_ROTORS,
	}
	for bus: String in expected_sends:
		var bus_idx: int = AudioServer.get_bus_index(bus)
		assert_gt(bus_idx, -1, "Bus '%s' must exist in default_bus_layout.tres" % bus)
		if bus_idx == -1:
			continue
		assert_eq(
			String(AudioServer.get_bus_send(bus_idx)),
			expected_sends[bus],
			"Bus '%s' must send to '%s' to match the UI mute hierarchy." % [bus, expected_sends[bus]]
		)


## Reads the serialized layout instead of relying on mutable AudioServer state.
## Bus indices are discovered by name so harmless insertions do not break tests.
func _layout_bus_index(layout: AudioBusLayout, bus_name: String) -> int:
	for property: Dictionary in layout.get_property_list():
		var property_name: String = property["name"]
		if property_name.begins_with("bus/") and property_name.ends_with("/name"):
			if String(layout.get(property_name)) == bus_name:
				return int(property_name.split("/")[1])
	return -1


## Both stereo channels and direct rotor playback must pass through the SFX
## volume/mute control before reaching Master (regression for Issue #1045).
func test_saved_rotor_output_path_includes_sfx(
	source: String = use_parameters(
		[
			AudioConstants.BUS_SFX_ROTORS,
			AudioConstants.BUS_SFX_ROTOR_LEFT,
			AudioConstants.BUS_SFX_ROTOR_RIGHT
		]
	)
) -> void:
	var layout: AudioBusLayout = load("res://default_bus_layout.tres") as AudioBusLayout
	assert_not_null(layout, "The shipped default audio layout must load")
	if layout == null:
		return
	var expected_path: Array[String] = ["SFX_Rotors", "SFX", "Master"]
	if source != "SFX_Rotors":
		expected_path.push_front(source)
	for hop: int in range(expected_path.size() - 1):
		var bus_name: String = expected_path[hop]
		var bus_idx: int = _layout_bus_index(layout, bus_name)
		assert_gt(bus_idx, -1, "Rotor output bus '%s' must exist" % bus_name)
		if bus_idx == -1:
			return
		assert_eq(
			String(layout.get("bus/%d/send" % bus_idx)), expected_path[hop + 1],
			"'%s' must not bypass its parent volume/mute control" % bus_name
		)


## Godot only sends audio to buses on the left. A correct send name alone
## cannot protect against a reordered layout silently falling back to Master.
func test_saved_rotor_send_targets_precede_their_sources(
	source: String = use_parameters(
		[
			AudioConstants.BUS_SFX_ROTORS,
			AudioConstants.BUS_SFX_ROTOR_LEFT,
			AudioConstants.BUS_SFX_ROTOR_RIGHT,
			AudioConstants.BUS_SFX
		]
	)
) -> void:
	var layout: AudioBusLayout = load("res://default_bus_layout.tres") as AudioBusLayout
	assert_not_null(layout)
	if layout == null:
		return
	var source_idx: int = _layout_bus_index(layout, source)
	assert_gt(source_idx, -1, "Source bus '%s' must exist" % source)
	if source_idx == -1:
		return
	var target: String = String(layout.get("bus/%d/send" % source_idx))
	var target_idx: int = _layout_bus_index(layout, target)
	assert_gt(target_idx, -1, "Send target '%s' must exist" % target)
	assert_lt(target_idx, source_idx, "'%s' must send to an earlier bus, without cycles" % source)


## The new route must be audible by default; a muted bus or a solo on a
## sibling could mask a routing regression even with the correct send names.
func test_saved_rotor_output_path_is_enabled_by_default() -> void:
	var layout: AudioBusLayout = load("res://default_bus_layout.tres") as AudioBusLayout
	assert_not_null(layout)
	if layout == null:
		return
	for bus_name: String in [
		AudioConstants.BUS_MASTER,
		AudioConstants.BUS_SFX,
		AudioConstants.BUS_SFX_ROTORS,
		AudioConstants.BUS_SFX_ROTOR_LEFT,
		AudioConstants.BUS_SFX_ROTOR_RIGHT
	]:
		var bus_idx: int = _layout_bus_index(layout, bus_name)
		assert_gt(bus_idx, -1, "Rotor output bus '%s' must exist" % bus_name)
		if bus_idx == -1:
			continue
		assert_false(bool(layout.get("bus/%d/mute" % bus_idx)), "'%s' must start unmuted" % bus_name)
	for property: Dictionary in layout.get_property_list():
		var property_name: String = property["name"]
		if property_name.begins_with("bus/") and property_name.ends_with("/solo"):
			assert_false(bool(layout.get(property_name)), "No bus should start soloed")


## Verifies play_sfx() correctly routes to the fallback bus when an invalid bus is requested.
func test_invalid_bus_fallback_routing() -> void:
	var test_key: String = AudioConstants.SFX_ASSET_MAP.keys()[0]
	var invalid_bus: String = "ThisIsAFakeBusThatDoesNotExist"
	
	# Trigger playback with invalid bus configuration
	SfxManager.play_sfx(test_key, invalid_bus)
	
	# Verify it safely fell back to SFX_Menu instead of failing or muting
	assert_eq(
		SfxManager.get_active_sfx_bus_name(), 
		AudioConstants.BUS_SFX_MENU, 
		"AudioManager failed to fall back to the Menu bus when an invalid bus was requested."
	)


## Verifies that play_sfx() survives and runs cleanly if a pooled player is freed midway through execution.
func test_play_sfx_resilience_to_freed_players() -> void:
	# Retrieve the pool through the public diagnostic API (Issue #726)
	var pool_array: Array[AudioStreamPlayer] = SfxManager.get_sfx_pool_players()
	assert_gt(pool_array.size(), 0, "SFX pool was not initialized correctly.")
	
	# Violently free the first node in the pool to create a dangling/previously-freed reference
	var target_player: AudioStreamPlayer = pool_array[0]
	target_player.free()
	
	# Trigger playback
	var test_key: String = AudioConstants.SFX_ASSET_MAP.keys()[0]
	SfxManager.play_sfx(test_key)
	
	# Assert that play_sfx gracefully bypassed the dead node and still executed on a living one
	assert_true(SfxManager.is_any_sfx_playing(), "AudioManager failed to play SFX after a pool node was freed.")


## The rotor buses are handled through their parent SFX_Rotors bus, so they stay out of
## BUS_CONFIG and get no volume or mute settings of their own (#1149).
func test_rotor_playback_buses_are_not_in_bus_config() -> void:
	assert_false(AudioConstants.BUS_CONFIG.has(AudioConstants.BUS_SFX_ROTOR_LEFT))
	assert_false(AudioConstants.BUS_CONFIG.has(AudioConstants.BUS_SFX_ROTOR_RIGHT))
	assert_true(
		AudioConstants.BUS_CONFIG.has(AudioConstants.BUS_SFX_ROTORS),
		"The parent SFX_Rotors bus keeps the rotor volume and mute settings."
	)


## The player routes each rotor's sound to its own playback bus (#1149).
func test_player_rotors_use_left_and_right_buses() -> void:
	var original_settings: GameSettingsResource = Globals.settings
	Globals.settings = GameSettingsResource.new()
	var player: Node2D = PlayerScene.instantiate()
	add_child(player)

	assert_not_null(player.rotor_left_sfx, "The left rotor must have an AudioStreamPlayer2D.")
	assert_not_null(player.rotor_right_sfx, "The right rotor must have an AudioStreamPlayer2D.")
	if player.rotor_left_sfx and player.rotor_right_sfx:
		assert_eq(String(player.rotor_left_sfx.bus), AudioConstants.BUS_SFX_ROTOR_LEFT)
		assert_eq(String(player.rotor_right_sfx.bus), AudioConstants.BUS_SFX_ROTOR_RIGHT)

	player.free()
	Globals.settings = original_settings


## The FPS toggle in Advanced Settings still plays the check sound, now through
## AudioConstants.SFX_CHECK instead of a string literal (#1149).
func test_advanced_settings_fps_toggle_plays_check_sound() -> void:
	SfxManager.stop_all_sfx()
	var advanced: Control = AdvancedSettingsScript.new()
	advanced._on_fps_toggle_pressed()

	assert_string_contains(
		SfxManager.get_active_sfx_stream_path(),
		"check.wav",
		"The FPS toggle must play check.wav."
	)
	advanced.free()
