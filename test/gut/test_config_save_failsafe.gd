## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_config_save_failsafe.gd
##
## GUT tests for #1145: every save path writes settings.cfg through Globals.save_config(),
## which saves encrypted with a valid key and plaintext with an empty key. With an empty key,
## Globals.safe_load_config() leaves an existing encrypted file alone, so no save overwrites
## it, and no .corrupt copy or reset notice is made.
##
## Godot's save_encrypted_pass() accepts an empty password and writes a GDEC file keyed by
## the MD5 of "". Before #1145, input and audio saves did that while gameplay saves wrote
## plaintext, so the file's format depended on which manager saved last, and a hollow file
## failed to decrypt once a real key returned. The "saves plaintext" checks below catch that.
##
## An empty key is simulated with Globals.set_test_empty_encryption_key(), because blanking
## save_encryption_pass only makes ensure_encryption_key() regenerate the key.
##
## Settings.save_last_input_device() always writes Settings.CONFIG_PATH, so tests that use it
## work on that path. The suite saves the bytes of that file and of its settings.cfg.corrupt
## recovery copy (#1144) before each test and writes them back afterwards.
##
## Log lines are read through a Logger added with OS.add_logger(), which receives everything
## Globals.log_message() prints.
##
## Issue: https://github.com/ikostan/SkyLockAssault/issues/1145

extends GutTest

const TEST_CONFIG_PATH: String = "user://test_config_save_failsafe.cfg"
const BACKUP_PATH: String = TEST_CONFIG_PATH + Globals.CORRUPT_BACKUP_SUFFIX
const CONFIG_BACKUP_PATH: String = Settings.CONFIG_PATH + Globals.CORRUPT_BACKUP_SUFFIX
## A file in a directory that doesn't exist, so every save to it fails.
const INVALID_CONFIG_PATH: String = "user://missing_dir_config_save_failsafe/test.cfg"
const KEY_A: String = "test_failsafe_key_a"
const PLAINTEXT_WARNING: String = "⚠️ FAILSAFE ACTIVE: Saved in PLAINTEXT: "


## Collects every logged line while it is added with OS.add_logger().
class LogCapture:
	extends Logger
	var lines: Array[String] = []
	var _mutex: Mutex = Mutex.new()

	func _log_message(message: String, _error: bool) -> void:
		_mutex.lock()
		lines.append(message)
		_mutex.unlock()

	## Returns true if any captured line contains [param text].
	func has_text(text: String) -> bool:
		_mutex.lock()
		var found: bool = false
		for line: String in lines:
			if line.contains(text):
				found = true
				break
		_mutex.unlock()
		return found


var _original_key: String
var _original_settings: GameSettingsResource
var _original_notice_pending: bool
var _original_last_audible: Dictionary = {}
## Bytes of Settings.CONFIG_PATH before the test, or empty if it didn't exist.
var _original_config_bytes: PackedByteArray = PackedByteArray()
var _original_config_existed: bool = false
## Bytes of the real settings.cfg.corrupt recovery copy (#1144), or empty if it didn't exist.
var _original_backup_bytes: PackedByteArray = PackedByteArray()
var _original_backup_existed: bool = false
var _log: LogCapture


func before_each() -> void:
	_original_key = Globals.save_encryption_pass
	_original_notice_pending = Globals._settings_reset_notice_pending
	Globals._settings_reset_notice_pending = false
	_original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()
	Globals.settings.current_log_level = Globals.LogLevel.DEBUG
	_original_last_audible = AudioManager._last_audible_volume.duplicate()

	_original_config_existed = FileAccess.file_exists(Settings.CONFIG_PATH)
	_original_config_bytes = PackedByteArray()
	if _original_config_existed:
		_original_config_bytes = FileAccess.get_file_as_bytes(Settings.CONFIG_PATH)
	_original_backup_existed = FileAccess.file_exists(CONFIG_BACKUP_PATH)
	_original_backup_bytes = PackedByteArray()
	if _original_backup_existed:
		_original_backup_bytes = FileAccess.get_file_as_bytes(CONFIG_BACKUP_PATH)
	_remove_test_files()

	Globals.set_test_encryption_key(KEY_A)
	_log = LogCapture.new()
	OS.add_logger(_log)


func after_each() -> void:
	OS.remove_logger(_log)
	# Always restore the key first, so later suites never run with a forced empty key.
	Globals.set_test_empty_encryption_key(false)
	Globals.save_encryption_pass = _original_key
	Globals.settings = _original_settings
	Globals._settings_reset_notice_pending = _original_notice_pending
	AudioManager._last_audible_volume = _original_last_audible.duplicate()
	_remove_test_files()

	if _original_config_existed:
		var file: FileAccess = FileAccess.open(Settings.CONFIG_PATH, FileAccess.WRITE)
		file.store_buffer(_original_config_bytes)
		file.close()
	if _original_backup_existed:
		var backup: FileAccess = FileAccess.open(CONFIG_BACKUP_PATH, FileAccess.WRITE)
		backup.store_buffer(_original_backup_bytes)
		backup.close()


## Removes the test files, a directory left at CONFIG_PATH, and any .corrupt copies.
func _remove_test_files() -> void:
	for path: String in [TEST_CONFIG_PATH, BACKUP_PATH, Settings.CONFIG_PATH, CONFIG_BACKUP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(Settings.CONFIG_PATH):
		DirAccess.remove_absolute(Settings.CONFIG_PATH)


## Saves an encrypted settings file with KEY_A and returns its bytes.
func _write_encrypted_file(path: String) -> PackedByteArray:
	var config: ConfigFile = ConfigFile.new()
	config.set_value(Globals.SETTINGS_SECTION, "difficulty", 1.7)
	config.set_value("audio", "master_volume", 0.3)
	config.set_value("input", "fire", ["key:%d" % KEY_K])
	assert_eq(config.save_encrypted_pass(path, KEY_A), OK, "test file must save")
	return FileAccess.get_file_as_bytes(path)


## Runs all four save paths against Settings.CONFIG_PATH.
func _run_all_save_paths() -> void:
	Globals._save_settings(Settings.CONFIG_PATH)
	Settings.save_input_mappings(Settings.CONFIG_PATH, ["fire"])
	Settings.save_last_input_device("gamepad")
	AudioManager.save_volumes(Settings.CONFIG_PATH)


## Returns the on-disk key AudioManager uses for the first configured bus volume.
func _first_bus_volume_key() -> String:
	var bus: String = AudioConstants.BUS_CONFIG.keys()[0]
	return AudioConstants.BUS_CONFIG[bus]["volume_var"]


# ==============================================================================
# save_config()
# ==============================================================================


## With a valid key, save_config() writes an encrypted file that the key can read.
func test_save_config_writes_encrypted_file_with_valid_key() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("test", "value", 42)

	assert_eq(Globals.save_config(config, TEST_CONFIG_PATH), OK, "save must succeed")
	assert_true(Globals.is_file_encrypted(TEST_CONFIG_PATH), "file must be encrypted")

	var reloaded: ConfigFile = ConfigFile.new()
	assert_eq(reloaded.load_encrypted_pass(TEST_CONFIG_PATH, KEY_A), OK, "key must read it")
	assert_eq(reloaded.get_value("test", "value"), 42, "value must round-trip")
	assert_false(_log.has_text(PLAINTEXT_WARNING), "no plaintext warning with a valid key")


## With an empty key, save_config() writes readable plaintext and logs the warning.
func test_save_config_writes_plaintext_and_warns_with_empty_key() -> void:
	Globals.set_test_empty_encryption_key()
	var config: ConfigFile = ConfigFile.new()
	config.set_value("test", "value", 42)

	assert_eq(Globals.save_config(config, TEST_CONFIG_PATH), OK, "save must succeed")
	assert_false(Globals.is_file_encrypted(TEST_CONFIG_PATH), "file must be plaintext")

	var reloaded: ConfigFile = ConfigFile.new()
	assert_eq(reloaded.load(TEST_CONFIG_PATH), OK, "plaintext must load without a key")
	assert_eq(reloaded.get_value("test", "value"), 42, "value must round-trip")
	assert_true(
		_log.has_text(PLAINTEXT_WARNING + TEST_CONFIG_PATH), "plaintext warning must name the path"
	)


## The forced empty key wins over a cached key and doesn't change it.
func test_empty_key_seam_overrides_and_keeps_cached_key() -> void:
	Globals.set_test_empty_encryption_key()
	assert_eq(Globals.ensure_encryption_key(), "", "forced key must be empty")
	assert_eq(Globals.save_encryption_pass, KEY_A, "cached key must be unchanged")

	Globals.set_test_empty_encryption_key(false)
	assert_eq(Globals.ensure_encryption_key(), KEY_A, "cached key must return after restore")


# ==============================================================================
# Empty key, no existing file
# ==============================================================================


## With an empty key and no file, each of the four save paths writes plaintext.
func test_every_save_path_saves_plaintext_with_empty_key() -> void:
	Globals.set_test_empty_encryption_key()
	var save_paths: Dictionary = {
		"gameplay settings": func() -> void: Globals._save_settings(Settings.CONFIG_PATH),
		"input mappings":
		func() -> void: Settings.save_input_mappings(Settings.CONFIG_PATH, ["fire"]),
		"last input device": func() -> void: Settings.save_last_input_device("gamepad"),
		"audio volumes": func() -> void: AudioManager.save_volumes(Settings.CONFIG_PATH),
	}

	for label: String in save_paths:
		_remove_test_files()
		var save_path: Callable = save_paths[label]
		save_path.call()
		assert_true(FileAccess.file_exists(Settings.CONFIG_PATH), label + " must create the file")
		assert_false(
			Globals.is_file_encrypted(Settings.CONFIG_PATH), label + " must save plaintext"
		)


## All four sections written with an empty key share one file and reload from it.
func test_all_sections_coexist_and_reload_with_empty_key() -> void:
	Globals.set_test_empty_encryption_key()
	Globals.settings.difficulty = 1.4

	_run_all_save_paths()

	var result: Dictionary = Globals.safe_load_config(Settings.CONFIG_PATH)
	var config: ConfigFile = result["config"]
	assert_eq(result["err"], OK, "plaintext file must load")
	assert_true(result["is_legacy"], "plaintext file must be flagged for migration")
	assert_eq(
		config.get_value(Globals.SETTINGS_SECTION, "difficulty"), 1.4, "gameplay must persist"
	)
	assert_true(config.has_section_key("input", "fire"), "input mappings must persist")
	assert_eq(
		config.get_value("input", "last_input_device"), "gamepad", "last device must persist"
	)
	assert_true(config.has_section_key("audio", _first_bus_volume_key()), "audio must persist")


# ==============================================================================
# Empty key, existing encrypted file
# ==============================================================================


## With an empty key, an encrypted file isn't decrypted, moved, or flagged as reset.
func test_encrypted_file_is_kept_on_load_with_empty_key() -> void:
	var original_bytes: PackedByteArray = _write_encrypted_file(TEST_CONFIG_PATH)
	Globals.set_test_empty_encryption_key()

	var result: Dictionary = Globals.safe_load_config(TEST_CONFIG_PATH)

	assert_eq(result["err"], ERR_UNCONFIGURED, "an unreadable key must be reported as an error")
	assert_false(result["is_legacy"], "an encrypted file is not legacy plaintext")
	assert_eq(
		FileAccess.get_file_as_bytes(TEST_CONFIG_PATH), original_bytes, "file must be unchanged"
	)
	assert_false(FileAccess.file_exists(BACKUP_PATH), "no .corrupt copy may be made")
	assert_false(Globals.consume_settings_reset_notice(), "no reset notice may be set")
	assert_true(_log.has_text("No encryption key"), "the skip must be logged")


## With an empty key, none of the four save paths overwrites an encrypted file.
func test_encrypted_file_survives_every_save_path_with_empty_key() -> void:
	var original_bytes: PackedByteArray = _write_encrypted_file(Settings.CONFIG_PATH)
	Globals.set_test_empty_encryption_key()

	_run_all_save_paths()

	assert_eq(
		FileAccess.get_file_as_bytes(Settings.CONFIG_PATH),
		original_bytes,
		"encrypted file must be byte-identical after every save path"
	)
	assert_false(FileAccess.file_exists(CONFIG_BACKUP_PATH), "no .corrupt copy may be made")
	assert_false(Globals.consume_settings_reset_notice(), "no reset notice may be set")


## With an empty key, loading gameplay settings from an encrypted file keeps defaults.
func test_load_settings_keeps_defaults_and_file_with_empty_key() -> void:
	var original_bytes: PackedByteArray = _write_encrypted_file(TEST_CONFIG_PATH)
	var default_difficulty: float = Globals.settings.difficulty
	Globals.set_test_empty_encryption_key()

	Globals._load_settings(TEST_CONFIG_PATH)

	assert_eq(Globals.settings.difficulty, default_difficulty, "defaults must stay in place")
	assert_eq(
		FileAccess.get_file_as_bytes(TEST_CONFIG_PATH), original_bytes, "file must be unchanged"
	)


# ==============================================================================
# Recovery once the key returns
# ==============================================================================


## A plaintext file saved without a key is encrypted by the existing migration once a valid
## key returns, and every section survives.
func test_plaintext_file_upgrades_to_encrypted_when_key_returns() -> void:
	Globals.set_test_empty_encryption_key()
	Globals.settings.difficulty = 1.4
	_run_all_save_paths()
	assert_false(Globals.is_file_encrypted(Settings.CONFIG_PATH), "precondition: plaintext")

	Globals.set_test_empty_encryption_key(false)
	Globals.settings = GameSettingsResource.new()
	Globals._load_settings(Settings.CONFIG_PATH)

	assert_true(Globals.is_file_encrypted(Settings.CONFIG_PATH), "migration must encrypt it")
	assert_eq(Globals.settings.difficulty, 1.4, "gameplay value must load from plaintext")

	var reloaded: ConfigFile = ConfigFile.new()
	assert_eq(reloaded.load_encrypted_pass(Settings.CONFIG_PATH, KEY_A), OK, "key must read it")
	assert_eq(reloaded.get_value(Globals.SETTINGS_SECTION, "difficulty"), 1.4, "gameplay kept")
	assert_true(reloaded.has_section_key("input", "fire"), "input mappings kept")
	assert_eq(reloaded.get_value("input", "last_input_device"), "gamepad", "last device kept")
	assert_true(reloaded.has_section_key("audio", _first_bus_volume_key()), "audio kept")


# ==============================================================================
# Write failures
# ==============================================================================


## save_config() returns the write error with an empty key and with a valid key.
func test_save_config_returns_write_error() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("test", "value", 1)

	assert_ne(Globals.save_config(config, INVALID_CONFIG_PATH), OK, "encrypted save must fail")

	Globals.set_test_empty_encryption_key()
	assert_ne(Globals.save_config(config, INVALID_CONFIG_PATH), OK, "plaintext save must fail")
	assert_true(
		_log.has_text("Failed to save plaintext " + INVALID_CONFIG_PATH),
		"plaintext failure must be logged"
	)
	assert_false(_log.has_text(PLAINTEXT_WARNING), "a failed save must not claim success")


## With an empty key, each caller logs its own error when the write fails.
func test_each_caller_logs_write_failure_with_empty_key() -> void:
	Globals.set_test_empty_encryption_key()

	Globals._save_settings(INVALID_CONFIG_PATH)
	assert_true(
		_log.has_text("Failed to save encrypted settings"), "gameplay save must log its error"
	)

	Settings.save_input_mappings(INVALID_CONFIG_PATH, ["fire"])
	assert_true(
		_log.has_text("Failed to save encrypted input mappings"), "input save must log its error"
	)

	AudioManager.save_volumes(INVALID_CONFIG_PATH)
	assert_true(_log.has_text("Failed to save config: "), "audio save must log its error")

	# save_last_input_device() always writes CONFIG_PATH: a directory there makes it fail.
	assert_eq(DirAccess.make_dir_absolute(Settings.CONFIG_PATH), OK, "blocker dir must be made")
	Settings.save_last_input_device("gamepad")
	assert_true(
		_log.has_text("Failed to save encrypted last input device"),
		"last device save must log its error"
	)
	assert_false(FileAccess.file_exists(INVALID_CONFIG_PATH), "no file may be written")


## A missing file remains a first-boot condition even when the key is unavailable.
func test_missing_file_with_empty_key_does_not_create_file_or_reset_notice() -> void:
	Globals.set_test_empty_encryption_key()

	var result: Dictionary = Globals.safe_load_config(TEST_CONFIG_PATH)

	assert_eq(result["err"], ERR_FILE_NOT_FOUND)
	assert_false(result["is_legacy"])
	assert_true(result["config"].get_sections().is_empty())
	assert_false(FileAccess.file_exists(TEST_CONFIG_PATH))
	assert_false(FileAccess.file_exists(BACKUP_PATH))
	assert_false(Globals.consume_settings_reset_notice())


## Each caller must preserve unfamiliar sections while updating existing plaintext.
func test_each_save_path_preserves_unknown_values_with_empty_key(
	caller: String = use_parameters(["gameplay", "input", "device", "audio"])
) -> void:
	Globals.set_test_empty_encryption_key()
	var seed_config := ConfigFile.new()
	seed_config.set_value("extension", "options", {"enabled": true, "levels": [1, 3]})
	seed_config.set_value(Globals.SETTINGS_SECTION, "future_setting", "keep gameplay")
	seed_config.set_value("input", "future_binding", "keep input")
	seed_config.set_value("audio", "future_bus", "keep audio")
	assert_eq(seed_config.save(Settings.CONFIG_PATH), OK, "plaintext seed file must save")

	match caller:
		"gameplay": Globals._save_settings(Settings.CONFIG_PATH)
		"input": Settings.save_input_mappings(Settings.CONFIG_PATH, ["fire"])
		"device": Settings.save_last_input_device("gamepad")
		"audio": AudioManager.save_volumes(Settings.CONFIG_PATH)

	var saved := ConfigFile.new()
	assert_eq(saved.load(Settings.CONFIG_PATH), OK, caller + " must retain plaintext")
	assert_eq(
		saved.get_value("extension", "options"),
		{"enabled": true, "levels": [1, 3]},
		caller + " must keep an unknown section"
	)
	assert_eq(
		saved.get_value(Globals.SETTINGS_SECTION, "future_setting"),
		"keep gameplay",
		caller + " must keep an unknown gameplay key"
	)
	assert_eq(
		saved.get_value("input", "future_binding"),
		"keep input",
		caller + " must keep an unknown input key"
	)
	assert_eq(
		saved.get_value("audio", "future_bus"),
		"keep audio",
		caller + " must keep an unknown audio key"
	)


## A key outage must not replace an earlier recovery copy or consume a pending notice.
func test_empty_key_keeps_existing_backup_and_pending_notice() -> void:
	var original: PackedByteArray = _write_encrypted_file(TEST_CONFIG_PATH)
	var backup := ConfigFile.new()
	backup.set_value("recovery", "value", "earlier save")
	assert_eq(backup.save(BACKUP_PATH), OK)
	var backup_bytes: PackedByteArray = FileAccess.get_file_as_bytes(BACKUP_PATH)
	Globals._settings_reset_notice_pending = true
	Globals.set_test_empty_encryption_key()

	assert_eq(Globals.safe_load_config(TEST_CONFIG_PATH)["err"], ERR_UNCONFIGURED)

	assert_eq(FileAccess.get_file_as_bytes(TEST_CONFIG_PATH), original)
	assert_eq(FileAccess.get_file_as_bytes(BACKUP_PATH), backup_bytes)
	assert_true(Globals.consume_settings_reset_notice(), "an earlier reset still needs reporting")
	assert_false(Globals.consume_settings_reset_notice(), "notice remains one-shot")


## Skipped writes during an outage must not prevent loading and saving when the key returns.
func test_encrypted_file_resumes_updates_after_key_returns() -> void:
	var original: PackedByteArray = _write_encrypted_file(Settings.CONFIG_PATH)
	Globals.set_test_empty_encryption_key()
	_run_all_save_paths()
	assert_eq(FileAccess.get_file_as_bytes(Settings.CONFIG_PATH), original)

	Globals.set_test_empty_encryption_key(false)
	Globals._load_settings(Settings.CONFIG_PATH)
	assert_eq(Globals.settings.difficulty, 1.7)
	Settings.save_last_input_device("gamepad")

	var saved := ConfigFile.new()
	assert_eq(saved.load_encrypted_pass(Settings.CONFIG_PATH, KEY_A), OK)
	assert_eq(saved.get_value(Globals.SETTINGS_SECTION, "difficulty"), 1.7)
	assert_eq(saved.get_value("audio", "master_volume"), 0.3)
	assert_eq(saved.get_value("input", "fire"), ["key:%d" % KEY_K])
	assert_eq(saved.get_value("input", "last_input_device"), "gamepad")
	assert_false(FileAccess.file_exists(CONFIG_BACKUP_PATH))
	assert_false(Globals.consume_settings_reset_notice())


## Plaintext parse failures must still stop all callers from overwriting the source.
func test_malformed_plaintext_is_preserved_with_empty_key() -> void:
	var file := FileAccess.open(Settings.CONFIG_PATH, FileAccess.WRITE)
	file.store_string("[broken section\nvalue=42\n")
	file.close()
	var original: PackedByteArray = FileAccess.get_file_as_bytes(Settings.CONFIG_PATH)
	Globals.set_test_empty_encryption_key()

	var result: Dictionary = Globals.safe_load_config(Settings.CONFIG_PATH)
	assert_eq(result["err"], ERR_PARSE_ERROR)
	assert_false(result["is_legacy"])
	_run_all_save_paths()
	# One explicit read and one read per save path each report the malformed source.
	for _read: int in range(5):
		assert_engine_error("ConfigFile parse error")

	assert_eq(FileAccess.get_file_as_bytes(Settings.CONFIG_PATH), original)
	assert_false(FileAccess.file_exists(CONFIG_BACKUP_PATH))
	assert_false(Globals.consume_settings_reset_notice())
