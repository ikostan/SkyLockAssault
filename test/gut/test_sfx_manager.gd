## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_sfx_manager.gd
##
## Regression tests for the SfxManager extracted from AudioManager in PR #1068.
##
## Black-box only (Issue #726): cache, missing-asset and pool state is read through
## SfxManager's public [DIAGNOSTIC] API and seeded or reset through its debug-only
## *_for_test() hooks. No private fields are read or written here.

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


## Seed dummy cache entries "cached_0".."cached_<count - 1>" without extra asset files.
## :param count: Number of entries to seed.
## :rtype: void
func _seed_cache(count: int) -> void:
	for i: int in range(count):
		SfxManager.cache_sfx_for_test("cached_" + str(i), AudioStreamWAV.new())


## Returns the pool player at the given index (may be a freed instance).
## :param index: Pool index.
## :rtype: AudioStreamPlayer
func _pool_player(index: int) -> AudioStreamPlayer:
	return SfxManager.get_sfx_pool_players()[index]


## Empty identifiers must not interrupt an active sound or poison either cache.
## :rtype: void
func test_empty_identifier_leaves_active_playback_untouched() -> void:
	SfxManager.play_sfx("slider")
	var player: AudioStreamPlayer = _pool_player(0)
	var stream: AudioStream = player.stream

	SfxManager.play_sfx("")

	assert_true(player.playing)
	assert_eq(player.stream, stream)
	assert_eq(SfxManager.get_active_sfx_playback_count(), 1)
	assert_eq(SfxManager.get_cached_sfx_count(), 1)
	assert_eq(SfxManager.get_missing_sfx_count(), 0)


## A failed request must neither steal an active player nor evict a valid cached stream.
## :rtype: void
func test_missing_asset_preserves_full_cache_and_playback() -> void:
	SfxManager.play_sfx("slider")
	var player: AudioStreamPlayer = _pool_player(0)
	var stream: AudioStream = player.stream
	# "slider" plus MAX - 1 dummies fills the cache exactly, with no eviction yet
	_seed_cache(SfxManager.MAX_SFX_CACHE_SIZE - 1)
	assert_eq(SfxManager.get_cached_sfx_count(), SfxManager.MAX_SFX_CACHE_SIZE)
	var cached_names: Array[String] = SfxManager.get_cached_sfx_names()

	SfxManager.play_sfx(MISSING_SFX)
	SfxManager.play_sfx(MISSING_SFX)

	assert_eq(
		SfxManager.get_cached_sfx_names(), cached_names, "Failures do not evict or reorder hits"
	)
	assert_true(SfxManager.is_sfx_missing(MISSING_SFX))
	assert_eq(SfxManager.get_missing_sfx_count(), 1)
	assert_true(player.playing)
	assert_eq(player.stream, stream)
	assert_eq(SfxManager.get_active_sfx_playback_count(), 1)


## Concurrent requests for one identifier share its resource but use separate players.
## :rtype: void
func test_cache_hit_reuses_stream_for_overlapping_playback() -> void:
	SfxManager.play_sfx("slider")
	var first: AudioStreamPlayer = _pool_player(0)
	var stream: AudioStream = first.stream

	SfxManager.play_sfx("slider")

	assert_eq(SfxManager.get_cached_sfx_count(), 1)
	assert_eq(_pool_player(1).stream, stream)
	assert_eq(first.stream, stream)
	assert_true(first.playing)
	assert_eq(SfxManager.get_active_sfx_playback_count(), 2)


## Replaying the oldest entry protects it from the next eviction: the cache is LRU, not FIFO.
## :rtype: void
func test_cache_hit_protects_stream_from_next_eviction() -> void:
	SfxManager.play_sfx("slider")
	var stream: AudioStream = _pool_player(0).stream
	_seed_cache(SfxManager.MAX_SFX_CACHE_SIZE - 1)
	assert_eq(SfxManager.get_cached_sfx_names()[0], "slider", "slider starts as the LRU entry")

	SfxManager.play_sfx("slider")
	SfxManager.play_sfx(AudioConstants.SFX_CHECK)

	assert_eq(SfxManager.get_cached_sfx_count(), SfxManager.MAX_SFX_CACHE_SIZE)
	assert_true(SfxManager.is_sfx_cached("slider"), "A cache hit refreshes recency")
	assert_false(SfxManager.is_sfx_cached("cached_0"), "Evict the least recently used entry")
	assert_true(SfxManager.is_sfx_cached("cached_1"), "Evict exactly one entry")
	assert_true(SfxManager.is_sfx_cached(AudioConstants.SFX_CHECK))

	# The surviving entry must still be the original stream, not a reload
	SfxManager.stop_all_sfx()
	SfxManager.play_sfx("slider")
	assert_eq(_pool_player(0).stream, stream, "The cached stream survives unchanged")


## Reusing an idle player must reset all overrides from its previous playback.
## :rtype: void
func test_reused_player_resets_bus_pitch_and_volume_to_defaults() -> void:
	SfxManager.play_sfx("slider", AudioConstants.BUS_SFX, 1.25, -9.0)
	var player: AudioStreamPlayer = _pool_player(0)
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
	var player: AudioStreamPlayer = _pool_player(0)
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
	var second_stream: AudioStream = _pool_player(1).stream

	SfxManager.play_sfx(AudioConstants.SFX_CHECK, AudioConstants.BUS_SFX, 1.5, -3.0)

	var first: AudioStreamPlayer = _pool_player(0)
	assert_eq(first.stream.resource_path, AudioConstants.SFX_DIR_PATH + "check.wav")
	assert_eq(first.bus, AudioConstants.BUS_SFX)
	assert_eq(first.pitch_scale, 1.5)
	assert_eq(first.volume_db, -3.0)
	assert_eq(_pool_player(1).stream, second_stream)
	assert_eq(SfxManager.get_active_sfx_playback_count(), SfxManager.SFX_POOL_SIZE)
	assert_eq(SfxManager.get_child_count(), node_count)


## Both saturation fallback and diagnostics must tolerate a freed first pool entry.
## :rtype: void
func test_saturated_pool_skips_freed_first_player() -> void:
	_pool_player(0).free()
	for i: int in range(SfxManager.SFX_POOL_SIZE - 1):
		SfxManager.play_sfx("slider")

	SfxManager.play_sfx(AudioConstants.SFX_CHECK, AudioConstants.BUS_SFX)

	assert_eq(_pool_player(1).stream.resource_path, AudioConstants.SFX_DIR_PATH + "check.wav")
	assert_eq(SfxManager.get_active_sfx_playback_count(), SfxManager.SFX_POOL_SIZE - 1)
	assert_true(SfxManager.is_any_sfx_playing())
	SfxManager.stop_all_sfx()
	assert_false(SfxManager.is_any_sfx_playing(), "Stopping also skips freed entries")


## Stopping playback releases every stream, resets diagnostics, and retains reusable cache data.
## :rtype: void
func test_stop_clears_players_and_diagnostics_but_keeps_cache() -> void:
	SfxManager.play_sfx("slider")
	var slider_stream: AudioStream = _pool_player(0).stream
	SfxManager.play_sfx(AudioConstants.SFX_CHECK, AudioConstants.BUS_SFX)
	var cached_names: Array[String] = SfxManager.get_cached_sfx_names()
	assert_eq(SfxManager.get_active_sfx_stream_path(), AudioConstants.SFX_DIR_PATH + "check.wav")
	assert_eq(SfxManager.get_active_sfx_bus_name(), AudioConstants.BUS_SFX)

	SfxManager.stop_all_sfx()
	SfxManager.stop_all_sfx()

	assert_false(SfxManager.is_any_sfx_playing())
	assert_eq(SfxManager.get_active_sfx_playback_count(), 0)
	assert_eq(SfxManager.get_active_sfx_stream_path(), "")
	assert_eq(SfxManager.get_active_sfx_bus_name(), "")
	assert_eq(SfxManager.get_cached_sfx_names(), cached_names)
	for player: AudioStreamPlayer in SfxManager.get_sfx_pool_players():
		assert_null(player.stream)
	SfxManager.play_sfx("slider")
	assert_eq(_pool_player(0).stream, slider_stream, "Replay uses the retained cached stream")
	assert_eq(SfxManager.get_active_sfx_playback_count(), 1)


## Cleanup removes success/failure cache entries and replaces the entire pool with idle players.
## :rtype: void
func test_cleanup_rebuilds_a_usable_pool_and_clears_both_caches() -> void:
	SfxManager.play_sfx("slider")
	SfxManager.play_sfx(MISSING_SFX)
	var old_players: Array[AudioStreamPlayer] = SfxManager.get_sfx_pool_players()

	SfxManager.cleanup_for_test()

	assert_eq(SfxManager.get_cached_sfx_count(), 0)
	assert_eq(SfxManager.get_missing_sfx_count(), 0)
	for player in old_players:
		assert_false(is_instance_valid(player), "Previous players were freed")
	var players: Array[AudioStreamPlayer] = SfxManager.get_sfx_pool_players()
	assert_eq(players.size(), SfxManager.SFX_POOL_SIZE)
	assert_eq(SfxManager.get_child_count(), SfxManager.SFX_POOL_SIZE)
	assert_eq(SfxManager.get_active_sfx_playback_count(), 0)
	for player: AudioStreamPlayer in players:
		assert_true(is_instance_valid(player))
		assert_eq(player.get_parent(), SfxManager)
		assert_null(player.stream)
	SfxManager.play_sfx("slider")
	assert_eq(SfxManager.get_active_sfx_playback_count(), 1, "The rebuilt pool remains usable")


## Playback lazily reconstructs an empty pool before resolving a sound.
## :rtype: void
func test_playback_initializes_an_empty_pool() -> void:
	SfxManager.clear_sfx_pool_for_test()
	assert_true(SfxManager.get_sfx_pool_players().is_empty(), "Precondition: pool is empty")

	SfxManager.play_sfx("slider")

	assert_eq(SfxManager.get_sfx_pool_players().size(), SfxManager.SFX_POOL_SIZE)
	assert_eq(SfxManager.get_child_count(), SfxManager.SFX_POOL_SIZE)
	assert_true(SfxManager.is_any_sfx_playing())
	assert_eq(SfxManager.get_active_sfx_playback_count(), 1)
	assert_eq(SfxManager.get_active_sfx_stream_path(), AudioConstants.SFX_DIR_PATH + "slider.wav")
