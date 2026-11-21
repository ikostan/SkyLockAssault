## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_settings_owned_state.gd
##
## Settings owns its own state (#1101): the current input device, with its setter and
## input_device_changed signal, and the run-once migration flags, which used to live on
## Globals (a field and metadata). The flags must keep their on-disk [meta] keys.

extends GutTest

const TEST_CONFIG_PATH: String = "user://test_settings_owned_state.cfg"

var _saved_device: String = ""
var _saved_events: Dictionary = {}
var _had_v2_flag: bool = false
var _had_v3_flag: bool = false


func before_each() -> void:
	# load_input_mappings() backfills defaults into the global InputMap; restore it afterwards.
	_saved_events.clear()
	for action: String in Settings.ACTIONS:
		_saved_events[action] = InputMap.action_get_events(action).duplicate()
	_saved_device = Settings.get_input_device()
	_had_v2_flag = Settings.is_migration_done(Settings.LEGACY_MIGRATION_KEY)
	_had_v3_flag = Settings.is_migration_done(Settings.INPUT_LAYOUT_MIGRATION_KEY)
	_remove_test_config()


func after_each() -> void:
	for action: String in _saved_events:
		InputMap.action_erase_events(action)
		for ev: InputEvent in _saved_events[action]:
			InputMap.action_add_event(action, ev)
	Settings.set_input_device(_saved_device)
	Settings.set_migration_done_for_test(Settings.LEGACY_MIGRATION_KEY, _had_v2_flag)
	Settings.set_migration_done_for_test(Settings.INPUT_LAYOUT_MIGRATION_KEY, _had_v3_flag)
	Settings.set_needs_save_for_test(false)
	_remove_test_config()


func _remove_test_config() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)


# ── Input device ─────────────────────────────────────────────────────────────


## DEV-01 | Setting another device changes it and emits input_device_changed once.
func test_dev_01_set_input_device_changes_and_emits() -> void:
	Settings.set_input_device("keyboard")
	watch_signals(Settings)

	Settings.set_input_device("gamepad")

	assert_eq(Settings.get_input_device(), "gamepad", "device changed")
	assert_signal_emit_count(Settings, "input_device_changed", 1, "one change, one signal")
	assert_signal_emitted_with_parameters(Settings, "input_device_changed", ["gamepad"])


## DEV-02 | Setting the device that is already current emits nothing.
func test_dev_02_same_device_does_not_emit() -> void:
	Settings.set_input_device("gamepad")
	watch_signals(Settings)

	Settings.set_input_device("gamepad")

	assert_eq(Settings.get_input_device(), "gamepad")
	assert_signal_not_emitted(Settings, "input_device_changed", "no change, no signal")


## DEV-03 | An unknown device is ignored: the device stays and no signal is emitted.
func test_dev_03_unknown_device_is_ignored() -> void:
	Settings.set_input_device("keyboard")
	watch_signals(Settings)

	for bad: String in ["mouse", "", "Gamepad"]:
		Settings.set_input_device(bad)
		assert_eq(Settings.get_input_device(), "keyboard", "'%s' is rejected" % bad)

	assert_signal_not_emitted(Settings, "input_device_changed")


## DEV-04 | Globals no longer holds the input device, so nothing can write it there.
func test_dev_04_globals_has_no_input_device_field() -> void:
	assert_false(
		"current_input_device" in Globals, "the device lives in Settings, not on Globals"
	)


# ── Migration flags ──────────────────────────────────────────────────────────


## FLAG-01 | Running the migrations sets the flags in Settings, not as Globals metadata.
func test_flag_01_migrations_do_not_write_globals_meta() -> void:
	Settings.set_migration_done_for_test(Settings.LEGACY_MIGRATION_KEY, false)
	Settings.set_migration_done_for_test(Settings.INPUT_LAYOUT_MIGRATION_KEY, false)

	Settings._migrate_legacy_unbound_states()
	Settings._migrate_input_layout_v3()

	for key: String in Settings.MIGRATION_KEYS:
		assert_true(Settings.is_migration_done(key), key + " is done")
		assert_false(Globals.has_meta(key), key + " is not Globals metadata")


## FLAG-02 | An existing save with both [meta] flags loads them, and saving writes them back
## under the same keys (the on-disk format is unchanged).
func test_flag_02_existing_save_keeps_meta_keys() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "settings_migrated_v2", true)
	cfg.set_value("meta", "input_layout_migrated_v3", true)
	assert_eq(cfg.save_encrypted_pass(TEST_CONFIG_PATH, Globals.save_encryption_pass), OK)
	Settings.set_migration_done_for_test(Settings.LEGACY_MIGRATION_KEY, false)
	Settings.set_migration_done_for_test(Settings.INPUT_LAYOUT_MIGRATION_KEY, false)

	Settings.load_input_mappings(TEST_CONFIG_PATH)

	assert_true(Settings.is_migration_done(Settings.LEGACY_MIGRATION_KEY), "v2 flag restored")
	assert_true(Settings.is_migration_done(Settings.INPUT_LAYOUT_MIGRATION_KEY), "v3 restored")

	Settings.save_input_mappings(TEST_CONFIG_PATH)
	var saved := ConfigFile.new()
	assert_eq(saved.load_encrypted_pass(TEST_CONFIG_PATH, Globals.save_encryption_pass), OK)
	assert_eq(saved.get_value("meta", "settings_migrated_v2", false), true, "v2 key kept")
	assert_eq(saved.get_value("meta", "input_layout_migrated_v3", false), true, "v3 key kept")


## FLAG-03 | A flag the config does not set to true leaves the migration to run: a missing
## key, false, or a hand-edited non-bool value.
func test_flag_03_non_true_meta_value_is_not_done() -> void:
	for value: Variant in [null, false, "yes", 1]:
		var cfg := ConfigFile.new()
		if value != null:
			cfg.set_value("meta", Settings.LEGACY_MIGRATION_KEY, value)
		cfg.set_value("meta", "placeholder", true)  # Keeps the file non-empty.
		assert_eq(cfg.save_encrypted_pass(TEST_CONFIG_PATH, Globals.save_encryption_pass), OK)
		Settings.set_migration_done_for_test(Settings.LEGACY_MIGRATION_KEY, false)

		Settings.load_input_mappings(TEST_CONFIG_PATH)

		assert_false(
			Settings.is_migration_done(Settings.LEGACY_MIGRATION_KEY),
			"meta value %s does not mark the migration done" % str(value)
		)


## FLAG-04 | A flag not marked done is not written to the config on save.
func test_flag_04_not_done_flag_is_not_saved() -> void:
	Settings.set_migration_done_for_test(Settings.LEGACY_MIGRATION_KEY, false)
	Settings.set_migration_done_for_test(Settings.INPUT_LAYOUT_MIGRATION_KEY, true)

	Settings.save_input_mappings(TEST_CONFIG_PATH)

	var saved := ConfigFile.new()
	assert_eq(saved.load_encrypted_pass(TEST_CONFIG_PATH, Globals.save_encryption_pass), OK)
	assert_false(saved.has_section_key("meta", Settings.LEGACY_MIGRATION_KEY), "v2 not saved")
	assert_true(saved.get_value("meta", Settings.INPUT_LAYOUT_MIGRATION_KEY, false), "v3 saved")


## A partial config can add a completed migration without undoing one already run.
func test_loading_partial_metadata_preserves_completed_migrations() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", Settings.INPUT_LAYOUT_MIGRATION_KEY, true)
	assert_eq(cfg.save_encrypted_pass(TEST_CONFIG_PATH, Globals.save_encryption_pass), OK)
	Settings.set_migration_done_for_test(Settings.LEGACY_MIGRATION_KEY, true)
	Settings.set_migration_done_for_test(Settings.INPUT_LAYOUT_MIGRATION_KEY, false)

	Settings.load_input_mappings(TEST_CONFIG_PATH)

	assert_true(Settings.is_migration_done(Settings.LEGACY_MIGRATION_KEY))
	assert_true(Settings.is_migration_done(Settings.INPUT_LAYOUT_MIGRATION_KEY))
	assert_false(Settings.is_migration_done("unknown_migration"))


## The pause hint follows the current device on each call.
func test_pause_label_follows_current_input_device() -> void:
	InputMap.action_erase_events("pause")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_ESCAPE
	InputMap.action_add_event("pause", key)
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_START
	InputMap.action_add_event("pause", button)

	Settings.set_input_device("keyboard")
	assert_eq(Settings.get_pause_binding_label(), "ESCAPE")
	Settings.set_input_device("gamepad")
	assert_eq(Settings.get_pause_binding_label(), "START")
