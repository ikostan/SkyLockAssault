## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## Regression tests for the SfxManager extracted from AudioManager in PR #1068.

extends "res://addons/gut/test.gd"

const MISSING_SFX: String = "missing_sfx_manager_regression_asset"


## Start with an empty cache and a fresh pool, independent of suite execution order.
## :rtype: void
func before_each() -> void:
	SfxManager.cleanup_for_test()


## Restore valid, idle pool nodes even when a test deliberately frees a player.
## :rtype: void
func after_each() -> void:
	SfxManager.cleanup_for_test()


## Fill the cache without creating extra files or relying on twenty distinct assets.
## :rtype: void
func _fill_cache() -> void:
	for i: int in range(SfxManager.MAX_SFX_CACHE_SIZE):
		SfxManager._sfx_cache["cached_" + str(i)] = AudioStreamWAV.new()


## Empty identifiers must not interrupt an active sound or poison either cache.
## :rtype: void
func test_empty_identifier_leaves_active_playback_untouched() -> void:
	SfxManager.play_sfx("slider")
	var player: AudioStreamPlayer = SfxManager._sfx_pool[0]
	var stream: AudioStream = player.stream

	SfxManager.play_sfx("")

	assert_true(player.playing)
	assert_eq(player.stream, stream)
	assert_eq(SfxManager.get_active_sfx_playback_count(), 1)
	assert_eq(SfxManager._sfx_cache.size(), 1)
	assert_true(SfxManager._missing_sfx_cache.is_empty())


## A failed request must neither steal an active player nor evict a valid cached stream.
## :rtype: void
func test_missing_asset_preserves_full_cache_and_playback() -> void:
	SfxManager.play_sfx("slider")
	var player: AudioStreamPlayer = SfxManager._sfx_pool[0]
	var stream: AudioStream = player.stream
	_fill_cache()
	SfxManager._sfx_cache.erase("cached_0")
	var cached_keys: Array = SfxManager._sfx_cache.keys()

	SfxManager.play_sfx(MISSING_SFX)
	SfxManager.play_sfx(MISSING_SFX)

	assert_eq(SfxManager._sfx_cache.keys(), cached_keys, "Failures do not evict or reorder hits")
	assert_true(SfxManager._missing_sfx_cache.has(MISSING_SFX))
	assert_eq(SfxManager._missing_sfx_cache.size(), 1)
	assert_true(player.playing)
	assert_eq(player.stream, stream)
	assert_eq(SfxManager.get_active_sfx_playback_count(), 1)


## Concurrent requests for one identifier share its resource but use separate players.
## :rtype: void
func test_cache_hit_reuses_stream_for_overlapping_playback() -> void:
	SfxManager.play_sfx("slider")
	var first: AudioStreamPlayer = SfxManager._sfx_pool[0]
	var stream: AudioStream = first.stream

	SfxManager.play_sfx("slider")

	assert_eq(SfxManager._sfx_cache.size(), 1)
	assert_eq(SfxManager._sfx_pool[1].stream, stream)
	assert_eq(first.stream, stream)
	assert_true(first.playing)
	assert_eq(SfxManager.get_active_sfx_playback_count(), 2)


## Replaying the oldest entry protects it from the next eviction: the cache is LRU, not FIFO.
## :rtype: void
func test_cache_hit_protects_stream_from_next_eviction() -> void:
	SfxManager.play_sfx("slider")
	var stream: AudioStream = SfxManager._sfx_cache["slider"]
	for i: int in range(SfxManager.MAX_SFX_CACHE_SIZE - 1):
		SfxManager._sfx_cache["cached_" + str(i)] = AudioStreamWAV.new()

	SfxManager.play_sfx("slider")
	SfxManager.play_sfx(AudioConstants.SFX_CHECK)

	assert_eq(SfxManager._sfx_cache.size(), SfxManager.MAX_SFX_CACHE_SIZE)
	assert_true(SfxManager._sfx_cache.has("slider"), "A cache hit refreshes recency")
	assert_eq(SfxManager._sfx_cache.get("slider"), stream)
	assert_false(SfxManager._sfx_cache.has("cached_0"), "Evict the least recently used entry")
	assert_true(SfxManager._sfx_cache.has("cached_1"), "Evict exactly one entry")
	assert_true(SfxManager._sfx_cache.has(AudioConstants.SFX_CHECK))


## Reusing an idle player must reset all overrides from its previous playback.
## :rtype: void
func test_reused_player_resets_bus_pitch_and_volume_to_defaults() -> void:
	SfxManager.play_sfx("slider", AudioConstants.BUS_SFX, 1.25, -9.0)
	var player: AudioStreamPlayer = SfxManager._sfx_pool[0]
	assert_eq(player.bus, AudioConstants.BUS_SFX)
	assert_eq(player.pitch_scale, 1.25)
	assert_eq(player.volume_db, -9.0)
	player.stop()

	SfxManager.play_sfx(AudioConstants.SFX_CHECK)

	assert_true(player.playing)
	assert_eq(player.stream.resource_path, AudioConstants.SFX_DIR_PATH + "check.wav")
	assert_eq(player.bus, AudioConstants.BUS_SFX_MENU)
	assert_eq(player.pitch_scale, 1.0)
	assert_eq(player.volume_db, 0.0)
	assert_eq(SfxManager.get_active_sfx_playback_count(), 1)


## Invalid bus fallback must replace an earlier valid routing on the reused player.
## :rtype: void
func test_invalid_bus_replaces_previous_player_routing() -> void:
	SfxManager.play_sfx("slider", AudioConstants.BUS_SFX)
	var player: AudioStreamPlayer = SfxManager._sfx_pool[0]
	player.stop()

	SfxManager.play_sfx(AudioConstants.SFX_CHECK, "MissingSfxRegressionBus", 0.8, -6.0)

	assert_true(player.playing)
	assert_eq(player.bus, AudioConstants.BUS_SFX_MENU)
	assert_eq(SfxManager.get_active_sfx_bus_name(), AudioConstants.BUS_SFX_MENU)
	assert_almost_eq(player.pitch_scale, 0.8, 0.0001)
	assert_eq(player.volume_db, -6.0)


## Saturation replaces the first valid player's sound while keeping the pool bounded.
## :rtype: void
func test_saturated_pool_replaces_first_player_without_allocating() -> void:
	for i: int in range(SfxManager.SFX_POOL_SIZE):
		SfxManager.play_sfx("slider")
	var node_count: int = SfxManager.get_child_count()
	var second_stream: AudioStream = SfxManager._sfx_pool[1].stream

	SfxManager.play_sfx(AudioConstants.SFX_CHECK, AudioConstants.BUS_SFX, 1.5, -3.0)

	var first: AudioStreamPlayer = SfxManager._sfx_pool[0]
	assert_eq(first.stream.resource_path, AudioConstants.SFX_DIR_PATH + "check.wav")
	assert_eq(first.bus, AudioConstants.BUS_SFX)
	assert_eq(first.pitch_scale, 1.5)
	assert_eq(first.volume_db, -3.0)
	assert_eq(SfxManager._sfx_pool[1].stream, second_stream)
	assert_eq(SfxManager.get_active_sfx_playback_count(), SfxManager.SFX_POOL_SIZE)
	assert_eq(SfxManager.get_child_count(), node_count)


## Both saturation fallback and diagnostics must tolerate a freed first pool entry.
## :rtype: void
func test_saturated_pool_skips_freed_first_player() -> void:
	SfxManager._sfx_pool[0].free()
	for i: int in range(SfxManager.SFX_POOL_SIZE - 1):
		SfxManager.play_sfx("slider")

	SfxManager.play_sfx(AudioConstants.SFX_CHECK, AudioConstants.BUS_SFX)

	assert_eq(
		SfxManager._sfx_pool[1].stream.resource_path, AudioConstants.SFX_DIR_PATH + "check.wav"
	)
	assert_eq(SfxManager.get_active_sfx_playback_count(), SfxManager.SFX_POOL_SIZE - 1)
	assert_true(SfxManager.is_any_sfx_playing())
	SfxManager.stop_all_sfx()
	assert_false(SfxManager.is_any_sfx_playing(), "Stopping also skips freed entries")


## Stopping playback releases every stream, resets diagnostics, and retains reusable cache data.
## :rtype: void
func test_stop_clears_players_and_diagnostics_but_keeps_cache() -> void:
	SfxManager.play_sfx("slider")
	SfxManager.play_sfx(AudioConstants.SFX_CHECK, AudioConstants.BUS_SFX)
	var cache: Dictionary = SfxManager._sfx_cache.duplicate()
	assert_eq(SfxManager.get_active_sfx_stream_path(), AudioConstants.SFX_DIR_PATH + "check.wav")
	assert_eq(SfxManager.get_active_sfx_bus_name(), AudioConstants.BUS_SFX)

	SfxManager.stop_all_sfx()
	SfxManager.stop_all_sfx()

	assert_false(SfxManager.is_any_sfx_playing())
	assert_eq(SfxManager.get_active_sfx_playback_count(), 0)
	assert_eq(SfxManager.get_active_sfx_stream_path(), "")
	assert_eq(SfxManager.get_active_sfx_bus_name(), "")
	assert_eq(SfxManager._sfx_cache, cache)
	for player: AudioStreamPlayer in SfxManager._sfx_pool:
		assert_null(player.stream)
	SfxManager.play_sfx("slider")
	assert_eq(SfxManager._sfx_pool[0].stream, cache["slider"])
	assert_eq(SfxManager.get_active_sfx_playback_count(), 1)


## Cleanup removes success/failure cache entries and replaces the entire pool with idle players.
## :rtype: void
func test_cleanup_rebuilds_a_usable_pool_and_clears_both_caches() -> void:
	SfxManager.play_sfx("slider")
	SfxManager.play_sfx(MISSING_SFX)
	var old_players: Array = SfxManager._sfx_pool.duplicate()

	SfxManager.cleanup_for_test()

	assert_true(SfxManager._sfx_cache.is_empty())
	assert_true(SfxManager._missing_sfx_cache.is_empty())
	for player in old_players:
		assert_false(is_instance_valid(player), "Previous players were freed")
	assert_eq(SfxManager._sfx_pool.size(), SfxManager.SFX_POOL_SIZE)
	assert_eq(SfxManager.get_child_count(), SfxManager.SFX_POOL_SIZE)
	assert_eq(SfxManager.get_active_sfx_playback_count(), 0)
	for player: AudioStreamPlayer in SfxManager._sfx_pool:
		assert_true(is_instance_valid(player))
		assert_eq(player.get_parent(), SfxManager)
		assert_null(player.stream)
	SfxManager.play_sfx("slider")
	assert_eq(SfxManager.get_active_sfx_playback_count(), 1, "The rebuilt pool remains usable")


## Playback lazily reconstructs an empty pool before resolving a sound.
## :rtype: void
func test_playback_initializes_an_empty_pool() -> void:
	for player: AudioStreamPlayer in SfxManager._sfx_pool:
		player.free()
	SfxManager._sfx_pool.clear()

	SfxManager.play_sfx("slider")

	assert_eq(SfxManager._sfx_pool.size(), SfxManager.SFX_POOL_SIZE)
	assert_eq(SfxManager.get_child_count(), SfxManager.SFX_POOL_SIZE)
	assert_true(SfxManager.is_any_sfx_playing())
	assert_eq(SfxManager.get_active_sfx_playback_count(), 1)
	assert_eq(SfxManager.get_active_sfx_stream_path(), AudioConstants.SFX_DIR_PATH + "slider.wav")
