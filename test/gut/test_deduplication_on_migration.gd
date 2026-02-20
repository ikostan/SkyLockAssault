## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_deduplication_on_migration.gd
## Additional GUT unit test to ensure migration doesn't add duplicates.
## Scenario: Legacy unbound → add defaults, but if partial duplicates, dedup.
## Fails if InputMap has duplicates after migration.
## :references: settings.gd _migrate_legacy_unbound_states()

extends GutTest

const TEST_ACTION: String = "fire"  # Critical action
const TEST_CONFIG_PATH: String = "user://test_dedup_migration.cfg"


## Per-test: Setup legacy config with partial duplicate.
func before_each() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", TEST_ACTION, [])  # Unbound, but we'll add duplicate manually post-load
	config.save(TEST_CONFIG_PATH)
	Settings.load_input_mappings(TEST_CONFIG_PATH)
	# Manually add duplicate before migration
	var def_ev: InputEventKey = InputEventKey.new()
	def_ev.physical_keycode = Settings.DEFAULT_KEYBOARD[TEST_ACTION]
	InputMap.action_add_event(TEST_ACTION, def_ev)
	InputMap.action_add_event(TEST_ACTION, def_ev.duplicate())
	Globals.remove_meta(Settings.LEGACY_MIGRATION_KEY)  # Force migration


## Per-test: Cleanup.
func after_each() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	await get_tree().process_frame


## DEDUP-04 | Migration on legacy with duplicates → adds defaults but dedups | No extras
func test_dedup_04_migration_with_duplicates() -> void:
	Settings._migrate_legacy_unbound_states()
	var events: Array[InputEvent] = InputMap.action_get_events(TEST_ACTION)
	# var key_events: Array = events.filter(func(ev): return ev is InputEventKey)
	var key_events: Array[InputEvent] = events.filter(func(ev: InputEvent) -> bool: return ev is InputEvent)
	assert_eq(key_events.size(), 1, "Migration should not add duplicates")
