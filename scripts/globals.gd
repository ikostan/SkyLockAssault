## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## globals.gd
## Global utilities singleton: Provides shared functions like logging.
## Access from any script as Globals.log_message("message").

extends Node

enum LogLevel { DEBUG, INFO, WARNING, ERROR, NONE = 4 }

# Shared constants
## Device-specific remap prompts to avoid layout shift.
# const REMAP_PROMPT_TEXT: String = "Press a key or controller button/axis..."
const REMAP_PROMPT_KEYBOARD: String = "Press a key..."
const REMAP_PROMPT_GAMEPAD: String = "Press a gamepad button/axis..."

@export var current_log_level: LogLevel = LogLevel.INFO  # Default: Show INFO and above
@export var enable_debug_logging: bool = false  # Toggle in Inspector or settings
@export var difficulty: float = 1.0  # Multiplier: 1.0=Normal, <1=Easy, >1=Hard

# In globals.gd (add after @export vars)
var options_instance: CanvasLayer = null
# var hidden_menu: Node = null
var hidden_menus: Array[Node] = []
var options_open: bool = false
## Key Mapping scene for direct loading from warning dialogs.
var key_mapping_scene: PackedScene = preload("res://scenes/key_mapping_menu.tscn")
var previous_scene: String = "res://scenes/main_menu.tscn"  # Default fallback
var options_scene: PackedScene = preload("res://scenes/options_menu.tscn")
var next_scene: String = ""  # Path to the next scene to load via loading screen.
## Last selected input device for UI messages and labels.
## Updated when player toggles Keyboard/Gamepad in Key Mapping.
var current_input_device: String = "keyboard"  # "keyboard" or "gamepad"


func _ready() -> void:
	if Engine.is_editor_hint() or enable_debug_logging:
		current_log_level = LogLevel.DEBUG
	log_message("Log level set to: " + LogLevel.keys()[current_log_level], LogLevel.DEBUG)
	_load_settings()  # Load persisted settings first
	# Load last input device early to fix unbound warning on first load when gamepad is saved preference.
	# Ensures has_unbound_critical_actions_for_current_device() uses correct device from config.
	Settings.load_last_input_device()


## Centralized "ensure initial focus" helper.
## Checks whether keyboard/controller focus is already inside this menu.
## If it isn't, defers grab_focus() on the candidate and logs the action.
## If it is, logs the skip (so you can still see what happened).
##
## :param candidate: The control that should receive focus by default.
## :param allowed_controls: All interactive controls that belong to this menu.
##                          If focus is already on any of them we do nothing.
## :param context: Optional string that appears in the log (e.g. "Pause Menu").
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
## :param menu_to_hide: Usually the UI Panel (not the root Control).
## :type menu_to_hide: Node
## :rtype: void
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

	var km_instance: CanvasLayer = key_mapping_scene.instantiate()
	get_tree().root.add_child(km_instance)


## Loads persisted settings from config if valid types; skips invalid/missing to keep current.
## :param path: Config file path (default: Settings.CONFIG_PATH).
## :type path: String
## :rtype: void
func _load_settings(path: String = Settings.CONFIG_PATH) -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(path)
	if err == OK:
		if config.has_section_key("Settings", "log_level"):
			var loaded_log_level: Variant = config.get_value("Settings", "log_level")
			if (
				loaded_log_level is int
				and loaded_log_level >= LogLevel.DEBUG
				and loaded_log_level <= LogLevel.NONE
			):
				current_log_level = loaded_log_level
				log_message(
					"Loaded saved log level: " + LogLevel.keys()[current_log_level], LogLevel.DEBUG
				)
			else:
				log_message(
					"Invalid type or value for log_level: " + str(typeof(loaded_log_level)),
					LogLevel.WARNING
				)

		if config.has_section_key("Settings", "difficulty"):
			var loaded_difficulty: Variant = config.get_value("Settings", "difficulty")
			if (loaded_difficulty is float) or (loaded_difficulty is int):
				difficulty = loaded_difficulty
				# Validate and clamp difficulty to slider range (0.5-2.0)
				if difficulty < 0.5 or difficulty > 2.0:
					log_message(
						(
							"Invalid difficulty loaded ("
							+ str(difficulty)
							+ ") - clamping to valid range."
						),
						LogLevel.WARNING
					)
					difficulty = clamp(difficulty, 0.5, 2.0)
				log_message("Loaded saved difficulty: " + str(difficulty), LogLevel.DEBUG)
			else:
				log_message(
					"Invalid type for difficulty: " + str(typeof(loaded_difficulty)),
					LogLevel.WARNING
				)
	elif err == ERR_FILE_NOT_FOUND:
		log_message("No settings config found, using defaults.", LogLevel.DEBUG)
	else:
		log_message("Failed to load settings config: " + str(err), LogLevel.ERROR)


# New: Add _save_settings to globals.gd (move from options_menu.gd if needed)
func _save_settings(path: String = Settings.CONFIG_PATH) -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(path)  # Load existing to preserve other sections
	if err != OK and err != ERR_FILE_NOT_FOUND:
		log_message(
			"Failed to load settings from " + path + " for save: " + str(err), LogLevel.ERROR
		)
		return

	config.set_value("Settings", "log_level", current_log_level)
	config.set_value("Settings", "difficulty", difficulty)
	err = config.save(path)
	if err != OK:
		log_message("Failed to save settings: " + str(err), LogLevel.ERROR)
	else:
		log_message("Settings saved.", LogLevel.DEBUG)


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

	if options_scene:
		## Set flag before adding child to block pause immediately.
		options_open = true  # Set early as before

		options_instance = options_scene.instantiate()
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
func log_message(message: String, level: LogLevel = LogLevel.INFO) -> void:
	if level < current_log_level:
		return  # Skip if below threshold
	var level_str: String = LogLevel.keys()[level]  # Converts enum to string: "INFO", etc.
	var timestamp: String = Time.get_datetime_string_from_system()
	print("[%s] [%s] %s" % [timestamp, level_str, message])


# Override to handle engine notifications, like window close requests.
# @param what: The notification ID (int constant from Godot).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Cleanup logic here—runs just before quit.
		log_message("Window close requested—performing cleanup...", LogLevel.DEBUG)

		# Example: Save game state if you have a save system.
		# Replace with your actual save function, e.g., from a save_manager.gd.
		# save_game_state()  # Uncomment and implement as needed.

		# After cleanup, let the quit proceed (optional on desktop; auto on web).
		get_tree().quit()


func load_scene_with_loading(target_path: String) -> void:
	# Queues a scene change via the loading screen.
	# Sets next_scene and transitions to loading_screen.tscn.
	# Handles empty/invalid paths gracefully.

	if target_path == "":
		log_message("Cannot load empty scene path.", LogLevel.ERROR)
		return

	next_scene = target_path
	get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")


# Static helpers for version (add after _ready())
static func get_game_version() -> String:
	return ProjectSettings.get_setting("application/config/version", "n/a") as String


# For tests only—avoids direct writes in prod
static func set_game_version_for_tests(value: String) -> void:
	ProjectSettings.set_setting("application/config/version", value)
