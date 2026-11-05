## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_audio_sfx_centralization.gd
##
## Automated verification suite for Feature Request #570.
## Validates object pooling, LRU cache eviction, failure isolation,
## and constant engine node tree allocation rules.
##
## Black-box only (Issue #726): every check goes through SfxManager's public
## playback and [DIAGNOSTIC] API. No private fields (_sfx_cache, _missing_sfx_cache,
## _sfx_pool) are read or written here, so internal layout changes don't break this suite.

extends "res://addons/gut/test.gd"


## Starts every test from empty caches and a silent pool.
## :rtype: void
func before_each() -> void:
	SfxManager.clear_diagnostic_caches()
	SfxManager.stop_all_sfx()
	Globals.set_test_encryption_key()


## Silences lingering audio and drops any seeded or loaded streams so nothing
## (e.g. the dummy streams from Verification 4) leaks into other suites.
## :rtype: void
func after_each() -> void:
	# FIX: Prevent global state pollution if assertions fail early in the test body
	Globals.options_open = false

	SfxManager.stop_all_sfx()
	SfxManager.clear_diagnostic_caches()


## Verification 1 |
## A menu sound plays correctly when passing its string identifier to the API.
## :rtype: void
func test_verification_01_play_by_identifier() -> void:
	var sfx_name: String = "slider"
	SfxManager.play_sfx(sfx_name)

	assert_true(
		SfxManager.is_any_sfx_playing(),
		"An audio player in the pool should be active and streaming the asset."
	)
	assert_string_contains(
		SfxManager.get_active_sfx_stream_path(),
		"slider.wav",
		"The active player must be streaming the requested asset."
	)
	assert_true(SfxManager.is_sfx_cached(sfx_name), "A played asset must be cached for reuse.")


## Verification 2 |
## Consecutive rapid calls succeed and naturally overlap using separate pool players.
## :rtype: void
func test_verification_02_consecutive_overlapping_playback() -> void:
	SfxManager.play_sfx("slider")
	SfxManager.play_sfx("ui_navigation")

	assert_eq(
		SfxManager.get_active_sfx_playback_count(),
		2,
		"Two separate audio players must execute concurrently to allow overlap sounds."
	)


## Verification 3 |
## Flooding the API handles playback gracefully via player hijacking without crashing.
## :rtype: void
func test_verification_03_pool_flooding_graceful_hijack() -> void:
	# Flood with 10 concurrent requests (Pool size is capped at 8)
	for i: int in range(10):
		SfxManager.play_sfx("slider")

	assert_eq(
		SfxManager.get_active_sfx_playback_count(),
		SfxManager.SFX_POOL_SIZE,
		"All pool channels must remain busy without crashing the execution loop."
	)


## Verification 4 |
## Cache bounds are respected: loading a 21st unique SFX successfully evicts the oldest cached stream.
## :rtype: void
func test_verification_04_lru_cache_eviction_strategy() -> void:
	# Fill the cache up to the maximum allowable limit (20 entries) via the test seeding hook
	for i: int in range(SfxManager.MAX_SFX_CACHE_SIZE):
		SfxManager.cache_sfx_for_test("dummy_sfx_" + str(i), AudioStreamWAV.new())

	assert_eq(SfxManager.get_cached_sfx_count(), SfxManager.MAX_SFX_CACHE_SIZE)
	assert_true(SfxManager.is_sfx_cached("dummy_sfx_0"), "Seeding must not evict below the cap.")

	# Request the 21st unique sound element to force an LRU eviction rule sweep
	SfxManager.play_sfx("slider")

	assert_eq(
		SfxManager.get_cached_sfx_count(),
		SfxManager.MAX_SFX_CACHE_SIZE,
		"The stream cache bounds must strictly enforce its hard threshold limit."
	)
	assert_false(
		SfxManager.is_sfx_cached("dummy_sfx_0"),
		"The oldest inserted stream element must be evicted from memory."
	)
	assert_true(SfxManager.is_sfx_cached("dummy_sfx_1"), "Exactly one entry must be evicted.")
	assert_true(
		SfxManager.is_sfx_cached("slider"),
		"The newly parsed asset payload must successfully occupy the cache structure."
	)


## Verification 5 |
## Requesting a non-existent SFX logs a warning once, caches the failure, and suppresses repeated disk lookups.
## :rtype: void
func test_verification_05_missing_asset_failure_suppression() -> void:
	var fake_sfx: String = "invalid_ghost_sound"
	SfxManager.play_sfx(fake_sfx)

	assert_true(
		SfxManager.is_sfx_missing(fake_sfx),
		"The missing resource path must map to the failure lookup table."
	)
	assert_false(SfxManager.is_sfx_cached(fake_sfx), "A failed load must never enter the cache.")
	assert_false(SfxManager.is_any_sfx_playing(), "A failed load must not start playback.")

	# Request again: the known failure must short-circuit before any disk access or caching
	SfxManager.play_sfx(fake_sfx)

	assert_false(
		SfxManager.is_sfx_cached(fake_sfx),
		"The API must short-circuit and completely bypass disk access routines for known failure keys."
	)
	assert_true(SfxManager.is_sfx_missing(fake_sfx), "The failure entry must persist.")
	assert_eq(SfxManager.get_cached_sfx_count(), 0, "Repeated failures must not touch the cache.")


## Verification 6 |
## The total number of AudioStreamPlayer child nodes remains constant before, during, and after playback.
## :rtype: void
func test_verification_06_pool_node_count_constancy() -> void:
	var initial_count: int = SfxManager.get_child_count()

	SfxManager.play_sfx("slider")
	var mid_count: int = SfxManager.get_child_count()

	SfxManager.stop_all_sfx()
	var final_count: int = SfxManager.get_child_count()

	assert_eq(initial_count, mid_count)
	assert_eq(
		mid_count,
		final_count,
		"The structural node tree footprint under SfxManager must remain completely constant."
	)


## Verification 7 |
## Validates that play_sfx resolves logical identifiers to their explicit file extensions using the asset map.
## :rtype: void
func test_play_sfx_resolves_via_asset_map() -> void:
	# Ensure the cache doesn't skew results
	AudioManager.cleanup_for_test()

	# Test an explicit .ogg file defined in our map
	# SfxManager should look for 'airplane_prop.ogg' instead of 'airplane_prop.wav'
	SfxManager.play_sfx("airplane_prop")

	var active_path := SfxManager.get_active_sfx_stream_path()
	assert_string_contains(
		active_path,
		"airplane_prop.ogg",
		"SfxManager should resolve mapping to exact extension found in asset map."
	)


## Verification 8 |
## Validates that fallback handling automatically appends the default .wav extension to unmapped sound identifiers.
## :rtype: void
func test_play_sfx_unmapped_legacy_fallback() -> void:
	AudioManager.cleanup_for_test()

	# FIX: Pass an unmapped logical string identifier ("check") instead of a mapped one ("slider")
	# to correctly exercise the .wav fallback branch.
	SfxManager.play_sfx("check")

	var active_path := SfxManager.get_active_sfx_stream_path()
	assert_string_contains(
		active_path,
		"check.wav",
		"Unmapped IDs should automatically append .wav for fallback compatibility."
	)


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

	# Route the fake event pack directly into our global tracker (Issue #490)
	UiManager._input(mouse_event)

	# Ensure no execution churn occurred and no playback pool frames were hijacked
	assert_false(
		SfxManager.is_any_sfx_playing(),
		"Mouse motion wiggles must drop immediately out of the input loop without triggering audio players."
	)
