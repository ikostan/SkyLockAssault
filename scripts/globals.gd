## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## globals.gd
## Global utilities singleton: Provides shared functions like logging.
## Access from any script as Globals.log_message("message").

extends Node

enum LogLevel { DEBUG, INFO, WARNING, ERROR, NONE = 4 }

## Path to the navigation sound file
const UI_NAV_SOUND_PATH: String = "res://files/sounds/sfx/ui_navigation.wav"

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

## Preloaded stream to prevent disk I/O lag during fast menu navigation.
var _ui_nav_stream: AudioStream = preload(UI_NAV_SOUND_PATH)

# NEW: The persistent audio player to prevent node churn
var _nav_sfx_player: AudioStreamPlayer

# List of actions that should trigger the navigation sound
var _nav_actions: Array[String] = [
	"ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev"
]


func _ready() -> void:
	# Keep processing inputs even when the game is paused!
	process_mode = Node.PROCESS_MODE_ALWAYS

	# --- NEW: Initialize the permanent SFX player ---
	_nav_sfx_player = AudioStreamPlayer.new()
	_nav_sfx_player.stream = _ui_nav_stream
	_nav_sfx_player.bus = AudioConstants.BUS_SFX_MENU
	add_child(_nav_sfx_player)

	# Load the resource here instead of preloading at the top
	settings = load("res://config_resources/default_settings.tres") as GameSettingsResource
	if settings == null:
		# Use push_error since Globals logging might not be ready
		push_error("CRITICAL: 'GameSettingsResource' failed to load at path.")
		# Fallback to in-memory defaults so Globals remains operational
		settings = GameSettingsResource.new()
		settings.current_log_level = LogLevel.WARNING

	if Engine.is_editor_hint() or settings.enable_debug_logging:
		settings.current_log_level = LogLevel.DEBUG
	log_message("Log level set to: " + LogLevel.keys()[settings.current_log_level], LogLevel.DEBUG)
	_load_settings()  # Load persisted settings first

	# Connect to the resource signal to centralize side effects
	if settings:
		settings.setting_changed.connect(_on_setting_changed)


## Reactive handler for the Observer Pattern
func _on_setting_changed(setting_name: String, new_value: Variant) -> void:
	# Skip persistence and logging if we are in a bulk-loading state
	if _is_loading_settings:
		return

	# FIX: Ensure we are comparing String to String or using correct types
	var log_msg: String = "Setting '%s' updated to: %s" % [setting_name, str(new_value)]

	# Automatically log the change
	# OLD: log_message(log_msg, LogLevel.DEBUG)
	# NEW: Prevent log spam by filtering out high-frequency runtime changes like fuel ticks
	if setting_name != "current_fuel":
		log_message(log_msg, LogLevel.DEBUG)

	# Automatically persist to disk
	# OLD: _save_settings()
	# NEW: Prevent disk I/O lag by stopping current_fuel from
	# triggering a file save on every frame/timer tick
	if setting_name != "current_fuel":
		_save_settings()


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


## Loads persisted settings from config if valid types;
## skips invalid/missing to keep current.
## :param path: Config file path (default: Settings.CONFIG_PATH).
## :type path: String
## :rtype: void
func _load_settings(path: String = Settings.CONFIG_PATH) -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(path)
	if err == OK:
		# Enable the guard before starting bulk updates
		_is_loading_settings = true

		if config.has_section_key("Settings", "log_level"):
			var loaded_log_level: Variant = config.get_value("Settings", "log_level")
			if (
				loaded_log_level is int
				and loaded_log_level >= LogLevel.DEBUG
				and loaded_log_level <= LogLevel.NONE
			):
				settings.current_log_level = loaded_log_level
				log_message(
					"Loaded saved log level: " + LogLevel.keys()[settings.current_log_level],
					LogLevel.DEBUG
				)
			else:
				log_message(
					"Invalid type or value for log_level: " + str(typeof(loaded_log_level)),
					LogLevel.WARNING
				)

		if config.has_section_key("Settings", "difficulty"):
			var loaded_difficulty: Variant = config.get_value("Settings", "difficulty")
			if (loaded_difficulty is float) or (loaded_difficulty is int):
				# Validate and clamp difficulty to slider range (0.5-2.0)
				settings.difficulty = loaded_difficulty
				log_message("Loaded saved difficulty: " + str(settings.difficulty), LogLevel.DEBUG)
			else:
				log_message(
					"Invalid type for difficulty: " + str(typeof(loaded_difficulty)),
					LogLevel.WARNING
				)

		# NEW: Load the debug logging flag
		if config.has_section_key("Settings", "enable_debug_logging"):
			var loaded_debug: Variant = config.get_value("Settings", "enable_debug_logging")
			if loaded_debug is bool:
				settings.enable_debug_logging = loaded_debug
				log_message(
					"Loaded saved debug logging: " + str(settings.enable_debug_logging),
					LogLevel.DEBUG
				)

		# NEW: Load the fuel related settings
		if config.has_section_key("Settings", "max_fuel"):
			var loaded_max: Variant = config.get_value("Settings", "max_fuel")
			if loaded_max is float or loaded_max is int:
				settings.max_fuel = float(loaded_max)
			else:
				log_message(
					"Invalid type for max_fuel: " + str(typeof(loaded_max)), LogLevel.WARNING
				)

		# Disable the guard and log a single summary instead
		_is_loading_settings = false
		log_message("All settings loaded and synchronized.", LogLevel.DEBUG)

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

	config.set_value("Settings", "log_level", settings.current_log_level)
	config.set_value("Settings", "difficulty", settings.difficulty)
	# NEW: Persist the debug logging flag
	config.set_value("Settings", "enable_debug_logging", settings.enable_debug_logging)
	# NEW: Persist the fuel settings
	config.set_value("Settings", "max_fuel", settings.max_fuel)

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
func log_message(message: String, level: LogLevel = LogLevel.INFO) -> void:
	# FIX: Guard the log level check. If settings is null, print everything.
	if is_instance_valid(settings) and level < settings.current_log_level:
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
		# NEW: Explicitly save all settings right before the game quits
		_save_settings()

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


## Use _input instead of _unhandled_input to catch events BEFORE the UI consumes them.
func _input(_event: InputEvent) -> void:
	# The Ultimate Menu Check: Does a UI element currently have keyboard/gamepad focus?
	var ui_has_focus: bool = is_instance_valid(get_viewport().gui_get_focus_owner())

	# Gate 1: Only play UI sounds if a UI element is focused OR we are in a known menu state
	var is_menu_context: bool = (
		get_tree().paused or options_open or not hidden_menus.is_empty() or ui_has_focus
	)

	if not is_menu_context:
		return

	for action: String in _nav_actions:
		# Gate 2: Prevent rapid-fire sound spam when holding down keys or analog sticks
		# We use the global Input singleton here because it perfectly handles
		# analog joystick deadzone debouncing, which event.is_echo() misses.
		if Input.is_action_just_pressed(action):
			_play_ui_navigation_sfx()
			return  # Exit once sound is triggered to avoid double-plays


## Internal helper to play the navigation sound through the dedicated Menu SFX bus.
func _play_ui_navigation_sfx() -> void:
	if not is_instance_valid(_nav_sfx_player):
		return

	# If the sound is already playing (e.g., from rapid button presses),
	# restart it from the beginning to feel responsive.
	_nav_sfx_player.play()
