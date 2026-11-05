## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_sfx_cache_diagnostics.gd
##
## Regression tests for the public cache APIs introduced in PR #1094 (Issue #726).
## Exercises cache behavior through playback, diagnostics and the debug seeding hook.

extends "res://addons/gut/test.gd"

const MISSING_SFX: String = "missing_sfx_cache_diagnostics_asset"
const RETRY_SFX: String = "retry_sfx_cache_diagnostics_asset"

var _retry_stream: AudioStream


## Isolate cache and playback state from other audio suites.
## :rtype: void
func before_each() -> void:
	SfxManager.cleanup_for_test()


## Release the synthetic loader entry as well as manager-owned resources.
## :rtype: void
func after_each() -> void:
	SfxManager.cleanup_for_test()
	if _retry_stream != null:
		_retry_stream.resource_path = ""
		_retry_stream = null


## Seed distinct logical identifiers without requiring additional sound files.
## :param count: Number of "cached_<i>" entries to seed.
## :rtype: void
func _seed_cache(count: int) -> void:
	for i: int in range(count):
		SfxManager.cache_sfx_for_test("cached_" + str(i), AudioStreamWAV.new())


## Builds the expected LRU name list "<prefix><first>".."<prefix><last>", oldest first.
## :param prefix: Key prefix.
## :param first: First index (inclusive).
## :param last: Last index (inclusive).
## :rtype: Array[String]
func _names(prefix: String, first: int, last: int) -> Array[String]:
	var names: Array[String] = []
	for i: int in range(first, last + 1):
		names.append(prefix + str(i))
	return names


## Queries for uncached identifiers, including the empty identifier, must not create entries.
## :rtype: void
func test_uncached_diagnostic_queries_are_side_effect_free(
	sfx_name: String = use_parameters(["", MISSING_SFX, "slider"])
) -> void:
	for i: int in range(2):
		assert_false(SfxManager.is_sfx_cached(sfx_name))
		assert_false(SfxManager.is_sfx_missing(sfx_name))
		assert_eq(SfxManager.get_cached_sfx_count(), 0)
		assert_eq(SfxManager.get_missing_sfx_count(), 0)
		assert_true(SfxManager.get_cached_sfx_names().is_empty())
	assert_false(SfxManager.is_any_sfx_playing())


## A diagnostic miss must not suppress a subsequent valid load.
## :rtype: void
func test_querying_an_uncached_asset_does_not_mark_it_missing() -> void:
	assert_false(SfxManager.is_sfx_cached("slider"))
	assert_false(SfxManager.is_sfx_missing("slider"))

	SfxManager.play_sfx("slider")

	assert_true(SfxManager.is_sfx_cached("slider"))
	assert_false(SfxManager.is_sfx_missing("slider"))
	assert_eq(SfxManager.get_cached_sfx_count(), 1)
	assert_eq(SfxManager.get_missing_sfx_count(), 0)
	assert_true(SfxManager.is_any_sfx_playing())


## Seeding only adds cache data, and keys remain distinct even for a shared stream.
## :rtype: void
func test_seeding_shared_stream_counts_identifiers_without_starting_playback() -> void:
	var stream := AudioStreamWAV.new()
	for i: int in range(3):
		var key: String = "shared_" + str(i)
		SfxManager.cache_sfx_for_test(key, stream)
		assert_true(SfxManager.is_sfx_cached(key))
		assert_false(SfxManager.is_sfx_missing(key))
		assert_eq(SfxManager.get_cached_sfx_count(), i + 1)
	assert_eq(SfxManager.get_cached_sfx_names(), _names("shared_", 0, 2), "Insertion order kept")
	assert_eq(SfxManager.get_active_sfx_playback_count(), 0)


## Repeated overflow keeps exactly the newest MAX entries, including at the first boundary.
## :rtype: void
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
	assert_eq(
		SfxManager.get_cached_sfx_names(),
		_names("overflow_", total - capacity, total - 1),
		"Survivors stay in LRU order, oldest first"
	)


## Replacing the oldest entry preserves other keys, updates its stream and refreshes recency.
## :rtype: void
func test_reseeding_existing_key_replaces_stream_and_refreshes_recency(
	initial_size: int = use_parameters([3, SfxManager.MAX_SFX_CACHE_SIZE])
) -> void:
	_seed_cache(initial_size)
	var replacement: AudioStream = load(AudioConstants.SFX_DIR_PATH + "check.wav")

	SfxManager.cache_sfx_for_test("cached_0", replacement)

	assert_eq(SfxManager.get_cached_sfx_count(), initial_size, "Replacement adds no entry")
	for i: int in range(initial_size):
		assert_true(SfxManager.is_sfx_cached("cached_" + str(i)), "Replacement evicts nothing")
	var names: Array[String] = SfxManager.get_cached_sfx_names()
	assert_eq(names[names.size() - 1], "cached_0", "Replacement moves the key to newest")
	assert_eq(names[0], "cached_1", "The next oldest key becomes the LRU entry")

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
## :rtype: void
func test_reseeding_newest_entry_at_capacity_does_not_evict_another_key() -> void:
	_seed_cache(SfxManager.MAX_SFX_CACHE_SIZE)
	var newest: String = "cached_" + str(SfxManager.MAX_SFX_CACHE_SIZE - 1)
	var order_before: Array[String] = SfxManager.get_cached_sfx_names()

	SfxManager.cache_sfx_for_test(newest, AudioStreamWAV.new())

	assert_eq(SfxManager.get_cached_sfx_count(), SfxManager.MAX_SFX_CACHE_SIZE)
	for i: int in range(SfxManager.MAX_SFX_CACHE_SIZE):
		assert_true(SfxManager.is_sfx_cached("cached_" + str(i)))
	assert_eq(SfxManager.get_cached_sfx_names(), order_before, "Newest stays newest; no reorder")
	SfxManager.cache_sfx_for_test("new_entry", AudioStreamWAV.new())
	assert_false(SfxManager.is_sfx_cached("cached_0"))
	assert_true(SfxManager.is_sfx_cached("cached_1"))
	assert_true(SfxManager.is_sfx_cached(newest))


## Reading the oldest entry through diagnostics must not protect it from eviction.
## :rtype: void
func test_cache_diagnostics_do_not_refresh_lru_recency() -> void:
	_seed_cache(SfxManager.MAX_SFX_CACHE_SIZE)
	var order_before: Array[String] = SfxManager.get_cached_sfx_names()
	for i: int in range(3):
		assert_true(SfxManager.is_sfx_cached("cached_0"))
		assert_false(SfxManager.is_sfx_missing("cached_0"))
		assert_eq(SfxManager.get_cached_sfx_count(), SfxManager.MAX_SFX_CACHE_SIZE)
		assert_eq(SfxManager.get_cached_sfx_names(), order_before, "Reads never reorder entries")

	SfxManager.cache_sfx_for_test("new_entry", AudioStreamWAV.new())

	assert_false(SfxManager.is_sfx_cached("cached_0"), "Diagnostic reads preserve LRU order")
	assert_true(SfxManager.is_sfx_cached("cached_1"))
	assert_true(SfxManager.is_sfx_cached("new_entry"))


## Editing the returned name list must not change the cache.
## :rtype: void
func test_cached_names_returns_a_copy() -> void:
	_seed_cache(3)
	var names: Array[String] = SfxManager.get_cached_sfx_names()

	names.clear()

	assert_eq(SfxManager.get_cached_sfx_count(), 3)
	assert_eq(SfxManager.get_cached_sfx_names(), _names("cached_", 0, 2))


## Normal playback refreshes a hit before a new load uses the shared insertion helper.
## :rtype: void
func test_normal_load_evicts_the_oldest_unplayed_entry() -> void:
	SfxManager.play_sfx("slider")
	_seed_cache(SfxManager.MAX_SFX_CACHE_SIZE - 1)

	SfxManager.play_sfx("slider")
	SfxManager.play_sfx(AudioConstants.SFX_CHECK)

	assert_eq(SfxManager.get_cached_sfx_count(), SfxManager.MAX_SFX_CACHE_SIZE)
	assert_true(SfxManager.is_sfx_cached("slider"))
	assert_true(SfxManager.is_sfx_cached(AudioConstants.SFX_CHECK))
	assert_false(SfxManager.is_sfx_cached("cached_0"))
	assert_true(SfxManager.is_sfx_cached("cached_1"))
	var names: Array[String] = SfxManager.get_cached_sfx_names()
	assert_eq(names[names.size() - 2], "slider", "The replayed hit sits just before the new load")
	assert_eq(names[names.size() - 1], AudioConstants.SFX_CHECK, "The new load is newest")
	assert_eq(SfxManager.get_active_sfx_stream_path(), AudioConstants.SFX_DIR_PATH + "check.wav")


## Failure tracking distinguishes identifiers and never inserts a success-cache entry.
## :rtype: void
func test_missing_diagnostic_tracks_failures_independently() -> void:
	SfxManager.play_sfx(MISSING_SFX)
	SfxManager.play_sfx(RETRY_SFX)
	SfxManager.play_sfx(MISSING_SFX)

	assert_true(SfxManager.is_sfx_missing(MISSING_SFX))
	assert_true(SfxManager.is_sfx_missing(RETRY_SFX))
	assert_eq(SfxManager.get_missing_sfx_count(), 2, "A repeated failure adds no second entry")
	assert_false(SfxManager.is_sfx_missing("slider"))
	assert_false(SfxManager.is_sfx_missing(""))
	assert_false(SfxManager.is_sfx_cached(MISSING_SFX))
	assert_false(SfxManager.is_sfx_cached(RETRY_SFX))
	assert_eq(SfxManager.get_cached_sfx_count(), 0)
	assert_false(SfxManager.is_any_sfx_playing())


## Clearing caches is idempotent, releases both kinds of entries and retains idle pool nodes.
## :rtype: void
func test_clear_diagnostic_caches_resets_both_tables_without_rebuilding_pool() -> void:
	_seed_cache(SfxManager.MAX_SFX_CACHE_SIZE)
	SfxManager.play_sfx(MISSING_SFX)
	SfxManager.play_sfx(RETRY_SFX)
	assert_eq(SfxManager.get_missing_sfx_count(), 2)
	var children: Array[Node] = SfxManager.get_children()

	SfxManager.clear_diagnostic_caches()
	SfxManager.clear_diagnostic_caches()

	assert_eq(SfxManager.get_cached_sfx_count(), 0)
	assert_true(SfxManager.get_cached_sfx_names().is_empty())
	for i: int in range(SfxManager.MAX_SFX_CACHE_SIZE):
		assert_false(SfxManager.is_sfx_cached("cached_" + str(i)))
	assert_eq(SfxManager.get_missing_sfx_count(), 0)
	assert_false(SfxManager.is_sfx_missing(MISSING_SFX))
	assert_false(SfxManager.is_sfx_missing(RETRY_SFX))
	assert_eq(SfxManager.get_children(), children, "Clearing caches retains the same pool nodes")
	assert_false(SfxManager.is_any_sfx_playing())


## Runtime cache reset preserves overlapping playback and allows a later lazy reload.
## :rtype: void
func test_clear_during_playback_keeps_active_sounds_and_allows_reload() -> void:
	SfxManager.play_sfx("slider", AudioConstants.BUS_SFX_MENU, 1.25, -6.0)
	SfxManager.play_sfx(AudioConstants.SFX_CHECK)
	var children: Array[Node] = SfxManager.get_children()
	assert_eq(SfxManager.get_active_sfx_playback_count(), 2)

	SfxManager.clear_diagnostic_caches()

	assert_eq(SfxManager.get_cached_sfx_count(), 0)
	assert_false(SfxManager.is_sfx_cached("slider"))
	assert_false(SfxManager.is_sfx_cached(AudioConstants.SFX_CHECK))
	assert_eq(SfxManager.get_children(), children)
	assert_eq(SfxManager.get_active_sfx_playback_count(), 2, "Clearing must not stop active sounds")
	assert_eq(SfxManager.get_active_sfx_stream_path(), AudioConstants.SFX_DIR_PATH + "check.wav")
	SfxManager.play_sfx("slider")
	assert_true(SfxManager.is_sfx_cached("slider"), "The next request lazily repopulates the cache")
	assert_eq(SfxManager.get_cached_sfx_count(), 1)
	assert_eq(SfxManager.get_active_sfx_playback_count(), 3)
	assert_eq(SfxManager.get_children(), children, "Reload reuses the existing pool")


## A previously missing asset is retried only after clearing the missing-asset table.
## :rtype: void
func test_clear_allows_previously_missing_asset_to_load() -> void:
	var path: String = AudioConstants.SFX_DIR_PATH + RETRY_SFX + ".wav"
	assert_false(ResourceLoader.exists(path), "Precondition: the synthetic asset is unavailable")
	SfxManager.play_sfx(RETRY_SFX)
	assert_true(SfxManager.is_sfx_missing(RETRY_SFX))

	# Make the asset available without a disk fixture: take_over_path() registers the stream in
	# the engine's ResourceCache, and in Godot 4 ResourceLoader.exists() checks that cache before
	# the filesystem, while load() returns the cached instance. If a Godot upgrade changes this,
	# the assert below fails first and points here.
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
	assert_eq(SfxManager.get_missing_sfx_count(), 0)
	assert_eq(SfxManager.get_active_sfx_stream_path(), path)


## Test cleanup still delegates cache clearing while stopping sounds and rebuilding the pool.
## :rtype: void
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
	assert_eq(SfxManager.get_missing_sfx_count(), 0)
	assert_false(SfxManager.is_sfx_missing(MISSING_SFX))
	assert_eq(SfxManager.get_active_sfx_playback_count(), 0)
	assert_eq(SfxManager.get_child_count(), SfxManager.SFX_POOL_SIZE)
	SfxManager.play_sfx("slider")
	assert_true(SfxManager.is_sfx_cached("slider"))
	assert_eq(SfxManager.get_active_sfx_playback_count(), 1)
