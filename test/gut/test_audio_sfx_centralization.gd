## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_audio_sfx_centralization.gd
##
## Automated verification suite for Feature Request #570.
## Validates object pooling, LRU cache eviction, failure isolation, 
## and constant engine node tree allocation rules.
extends "res://addons/gut/test.gd"

var _orig_cache: Dictionary = {}
var _orig_missing: Dictionary = {}


## Captures manager state to shield the runtime environment from test pollution
## :rtype: void
func before_each() -> void:
	_orig_cache = AudioManager._sfx_cache.duplicate()
	_orig_missing = AudioManager._missing_sfx_cache.duplicate()
	AudioManager._sfx_cache.clear()
	AudioManager._missing_sfx_cache.clear()
	Globals.set_test_encryption_key()


## Restores manager state tracking loops and silences lingering audio threads
## :rtype: void
func after_each() -> void:
	AudioManager._sfx_cache = _orig_cache
	AudioManager._missing_sfx_cache = _orig_missing
	for p: AudioStreamPlayer in AudioManager._sfx_pool:
		p.stop()


## Verification 1 |
## A menu sound plays correctly when passing its string identifier to the API.
## :rtype: void
func test_verification_01_play_by_identifier() -> void:
	var sfx_name: String = "slider"
	AudioManager.play_sfx(sfx_name)
	
	var sound_playing: bool = false
	for p: AudioStreamPlayer in AudioManager._sfx_pool:
		if p.playing and p.stream != null:
			sound_playing = true
			break
			
	assert_true(sound_playing, "An audio player in the pool should be active and streaming the asset.")


## Verification 2 |
## Consecutive rapid calls succeed and naturally overlap using separate pool players.
## :rtype: void
func test_verification_02_consecutive_overlapping_playback() -> void:
	AudioManager.play_sfx("slider")
	AudioManager.play_sfx("ui_navigation")
	
	var active_players: int = 0
	for p: AudioStreamPlayer in AudioManager._sfx_pool:
		if p.playing:
			active_players += 1
			
	assert_eq(active_players, 2, "Two separate audio players must execute concurrently to allow overlap sounds.")


## Verification 3 |
## Flooding the API handles playback gracefully via player hijacking without crashing.
## :rtype: void
func test_verification_03_pool_flooding_graceful_hijack() -> void:
	# Flood with 10 concurrent requests (Pool size is capped at 8)
	for i: int in range(10):
		AudioManager.play_sfx("slider")
		
	var active_players: int = 0
	for p: AudioStreamPlayer in AudioManager._sfx_pool:
		if p.playing:
			active_players += 1
			
	assert_eq(active_players, AudioManager.SFX_POOL_SIZE, "All pool channels must remain busy without crashing the execution loop.")


## Verification 4 |
## Cache bounds are respected: loading a 21st unique SFX successfully evicts the oldest cached stream.
## :rtype: void
func test_verification_04_lru_cache_eviction_strategy() -> void:
	# Populate the internal cache up to the maximum allowable limit (20 entries)
	for i: int in range(AudioManager.MAX_SFX_CACHE_SIZE):
		var dummy_stream: AudioStreamWAV = AudioStreamWAV.new()
		AudioManager._sfx_cache["dummy_sfx_" + str(i)] = dummy_stream
		
	assert_eq(AudioManager._sfx_cache.size(), AudioManager.MAX_SFX_CACHE_SIZE)
	
	# Request the 21st unique sound element to force an LRU eviction rule sweep
	AudioManager.play_sfx("slider")
	
	assert_eq(AudioManager._sfx_cache.size(), AudioManager.MAX_SFX_CACHE_SIZE, "The stream cache bounds must strictly enforce its hard threshold limit.")
	assert_false(AudioManager._sfx_cache.has("dummy_sfx_0"), "The oldest inserted stream element must be evicted from memory.")
	assert_true(AudioManager._sfx_cache.has("slider"), "The newly parsed asset payload must successfully occupy the cache structure.")


## Verification 5 |
## Requesting a non-existent SFX logs a warning once, caches the failure, and suppresses repeated disk lookups.
## :rtype: void
func test_verification_05_missing_asset_failure_suppression() -> void:
	var fake_sfx: String = "invalid_ghost_sound"
	AudioManager.play_sfx(fake_sfx)
	
	assert_true(AudioManager._missing_sfx_cache.has(fake_sfx), "The missing resource path must map to the failure lookup table.")
	
	# Manually evict the item from the primary loader cache to check if it tries to hit disk again
	AudioManager._sfx_cache.erase(fake_sfx)
	AudioManager.play_sfx(fake_sfx)
	
	assert_false(AudioManager._sfx_cache.has(fake_sfx), "The API must short-circuit and completely bypass disk access routines for known failure keys.")


## Verification 6 |
## The total number of AudioStreamPlayer child nodes remains constant before, during, and after playback.
## :rtype: void
func test_verification_06_pool_node_count_constancy() -> void:
	var initial_count: int = AudioManager.get_child_count()
	
	AudioManager.play_sfx("slider")
	var mid_count: int = AudioManager.get_child_count()
	
	for p: AudioStreamPlayer in AudioManager._sfx_pool:
		p.stop()
	var final_count: int = AudioManager.get_child_count()
	
	assert_eq(initial_count, mid_count)
	assert_eq(mid_count, final_count, "The structural node tree footprint under AudioManager must remain completely constant.")


## Verification 7 |
## Validates that play_sfx resolves logical identifiers to their explicit file extensions using the asset map.
## :rtype: void
func test_play_sfx_resolves_via_asset_map() -> void:
	# Ensure the cache doesn't skew results
	AudioManager.cleanup_for_test()
	
	# Test an explicit .ogg file defined in our map
	# AudioManager should look for 'airplane_prop.ogg' instead of 'airplane_prop.wav'
	AudioManager.play_sfx("airplane_prop")
	
	var active_path := AudioManager.get_active_sfx_stream_path()
	assert_string_contains(active_path, "airplane_prop.ogg", "AudioManager should resolve mapping to exact extension found in asset map.")
	
	
## Verification 8 |
## Validates that fallback handling automatically appends the default .wav extension to unmapped sound identifiers.
## :rtype: void
func test_play_sfx_unmapped_legacy_fallback() -> void:
	AudioManager.cleanup_for_test()
	
	# Pass an unmapped logical string identifier
	AudioManager.play_sfx("slider")
	
	var active_path := AudioManager.get_active_sfx_stream_path()
	assert_string_contains(active_path, "slider.wav", "Unmapped IDs should automatically append .wav for fallback compatibility.")


## Verification 9 |
## Validates that high-frequency mouse motion inputs are dropped out of the global input process loop to optimize performance.
## :rtype: void
func test_input_ignores_mouse_motion() -> void:
	AudioManager.cleanup_for_test()
	
	# Simulate entering a menu layer to activate context checks
	Globals.options_open = true
	
	# Construct a generic high-frequency mouse movement packet
	var mouse_event := InputEventMouseMotion.new()
	mouse_event.position = Vector2(250, 450)
	mouse_event.relative = Vector2(5, 5)
	
	# Route the fake event pack directly into our global tracker
	Globals._input(mouse_event)
	
	# Ensure no execution churn occurred and no playback pool frames were hijacked
	assert_false(AudioManager.is_any_sfx_playing(), "Mouse motion wiggles must drop immediately out of the input loop without triggering audio players.")
	
	# Tear down state
	Globals.options_open = false
