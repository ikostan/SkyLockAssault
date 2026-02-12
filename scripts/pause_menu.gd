## SPDX-License-Identifier: GPL-3.0-or-later
## Use for exiting game levels back to main menu without quitting.
## pause_menu.gd
##
## Pause menu overlay: Toggles with ESC, pauses the game tree, and handles resume/back to menu.
## Copyright (C) 2025 Egor Kostan

extends CanvasLayer

var options_menu: PackedScene = preload("res://scenes/options_menu.tscn")
@onready var resume_button: Button = $VBoxContainer/ResumeButton
@onready var back_to_main_button: Button = $VBoxContainer/BackToMainButton
@onready var options_button: Button = $VBoxContainer/OptionsButton


func _input(event: InputEvent) -> void:
	## Handles input events.
	##
	## Logs mouse clicks for debugging.
	##
	## :param event: Input event.
	## :type event: InputEvent
	## :rtype: void
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = event.position
		Globals.log_message("Clicked at: (%s, %s)" % [pos.x, pos.y], Globals.LogLevel.DEBUG)


func _ready() -> void:
	## Initializes pause menu.
	##
	## Guards signal connects, hides menu, logs ready.
	##
	## :rtype: void
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not resume_button.pressed.is_connected(_on_resume_button_pressed):
		resume_button.pressed.connect(_on_resume_button_pressed)
	if not back_to_main_button.pressed.is_connected(_on_back_to_main_button_pressed):
		back_to_main_button.pressed.connect(_on_back_to_main_button_pressed)
	if not options_button.pressed.is_connected(_on_options_button_pressed):
		options_button.pressed.connect(_on_options_button_pressed)
	visible = false
	Globals.log_message("Pause menu is ready.", Globals.LogLevel.DEBUG)


func _unhandled_input(event: InputEvent) -> void:
	## Processes unhandled input for pause toggle.
	##
	## Ignores if hidden and options open.
	##
	## :param event: Input event.
	## :type event: InputEvent
	## :rtype: void
	if not visible and Globals.options_open:
		return
	if event.is_action_pressed("pause"):
		toggle_pause()


func toggle_pause() -> void:
	## Toggles pause menu visibility and pause state.
	##
	## Grabs focus on resume button when shown for keyboard/D-pad navigation.
	##
	## :rtype: void
	visible = not visible
	get_tree().paused = visible
	if visible and is_instance_valid(resume_button):
		resume_button.call_deferred("grab_focus")


func _on_resume_button_pressed() -> void:
	## Handles resume button press.
	##
	## Logs and toggles pause.
	##
	## :rtype: void
	Globals.log_message("Resume button pressed.", Globals.LogLevel.DEBUG)
	toggle_pause()


func _on_back_to_main_button_pressed() -> void:
	## Handles back to main button press.
	##
	## Unpauses, hides, loads main menu.
	##
	## :rtype: void
	Globals.log_message("Back To Main Menu button pressed.", Globals.LogLevel.DEBUG)
	get_tree().paused = false
	visible = false
	Globals.load_scene_with_loading("res://scenes/main_menu.tscn")


func _on_options_button_pressed() -> void:
	## Handles options button press.
	##
	## Logs and loads options, hides self.
	##
	## :rtype: void
	Globals.log_message("Options button pressed.", Globals.LogLevel.DEBUG)
	Globals.load_options(self)
