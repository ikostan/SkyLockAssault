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

# Reference to the quit dialog node, assigned in setup_quit_dialog or _ready()
var quit_dialog: ConfirmationDialog
var options_menu: PackedScene = preload("res://scenes/options_menu.tscn")
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
	# Prepare menu for fade-in: Make visible but fully transparent
	menu.visible = true
	menu.modulate.a = 0.0  # Start invisible (alpha 0)
	# Wait for 3 seconds (adjust as needed)
	await get_tree().create_timer(3.0).timeout
	# Optional: Play a fade-in animation if you have an AnimationPlayer
	# Fade in the main panel over 1 second (smooth easing)
	var panel_tween := create_tween()
	# Property to animate (alpha channel)  # End value (fully opaque)  # Duration in seconds
	panel_tween.tween_property(menu, "modulate:a", 1.0, 1.0).set_ease(Tween.EASE_OUT).set_trans(
		Tween.TRANS_QUAD
	)  # Smooth curve (eases out, quadratic)
	# Wait only if tween is good and started
	if panel_tween and panel_tween.is_valid() and panel_tween.is_running():
		await panel_tween.finished
	# Fallback: Grab focus immediately if tween isn't running (e.g., error or instant)
	# Give keyboard focus to the first button after the fade-in completes
	start_button.call_deferred("grab_focus")
	# Connect START button signal
	@warning_ignore("return_value_discarded")
	start_button.pressed.connect(_on_start_pressed)
	# Connect OPTIONS button signal
	@warning_ignore("return_value_discarded")
	options_button.pressed.connect(_on_options_button_pressed)
	# Connect QUIT button signal
	@warning_ignore("return_value_discarded")
	quit_button.pressed.connect(_on_quit_pressed)
	# Setup quit dialog
	setup_quit_dialog()
	# To prevent garbage collection of JavaScriptObject callbacks in Godot's JS bindings,
	# which can break the references and cause calls like window.optionsPressed([]) to fail
	# silently, leading to issues like the test timeout on waiting for visible elements
	# (e.g., #audio-button remains hidden because options menu _ready() doesn't run).
	# Storing them as member variables ensures they persist.
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


func _input(_event: InputEvent) -> void:
	## Handles input events for the main menu.
	##
	## Logs mouse clicks and unlocks audio on web platforms upon user gesture.
	##
	## :param _event: The input event to process.
	## :type _event: InputEvent
	## :rtype: void
	# New: Unlock audio on first qualifying gesture (click or key press)
	if OS.get_name() == "Web" and not background_music.playing:
		background_music.play()
		Globals.log_message(
			"User gesture detected—starting background music.", Globals.LogLevel.DEBUG
		)


func setup_quit_dialog() -> void:
	## Sets up the quit confirmation dialog.
	##
	## Finds the dialog node and connects signals if not already connected.
	## Hides the dialog initially.
	##
	## :rtype: void
	## Sets up the quit confirmation dialog.
	quit_dialog = get_node_or_null(quit_dialog_path)
	if is_instance_valid(quit_dialog):
		# Confirmed = user wants to quit
		if not quit_dialog.confirmed.is_connected(_on_quit_dialog_confirmed):
			quit_dialog.confirmed.connect(_on_quit_dialog_confirmed)
		# Canceled = Cancel button or Esc
		if not quit_dialog.canceled.is_connected(_on_quit_dialog_canceled):
			quit_dialog.canceled.connect(_on_quit_dialog_canceled)
		# Close button (×) in title bar or other "just hide" cases
		if not quit_dialog.close_requested.is_connected(_on_quit_dialog_canceled):
			quit_dialog.close_requested.connect(_on_quit_dialog_canceled)
		# Ensure initially hidden
		quit_dialog.hide()
		Globals.log_message("QuitDialog signals connected.", Globals.LogLevel.DEBUG)
	else:
		Globals.log_message(
			"QuitDialog not found at path: " + str(quit_dialog_path), Globals.LogLevel.ERROR
		)


func _on_start_pressed(_args: Array = []) -> void:
	## Handles the Start button press.
	##
	## Loads and transitions to the main game scene.
	##
	## :param _args: Optional arguments from web overlays (unused).
	## :type _args: Array
	## :rtype: void
	# Stub; later: get_tree().change_scene_to_file("res://game_scene.tscn")
	Globals.log_message("Start Game menu button pressed.", Globals.LogLevel.DEBUG)
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
		quit_dialog.show()
		Globals.log_message("Attempting to show QuitDialog.", Globals.LogLevel.DEBUG)
		quit_dialog.popup_centered()  # Sets visible=true internally
	else:
		Globals.log_message("No quit_dialog found.", Globals.LogLevel.ERROR)


func _on_quit_dialog_confirmed() -> void:
	## Handles quit dialog confirmation.
	##
	## Performs platform-specific quit actions.
	##
	## :rtype: void
	# User confirmed: Execute platform-specific quit
	if OS.get_name() == "Web":
		# Web export: Redirect to itch.io game page (clean exit, no freeze)
		JavaScriptBridge.eval("window.location.href = 'https://ikostan.itch.io/sky-lock-assault';")
	else:
		# Desktop/editor: Standard quit
		get_tree().quit()
	Globals.log_message("Quit confirmed and executed!", Globals.LogLevel.DEBUG)


func _on_quit_dialog_canceled() -> void:
	## Handles quit dialog cancellation.
	##
	## Hides the dialog and logs the action.
	##
	## :rtype: void
	# Optional: Handle cancel (e.g., play sound or log)
	quit_dialog.hide()
	Globals.log_message("Quit canceled.", Globals.LogLevel.DEBUG)
	# Return focus to the button that opened the dialog
	quit_button.call_deferred("grab_focus")
