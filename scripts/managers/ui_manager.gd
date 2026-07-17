## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## ui_manager.gd
##
## Global controller responsible for capturing UI input events, tracking user 
## hardware control schemes, and routing global navigation, acceptance, and 
## cancellation sound effects through the central AudioManager.

extends Node

## List of explicit directional and focus-shifting UI actions.
var _nav_actions: Array[String] = [
	"ui_up", 
	"ui_down", 
	"ui_left", 
	"ui_right", 
	"ui_focus_next", 
	"ui_focus_prev"
]


## Intercepts global unhandled input events to trigger contextual UI audio feedback.
## @param event: The raw input event captured by the viewport.
## :rtype: void
func _unhandled_input(event: InputEvent) -> void:
	# Gate 1: Prevent double-triggering on held-down keys/buttons
	if event.is_echo():
		return

	# Gate 2: Update the active hardware control scheme (keyboard/mouse vs gamepad)
	_track_input_device(event)

	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	var ui_has_focus: bool = is_instance_valid(focus_owner)

	# Gate 3: Guarantee we are inside a valid menu context before playing sound effects
	if not _check_menu_context(ui_has_focus):
		return

	# Gate 4: Drop heavy-polling mouse movements or non-action inputs early
	if event is InputEventMouseMotion or not event.is_action_type():
		return

	# Gate 5: Parse and route the action to its corresponding sound effect
	_process_ui_navigation_sfx(event, focus_owner, ui_has_focus)


## Tracks the active input device scheme and updates the global state.
## @param event: The current InputEvent being evaluated.
## :rtype: void
func _track_input_device(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		Globals.current_input_device = "keyboard"
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		Globals.current_input_device = "gamepad"


## Evaluates the current SceneTree state and system flags to verify menu boundaries.
## @param ui_has_focus: Whether a UI element currently holds active focus.
## @return bool: True if the current state is an eligible menu context.
func _check_menu_context(ui_has_focus: bool) -> bool:
	var is_menu_context: bool = (
		get_tree().paused 
		or Globals.options_open 
		or not Globals.hidden_menus.is_empty() 
		or ui_has_focus
	)

	# Safeguard: Verify the active scene is fully initialized
	var active_scene: Node = get_tree().current_scene if get_tree() else null
	if not is_instance_valid(active_scene):
		return is_menu_context

	# Use explicit group/metadata markers with a fallback string match for safety
	if not is_menu_context:
		if (
			active_scene.is_in_group("menu_context")
			or active_scene.has_meta("is_menu_context")
			or "Menu" in active_scene.name
		):
			is_menu_context = true

	# Test Environment Fallback: Support test runner assertions during automated pipelines
	if (OS.has_feature("debug") or OS.has_feature("ci")) and not is_menu_context:
		if (
			"Menu" in active_scene.name
			or active_scene.has_meta("is_menu_context")
			or active_scene.is_in_group("menu_context")
		):
			is_menu_context = true

	return is_menu_context


## Matches actions against UI_SFX configurations and handles specific control overrides.
## @param event: The active input event.
## @param focus_owner: The Control node currently holding focus (can be null).
## @param ui_has_focus: Boolean state verifying if focus is owned.
## :rtype: void
func _process_ui_navigation_sfx(
	event: InputEvent, 
	focus_owner: Control, 
	ui_has_focus: bool
) -> void:
	for action: String in AudioConstants.UI_SFX.keys():
		if event.is_action_pressed(action, false):
			# Context Guard A: Handle Escape/Cancel scenarios
			if action == "ui_cancel":
				_handle_ui_cancel_action(focus_owner, action)
				return

			# Context Guard B: Quietly drop events on interactive control submissions
			if action == "ui_accept":
				if (
					focus_owner is BaseButton
					or focus_owner is Slider
					or focus_owner is LineEdit
					or focus_owner is TextEdit
				):
					return

			# Context Guard C: Evaluate standard focus swaps and directional movements
			_handle_ui_navigation_action(action, focus_owner, ui_has_focus)
			return


## Handles UI cancellation/back inputs, filtering out active text fields or input-remapping.
## @param focus_owner: The currently focused control node.
## @param action: The input action name string.
## :rtype: void
func _handle_ui_cancel_action(focus_owner: Control, action: String) -> void:
	var is_editing_control: bool = (
		focus_owner is LineEdit
		or focus_owner is TextEdit
		or focus_owner is Range
		or focus_owner is CheckButton
		or focus_owner is OptionButton
	)

	var is_remap_control: bool = false
	if is_instance_valid(focus_owner):
		is_remap_control = (
			focus_owner.has_method("cancel_remap")
			or focus_owner.get("action") != null
			or focus_owner.get("action_name") != null
		)

	if not is_editing_control and not is_remap_control:
		var logical_id: String = AudioConstants.UI_SFX[action]
		# Explicitly route all cancellation SFX through the SFX bus (Issue #490)
		AudioManager.play_sfx(logical_id, AudioConstants.BUS_SFX)


## Evaluates focus transitions and triggers directional UI navigation sounds.
## @param action: The directional action key.
## @param focus_owner: The currently focused Control element.
## @param ui_has_focus: Check determining if focus is active.
## :rtype: void
func _handle_ui_navigation_action(
	action: String, 
	focus_owner: Control, 
	ui_has_focus: bool
) -> void:
	var is_horizontal_slider: bool = (
		focus_owner is Slider and (action == "ui_left" or action == "ui_right")
	)
	var is_nav_action: bool = action in _nav_actions
	var should_play_nav_sfx: bool = (ui_has_focus or is_nav_action) and not is_horizontal_slider

	if should_play_nav_sfx:
		var logical_id: String = AudioConstants.UI_SFX[action]
		# Explicitly route navigation SFX through the SFX bus (Issue #490)
		AudioManager.play_sfx(logical_id, AudioConstants.BUS_SFX)
