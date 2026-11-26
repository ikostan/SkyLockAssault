## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_quit_game_confirm_dialog_sfx.gd
## GUT unit tests for main menu quit dialog confirmation audio pathways.

extends GutTest

# FIX: Load the PackedScene layout to build the required @onready subnode tree hierarchy
var MainMenuScene: PackedScene = load("res://scenes/main_menu.tscn")
var main_menu_instance: Control
var original_audio_script: Script
var original_fields := {}


## Suite setup: Double the SfxManager using an inherited script to preserve real node-wiring behavior.
## :rtype: void
func before_all() -> void:
	if is_instance_valid(SfxManager):
		original_audio_script = SfxManager.get_script()
		var script_path: String = original_audio_script.resource_path
		var mock_script := GDScript.new()
		
		# FIX (Sourcery-AI): Inherit directly from the production script so all real validation,
		# tree tracking, and filtering logic remain active. We only override play_sfx to spy on output.
		mock_script.source_code = """
extends "%s"

var sfx_calls: Array = []

# Override play_sfx matching the production signature to intercept audio calls safely
func play_sfx(sfx_name: String, bus_name: String = "SFX_Menu", pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	sfx_calls.append([sfx_name, bus_name])
""" % script_path
		
		mock_script.reload()
		SfxManager.set_script(mock_script)


## Suite cleanup: Safely restore original production script after all tests execute.
## :rtype: void
func after_all() -> void:
	if original_audio_script and is_instance_valid(SfxManager):
		SfxManager.set_script(original_audio_script)
		# FIX: Re-populate and rebuild the internal variable states wiped by set_script()
		if SfxManager.has_method("cleanup_for_test"):
			SfxManager.cleanup_for_test()


## Per-test setup: Instantiate target menu scene layout tree and clear call logs.
## :rtype: void
func before_each() -> void:
	# Instantiate the scene instead of using script.new() to initialize @onready child nodes
	main_menu_instance = MainMenuScene.instantiate() as Control
	
	# FIX: Turn on the safety guard to block get_tree().quit() from crashing the runner
	if "bypass_quit_for_testing" in main_menu_instance:
		main_menu_instance.set("bypass_quit_for_testing", true)
		
	add_child_autofree(main_menu_instance)
	
	if SfxManager.get("sfx_calls") != null:
		SfxManager.set("sfx_calls", [])
		
	await get_tree().process_frame


## Per-test cleanup: Release active control focuses cleanly.
## :rtype: void
func after_each() -> void:
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
	assert_eq(actual_count, count, "Expected play_sfx to be called %d times. Got %d." % [count, actual_count])


func _assert_sfx_not_called(key: String) -> void:
	var found := false
	var calls: Array = SfxManager.get("sfx_calls")
	for c: Array in calls:
		if c[0] == key:
			found = true
			break
	assert_false(found, "Expected play_sfx NOT to be called with: " + key)


## Assert that calling the localized _on_quit_dialog_confirmed sequence triggers an accept chime.
## :rtype: void
func test_dialog_confirmation_audio() -> void:
	if main_menu_instance.has_method("_on_quit_dialog_confirmed"):
		main_menu_instance._on_quit_dialog_confirmed()
		
	_assert_sfx_called("ui_accept")
	_assert_sfx_call_count(1)


## Assert that invoking the localized _on_quit_dialog_canceled sequence triggers a cancellation sound.
## :rtype: void
func test_dialog_cancellation_audio() -> void:
	if main_menu_instance.has_method("_on_quit_dialog_canceled"):
		main_menu_instance._on_quit_dialog_canceled()
		
	_assert_sfx_called("ui_cancel")
	_assert_sfx_call_count(1)


# ==========================================================================
# #1169 CONFIRM-FIRST: THE QUIT DIALOG NEEDS NO HANDLER SANITIZING
# ==========================================================================

## Counts connections on [param button]'s pressed signal to any method named
## _on_global_button_pressed, whichever object owns it (SfxManager or the old Globals hook).
func _count_global_sound_connections(button: BaseButton) -> int:
	var count: int = 0
	for connection: Dictionary in button.pressed.get_connections():
		var callable: Callable = connection.get("callable", Callable())
		if callable.get_method() == "_on_global_button_pressed":
			count += 1
	return count


## The global click sound handler lives on SfxManager only; Globals no longer has one.
func test_globals_has_no_global_button_sound_handler() -> void:
	assert_false(
		Globals.has_method("_on_global_button_pressed"),
		"Globals must not own a global button sound handler; SfxManager does."
	)
	assert_true(
		SfxManager.has_method("_on_global_button_pressed"),
		"SfxManager must own the global button sound handler."
	)


## SfxManager never hooks the internal OK and Cancel buttons of a dialog, even one that
## main_menu.gd never touches, so the quit dialog has nothing to disconnect.
func test_sfx_manager_skips_internal_dialog_buttons() -> void:
	var dialog := ConfirmationDialog.new()
	add_child_autofree(dialog)
	await wait_process_frames(2)

	assert_eq(
		_count_global_sound_connections(dialog.get_ok_button()),
		0,
		"SfxManager must not connect to a dialog's internal OK button."
	)
	assert_eq(
		_count_global_sound_connections(dialog.get_cancel_button()),
		0,
		"SfxManager must not connect to a dialog's internal Cancel button."
	)


## The main menu's quit dialog buttons have no global sound connection.
func test_quit_dialog_buttons_have_no_global_sound_connection() -> void:
	var dialog: ConfirmationDialog = main_menu_instance.quit_dialog
	assert_true(is_instance_valid(dialog), "Quit dialog must be found.")
	assert_eq(
		_count_global_sound_connections(dialog.get_ok_button()),
		0,
		"Quit dialog OK button must have no global sound connection."
	)
	assert_eq(
		_count_global_sound_connections(dialog.get_cancel_button()),
		0,
		"Quit dialog Cancel button must have no global sound connection."
	)


## Pressing the quit dialog's OK button plays exactly one accept sound.
func test_quit_dialog_ok_button_plays_one_sound() -> void:
	var dialog: ConfirmationDialog = main_menu_instance.quit_dialog
	dialog.get_ok_button().pressed.emit()
	# Deferred handlers (CONNECT_DEFERRED) would fire here, so wait before counting.
	await wait_process_frames(2)

	_assert_sfx_called("ui_accept")
	_assert_sfx_call_count(1)


## Pressing the quit dialog's Cancel button plays exactly one cancel sound.
func test_quit_dialog_cancel_button_plays_one_sound() -> void:
	var dialog: ConfirmationDialog = main_menu_instance.quit_dialog
	dialog.get_cancel_button().pressed.emit()
	await wait_process_frames(2)

	_assert_sfx_called("ui_cancel")
	_assert_sfx_not_called("ui_accept")
	_assert_sfx_call_count(1)


## Setting the dialog up again keeps one confirmed and one canceled connection.
func test_quit_dialog_setup_keeps_single_confirm_and_cancel_connections() -> void:
	main_menu_instance._setup_quit_dialog()
	var dialog: ConfirmationDialog = main_menu_instance.quit_dialog
	var confirmed_count: int = 0
	for connection: Dictionary in dialog.confirmed.get_connections():
		if connection.callable == main_menu_instance._on_quit_dialog_confirmed:
			confirmed_count += 1
	var canceled_count: int = 0
	for connection: Dictionary in dialog.canceled.get_connections():
		if connection.callable == main_menu_instance._on_quit_dialog_canceled:
			canceled_count += 1
	assert_eq(confirmed_count, 1, "Exactly one confirmed connection.")
	assert_eq(canceled_count, 1, "Exactly one canceled connection.")
	assert_false(dialog.visible, "Setup leaves the dialog hidden.")
