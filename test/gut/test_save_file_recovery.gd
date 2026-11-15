## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_save_file_recovery.gd
##
## GUT tests for #1144: an encrypted settings file that can't be decrypted is kept as
## <path>.corrupt instead of being deleted, the game starts with defaults, and the main menu
## is told once through Globals.consume_settings_reset_notice().
##
## The files here are real encrypted files: they are saved with KEY_A and loaded with KEY_B
## (wrong key), or saved with KEY_A and damaged after the header. Godot reports both as
## ERR_FILE_CORRUPT and prints an engine error for each failed decryption, which every test
## asserts with assert_engine_error().
##
## Issue: https://github.com/ikostan/SkyLockAssault/issues/1144

extends GutTest

const InputDefaults = preload("res://scripts/core/input_defaults.gd")
const TEST_CONFIG_PATH: String = "user://test_save_file_recovery.cfg"
const BACKUP_PATH: String = TEST_CONFIG_PATH + Globals.CORRUPT_BACKUP_SUFFIX
const KEY_A: String = "test_recovery_key_a"
const KEY_B: String = "test_recovery_key_b"
## Size of Godot's encrypted file header: magic (4) + MD5 (16) + length (8) + IV (16).
## Bytes after it are the encrypted payload.
const ENCRYPTED_HEADER_SIZE: int = 44
## Engine error text printed by FileAccessEncrypted when the MD5 check fails.
const MD5_ERROR_TEXT: String = "MD5 sum of the decrypted file does not match"
## Engine error text printed by ConfigFile when the text can't be parsed.
const PARSE_ERROR_TEXT: String = "ConfigFile parse error"

var _original_key: String
var _original_settings: GameSettingsResource
var _original_notice_pending: bool
var _original_audio_path: String
var _original_bus_states: Dictionary = {}
## AudioManager's last-audible volume per bus. load_volumes() and save_volumes() rebuild it,
## and a later unmute from zero restores it, so it is restored along with the bus values.
var _original_last_audible: Dictionary = {}
var _original_input_events: Dictionary = {}
var _original_needs_save: bool


func before_all() -> void:
	_original_audio_path = AudioManager.current_config_path
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		_original_bus_states[bus] = AudioManager.get_bus_state(bus)
	_original_last_audible = AudioManager._last_audible_volume.duplicate()
	for action: String in Settings.ACTIONS:
		_original_input_events[action] = InputMap.action_get_events(action)
	_original_needs_save = Settings.needs_save()


func after_all() -> void:
	AudioManager.current_config_path = _original_audio_path
	for bus: String in _original_bus_states:
		var state: Dictionary = _original_bus_states[bus]
		AudioManager.set_bus_state(bus, state["volume"], state["muted"])
	AudioManager.apply_all_volumes()
	# After the bus values, so nothing rebuilds the history again
	AudioManager._last_audible_volume = _original_last_audible.duplicate()
	for action: String in _original_input_events:
		InputMap.action_erase_events(action)
		for event: InputEvent in _original_input_events[action]:
			InputMap.action_add_event(action, event)
	Settings.set_needs_save_for_test(_original_needs_save)


func before_each() -> void:
	_remove_test_files()
	_original_key = Globals.save_encryption_pass
	_original_notice_pending = Globals._settings_reset_notice_pending
	Globals._settings_reset_notice_pending = false
	_original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()
	Globals.set_test_encryption_key(KEY_A)


func after_each() -> void:
	Globals.settings = _original_settings
	Globals.save_encryption_pass = _original_key
	Globals._settings_reset_notice_pending = _original_notice_pending
	_remove_test_files()


## Removes the test config, its backup, and the backup directory used by the rename test.
func _remove_test_files() -> void:
	for path: String in [TEST_CONFIG_PATH, BACKUP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(BACKUP_PATH):
		var blocker: String = BACKUP_PATH.path_join("blocker.txt")
		if FileAccess.file_exists(blocker):
			DirAccess.remove_absolute(blocker)
		DirAccess.remove_absolute(BACKUP_PATH)


## Saves a settings file encrypted with [param key] and returns its bytes.
func _write_encrypted_file(key: String, difficulty: float = 1.7) -> PackedByteArray:
	var config: ConfigFile = ConfigFile.new()
	config.set_value(Globals.SETTINGS_SECTION, "difficulty", difficulty)
	config.set_value("audio", "master_volume", 0.3)
	config.set_value("input", "fire", ["key:%d" % KEY_K])
	assert_eq(config.save_encrypted_pass(TEST_CONFIG_PATH, key), OK, "test file must save")
	return FileAccess.get_file_as_bytes(TEST_CONFIG_PATH)


## Saves a file with KEY_A, then flips one payload byte. The header stays valid, so the file
## is still detected as encrypted, but the MD5 check fails.
func _write_damaged_file() -> PackedByteArray:
	var bytes: PackedByteArray = _write_encrypted_file(KEY_A)
	assert_gt(bytes.size(), ENCRYPTED_HEADER_SIZE + 8, "file must have a payload to damage")
	bytes[ENCRYPTED_HEADER_SIZE + 5] = bytes[ENCRYPTED_HEADER_SIZE + 5] ^ 0xFF
	var file: FileAccess = FileAccess.open(TEST_CONFIG_PATH, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	return bytes


## A wrong-key file moves to .corrupt with its contents unchanged, and the original path
## no longer exists.
func test_wrong_key_file_moves_to_corrupt_unchanged() -> void:
	var original_bytes: PackedByteArray = _write_encrypted_file(KEY_A)
	Globals.set_test_encryption_key(KEY_B)

	var result: Dictionary = Globals.safe_load_config(TEST_CONFIG_PATH)
	assert_engine_error(MD5_ERROR_TEXT)

	assert_false(FileAccess.file_exists(TEST_CONFIG_PATH), "original path must be gone")
	assert_true(FileAccess.file_exists(BACKUP_PATH), "file must be kept as .corrupt")
	assert_eq(
		FileAccess.get_file_as_bytes(BACKUP_PATH), original_bytes, "backup must be byte-identical"
	)
	assert_eq(result["err"], ERR_FILE_NOT_FOUND, "callers must take the first-boot path")
	assert_false(result["is_legacy"], "a preserved file is not a legacy plaintext file")


## A damaged encrypted file with a valid header moves to .corrupt.
func test_damaged_encrypted_file_moves_to_corrupt() -> void:
	var damaged_bytes: PackedByteArray = _write_damaged_file()
	assert_true(Globals.is_file_encrypted(TEST_CONFIG_PATH), "header must still be valid")

	var result: Dictionary = Globals.safe_load_config(TEST_CONFIG_PATH)
	assert_engine_error(MD5_ERROR_TEXT)

	assert_false(FileAccess.file_exists(TEST_CONFIG_PATH), "original path must be gone")
	assert_eq(
		FileAccess.get_file_as_bytes(BACKUP_PATH), damaged_bytes, "backup must be byte-identical"
	)
	assert_eq(result["err"], ERR_FILE_NOT_FOUND, "callers must take the first-boot path")


## Both unreadable cases return an empty config, and Globals keeps its defaults.
func test_unreadable_files_return_empty_config_and_defaults_load() -> void:
	var default_difficulty: float = GameSettingsResource.new().difficulty

	_write_encrypted_file(KEY_A, 1.7)
	Globals.set_test_encryption_key(KEY_B)
	var wrong_key: Dictionary = Globals.safe_load_config(TEST_CONFIG_PATH)
	assert_engine_error(MD5_ERROR_TEXT)
	assert_eq(wrong_key["err"], ERR_FILE_NOT_FOUND, "wrong key: first-boot error")
	assert_eq((wrong_key["config"] as ConfigFile).get_sections().size(), 0, "wrong key: empty")

	_remove_test_files()
	Globals.set_test_encryption_key(KEY_A)
	_write_damaged_file()
	Globals._load_settings(TEST_CONFIG_PATH)
	assert_engine_error(MD5_ERROR_TEXT)
	assert_almost_eq(
		Globals.settings.difficulty, default_difficulty, 0.0001, "damaged: default difficulty"
	)
	assert_true(FileAccess.file_exists(BACKUP_PATH), "damaged: file kept as .corrupt")


## An existing .corrupt file is replaced without an error, so only the latest copy is kept.
func test_existing_backup_is_replaced() -> void:
	_write_encrypted_file(KEY_A, 1.2)
	Globals.set_test_encryption_key(KEY_B)
	Globals.safe_load_config(TEST_CONFIG_PATH)
	assert_engine_error(MD5_ERROR_TEXT)
	var first_backup: PackedByteArray = FileAccess.get_file_as_bytes(BACKUP_PATH)

	Globals.set_test_encryption_key(KEY_A)
	var second_bytes: PackedByteArray = _write_encrypted_file(KEY_A, 1.9)
	Globals.set_test_encryption_key(KEY_B)
	var result: Dictionary = Globals.safe_load_config(TEST_CONFIG_PATH)
	assert_engine_error(MD5_ERROR_TEXT)

	assert_eq(result["err"], ERR_FILE_NOT_FOUND, "second failure must also be preserved")
	assert_false(FileAccess.file_exists(TEST_CONFIG_PATH), "original path must be gone")
	assert_eq(FileAccess.get_file_as_bytes(BACKUP_PATH), second_bytes, "latest copy is kept")
	assert_ne(first_backup, second_bytes, "the two files must differ for this check")


## If the rename fails, the file stays in place, the original error is returned, and no
## notice is set. A non-empty directory at the backup path makes the rename fail.
func test_failed_rename_keeps_file_and_returns_original_error() -> void:
	var original_bytes: PackedByteArray = _write_encrypted_file(KEY_A)
	DirAccess.make_dir_recursive_absolute(BACKUP_PATH)
	var blocker: FileAccess = FileAccess.open(
		BACKUP_PATH.path_join("blocker.txt"), FileAccess.WRITE
	)
	blocker.store_string("keeps the directory non-empty")
	blocker.close()
	Globals.set_test_encryption_key(KEY_B)

	var result: Dictionary = Globals.safe_load_config(TEST_CONFIG_PATH)
	assert_engine_error(MD5_ERROR_TEXT)

	assert_eq(result["err"], ERR_FILE_CORRUPT, "original decryption error must be returned")
	assert_eq(
		FileAccess.get_file_as_bytes(TEST_CONFIG_PATH), original_bytes, "file must be untouched"
	)
	assert_false(Globals.consume_settings_reset_notice(), "no notice when nothing was reset")


## Non-corrupt read errors leave the file untouched and don't set the notice: an encrypted
## file that decrypts but isn't valid config text, and an unparsable plaintext file.
func test_non_corrupt_read_errors_leave_file_untouched() -> void:
	var encrypted: FileAccess = FileAccess.open_encrypted_with_pass(
		TEST_CONFIG_PATH, FileAccess.WRITE, KEY_A
	)
	encrypted.store_string("[[[ not = a config\n=\n[")
	encrypted.close()
	var encrypted_bytes: PackedByteArray = FileAccess.get_file_as_bytes(TEST_CONFIG_PATH)

	var encrypted_result: Dictionary = Globals.safe_load_config(TEST_CONFIG_PATH)
	assert_engine_error(PARSE_ERROR_TEXT)
	assert_eq(encrypted_result["err"], ERR_PARSE_ERROR, "encrypted: parse error returned")
	assert_eq(
		FileAccess.get_file_as_bytes(TEST_CONFIG_PATH), encrypted_bytes, "encrypted: untouched"
	)
	assert_false(FileAccess.file_exists(BACKUP_PATH), "encrypted: no .corrupt copy")

	_remove_test_files()
	var plaintext: FileAccess = FileAccess.open(TEST_CONFIG_PATH, FileAccess.WRITE)
	plaintext.store_string("[[[ not = a config\n=\n[")
	plaintext.close()
	var plaintext_bytes: PackedByteArray = FileAccess.get_file_as_bytes(TEST_CONFIG_PATH)

	var plaintext_result: Dictionary = Globals.safe_load_config(TEST_CONFIG_PATH)
	assert_engine_error(PARSE_ERROR_TEXT)
	assert_ne(plaintext_result["err"], OK, "plaintext: error returned")
	assert_ne(plaintext_result["err"], ERR_FILE_NOT_FOUND, "plaintext: not a first boot")
	assert_eq(
		FileAccess.get_file_as_bytes(TEST_CONFIG_PATH), plaintext_bytes, "plaintext: untouched"
	)
	assert_false(FileAccess.file_exists(BACKUP_PATH), "plaintext: no .corrupt copy")
	assert_false(Globals.consume_settings_reset_notice(), "no notice for other read errors")


## A readable encrypted file and a legacy plaintext file load as before, with no .corrupt
## file and no notice.
func test_readable_files_load_without_backup_or_notice() -> void:
	_write_encrypted_file(KEY_A, 1.4)
	var encrypted_result: Dictionary = Globals.safe_load_config(TEST_CONFIG_PATH)
	assert_eq(encrypted_result["err"], OK, "encrypted file must load")
	assert_false(encrypted_result["is_legacy"], "encrypted file is not legacy")
	assert_almost_eq(
		(encrypted_result["config"] as ConfigFile).get_value(
			Globals.SETTINGS_SECTION, "difficulty"
		),
		1.4,
		0.0001,
		"encrypted value must be read"
	)

	_remove_test_files()
	var config: ConfigFile = ConfigFile.new()
	config.set_value(Globals.SETTINGS_SECTION, "difficulty", 1.6)
	config.save(TEST_CONFIG_PATH)
	var plaintext_result: Dictionary = Globals.safe_load_config(TEST_CONFIG_PATH)
	assert_eq(plaintext_result["err"], OK, "plaintext file must load")
	assert_true(plaintext_result["is_legacy"], "plaintext file needs migration")

	assert_true(FileAccess.file_exists(TEST_CONFIG_PATH), "file must stay in place")
	assert_false(FileAccess.file_exists(BACKUP_PATH), "no .corrupt copy for readable files")
	assert_false(Globals.consume_settings_reset_notice(), "no notice for readable files")


## consume_settings_reset_notice() returns true once after a reset, then false.
func test_consume_settings_reset_notice_returns_true_once() -> void:
	assert_false(Globals.consume_settings_reset_notice(), "no notice before any reset")

	_write_encrypted_file(KEY_A)
	Globals.set_test_encryption_key(KEY_B)
	Globals.safe_load_config(TEST_CONFIG_PATH)
	assert_engine_error(MD5_ERROR_TEXT)

	assert_true(Globals.consume_settings_reset_notice(), "first call reports the reset")
	assert_false(Globals.consume_settings_reset_notice(), "second call returns false")


## After a reset, Globals, Settings, and AudioManager all load defaults, the first read moves
## the file once, and the next save creates a file the new key can read.
func test_reset_loads_defaults_everywhere_and_next_save_is_readable() -> void:
	var default_difficulty: float = GameSettingsResource.new().difficulty
	AudioManager._init_to_defaults()
	var default_master: float = AudioManager.get_bus_state(AudioConstants.BUS_MASTER)["volume"]
	# Start from the default fire binding (Space + gamepad A), not whatever an earlier suite
	# left in the shared InputMap. The saved file binds KEY_K, so K can only appear if the
	# unreadable file was applied. Both devices are bound, so backfill adds nothing.
	# after_all() restores the original InputMap.
	var fire_key: InputEventKey = InputDefaults.make_event("fire", "keyboard")
	assert_ne(fire_key.physical_keycode, KEY_K, "known binding must differ from the saved one")
	InputMap.action_erase_events("fire")
	InputMap.action_add_event("fire", fire_key)
	InputMap.action_add_event("fire", InputDefaults.make_event("fire", "gamepad"))

	_write_encrypted_file(KEY_A)
	Globals.set_test_encryption_key(KEY_B)

	# Same order as the autoloads: Globals, then Settings, then AudioManager.
	Globals._load_settings(TEST_CONFIG_PATH)
	Settings.load_input_mappings(TEST_CONFIG_PATH)
	AudioManager.load_volumes(TEST_CONFIG_PATH)
	assert_engine_error_count(1, "only the first read fails; later reads see no file")

	assert_almost_eq(Globals.settings.difficulty, default_difficulty, 0.0001, "Globals default")
	assert_almost_eq(
		AudioManager.get_bus_state(AudioConstants.BUS_MASTER)["volume"],
		default_master,
		0.0001,
		"AudioManager default"
	)
	var fire_after: Array[InputEvent] = InputMap.action_get_events("fire")
	assert_eq(fire_after.size(), 2, "fire keeps exactly its known keyboard and gamepad binding")
	for event: InputEvent in fire_after:
		if event is InputEventKey:
			assert_eq(
				(event as InputEventKey).physical_keycode,
				fire_key.physical_keycode,
				"saved KEY_K binding not applied"
			)
	assert_true(Globals.consume_settings_reset_notice(), "the reset is reported once")

	Globals._save_settings(TEST_CONFIG_PATH)
	Settings.save_input_mappings(TEST_CONFIG_PATH)
	AudioManager.save_volumes(TEST_CONFIG_PATH)

	var reloaded: ConfigFile = ConfigFile.new()
	assert_eq(reloaded.load_encrypted_pass(TEST_CONFIG_PATH, KEY_B), OK, "new file is readable")
	assert_true(reloaded.has_section(Globals.SETTINGS_SECTION), "Globals section saved")
	assert_true(reloaded.has_section("input"), "input section saved")
	assert_true(reloaded.has_section("audio"), "audio section saved")
	assert_true(FileAccess.file_exists(BACKUP_PATH), "backup is still kept")
