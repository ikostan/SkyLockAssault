## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_hidden_menu_stack.gd
##
## HMS: freed entries on Globals.hidden_menus (#1211).
##
## A menu freed while it is still on the stack leaves a stale entry. Every path that restores
## the previous menu pops through Globals.pop_hidden_menu(), which discards freed entries and
## returns the nearest live menu. Before the fix, a typed `var prev_menu: Node = pop_back()`
## raised "Trying to assign invalid previously freed instance" and stopped the function.
##
## Each per-path test puts a freed entry on top of a live menu: the function must finish
## (menu freed / state reset / rollback done) and show the live menu. Key Mapping and
## SettingsMenuBase are covered by KM-WEB-10, SMB-09 and SMB-14.

extends "res://addons/gut/test.gd"

const ADVANCED_SETTINGS_SCENE: String = "res://scenes/advanced_settings.tscn"

var _orig_previous_scene: String
var _orig_options_scene: PackedScene
var _orig_key_mapping_scene: PackedScene


func before_each() -> void:
	Globals.hidden_menus.clear()
	_orig_previous_scene = Globals.previous_scene
	_orig_options_scene = Globals.settings.options_scene
	_orig_key_mapping_scene = Globals.settings.key_mapping_scene
	# Audio Back falls back to this scene when no live menu is left; blank it so the test
	# runner's scene is never replaced.
	Globals.previous_scene = ""


func after_each() -> void:
	Globals.hidden_menus.clear()
	Globals.previous_scene = _orig_previous_scene
	Globals.settings.options_scene = _orig_options_scene
	Globals.settings.key_mapping_scene = _orig_key_mapping_scene
	Globals.options_open = false
	Globals.options_instance = null


# ==============================================================================
# HELPERS
# ==============================================================================


## Adds a hidden live menu to the tree and pushes it onto the stack.
func _push_live_menu(menu_name: String = "LiveMenu") -> Panel:
	var menu: Panel = Panel.new()
	menu.name = menu_name
	add_child_autofree(menu)
	menu.hide()
	Globals.hidden_menus.push_back(menu)
	return menu


## Pushes a menu onto the stack and frees it while it is still there.
func _push_freed_menu() -> void:
	var stale: Panel = Panel.new()
	Globals.hidden_menus.push_back(stale)
	stale.free()


## A live menu with the button Advanced Settings Back focuses on the Options menu.
func _push_options_like_menu() -> Control:
	var menu: Control = Control.new()
	menu.name = "OptionsLike"
	var panel: Panel = Panel.new()
	panel.name = "Panel"
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "OptionsVBoxContainer"
	var button: Button = Button.new()
	button.name = "AdvancedSettingsButton"
	box.add_child(button)
	panel.add_child(box)
	menu.add_child(panel)
	add_child_autofree(menu)
	menu.hide()
	Globals.hidden_menus.push_back(menu)
	return menu


# ==============================================================================
# Globals.pop_hidden_menu()
# ==============================================================================


## HMS-01 | Empty stack: returns null
func test_hms_01_pop_empty_stack_returns_null() -> void:
	assert_null(Globals.pop_hidden_menu())
	assert_true(Globals.hidden_menus.is_empty())


## HMS-02 | Only freed entries: all are popped and null is returned
func test_hms_02_pop_only_freed_entries_returns_null() -> void:
	_push_freed_menu()
	_push_freed_menu()

	assert_null(Globals.pop_hidden_menu())
	assert_true(Globals.hidden_menus.is_empty(), "Every freed entry is discarded")


## HMS-03 | Freed entry above a live menu: the live menu is returned, the menu below it is
## kept, and nothing is shown (showing is the caller's job)
func test_hms_03_pop_freed_entry_above_live_menu() -> void:
	var lower: Panel = _push_live_menu("LowerMenu")
	var live: Panel = _push_live_menu("LiveMenu")
	_push_freed_menu()

	var popped: Node = Globals.pop_hidden_menu()

	assert_eq(popped, live, "The nearest live menu is returned")
	assert_eq(Globals.hidden_menus, [lower], "Only the freed entry and the live menu are popped")
	assert_false(live.visible, "The helper only pops")


## HMS-04 | Live menu on top: it is returned and nothing else is popped
func test_hms_04_pop_live_menu_on_top() -> void:
	var lower: Panel = _push_live_menu("LowerMenu")
	var top: Panel = _push_live_menu("TopMenu")

	assert_eq(Globals.pop_hidden_menu(), top)
	assert_eq(Globals.hidden_menus, [lower])


# ==============================================================================
# OPTIONS MENU
# ==============================================================================


## HMS-05 | Options Back (_teardown) with a freed entry on top: the live menu is shown and
## options_open / options_instance are reset
func test_hms_05_options_teardown_skips_freed_entry() -> void:
	var options: CanvasLayer = load(GamePaths.OPTIONS_MENU_SCENE).instantiate()
	add_child_autofree(options)
	Globals.options_open = true
	Globals.options_instance = options
	var live: Panel = _push_live_menu()
	_push_freed_menu()

	options._on_options_back_button_pressed()

	assert_true(live.visible, "The live menu below the freed entry is shown")
	assert_true(Globals.hidden_menus.is_empty())
	assert_false(Globals.options_open, "options_open is reset")
	assert_null(Globals.options_instance, "options_instance is reset")
	assert_true(options.is_queued_for_deletion())


# ==============================================================================
# AUDIO SETTINGS
# ==============================================================================


## HMS-06 | Audio Back with a freed entry on top: the live menu is shown and Audio is freed
func test_hms_06_audio_back_skips_freed_entry() -> void:
	var audio: Control = load(GamePaths.AUDIO_SETTINGS_SCENE).instantiate()
	add_child_autofree(audio)
	var live: Panel = _push_live_menu()
	_push_freed_menu()

	audio._on_back_button_pressed()

	assert_true(live.visible, "The live menu below the freed entry is shown")
	assert_true(Globals.hidden_menus.is_empty())
	assert_true(audio.is_queued_for_deletion(), "The player is not stuck in Audio Settings")


## HMS-07 | Audio Back with only freed entries: handled like an empty stack (the
## previous_scene fallback, blanked here), and Audio is still freed
func test_hms_07_audio_back_only_freed_entries_still_closes() -> void:
	var audio: Control = load(GamePaths.AUDIO_SETTINGS_SCENE).instantiate()
	add_child_autofree(audio)
	_push_freed_menu()

	audio._on_back_button_pressed()

	assert_true(Globals.hidden_menus.is_empty())
	assert_true(audio.is_queued_for_deletion())


## HMS-08 | Audio unexpected exit with a freed entry on top: the live menu is shown
func test_hms_08_audio_unexpected_exit_skips_freed_entry() -> void:
	var audio: Control = load(GamePaths.AUDIO_SETTINGS_SCENE).instantiate()
	add_child(audio)
	var live: Panel = _push_live_menu()
	_push_freed_menu()

	audio.queue_free()
	await get_tree().process_frame

	assert_false(is_instance_valid(audio))
	assert_true(live.visible, "The live menu below the freed entry is shown")
	assert_true(Globals.hidden_menus.is_empty())


# ==============================================================================
# ADVANCED SETTINGS
# ==============================================================================


## HMS-09 | Advanced Back with a freed entry on top: the live menu is shown and Advanced is
## freed
func test_hms_09_advanced_back_skips_freed_entry() -> void:
	var advanced: Control = load(ADVANCED_SETTINGS_SCENE).instantiate()
	add_child_autofree(advanced)
	var live: Control = _push_options_like_menu()
	_push_freed_menu()

	advanced._on_advanced_back_button_pressed()

	assert_true(live.visible, "The live menu below the freed entry is shown")
	assert_true(Globals.hidden_menus.is_empty())
	assert_true(advanced.is_queued_for_deletion())


## HMS-10 | Advanced unexpected exit with a freed entry on top: the live menu is shown
func test_hms_10_advanced_unexpected_exit_skips_freed_entry() -> void:
	var advanced: Control = load(ADVANCED_SETTINGS_SCENE).instantiate()
	add_child(advanced)
	var live: Panel = _push_live_menu()
	_push_freed_menu()

	advanced.queue_free()
	await get_tree().process_frame

	assert_false(is_instance_valid(advanced))
	assert_true(live.visible, "The live menu below the freed entry is shown")
	assert_true(Globals.hidden_menus.is_empty())


# ==============================================================================
# GLOBALS RECOVERY PATHS
# ==============================================================================


## HMS-11 | load_key_mapping() with no Key Mapping scene: the rollback skips the freed entry
## and shows the live menu
func test_hms_11_load_key_mapping_rollback_skips_freed_entry() -> void:
	Globals.settings.key_mapping_scene = null
	var live: Panel = _push_live_menu()
	_push_freed_menu()

	Globals.load_key_mapping(null)

	assert_true(live.visible, "Rollback shows the live menu")
	assert_true(Globals.hidden_menus.is_empty())


## HMS-12 | Options exits unexpectedly with a freed entry on top: the live menu is shown and
## options_open / options_instance are reset
func test_hms_12_options_exited_unexpectedly_skips_freed_entry() -> void:
	Globals.options_open = true
	Globals.options_instance = null
	var live: Panel = _push_live_menu()
	_push_freed_menu()

	Globals._on_options_exited_unexpectedly()

	assert_true(live.visible, "The live menu below the freed entry is shown")
	assert_true(Globals.hidden_menus.is_empty())
	assert_false(Globals.options_open, "options_open is reset")
	assert_null(Globals.options_instance, "options_instance is reset")


## HMS-13 | load_options() with no Options scene: the rollback skips the freed entry and
## shows the live menu
func test_hms_13_load_options_missing_scene_rollback_skips_freed_entry() -> void:
	Globals.settings.options_scene = null
	var live: Panel = _push_live_menu()
	_push_freed_menu()

	Globals.load_options(null)

	assert_true(live.visible, "Rollback shows the live menu")
	assert_true(Globals.hidden_menus.is_empty())
	assert_false(Globals.options_open)


## HMS-14 | load_options() whose scene fails to instantiate: the rollback skips the freed
## entry, shows the live menu and resets options_open
func test_hms_14_load_options_instantiate_failure_rollback_skips_freed_entry() -> void:
	Globals.settings.options_scene = PackedScene.new()  # Empty: instantiate() returns null
	var live: Panel = _push_live_menu()
	_push_freed_menu()

	Globals.load_options(null)

	assert_engine_error("Failed to instantiate scene state")
	assert_true(live.visible, "Rollback shows the live menu")
	assert_true(Globals.hidden_menus.is_empty())
	assert_false(Globals.options_open, "options_open is reset")
	assert_null(Globals.options_instance)
