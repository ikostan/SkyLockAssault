## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_main_menu_intro_focus.gd
##
## The main menu's intro ends by giving StartButton focus. If Options was opened during the
## intro, that must not move focus away from the Options menu to the hidden main menu.

extends GdUnitTestSuite

const MAIN_MENU_PATH: String = "res://scenes/main_menu.tscn"

var _original_options_open: bool


func before_test() -> void:
	_original_options_open = Globals.options_open


func after_test() -> void:
	if is_instance_valid(Globals.options_instance):
		Globals.options_instance.free()
	Globals.hidden_menus.clear()
	Globals.options_open = _original_options_open


## Options opened before the intro finishes keeps focus once the intro ends.
func test_intro_does_not_steal_focus_from_options() -> void:
	var main_menu: Node = auto_free(load(MAIN_MENU_PATH).instantiate())
	main_menu.intro_delay = 0.1
	main_menu.fade_duration = 0.1
	add_child(main_menu)
	await await_idle_frame()

	Globals.load_options(main_menu.get_node("VideoStreamPlayer/Panel"))
	await await_idle_frame()
	await await_idle_frame()
	var options_focus: Control = get_viewport().gui_get_focus_owner()
	assert_object(options_focus).is_not_null()

	await get_tree().create_timer(0.4).timeout
	await await_idle_frame()

	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	assert_object(focus_owner).is_same(options_focus)
	assert_bool(focus_owner.is_visible_in_tree()).is_true()


## With nothing opened over it, the intro still focuses StartButton.
func test_intro_focuses_start_button_when_visible() -> void:
	var main_menu: Node = auto_free(load(MAIN_MENU_PATH).instantiate())
	main_menu.intro_delay = 0.1
	main_menu.fade_duration = 0.1
	add_child(main_menu)

	await get_tree().create_timer(0.4).timeout
	await await_idle_frame()

	var start_button: Button = main_menu.get_node(
		"VideoStreamPlayer/Panel/VBoxContainer/StartButton"
	)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(start_button)
