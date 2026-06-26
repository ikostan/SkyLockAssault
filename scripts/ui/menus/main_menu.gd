## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## Main Menu Script
##
## Handles initialization, button connections, and platform-specific behaviors
## for the main menu scene.
##
## This script manages the main menu UI, including button presses,
## quit confirmation, and scene transitions.
##
## It includes platform-specific handling for web exports.
##
## :vartype quit_dialog: ConfirmationDialog
## :vartype game_scene: PackedScene
## :vartype options_menu: PackedScene
## :vartype ui_panel: Panel
## :vartype ui_container: VBoxContainer
## :vartype start_button: Button
## :vartype options_button: Button
## :vartype quit_button: Button
## :vartype background_music: AudioStreamPlayer2D

extends Control

# Default relative path; override in Inspector if needed
const QUIT_DIALOG_DEFAULT_PATH: String = "VideoStreamPlayer/Panel/VBoxContainer/QuitDialog"
@export var quit_dialog_path: NodePath = NodePath(QUIT_DIALOG_DEFAULT_PATH)
# Add a safety boundary constraint to the inspector variable at the top of main_menu.gd
# to completely eliminate input range bugs:
@export_range(0.0, 5.0, 0.1) var intro_delay: float = 3.0
@export_range(0.0, 3.0, 0.1) var fade_duration: float = 1.0
@export_range(0.0, 2.0, 0.05) var audio_flush_delay: float = 0.2

# Reference to the quit dialog node, assigned in setup_quit_dialog or _ready()
var quit_dialog: ConfirmationDialog
# The unbound controls warning dialog
var unbound_dialog: ConfirmationDialog
var options_menu: PackedScene = preload("res://scenes/options_menu.tscn")
var last_focused_button: Button = null  # Tracks which button opened the dialog
# FIX: Safety flag to shield test runners from process termination loops
var bypass_quit_for_testing: bool = false
var _start_pressed_cb: JavaScriptObject
var _options_pressed_cb: JavaScriptObject
var _quit_pressed_cb: JavaScriptObject

@onready var ui_panel: Panel = $VideoStreamPlayer/Panel
@onready var ui_container: VBoxContainer = $VideoStreamPlayer/Panel/VBoxContainer
@onready var start_button: Button = $VideoStreamPlayer/Panel/VBoxContainer/StartButton
@onready var options_button: Button = $VideoStreamPlayer/Panel/VBoxContainer/OptionsButton
@onready var quit_button: Button = $VideoStreamPlayer/Panel/VBoxContainer/QuitButton
@onready var background_music: AudioStreamPlayer2D = $AudioStreamPlayer2D
@onready var menu: Panel = $VideoStreamPlayer/Panel


func _ready() -> void:
	## Initializes the main menu when the node enters the scene tree.
	##
	## Connects button signals and sets up the quit dialog.
	## Exposes functions to JS for web overlays if on web.
	##
	## :rtype: void
	Globals.log_message("Initializing main menu...", Globals.LogLevel.DEBUG)

	# 1. Connect core button signals on Frame 1 (Metadata is already set in _enter_tree)
	@warning_ignore("return_value_discarded")
	start_button.pressed.connect(_on_start_pressed)

	@warning_ignore("return_value_discarded")
	options_button.pressed.connect(_on_options_button_pressed)

	@warning_ignore("return_value_discarded")
	quit_button.pressed.connect(_on_quit_pressed)

	# 2. Run dialog configurations instantly
	_setup_quit_dialog()
	_setup_unbound_dialog()

	# 3. Expose JS Web callbacks right away if on Web platform
	if OS.get_name() == "Web":
		var js_window := JavaScriptBridge.get_interface("window")
		if js_window:
			_start_pressed_cb = JavaScriptBridge.create_callback(
				Callable(self, "_on_start_pressed")
			)
			js_window.startPressed = _start_pressed_cb
			_options_pressed_cb = JavaScriptBridge.create_callback(
				Callable(self, "_on_options_button_pressed")
			)
			js_window.optionsPressed = _options_pressed_cb
			_quit_pressed_cb = JavaScriptBridge.create_callback(Callable(self, "_on_quit_pressed"))
			js_window.quitPressed = _quit_pressed_cb
			Globals.log_message(
				"Exposed main menu callbacks to JS for web overlays.", Globals.LogLevel.DEBUG
			)

	# 4. Handle visual fade-in sequence asynchronously in the background
	_run_fade_in_sequence()


func _enter_tree() -> void:
	## Assign protection metadata before child nodes trigger node_added signals.
	var path := "VideoStreamPlayer/Panel/VBoxContainer/"
	get_node(path + "StartButton").set_meta("no_global_sound", true)
	get_node(path + "OptionsButton").set_meta("no_global_sound", true)
	get_node(path + "QuitButton").set_meta("no_global_sound", true)


func _run_fade_in_sequence() -> void:
	## Manages the initial main menu background layout animation.
	menu.visible = true
	menu.modulate.a = 0.0  # Start invisible

	# Non-blocking background sequence wait using configured properties
	await get_tree().create_timer(intro_delay).timeout

	# GUARD 1: Safe exit if the menu scene was torn down during the intro delay
	if not is_inside_tree() or not is_instance_valid(menu):
		return

	var panel_tween := create_tween()
	(
		panel_tween
		. tween_property(menu, "modulate:a", 1.0, fade_duration)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)

	if panel_tween and panel_tween.is_valid():
		Globals.log_message("Waiting for fade-in tween to finish.", Globals.LogLevel.DEBUG)
		await panel_tween.finished

		# GUARD 2: Safe exit if the menu scene was torn down during the fade animation
		if not is_inside_tree() or not is_instance_valid(start_button):
			return

		Globals.log_message("Fade-in complete—granting focus.", Globals.LogLevel.DEBUG)
	else:
		Globals.log_message("Invalid tween—grabbing focus immediately.", Globals.LogLevel.WARNING)

	Globals.ensure_initial_focus(
		start_button, [start_button, options_button, quit_button], "Main Menu"
	)


func _setup_unbound_dialog() -> void:
	# Create and configure the unbound controls warning dialog once
	unbound_dialog = ConfirmationDialog.new()
	unbound_dialog.title = "Unbound Controls"
	unbound_dialog.dialog_text = "Some critical controls are unbound.\nGo to Key Mapping to fix?"
	unbound_dialog.get_ok_button().text = "Open Key Mapping"
	unbound_dialog.get_cancel_button().text = "Start Anyway"
	# Make the dialog modal to prevent clicks outside or propagation issues
	unbound_dialog.exclusive = true
	add_child(unbound_dialog)  # Add to the scene tree so it can be shown
	unbound_dialog.hide()  # Start hidden

	# Connect confirmed (OK button or Enter): Load key mapping and hide
	unbound_dialog.confirmed.connect(
		func() -> void:
			Globals.load_key_mapping(ui_panel)
			unbound_dialog.hide()
	)

	# Connect only to cancel button pressed (click "Start Anyway"): Hide then load scene
	var cancel_button: Button = unbound_dialog.get_cancel_button()
	cancel_button.pressed.connect(
		func() -> void:
			unbound_dialog.hide()
			Globals.load_scene_with_loading("res://scenes/main_scene.tscn")
	)

	# Handle close button (X): Just hide
	unbound_dialog.close_requested.connect(
		func() -> void:
			Globals.log_message("Close requested triggered.", Globals.LogLevel.DEBUG)
			unbound_dialog.hide()
	)

	# Re-enable and focus Start button after fully hidden (handles all non-load cases safely)
	unbound_dialog.visibility_changed.connect(
		func() -> void:
			if not unbound_dialog.visible and is_instance_valid(start_button):
				start_button.disabled = false
				start_button.call_deferred("grab_focus")
	)


func _input(_event: InputEvent) -> void:
	## Handles input events for the main menu.
	# Keep your existing Web platform audio gesture unlock logic intact
	if OS.get_name() == "Web" and not background_music.playing:
		background_music.play()
		Globals.log_message(
			"User gesture detected—starting background music.", Globals.LogLevel.DEBUG
		)


func _setup_quit_dialog() -> void:
	## Sets up the quit confirmation dialog.
	## Finds the dialog node and connects signals if not already connected.
	## Hides the dialog initially.
	## :rtype: void
	quit_dialog = get_node_or_null(quit_dialog_path)
	if is_instance_valid(quit_dialog):
		# Confirmed = user wants to quit
		if not quit_dialog.confirmed.is_connected(_on_quit_dialog_confirmed):
			quit_dialog.confirmed.connect(_on_quit_dialog_confirmed)

		# Centralized Dismissal: In Godot, 'canceled' covers the explicit Cancel button,
		# the Escape key, and title-bar Close (X) actions natively. Connecting close_requested
		# here is redundant and would cause double audio triggers.
		if not quit_dialog.canceled.is_connected(_on_quit_dialog_canceled):
			quit_dialog.canceled.connect(_on_quit_dialog_canceled)

		# Clear generic audio connections on the internal Cancel button
		var cancel_button := quit_dialog.get_cancel_button()
		if is_instance_valid(cancel_button):
			for connection: Dictionary in cancel_button.pressed.get_connections():
				# Check both the object and the explicit audio handler name
				if (
					connection.callable.get_object() == Globals
					and connection.callable.get_method() == "_on_global_button_pressed"
				):
					cancel_button.pressed.disconnect(connection.callable)

		# Do the same for the OK button to prevent double-triggering the accept sound
		var ok_button := quit_dialog.get_ok_button()
		if is_instance_valid(ok_button):
			for connection: Dictionary in ok_button.pressed.get_connections():
				# Explicitly target only the Globals singleton audio hook by object and method
				if (
					connection.callable.get_object() == Globals
					and connection.callable.get_method() == "_on_global_button_pressed"
				):
					ok_button.pressed.disconnect(connection.callable)

		# Ensure initially hidden
		quit_dialog.hide()
		Globals.log_message(
			"QuitDialog signals connected and internal buttons sanitized.", Globals.LogLevel.DEBUG
		)
	else:
		Globals.log_message(
			"QuitDialog not found at path: " + str(quit_dialog_path), Globals.LogLevel.ERROR
		)


## Called when Start Game is pressed.
## Checks for unbound critical actions and shows warning if needed.
## Warning now appears only for the currently selected device (keyboard/gamepad).
func _on_start_pressed(_args: Array = []) -> void:
	## Handles the Start button press.
	##
	## Loads and transitions to the main game scene.
	##
	## :param _args: Optional arguments from web overlays (unused).
	## :type _args: Array
	## :rtype: void
	Globals.log_message("Start Game menu button pressed.", Globals.LogLevel.DEBUG)
	if Settings.has_unbound_critical_actions_for_current_device():
		# Guard: Disable button to prevent spamming while dialog is open
		start_button.disabled = true
		unbound_dialog.popup_centered()  # Show the reused dialog
	else:
		Globals.load_scene_with_loading("res://scenes/main_scene.tscn")


func _on_options_button_pressed(_args: Array = []) -> void:
	## Handles the Options button press.
	##
	## Loads options and logs the action.
	##
	## :param _args: Optional arguments from web overlays (unused).
	## :type _args: Array
	## :rtype: void
	Globals.log_message("Options button pressed.", Globals.LogLevel.DEBUG)
	Globals.load_options(ui_panel)  # Your existing load


func _on_quit_pressed(_args: Array = []) -> void:
	## Handles the Quit button press.
	##
	## Shows the quit confirmation dialog if available.
	##
	## :param _args: Optional arguments from web overlays (unused).
	## :type _args: Array
	## :rtype: void
	# Show confirmation dialog
	if is_instance_valid(quit_dialog):
		last_focused_button = quit_button  # Remember the opener
		quit_dialog.show()
		Globals.log_message("Attempting to show QuitDialog.", Globals.LogLevel.DEBUG)
		quit_dialog.popup_centered()  # Sets visible=true internally
	else:
		Globals.log_message("No quit_dialog found.", Globals.LogLevel.ERROR)


func _on_quit_dialog_confirmed() -> void:
	## Handles quit dialog confirmation.
	## Performs platform-specific quit actions.
	## :rtype: void

	# 1. Fire the confirmation sound asset
	AudioManager.play_sfx("ui_accept")

	# 2. Hide the panel immediately so the player gets immediate feedback
	if is_instance_valid(quit_dialog):
		quit_dialog.hide()

	# FIX: Guard against terminating the engine/editor during automated test execution
	if bypass_quit_for_testing:
		Globals.log_message(
			"Bypassing game quit execution for unit testing.", Globals.LogLevel.DEBUG
		)
		return

	# 3. Execute platform-specific quit execution path
	if OS.get_name() == "Web":
		# Offload the delay to JavaScript instead of utilizing a Godot await
		var ms_delay: int = int(audio_flush_delay * 1000.0)
		JavaScriptBridge.eval(
			(
				"setTimeout(function() "
				+ "{ window.top.location.href = 'https://ikostan.itch.io/sky-lock-assault'; }"
				+ ", %d);" % ms_delay
			)
		)
		Globals.log_message("Web quit: Scheduled JS timeout redirect.", Globals.LogLevel.DEBUG)
	else:
		# Desktop/editor: Use the clean, configurable export delay parameter
		await get_tree().create_timer(audio_flush_delay).timeout
		get_tree().quit()
		Globals.log_message("Native quit executed!", Globals.LogLevel.DEBUG)


func _on_quit_dialog_canceled() -> void:
	## Handles quit dialog cancellation visual resets and focus recovery.
	## :rtype: void
	AudioManager.play_sfx("ui_cancel")
	quit_dialog.hide()
	Globals.log_message("Quit canceled.", Globals.LogLevel.DEBUG)

	# Return focus to the button that opened the dialog
	if is_instance_valid(last_focused_button):
		last_focused_button.call_deferred("grab_focus")
		Globals.log_message(
			"Restored focus to: " + last_focused_button.name, Globals.LogLevel.DEBUG
		)
	else:
		if is_instance_valid(quit_button):
			quit_button.call_deferred("grab_focus")
