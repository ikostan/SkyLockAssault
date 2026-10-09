## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## globals.gd
## Global utilities singleton: Provides shared functions like logging.
## Access from any script as Globals.log_message("message").

@tool
extends Node

enum LogLevel { DEBUG, INFO, WARNING, ERROR, NONE = 4 }

## ConfigFile section owned by Globals. The audio and input managers write their own
## sections to the same settings.cfg, so Globals must never touch anything outside this one.
const SETTINGS_SECTION: String = "Settings"

# --- ISSUE #470: Table-driven settings serialization ---
## Persistence schema for GameSettingsResource properties.
##
## Each entry maps a resource property name to:
##   "key"   - On-disk key inside SETTINGS_SECTION. NEVER rename an existing key:
##             player saves in the wild depend on it.
##   "types" - Accepted Variant.Type values for the raw value read from disk.
##             Anything else is rejected and the current default is kept.
##   "cast"  - (Optional) Variant.Type the value is converted to after the type check,
##             e.g. an int written by an older build becoming a float.
##   "min"   - (Optional) Inclusive lower bound. Out-of-range values are rejected, not clamped.
##   "max"   - (Optional) Inclusive upper bound. Out-of-range values are rejected, not clamped.
##
## Adding a persisted setting is a one-entry change here. Dictionary insertion order is
## preserved, so it also defines load and save order.
## Declared as a mutable static var (snake_case per gdlint's class-variable-name rule) so
## tests can extend or replace the schema; production code must treat it as read-only.
static var persisted_schema: Dictionary = {
	"current_log_level":
	{
		"key": "log_level",
		"types": [TYPE_INT],
		"min": LogLevel.DEBUG,
		"max": LogLevel.NONE,
	},
	"difficulty":
	{
		"key": "difficulty",
		"types": [TYPE_FLOAT, TYPE_INT],
		"cast": TYPE_FLOAT,
	},
	"enable_debug_logging":
	{
		"key": "enable_debug_logging",
		"types": [TYPE_BOOL],
	},
	"max_fuel":
	{
		"key": "max_fuel",
		"types": [TYPE_FLOAT, TYPE_INT],
		"cast": TYPE_FLOAT,
	},
	"show_fps":
	{
		"key": "show_fps",
		"types": [TYPE_BOOL],
	},
}

# --- TASK #529: Encryption Key Management ---
## Centralized key for securing local configuration files.
## This ensures consistent encryption/decryption across different game systems.
## Define the variable by pulling from ProjectSettings.
## If the setting doesn't exist, it falls back to a non-secure string.
var save_encryption_pass: String = _get_encryption_key()

# Add the resource reference here
var settings: GameSettingsResource
# In globals.gd (add after @export vars)
var options_instance: CanvasLayer = null
# var hidden_menu: Node = null
var hidden_menus: Array[Node] = []
var options_open: bool = false
## Key Mapping scene for direct loading from warning dialogs.
# var key_mapping_scene: PackedScene = preload("res://scenes/key_mapping_menu.tscn")
var previous_scene: String = "res://scenes/main_menu.tscn"  # Default fallback
# var options_scene: PackedScene = preload("res://scenes/options_menu.tscn")
var next_scene: String = ""  # Path to the next scene to load via loading screen.
## Last selected input device for UI messages and labels.
## Updated when player toggles Keyboard/Gamepad in Key Mapping.
var current_input_device: String = "keyboard"  # "keyboard" or "gamepad"
var _is_loading_settings: bool = false  # Guard flag


func _ready() -> void:
	# Keep processing inputs even when the game is paused!
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Prevent editor execution from dirtying local config files and state
	if Engine.is_editor_hint():
		return

	# Load the resource here instead of preloading at the top
	settings = load("res://config_resources/default_settings.tres") as GameSettingsResource
	if settings == null:
		# Use push_error since Globals logging might not be ready
		push_error("CRITICAL: 'GameSettingsResource' failed to load at path.")
		# Fallback to in-memory defaults so Globals remains operational
		settings = GameSettingsResource.new()
		settings.current_log_level = LogLevel.WARNING

		# FIX: Manually inject the scenes into the fallback instance to avoid null UI errors
		settings.key_mapping_scene = load("res://scenes/key_mapping_menu.tscn")
		settings.options_scene = load("res://scenes/options_menu.tscn")

	if Engine.is_editor_hint() or settings.enable_debug_logging:
		settings.current_log_level = LogLevel.DEBUG
	log_message("Log level set to: " + LogLevel.keys()[settings.current_log_level], LogLevel.DEBUG)
	_load_settings()  # Load persisted settings first

	# Connect to the resource signal to centralize side effects
	if is_instance_valid(settings):
		settings.setting_changed.connect(_on_setting_changed)

	# Signal Playwright that the engine is ready and initialize current log level state
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.godotInitialized = true")
		if is_instance_valid(settings):
			JavaScriptBridge.eval(
				"window.currentLogLevel = " + JSON.stringify(settings.current_log_level)
			)


## Reactive handler for the Observer Pattern connected to GameSettingsResource signals.
##
## Triggers centralized side effects whenever a setting property is mutated.
## Handles conditional console logging, encrypted disk persistence, and real-time state
## synchronization with the browser window for Web builds and Playwright E2E tests.
##
## :param setting_name: The string identifier of the modified setting property.
## :type setting_name: String
## :param new_value: The updated property value.
## :type new_value: Variant
## :rtype: void
func _on_setting_changed(setting_name: String, new_value: Variant) -> void:
	# Guard: Skip persistence, logging, and JS bridge calls during bulk settings loading
	# to prevent disk I/O lag, log spam, and redundant bridge updates during initialization.
	if _is_loading_settings:
		return

	var log_msg: String = "Setting '%s' updated to: %s" % [setting_name, str(new_value)]

	# Web / E2E state synchronization: Expose current log level to window.currentLogLevel
	if setting_name == "current_log_level":
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.currentLogLevel = " + JSON.stringify(new_value))

	# Log standard setting mutations at DEBUG level
	log_message(log_msg, LogLevel.DEBUG)

	# Automatically persist updated setting values to encrypted disk storage
	_save_settings()


## Ensures keyboard or controller focus is set correctly within this menu.
##
## Checks whether the focus is already inside this menu's allowed controls. If not, defers
## grab_focus() on the candidate and logs the action; otherwise, logs the skip.
##
## [param candidate]: The candidate parameter.
## [param allowed_controls]: The allowed_controls parameter.
## [param context]: The context parameter.
func ensure_initial_focus(
	candidate: Control, allowed_controls: Array[Control] = [], context: String = ""
) -> void:
	if not is_instance_valid(candidate):
		log_message(
			"ensure_initial_focus: Candidate is null or freed - skipping.", LogLevel.WARNING
		)
		return

	var focus_owner: Control = get_tree().root.get_viewport().gui_get_focus_owner()

	var already_has_focus := false
	if is_instance_valid(focus_owner):
		for ctrl: Control in allowed_controls:
			if focus_owner == ctrl:
				already_has_focus = true
				break

	var ctx: String = " (" + context + ")" if not context.is_empty() else ""

	if not already_has_focus:
		candidate.call_deferred("grab_focus")
		log_message("Grabbed initial focus on " + candidate.name + ctx, LogLevel.DEBUG)
	else:
		log_message(
			"Focus already on a menu control" + ctx + " — skipping initial grab.", LogLevel.DEBUG
		)


## Loads Key Mapping menu directly while keeping background video visible.
##
## Loads the Key Mapping menu, hides the specified menu node, and keeps the background
## video visible and processing when found at one of the expected relative paths.
##
## [param menu_to_hide]: The menu_to_hide parameter.
func load_key_mapping(menu_to_hide: Node) -> void:
	if is_instance_valid(menu_to_hide):
		hidden_menus.push_back(menu_to_hide)
		menu_to_hide.visible = false

		# Robust video lookup (works for both Panel and root Control)
		var video: VideoStreamPlayer = menu_to_hide.get_node_or_null("../VideoStreamPlayer")
		if not is_instance_valid(video):
			video = menu_to_hide.get_node_or_null("VideoStreamPlayer")
		if is_instance_valid(video):
			video.visible = true
			video.process_mode = Node.PROCESS_MODE_ALWAYS  # keep playing
	# FIX: We must call .instantiate() on the PackedScene inside settings
	if settings.key_mapping_scene == null:
		log_message("Error: Key mapping scene not configured.", LogLevel.ERROR)
		if not hidden_menus.is_empty():
			var prev_menu: Node = hidden_menus.pop_back()
			if is_instance_valid(prev_menu):
				prev_menu.visible = true
		return
	var km_instance: CanvasLayer = settings.key_mapping_scene.instantiate()
	get_tree().root.add_child(km_instance)


## Loads persisted settings with backward compatibility for plaintext files.
##
## Iterates persisted_schema: for each entry, reads the on-disk key, checks the raw
## value's type, applies the optional cast, and rejects out-of-range values. Missing keys
## and rejected values leave the current default untouched.
##
## :param path: Config file path (default: Settings.CONFIG_PATH).
## :type path: String
## :rtype: void
func _load_settings(path: String = Settings.CONFIG_PATH) -> void:
	var load_data: Dictionary = safe_load_config(path)
	var config: ConfigFile = load_data["config"]
	var err: int = load_data["err"]
	var needs_migration: bool = load_data["is_legacy"]

	if needs_migration:
		log_message("Legacy plaintext settings found. Migration required.", LogLevel.INFO)

	if err == OK:
		# Guard covers the whole loop: setters emit setting_changed, and the observer must
		# not persist, log, or bridge to JS while we are bulk-applying values.
		_is_loading_settings = true

		for prop: String in persisted_schema:
			var spec: Dictionary = persisted_schema[prop]
			var disk_key: String = spec["key"]

			if not config.has_section_key(SETTINGS_SECTION, disk_key):
				continue  # Missing key: keep current default.

			if not (prop in settings):
				log_message(
					"Schema error: '%s' is not a GameSettingsResource property." % prop,
					LogLevel.ERROR
				)
				continue

			var value: Variant = config.get_value(SETTINGS_SECTION, disk_key)

			if not (typeof(value) in spec["types"]):
				log_message(
					(
						"Ignoring persisted '%s': unexpected type %s."
						% [disk_key, type_string(typeof(value))]
					),
					LogLevel.WARNING
				)
				continue

			if spec.has("cast"):
				value = type_convert(value, spec["cast"])

			var below_min: bool = spec.has("min") and value < spec["min"]
			var above_max: bool = spec.has("max") and value > spec["max"]
			if below_min or above_max:
				log_message(
					"Ignoring persisted '%s': value %s out of range." % [disk_key, str(value)],
					LogLevel.WARNING
				)
				continue

			settings.set(prop, value)

		_is_loading_settings = false
		log_message("Settings synchronization complete.", LogLevel.DEBUG)

		if needs_migration:
			log_message("Upgrading settings file to encrypted format...", LogLevel.INFO)
			_save_settings(path)

	elif err == ERR_FILE_NOT_FOUND:
		log_message("No configuration file found; using defaults.", LogLevel.DEBUG)
	else:
		log_message("Failed to load settings (Error %d)." % err, LogLevel.ERROR)


## Persists current settings to an encrypted config file.
##
## Re-reads the existing file first so sections owned by other managers (audio, input)
## survive, then writes every persisted_schema property into SETTINGS_SECTION.
## Does not touch _is_loading_settings.
##
## :param path: Config file path (default: Settings.CONFIG_PATH).
## :type path: String
## :rtype: void
func _save_settings(path: String = Settings.CONFIG_PATH) -> void:
	var load_data: Dictionary = safe_load_config(path)
	var config: ConfigFile = load_data["config"]
	var err: int = load_data["err"]

	if err != OK and err != ERR_FILE_NOT_FOUND:
		log_message(
			(
				"CRITICAL: Could not load settings from "
				+ path
				+ ", aborting save to prevent data loss."
			),
			LogLevel.ERROR
		)
		return

	for prop: String in persisted_schema:
		# Guard: settings.get() on a missing property returns null, and
		# ConfigFile.set_value(..., null) ERASES the key instead of writing it.
		if not (prop in settings):
			log_message(
				"Schema error: '%s' is not a GameSettingsResource property." % prop, LogLevel.ERROR
			)
			continue
		config.set_value(SETTINGS_SECTION, persisted_schema[prop]["key"], settings.get(prop))

	# FIX: Re-added the branch to properly handle the plaintext failsafe
	var key: String = ensure_encryption_key()

	if key.is_empty():
		err = config.save(path)
		if err != OK:
			log_message(
				"🚨 CRITICAL FAILURE: Failed to save plaintext settings (Error: " + str(err) + ")",
				LogLevel.ERROR
			)
		else:
			log_message("⚠️ FAILSAFE ACTIVE: Settings saved in PLAINTEXT.", LogLevel.WARNING)
	else:
		err = config.save_encrypted_pass(path, key)
		if err != OK:
			log_message(
				(
					"🚨 CRITICAL ENCRYPTION FAILURE: Failed to save encrypted settings (Error: "
					+ str(err)
					+ ")"
				),
				LogLevel.ERROR
			)
		else:
			log_message("🔒 Encrypted settings persisted successfully.", LogLevel.DEBUG)


func _on_options_exited_unexpectedly() -> void:
	## Handles unexpected tree exit of options_instance.
	##
	## Resets flag if stuck open; cleans ref.
	##
	## :rtype: void
	if options_open:  # Guard: Only log if it was still "open" (unexpected exit)
		log_message("Options instance exited unexpectedly—resetting flag.", LogLevel.WARNING)

	if not hidden_menus.is_empty():
		var prev_menu: Node = hidden_menus.pop_back()
		if is_instance_valid(prev_menu):
			prev_menu.visible = true

	options_open = false
	options_instance = null


## Loads options menu and hides the caller menu if valid.
##
## Guards against re-entrancy by checking existing instance.
##
## [param menu_to_hide]: The menu_to_hide parameter.
## Returns No return value.
func load_options(menu_to_hide: Node) -> void:
	## Loads options menu and hides the caller menu (if valid).
	##
	## Guards against re-entrancy by checking existing instance.
	##
	## :param menu_to_hide: The menu node to hide (guarded against null/invalid).
	## :type menu_to_hide: Node
	## :rtype: void
	if is_instance_valid(options_instance):
		log_message("Options menu already open—ignoring load request.", LogLevel.WARNING)
		return

	if menu_to_hide == null:
		log_message("load_options: Called with null menu_to_hide—skipping hide.", LogLevel.WARNING)
	elif not is_instance_valid(menu_to_hide):
		log_message(
			"load_options: Invalid/freed menu_to_hide (" + str(menu_to_hide) + ")—skipping hide.",
			LogLevel.WARNING
		)
	else:
		hidden_menus.push_back(menu_to_hide)
		menu_to_hide.visible = false
		log_message("Hiding menu: " + menu_to_hide.name, LogLevel.DEBUG)

	if settings.options_scene:
		## Set flag before adding child to block pause immediately.
		options_open = true  # Set early as before
		# FIX: Assign the instance to the global variable
		options_instance = settings.options_scene.instantiate()
		if options_instance == null:
			log_message("Failed to instantiate options scene—resetting flag.", LogLevel.ERROR)
			options_open = false  # Reset to avoid stuck state
			if not hidden_menus.is_empty():
				var prev_menu: Node = hidden_menus.pop_back()
				if is_instance_valid(prev_menu):
					prev_menu.visible = true  # Restore if we bailed
			return

		# Optional: Connect to tree_exited for unexpected free (extra safety)
		options_instance.tree_exited.connect(_on_options_exited_unexpectedly)
		get_tree().root.add_child(options_instance)
	else:
		log_message("Error: Options scene not found!", LogLevel.ERROR)
		if not hidden_menus.is_empty():
			var prev_menu: Node = hidden_menus.pop_back()
			if is_instance_valid(prev_menu):
				prev_menu.visible = true
				log_message("Restored visibility of menu: " + prev_menu.name, LogLevel.WARNING)


# Custom logging function with timestamp and level filtering.
# @param message: The string message to log.
# @param level: The log level (default INFO).
## Prints a formatted log message if it meets the configured log level threshold.
##
## Converts the given log level enum to a string, prepends a system timestamp, and prints the
## message if the level is greater than or equal to the current configured threshold in
## settings.
##
## [param message]: The message parameter.
## [param level]: The level parameter.
## Returns No return value.
func log_message(message: String, level: LogLevel = LogLevel.INFO) -> void:
	# FIX: Guard the log level check.
	# If settings is null, print everything.
	if is_instance_valid(settings) and level < settings.current_log_level:
		return  # Skip if below threshold

	var level_str: String = LogLevel.keys()[level]  # Converts enum to string: "INFO", etc.
	var timestamp: String = Time.get_datetime_string_from_system()
	print("[%s] [%s] %s" % [timestamp, level_str, message])


# Override to handle engine notifications, like window close requests.
# @param what: The notification ID (int constant from Godot).
func _notification(what: int) -> void:
	# Prevent the editor's close routine from executing game quit logic
	if Engine.is_editor_hint():
		return

	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Cleanup logic here—runs just before quit.
		log_message("Window close requested—performing cleanup...", LogLevel.DEBUG)

		# Example: Save game state if you have a save system.
		# Replace with your actual save function, e.g., from a save_manager.gd.
		# NEW: Explicitly save all settings right before the game quits
		_save_settings()

		# After cleanup, let the quit proceed (optional on desktop; auto on web).
		get_tree().quit()


## Queues a scene change via the loading screen.
##
## Sets the next scene path and transitions to the loading screen scene. Handles empty paths
## gracefully.
##
## [param target_path]: The target_path parameter.
func load_scene_with_loading(target_path: String) -> void:
	# Queues a scene change via the loading screen.
	# Sets next_scene and transitions to loading_screen.tscn.
	# Handles empty paths gracefully.
	# Handles empty/invalid paths gracefully.

	if target_path == "":
		log_message("Cannot load empty scene path.", LogLevel.ERROR)
		return

	next_scene = target_path
	get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")


# Static helpers for version (add after _ready())
## Returns the game version from project settings.
##
## Retrieves the version string from the application configuration settings, defaulting to
## "n/a" if not set.
## Returns The application configuration version string, or "n/a" if not set.
static func get_game_version() -> String:
	return ProjectSettings.get_setting("application/config/version", "n/a") as String


# For tests only—avoids direct writes in prod
## Sets the game version project setting for automated testing.
##
## Updates the application configuration version setting in ProjectSettings using the
## provided string value.
##
## [param value]: The value parameter.
static func set_game_version_for_tests(value: String) -> void:
	ProjectSettings.set_setting("application/config/version", value)


## Ensures the encryption key is initialized and returns it.
## Centralizes the safety check so other scripts don't have to repeat it.
func ensure_encryption_key() -> String:
	if save_encryption_pass.is_empty():
		save_encryption_pass = _get_encryption_key()
		if save_encryption_pass.is_empty():
			log_message(
				"🚨 KEY GENERATION FAILED: Generated encryption key is empty!", LogLevel.ERROR
			)
		else:
			log_message(
				"🔑 Encryption key successfully generated and cached in memory.", LogLevel.DEBUG
			)
	return save_encryption_pass


## Generates a unique, deterministic encryption key for local save files.
##
## This function combines the device's hardware ID (`OS.get_unique_id()`) with a
## project-specific salt retrieved from `ProjectSettings`, returning a SHA-256 hash.
##
## Security Guard:
## In production builds (when neither 'editor' nor 'debug' features are present),
## this function strictly validates that a secure salt was successfully injected
## during the CI/CD deployment.
## If the salt is missing or matches the weak development
## fallback, it forces an immediate engine crash.
## This prevents the game from silently
## encrypting data with a weak/empty key.
##
## :rtype: String (The SHA-256 hashed key)
## Generates a unique, deterministic encryption key for local save files.
func _get_encryption_key() -> String:
	# Safe placeholder.
	# This is an open source repo, so the REAL salt
	# is injected by GitHub Actions / CI pipeline during the build process.
	var salt: String = "CI_INJECT_SALT_HERE"

	# 1. FAILSAFE: If the salt is literally empty, always abort
	if salt.is_empty():
		log_message("🚨 ENCRYPTION ABORTED: Salt is empty.", LogLevel.WARNING)
		return ""

	# 2. SECURITY GUARD: Prevent silent weak-key fallback in production.
	# We use a custom "ci" feature flag instead of a blanket "web" check
	# to keep the production security guard fully active on itch.io.
	var is_automated_test: bool = OS.has_feature("ci")
	log_message(
		"⚙️ ENV CHECK (is_automated_test): " + str(is_automated_test), Globals.LogLevel.DEBUG
	)

	if not OS.has_feature("editor") and not OS.has_feature("debug") and not is_automated_test:
		# CI CONTRACT: The injection pipeline strictly verifies this exact literal string pattern.
		# Do not alter or split this line without updating the build scripts.
		if salt == "CI_INJECT_SALT_HERE":
			var error_msg: String = "CRITICAL SECURITY ERROR: Missing production salt."
			push_error(error_msg)
			OS.crash(error_msg)

	# FIX: Removed JavaScriptBridge.eval() from here.
	# Calling JS from a
	# class-level variable initialization silently crashes the WebAssembly module!
	var device_id: String = "web_fallback"
	if not OS.has_feature("web"):
		device_id = OS.get_unique_id()

	# Logging the key length immediately after generation gives you the cleanest
	# signal whether the real production salt was used.
	var final_key: String = (device_id + salt).sha256_text()
	# NEW: Log key length for easier debugging of injection issues
	log_message("Generated key length: %d" % final_key.length(), LogLevel.DEBUG)

	return final_key


## Determine if a config file is encrypted.
##
## Checks whether the specified file exists and whether its magic number matches the Godot
## encrypted file magic number 0x43454447 ("GDEC").
##
## [param path]: The path parameter.
## Returns [code]true[/code] if the file is encrypted, [code]false[/code] otherwise.
func is_file_encrypted(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not f:
		return false
	if f.get_length() < 4:
		f.close()
		return false
	var magic: int = f.get_32()
	f.close()
	# Godot Encrypted File Magic Number: 0x43454447 ("GDEC")
	return magic == 0x43454447


## Safely loads a config file, handling encrypted and legacy plaintext formats.
##
## Loads a configuration file from the specified path, automatically handling encrypted keys
## and plaintext fallbacks.
##
## [param path]: The path parameter.
## Returns A Dictionary containing the keys config as ConfigFile, err as int, and is_legacy as
## bool.
func safe_load_config(path: String) -> Dictionary:
	var key: String = ensure_encryption_key()

	var config: ConfigFile = ConfigFile.new()
	var err: int = OK
	var is_legacy: bool = false

	if not FileAccess.file_exists(path):
		err = ERR_FILE_NOT_FOUND
		log_message(
			"Config file not found at: " + path + " (Normal for first-time boot)", LogLevel.DEBUG
		)
	elif is_file_encrypted(path):
		err = config.load_encrypted_pass(path, key)
		if err != OK:
			log_message(
				"🚨 DECRYPTION FAILED for file: " + path + " (Error code: " + str(err) + ").",
				LogLevel.ERROR
			)

			# --- AUTO-RECOVERY FIX: TIGHTENED CONDITIONS ---
			# Only delete if the file is explicitly corrupted or has invalid data (bad password/hash).
			if err == ERR_FILE_CORRUPT or err == ERR_INVALID_DATA:
				log_message(
					"🗑️ Attempting to auto-delete corrupted/orphaned save file to allow clean recovery.",
					LogLevel.INFO
				)

				var remove_err: int = DirAccess.remove_absolute(path)
				if remove_err == OK:
					log_message("✅ Corrupted file successfully deleted.", LogLevel.DEBUG)
					# Treat as a first-time boot so the game generates fresh defaults
					err = ERR_FILE_NOT_FOUND
				else:
					log_message(
						(
							"❌ FAILED to delete corrupted file at "
							+ path
							+ " (Error: "
							+ str(remove_err)
							+ "). Game may be unable to save!"
						),
						LogLevel.ERROR
					)
			else:
				log_message(
					(
						"⚠️ File is unreadable but NOT explicitly corrupted. "
						+ "Skipping auto-deletion to prevent accidental data loss."
					),
					LogLevel.WARNING
				)
		else:
			log_message("🔓 Successfully decrypted file: " + path, LogLevel.DEBUG)
	else:
		err = config.load(path)
		if err == OK:
			is_legacy = true
			log_message(
				"⚠️ Loaded unencrypted plaintext file: " + path + ". Migration needed.",
				LogLevel.WARNING
			)
		else:
			log_message(
				"Failed to load plaintext file: " + path + " (Error: " + str(err) + ")",
				LogLevel.ERROR
			)

	return {"config": config, "err": err, "is_legacy": is_legacy}


## Overrides the encryption key with a deterministic value for unit tests.
##
## This decouples test artifacts from specific hardware IDs so failures are reproducible.
##
## [param override_key]: The override_key parameter.
func set_test_encryption_key(override_key: String = "test_deterministic_key_123") -> void:
	save_encryption_pass = override_key
	log_message("Encryption key overridden for testing.", LogLevel.DEBUG)
