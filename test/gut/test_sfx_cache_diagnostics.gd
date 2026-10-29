## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## Regression tests for the public cache APIs introduced in PR #1094.
## Exercises cache behavior through playback, diagnostics and the debug seeding hook.

extends "res://addons/gut/test.gd"

const MISSING_SFX: String = "missing_sfx_cache_diagnostics_asset"
const RETRY_SFX: String = "retry_sfx_cache_diagnostics_asset"

var _retry_stream: AudioStream


## Isolate cache and playback state from other audio suites.
func before_each() -> void:
	SfxManager.cleanup_for_test()


## Release the synthetic loader entry as well as manager-owned resources.
func after_each() -> void:
	SfxManager.cleanup_for_test()
	if _retry_stream != null:
		_retry_stream.resource_path = ""
		_retry_stream = null


## Seed distinct logical identifiers without requiring additional sound files.
func _seed_cache(count: int) -> void:
	for i: int in range(count):
		SfxManager.cache_sfx_for_test("cached_" + str(i), AudioStreamWAV.new())


## Unknown queries, including the empty identifier, must not create cache entries.
func test_unknown_diagnostic_queries_are_side_effect_free(
	sfx_name: String = use_parameters(["", MISSING_SFX, "slider"])
) -> void:
	for i: int in range(2):
		assert_false(SfxManager.is_sfx_cached(sfx_name))
		assert_false(SfxManager.is_sfx_missing(sfx_name))
		assert_eq(SfxManager.get_cached_sfx_count(), 0)
	assert_false(SfxManager.is_any_sfx_playing())


## A diagnostic miss must not suppress a subsequent valid load.
func test_querying_an_uncached_asset_does_not_mark_it_missing() -> void:
	assert_false(SfxManager.is_sfx_cached("slider"))
	assert_false(SfxManager.is_sfx_missing("slider"))

	SfxManager.play_sfx("slider")

	assert_true(SfxManager.is_sfx_cached("slider"))
	assert_false(SfxManager.is_sfx_missing("slider"))
	assert_eq(SfxManager.get_cached_sfx_count(), 1)
	assert_true(SfxManager.is_any_sfx_playing())


## Seeding only adds cache data, and keys remain distinct even for a shared stream.
func test_seeding_shared_stream_counts_identifiers_without_starting_playback() -> void:
	var stream := AudioStreamWAV.new()
	for i: int in range(3):
		var key: String = "shared_" + str(i)
		SfxManager.cache_sfx_for_test(key, stream)
		assert_true(SfxManager.is_sfx_cached(key))
		assert_false(SfxManager.is_sfx_missing(key))
		assert_eq(SfxManager.get_cached_sfx_count(), i + 1)
	assert_eq(SfxManager.get_active_sfx_playback_count(), 0)


## Repeated overflow keeps exactly the newest MAX entries, including at the first boundary.
func test_repeated_seed_overflow_preserves_the_capacity_and_eviction_order() -> void:
	var capacity: int = SfxManager.MAX_SFX_CACHE_SIZE
	var total: int = capacity * 2 + 1
	for i: int in range(total):
		var key: String = "overflow_" + str(i)
		SfxManager.cache_sfx_for_test(key, AudioStreamWAV.new())
		assert_eq(SfxManager.get_cached_sfx_count(), mini(i + 1, capacity))
		assert_true(SfxManager.is_sfx_cached(key), "Every new entry must be retained")
		if i < capacity:
			assert_true(SfxManager.is_sfx_cached("overflow_0"), "No eviction below capacity")
		else:
			assert_false(SfxManager.is_sfx_cached("overflow_" + str(i - capacity)))

	for i: int in range(total):
		assert_eq(
			SfxManager.is_sfx_cached("overflow_" + str(i)),
			i >= total - capacity,
			"Only the newest capacity entries should survive"
		)


## Replacing the oldest entry preserves other keys, updates its stream and refreshes recency.
func test_reseeding_existing_key_replaces_stream_and_refreshes_recency(
	initial_size: int = use_parameters([3, SfxManager.MAX_SFX_CACHE_SIZE])
) -> void:
	_seed_cache(initial_size)
	var replacement: AudioStream = load(AudioConstants.SFX_DIR_PATH + "check.wav")

	SfxManager.cache_sfx_for_test("cached_0", replacement)

	assert_eq(SfxManager.get_cached_sfx_count(), initial_size, "Replacement adds no entry")
	for i: int in range(initial_size):
		assert_true(SfxManager.is_sfx_cached("cached_" + str(i)), "Replacement evicts nothing")

	for i: int in range(initial_size, SfxManager.MAX_SFX_CACHE_SIZE):
		SfxManager.cache_sfx_for_test("cached_" + str(i), AudioStreamWAV.new())
	SfxManager.cache_sfx_for_test("new_entry", AudioStreamWAV.new())

	assert_eq(SfxManager.get_cached_sfx_count(), SfxManager.MAX_SFX_CACHE_SIZE)
	assert_true(SfxManager.is_sfx_cached("cached_0"), "Replacement refreshes LRU recency")
	assert_false(SfxManager.is_sfx_cached("cached_1"), "The next oldest key is evicted")
	assert_true(SfxManager.is_sfx_cached("cached_2"), "Only one key is evicted")
	SfxManager.play_sfx("cached_0")
	assert_true(SfxManager.is_any_sfx_playing())
	assert_eq(SfxManager.get_active_sfx_stream_path(), replacement.resource_path)


## Updating a newer key in a full cache must not discard the untouched oldest key.
func test_reseeding_newest_entry_at_capacity_does_not_evict_another_key() -> void:
	_seed_cache(SfxManager.MAX_SFX_CACHE_SIZE)
	var newest: String = "cached_" + str(SfxManager.MAX_SFX_CACHE_SIZE - 1)

	SfxManager.cache_sfx_for_test(newest, AudioStreamWAV.new())

	assert_eq(SfxManager.get_cached_sfx_count(), SfxManager.MAX_SFX_CACHE_SIZE)
	for i: int in range(SfxManager.MAX_SFX_CACHE_SIZE):
		assert_true(SfxManager.is_sfx_cached("cached_" + str(i)))
	SfxManager.cache_sfx_for_test("new_entry", AudioStreamWAV.new())
	assert_false(SfxManager.is_sfx_cached("cached_0"))
	assert_true(SfxManager.is_sfx_cached("cached_1"))
	assert_true(SfxManager.is_sfx_cached(newest))


## Reading the oldest entry through diagnostics must not protect it from eviction.
func test_cache_diagnostics_do_not_refresh_lru_recency() -> void:
	_seed_cache(SfxManager.MAX_SFX_CACHE_SIZE)
	for i: int in range(3):
		assert_true(SfxManager.is_sfx_cached("cached_0"))
		assert_false(SfxManager.is_sfx_missing("cached_0"))
		assert_eq(SfxManager.get_cached_sfx_count(), SfxManager.MAX_SFX_CACHE_SIZE)

	SfxManager.cache_sfx_for_test("new_entry", AudioStreamWAV.new())

	assert_false(SfxManager.is_sfx_cached("cached_0"), "Diagnostic reads preserve LRU order")
	assert_true(SfxManager.is_sfx_cached("cached_1"))
	assert_true(SfxManager.is_sfx_cached("new_entry"))


## Normal playback refreshes a hit before a new load uses the shared insertion helper.
func test_normal_load_evicts_the_oldest_unplayed_entry() -> void:
	SfxManager.play_sfx("slider")
	_seed_cache(SfxManager.MAX_SFX_CACHE_SIZE - 1)

	SfxManager.play_sfx("slider")
	SfxManager.play_sfx("check")

	assert_eq(SfxManager.get_cached_sfx_count(), SfxManager.MAX_SFX_CACHE_SIZE)
	assert_true(SfxManager.is_sfx_cached("slider"))
	assert_true(SfxManager.is_sfx_cached("check"))
	assert_false(SfxManager.is_sfx_cached("cached_0"))
	assert_true(SfxManager.is_sfx_cached("cached_1"))
	assert_eq(SfxManager.get_active_sfx_stream_path(), AudioConstants.SFX_DIR_PATH + "check.wav")


## Failure tracking distinguishes identifiers and never inserts a success-cache entry.
func test_missing_diagnostic_tracks_failures_independently() -> void:
	SfxManager.play_sfx(MISSING_SFX)
	SfxManager.play_sfx(RETRY_SFX)
	SfxManager.play_sfx(MISSING_SFX)

	assert_true(SfxManager.is_sfx_missing(MISSING_SFX))
	assert_true(SfxManager.is_sfx_missing(RETRY_SFX))
	assert_false(SfxManager.is_sfx_missing("slider"))
	assert_false(SfxManager.is_sfx_missing(""))
	assert_false(SfxManager.is_sfx_cached(MISSING_SFX))
	assert_false(SfxManager.is_sfx_cached(RETRY_SFX))
	assert_eq(SfxManager.get_cached_sfx_count(), 0)
	assert_false(SfxManager.is_any_sfx_playing())


## Clearing caches is idempotent, releases both kinds of entries and retains idle pool nodes.
func test_clear_diagnostic_caches_resets_both_tables_without_rebuilding_pool() -> void:
	_seed_cache(SfxManager.MAX_SFX_CACHE_SIZE)
	SfxManager.play_sfx(MISSING_SFX)
	SfxManager.play_sfx(RETRY_SFX)
	var children: Array[Node] = SfxManager.get_children()

	SfxManager.clear_diagnostic_caches()
	SfxManager.clear_diagnostic_caches()

	assert_eq(SfxManager.get_cached_sfx_count(), 0)
	for i: int in range(SfxManager.MAX_SFX_CACHE_SIZE):
		assert_false(SfxManager.is_sfx_cached("cached_" + str(i)))
	assert_false(SfxManager.is_sfx_missing(MISSING_SFX))
	assert_false(SfxManager.is_sfx_missing(RETRY_SFX))
	assert_eq(SfxManager.get_children(), children, "Clearing caches retains the same pool nodes")
	assert_false(SfxManager.is_any_sfx_playing())


## Runtime cache reset preserves overlapping playback and allows a later lazy reload.
func test_clear_during_playback_keeps_active_sounds_and_allows_reload() -> void:
	SfxManager.play_sfx("slider", AudioConstants.BUS_SFX_MENU, 1.25, -6.0)
	SfxManager.play_sfx("check")
	var children: Array[Node] = SfxManager.get_children()
	assert_eq(SfxManager.get_active_sfx_playback_count(), 2)

	SfxManager.clear_diagnostic_caches()

	assert_eq(SfxManager.get_cached_sfx_count(), 0)
	assert_false(SfxManager.is_sfx_cached("slider"))
	assert_false(SfxManager.is_sfx_cached("check"))
	assert_eq(SfxManager.get_children(), children)
	assert_eq(SfxManager.get_active_sfx_playback_count(), 2, "Clearing must not stop active sounds")
	assert_eq(SfxManager.get_active_sfx_stream_path(), AudioConstants.SFX_DIR_PATH + "check.wav")
	SfxManager.play_sfx("slider")
	assert_true(SfxManager.is_sfx_cached("slider"), "The next request lazily repopulates the cache")
	assert_eq(SfxManager.get_cached_sfx_count(), 1)
	assert_eq(SfxManager.get_active_sfx_playback_count(), 3)
	assert_eq(SfxManager.get_children(), children, "Reload reuses the existing pool")


## A previously missing asset is retried only after clearing the missing-asset table.
func test_clear_allows_previously_missing_asset_to_load() -> void:
	var path: String = AudioConstants.SFX_DIR_PATH + RETRY_SFX + ".wav"
	assert_false(ResourceLoader.exists(path), "Precondition: the synthetic asset is unavailable")
	SfxManager.play_sfx(RETRY_SFX)
	assert_true(SfxManager.is_sfx_missing(RETRY_SFX))

	# Make the asset available in the engine resource cache without creating a disk fixture.
	_retry_stream = load(AudioConstants.SFX_DIR_PATH + "slider.wav").duplicate()
	_retry_stream.take_over_path(path)
	assert_true(ResourceLoader.exists(path), "The loader can now resolve the synthetic asset")
	SfxManager.play_sfx(RETRY_SFX)
	assert_false(SfxManager.is_any_sfx_playing(), "Known failures short-circuit even if available")
	assert_false(SfxManager.is_sfx_cached(RETRY_SFX))

	SfxManager.clear_diagnostic_caches()
	assert_false(SfxManager.is_sfx_missing(RETRY_SFX))
	SfxManager.play_sfx(RETRY_SFX)

	assert_true(SfxManager.is_any_sfx_playing(), "Clearing permits a fresh load attempt")
	assert_true(SfxManager.is_sfx_cached(RETRY_SFX))
	assert_false(SfxManager.is_sfx_missing(RETRY_SFX))
	assert_eq(SfxManager.get_cached_sfx_count(), 1)
	assert_eq(SfxManager.get_active_sfx_stream_path(), path)


## Test cleanup still delegates cache clearing while stopping sounds and rebuilding the pool.
func test_cleanup_for_test_clears_both_caches_and_leaves_playback_usable() -> void:
	SfxManager.play_sfx("slider")
	SfxManager.cache_sfx_for_test("seeded", AudioStreamWAV.new())
	SfxManager.play_sfx(MISSING_SFX)
	assert_eq(SfxManager.get_cached_sfx_count(), 2)
	assert_true(SfxManager.is_sfx_missing(MISSING_SFX))

	SfxManager.cleanup_for_test()

	assert_eq(SfxManager.get_cached_sfx_count(), 0)
	assert_false(SfxManager.is_sfx_cached("slider"))
	assert_false(SfxManager.is_sfx_cached("seeded"))
	assert_false(SfxManager.is_sfx_missing(MISSING_SFX))
	assert_eq(SfxManager.get_active_sfx_playback_count(), 0)
	assert_eq(SfxManager.get_child_count(), SfxManager.SFX_POOL_SIZE)
	SfxManager.play_sfx("slider")
	assert_true(SfxManager.is_sfx_cached("slider"))
	assert_eq(SfxManager.get_active_sfx_playback_count(), 1)
