## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_nav_escape_sfx.gd

extends GutTest

## Scene-root group that opts a scene into UI sounds (UiManager._check_menu_context).
const MENU_CONTEXT_GROUP: String = "menu_context"
## Scene-root metadata key with the same effect as MENU_CONTEXT_GROUP.
const MENU_CONTEXT_META: String = "is_menu_context"

var globals_instance: Node
var original_audio_script: Script
var original_scene_name: String = ""
var dummy_scene_node: Node = null
## Whether the shared current scene was already in the menu_context group before the test.
var scene_was_in_menu_group: bool = false
## Whether the shared current scene already had the is_menu_context meta before the test.
var _meta_was_preexisting: bool = false
## Runtime menu state snapshotted in before_each() and restored in after_each(), so a test
## that stops on a script error can't leave a menu context on for later tests.
var _saved_options_open: bool = false
var _saved_hidden_menus: Array[Node] = []
var _saved_paused: bool = false
## Restore the scene even if a context regression test stops before its cleanup.
var _saved_test_scene: Node = null

## Suite setup: Double the SfxManager using a decoupled script to bypass lifecycle destruction guards.
## :rtype: void
func before_all() -> void:
	if is_instance_valid(SfxManager):
		original_audio_script = SfxManager.get_script()
		var mock_script := GDScript.new()
		# FIX: Match production signature (4 arguments) and log [key, bus_name]
		mock_script.source_code = """
extends Node
var sfx_calls: Array = []
func play_sfx(key: String, bus_name: String = "SFX_Menu", pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	sfx_calls.append([key, bus_name])
"""
		mock_script.reload()
		SfxManager.set_script(mock_script)


## Suite cleanup: Safely restore original production script after all tests execute.
## :rtype: void
func after_all() -> void:
	if original_audio_script and is_instance_valid(SfxManager):
		SfxManager.set_script(original_audio_script)
		# Re-populate and rebuild the internal variable states wiped by set_script()
		if SfxManager.has_method("cleanup_for_test"):
			SfxManager.cleanup_for_test()


## Per-test setup: Snapshot the shared SceneTree state and reset mock logs.
## :rtype: void
func before_each() -> void:
	globals_instance = Globals
	_saved_options_open = Globals.options_open
	_saved_hidden_menus = Globals.hidden_menus.duplicate()
	_saved_paused = get_tree().paused
	
	# Securely snapshot the active root scene name and group before any mutations occur
	if get_tree().current_scene:
		original_scene_name = get_tree().current_scene.name
		scene_was_in_menu_group = get_tree().current_scene.is_in_group(MENU_CONTEXT_GROUP)
		_meta_was_preexisting = get_tree().current_scene.has_meta(MENU_CONTEXT_META)
		dummy_scene_node = null
	else:
		# FIX: If running headlessly/CI, create a temporary dummy node to safely act as current_scene
		dummy_scene_node = Node.new()
		get_tree().root.add_child(dummy_scene_node)
		get_tree().current_scene = dummy_scene_node
		original_scene_name = ""
		scene_was_in_menu_group = false
			
	_saved_test_scene = get_tree().current_scene

	if SfxManager.get("sfx_calls") != null:
		SfxManager.set("sfx_calls", [])
		
	await get_tree().process_frame


## Per-test cleanup: Restore the shared engine scene tree name wrapper cleanly.
## :rtype: void
func after_each() -> void:
	if is_instance_valid(_saved_test_scene):
		get_tree().current_scene = _saved_test_scene
	_saved_test_scene = null
	# FIX: Cleanly teardown and unmount the dummy scene tracker if initialized
	if dummy_scene_node and is_instance_valid(dummy_scene_node):
		if get_tree().current_scene == dummy_scene_node:
			get_tree().current_scene = null
		dummy_scene_node.queue_free()
		dummy_scene_node = null
	elif original_scene_name != "" and get_tree().current_scene:
		var scene: Node = get_tree().current_scene
		scene.name = original_scene_name
		# Restore the group membership the scene had before the test
		if scene_was_in_menu_group:
			scene.add_to_group(MENU_CONTEXT_GROUP)
		elif scene.is_in_group(MENU_CONTEXT_GROUP):
			scene.remove_from_group(MENU_CONTEXT_GROUP)
		if scene.has_meta(MENU_CONTEXT_META) and not _meta_was_preexisting:
			scene.remove_meta(MENU_CONTEXT_META)

	original_scene_name = ""
	scene_was_in_menu_group = false
	_meta_was_preexisting = false
	# Restore runtime menu state in place (hidden_menus is never reassigned in production)
	get_tree().paused = _saved_paused
	Globals.options_open = _saved_options_open
	Globals.hidden_menus.assign(_saved_hidden_menus)
	_saved_hidden_menus = []
	# Release any focus a test left behind so the next test starts outside a menu context
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus_owner):
		focus_owner.release_focus()
	await get_tree().process_frame


## Helper assertions for tracking explicit mock array triggers
func _assert_sfx_called(key: String) -> void:
	var found := false
	var calls: Array = SfxManager.get("sfx_calls")
	for c: Array in calls:
		if c[0] == key:
			found = true
			break
	assert_true(found, "Expected play_sfx to be called with: " + key)


func _assert_sfx_call_count(count: int) -> void:
	var actual_count: int = SfxManager.get("sfx_calls").size() 
	# FIX: Combined split string literal into a single line to resolve the engine compilation crash
	assert_eq(actual_count, count, "Expected play_sfx to be called %d times. Got %d." % [count, actual_count])


func _assert_sfx_not_called() -> void:
	var actual_count: int = SfxManager.get("sfx_calls").size()
	assert_eq(actual_count, 0, "Expected zero play_sfx calls. Got %d." % actual_count)


## Asserts that every recorded play_sfx call for [param key] requested [param bus_name].
## Fails if no call for the key was recorded.
func _assert_sfx_bus(key: String, bus_name: String) -> void:
	var matched: int = 0
	var calls: Array = SfxManager.get("sfx_calls")
	for c: Array in calls:
		if c[0] == key:
			matched += 1
			assert_eq(c[1], bus_name, "play_sfx('%s') must request bus '%s'." % [key, bus_name])
	assert_gt(matched, 0, "Expected at least one play_sfx call with: " + key)


## Puts the current scene in or out of a menu context through the explicit
## menu_context group (Issue #1152: the scene name is no longer used).
## :rtype: void
func _set_menu_context(value: bool) -> void:
	var scene: Node = get_tree().current_scene
	if not scene:
		return
	if value:
		scene.add_to_group(MENU_CONTEXT_GROUP)
	elif scene.is_in_group(MENU_CONTEXT_GROUP):
		scene.remove_from_group(MENU_CONTEXT_GROUP)


## Builds a pressed InputEventAction for [param action].
func _action_event(action: String) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


## Helper to feed simulated inputs safely and directly through the pipeline contexts.
## :rtype: void
func _simulate_input(event: InputEvent) -> void:
	# Route simulated input events directly into the new decoupled UiManager (Issue #490)
	if is_instance_valid(UiManager) and UiManager.has_method("_input"):
		UiManager._input(event)


## Assert that simulating a ui_cancel input event when inside a menu context triggers cancel audio.
## :rtype: void
func test_global_cancellation_in_menu_context() -> void:
	_set_menu_context(true)
	
	var event: InputEventAction = InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	
	_simulate_input(event)
	_assert_sfx_called("ui_cancel")
	_assert_sfx_call_count(1)
	_assert_sfx_bus("ui_cancel", AudioConstants.BUS_SFX_MENU)


## Assert that no interface audio streams are triggered if input events occur outside menu contexts.
## :rtype: void
func test_global_out_of_context_suppression() -> void:
	_set_menu_context(false)
	
	var event_cancel: InputEventAction = InputEventAction.new()
	event_cancel.action = "ui_cancel"
	event_cancel.pressed = true
	
	var event_nav: InputEventAction = InputEventAction.new()
	event_nav.action = "ui_up"
	event_nav.pressed = true
	
	_simulate_input(event_cancel)
	_simulate_input(event_nav)
	_assert_sfx_not_called()


## Assert that immediately after leaving a menu context, subsequent cancel inputs do not trigger audio.
## :rtype: void
func test_menu_context_exit_cleanup() -> void:
	_set_menu_context(true)
	_set_menu_context(false) 
	
	var event: InputEventAction = InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	
	_simulate_input(event)
	_assert_sfx_not_called()


## Assert that repeated input instances flagged as echo completely bypass the audio frame.
## :rtype: void
func test_input_repeat_gate_echo_mitigation() -> void:
	_set_menu_context(true)
	
	var event: InputEventKey = InputEventKey.new()
	event.echo = true
	event.pressed = true
	event.physical_keycode = KEY_UP
	
	_simulate_input(event)
	_assert_sfx_not_called()


## Assert that directional actions successfully trigger the navigation tick when components are focused.
## :rtype: void
func test_navigation_positive_case() -> void:
	_set_menu_context(true)
	
	var dummy_btn: Button = Button.new()
	add_child_autofree(dummy_btn)
	dummy_btn.grab_focus()
	await get_tree().process_frame 
	
	var event: InputEventAction = InputEventAction.new()
	event.action = "ui_up"
	event.pressed = true
	
	_simulate_input(event)
	_assert_sfx_called("ui_navigation")
	_assert_sfx_bus("ui_navigation", AudioConstants.BUS_SFX_MENU)


## Assert that a single discrete navigation input event produces exactly one audio trigger request.
## :rtype: void
func test_single_dispatch_guarantee() -> void:
	_set_menu_context(true)
	
	var dummy_btn: Button = Button.new()
	add_child_autofree(dummy_btn)
	dummy_btn.grab_focus()
	await get_tree().process_frame
	
	var event: InputEventAction = InputEventAction.new()
	event.action = "ui_down"
	event.pressed = true
	
	_simulate_input(event)
	_assert_sfx_call_count(1)


## Assert that when a LineEdit control node holds active focus, global interface sound is suppressed.
## :rtype: void
func test_value_editing_text_gate() -> void:
	_set_menu_context(true)
	
	var line_edit: LineEdit = LineEdit.new()
	add_child_autofree(line_edit)
	line_edit.grab_focus() 
	await get_tree().process_frame
	
	var event: InputEventAction = InputEventAction.new()
	# FIX: Swapped from ui_accept to ui_cancel to properly challenge the text control bypass branch
	event.action = "ui_cancel"
	event.pressed = true
	
	_simulate_input(event)
	_assert_sfx_not_called()


## Assert that when a Slider control holds active focus, horizontal directional inputs are bypassed.
## :rtype: void
func test_slider_double_audio_gate() -> void:
	_set_menu_context(true)
	
	var slider: HSlider = HSlider.new()
	add_child_autofree(slider)
	slider.grab_focus() 
	await get_tree().process_frame
	
	var event_left: InputEventAction = InputEventAction.new()
	event_left.action = "ui_left"
	event_left.pressed = true
	
	var event_right: InputEventAction = InputEventAction.new()
	event_right.action = "ui_right"
	event_right.pressed = true
	
	_simulate_input(event_left)
	_simulate_input(event_right)
	_assert_sfx_not_called()


## Assert that unrelated input actions never trigger interface selection, navigation, or cancellation audio.
## :rtype: void
func test_unrelated_action_integrity() -> void:
	_set_menu_context(true)
	
	var actions: Array[String] = ["weapon_fire", "pause_toggle", "move_left"]
	for act: String in actions:
		var event: InputEventAction = InputEventAction.new()
		event.action = act
		event.pressed = true
		_simulate_input(event)
		
	_assert_sfx_not_called()


## Issue #1152: navigation without focus (pure menu context) still requests the Menu bus,
## for every directional action.
## :rtype: void
func test_navigation_without_focus_requests_menu_bus() -> void:
	_set_menu_context(true)
	for act: String in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		_simulate_input(_action_event(act))
	_assert_sfx_call_count(4)
	_assert_sfx_bus("ui_navigation", AudioConstants.BUS_SFX_MENU)


## Issue #1152: no UI sound requests the parent SFX bus any more.
## :rtype: void
func test_no_ui_sound_requests_parent_sfx_bus() -> void:
	_set_menu_context(true)
	_simulate_input(_action_event("ui_cancel"))
	_simulate_input(_action_event("ui_down"))
	var calls: Array = SfxManager.get("sfx_calls")
	assert_eq(calls.size(), 2, "Expected one cancel and one navigation request.")
	for c: Array in calls:
		assert_ne(c[1], AudioConstants.BUS_SFX, "'%s' must not be routed to the SFX bus." % c[0])


## Issue #1152: a scene whose name contains "Menu" but has no group, meta, or focus is
## not a menu context.
## :rtype: void
func test_scene_named_menu_without_group_is_not_menu_context() -> void:
	var scene: Node = get_tree().current_scene
	assert_not_null(scene, "Precondition: a current scene is required.")
	_set_menu_context(false)
	for scene_name: String in ["MainMenu", "OptionsMenu", "Menu"]:
		scene.name = scene_name
		assert_false(
			UiManager._check_menu_context(false),
			"A scene named '%s' must not be treated as a menu context." % scene_name
		)
		_simulate_input(_action_event("ui_cancel"))
		_simulate_input(_action_event("ui_up"))
	_assert_sfx_not_called()


## Issue #1152: a scene in the menu_context group is a menu context, whatever its name.
## :rtype: void
func test_scene_in_menu_context_group_is_menu_context() -> void:
	var scene: Node = get_tree().current_scene
	assert_not_null(scene, "Precondition: a current scene is required.")
	scene.name = "GameLevel"
	_set_menu_context(false)
	assert_false(UiManager._check_menu_context(false), "Precondition: no menu context.")

	_set_menu_context(true)
	assert_true(UiManager._check_menu_context(false), "The group must enable the menu context.")
	_simulate_input(_action_event("ui_cancel"))
	_assert_sfx_called("ui_cancel")
	_assert_sfx_call_count(1)


## The is_menu_context metadata marker is kept as an explicit opt-in (Issue #1152).
## :rtype: void
func test_scene_with_menu_context_meta_is_menu_context() -> void:
	var scene: Node = get_tree().current_scene
	assert_not_null(scene, "Precondition: a current scene is required.")
	_set_menu_context(false)
	assert_false(UiManager._check_menu_context(false), "Precondition: no menu context.")

	scene.set_meta(MENU_CONTEXT_META, true)
	assert_true(UiManager._check_menu_context(false), "The meta must enable the menu context.")
	_simulate_input(_action_event("ui_cancel"))
	_assert_sfx_call_count(1)


## The runtime flags still open a menu context without any scene marker.
## :rtype: void
func test_runtime_flags_open_menu_context_without_scene_marker() -> void:
	_set_menu_context(false)
	assert_false(UiManager._check_menu_context(false), "Precondition: no menu context.")

	get_tree().paused = true
	var paused_ctx: bool = UiManager._check_menu_context(false)
	get_tree().paused = false
	assert_true(paused_ctx, "A paused tree must enable the menu context.")

	Globals.options_open = true
	assert_true(UiManager._check_menu_context(false), "options_open must enable the menu context.")
	Globals.options_open = false

	var dummy_menu: Control = Control.new()
	add_child_autofree(dummy_menu)
	Globals.hidden_menus.push_back(dummy_menu)
	assert_true(UiManager._check_menu_context(false), "A hidden menu must enable the menu context.")
	Globals.hidden_menus.erase(dummy_menu)

	assert_true(UiManager._check_menu_context(true), "Focus must enable the menu context.")
	assert_false(UiManager._check_menu_context(false), "No flag left set: no menu context.")


## Remap buttons (InputRemapButton exposes `action`) still suppress the cancel sound.
## :rtype: void
func test_remap_button_action_suppresses_cancel_sound() -> void:
	_set_menu_context(true)
	var remap_btn: InputRemapButton = InputRemapButton.new()
	remap_btn.action = "move_left"
	add_child_autofree(remap_btn)
	remap_btn.grab_focus()
	await get_tree().process_frame
	assert_eq(get_viewport().gui_get_focus_owner(), remap_btn, "Precondition: remap button focused.")

	_simulate_input(_action_event("ui_cancel"))
	_assert_sfx_not_called()


## A focused control exposing `action_name` also suppresses the cancel sound.
## :rtype: void
func test_action_name_control_suppresses_cancel_sound() -> void:
	_set_menu_context(true)
	var script := GDScript.new()
	script.source_code = "extends Button\nvar action_name: String = \"move_left\"\n"
	script.reload()
	var btn: Button = Button.new()
	btn.set_script(script)
	add_child_autofree(btn)
	btn.grab_focus()
	await get_tree().process_frame
	assert_eq(get_viewport().gui_get_focus_owner(), btn, "Precondition: button focused.")

	_simulate_input(_action_event("ui_cancel"))
	_assert_sfx_not_called()


## A plain focused button (no `action` / `action_name`) still gets the cancel sound on
## the Menu bus.
## :rtype: void
func test_plain_button_cancel_plays_on_menu_bus() -> void:
	_set_menu_context(true)
	var btn: Button = Button.new()
	add_child_autofree(btn)
	btn.grab_focus()
	await get_tree().process_frame

	_simulate_input(_action_event("ui_cancel"))
	_assert_sfx_call_count(1)
	_assert_sfx_bus("ui_cancel", AudioConstants.BUS_SFX_MENU)


## A legacy method alone no longer identifies a control as an input remapper.
class LegacyCancelButton extends Button:
	var cancel_calls: int = 0

	func cancel_remap() -> void:
		cancel_calls += 1


## Null properties represent a normal control; empty strings still mark remappers.
class RemapPropertyButton extends Button:
	var action: Variant = null
	var action_name: Variant = null


func test_cancel_remap_method_alone_does_not_suppress_menu_audio() -> void:
	var button := LegacyCancelButton.new()
	add_child_autofree(button)

	UiManager._handle_ui_cancel_action(button, "ui_cancel")

	assert_eq(SfxManager.get("sfx_calls"), [["ui_cancel", AudioConstants.BUS_SFX_MENU]])
	assert_eq(button.cancel_calls, 0, "Audio dispatch must not invoke a control's cancel method.")


func test_null_remap_properties_allow_cancel_on_menu_bus() -> void:
	var button := RemapPropertyButton.new()
	add_child_autofree(button)

	UiManager._handle_ui_cancel_action(button, "ui_cancel")

	assert_eq(SfxManager.get("sfx_calls"), [["ui_cancel", AudioConstants.BUS_SFX_MENU]])


func test_empty_action_still_suppresses_cancel() -> void:
	var button := RemapPropertyButton.new()
	button.action = ""
	add_child_autofree(button)

	UiManager._handle_ui_cancel_action(button, "ui_cancel")

	_assert_sfx_not_called()


func test_empty_action_name_still_suppresses_cancel() -> void:
	var button := RemapPropertyButton.new()
	button.action_name = ""
	add_child_autofree(button)

	UiManager._handle_ui_cancel_action(button, "ui_cancel")

	_assert_sfx_not_called()


## Root markers must be evaluated afresh, including immediately after removal.
func test_removing_scene_marker_stops_navigation_and_cancel_audio() -> void:
	var previous_scene: Node = get_tree().current_scene
	var scene := Node.new()
	# current_scene must be a direct child of the root; under the test node it is refused
	get_tree().root.add_child(scene)
	autofree(scene)
	get_tree().current_scene = scene
	Globals.options_open = false
	Globals.hidden_menus.clear()
	get_tree().paused = false

	for marker: String in [MENU_CONTEXT_GROUP, MENU_CONTEXT_META]:
		if marker == MENU_CONTEXT_GROUP:
			scene.add_to_group(marker)
		else:
			scene.set_meta(marker, true)
		_simulate_input(_action_event("ui_cancel"))
		_simulate_input(_action_event("ui_up"))
		assert_eq(SfxManager.get("sfx_calls"), [
			["ui_cancel", AudioConstants.BUS_SFX_MENU],
			["ui_navigation", AudioConstants.BUS_SFX_MENU],
		])
		SfxManager.set("sfx_calls", [])
		if marker == MENU_CONTEXT_GROUP:
			scene.remove_from_group(marker)
		else:
			scene.remove_meta(marker)
		_simulate_input(_action_event("ui_cancel"))
		_simulate_input(_action_event("ui_up"))
		_assert_sfx_not_called()

	get_tree().current_scene = previous_scene


## With no current scene, focus and runtime state still determine the context.
func test_missing_scene_preserves_runtime_context_checks() -> void:
	var previous_scene: Node = get_tree().current_scene
	get_tree().current_scene = null
	Globals.options_open = false
	Globals.hidden_menus.clear()
	get_tree().paused = false

	assert_false(UiManager._check_menu_context(false))
	assert_true(UiManager._check_menu_context(true), "Focus works during scene transitions.")
	Globals.options_open = true
	assert_true(UiManager._check_menu_context(false))
	Globals.options_open = false
	get_tree().paused = true
	var paused_context: bool = UiManager._check_menu_context(false)
	get_tree().paused = false
	assert_true(paused_context)
	var menu := Control.new()
	add_child_autofree(menu)
	Globals.hidden_menus.append(menu)
	assert_true(UiManager._check_menu_context(false))
	Globals.hidden_menus.clear()
	assert_false(UiManager._check_menu_context(false), "Context must not be cached.")

	get_tree().current_scene = previous_scene


## A marker on a descendant must not opt the entire scene into UI audio.
func test_child_menu_markers_do_not_enable_scene_context() -> void:
	var previous_scene: Node = get_tree().current_scene
	var scene := Node.new()
	# current_scene must be a direct child of the root; under the test node it is refused
	get_tree().root.add_child(scene)
	autofree(scene)
	var child := Node.new()
	scene.add_child(child)
	child.add_to_group(MENU_CONTEXT_GROUP)
	child.set_meta(MENU_CONTEXT_META, true)
	get_tree().current_scene = scene
	Globals.options_open = false
	Globals.hidden_menus.clear()
	get_tree().paused = false

	var context: bool = UiManager._check_menu_context(false)
	get_tree().current_scene = previous_scene

	assert_false(context, "Only the active scene root can opt in with a marker.")


## Slider value changes stay quiet; moving vertically still uses the Menu bus.
func test_slider_vertical_navigation_routes_to_menu_bus() -> void:
	var slider := HSlider.new()
	add_child_autofree(slider)

	for action: String in ["ui_left", "ui_right"]:
		UiManager._handle_ui_navigation_action(action, slider, true)
	_assert_sfx_not_called()
	for action: String in ["ui_up", "ui_down"]:
		UiManager._handle_ui_navigation_action(action, slider, true)
	assert_eq(SfxManager.get("sfx_calls"), [
		["ui_navigation", AudioConstants.BUS_SFX_MENU],
		["ui_navigation", AudioConstants.BUS_SFX_MENU],
	])


## Releasing a key must not emit a second Menu-bus sound after its press.
func test_released_navigation_and_cancel_actions_are_silent() -> void:
	_set_menu_context(true)
	for action: String in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_cancel"]:
		var event: InputEventAction = _action_event(action)
		event.pressed = false
		_simulate_input(event)
	_assert_sfx_not_called()
