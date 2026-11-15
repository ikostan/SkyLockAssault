## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_main_menu_settings_reset_notice.gd
##
## When Globals moves an unreadable save file aside, the main menu shows a short notice once.
## The notice must not take focus or block the menu buttons (#1144).
##
## Issue: https://github.com/ikostan/SkyLockAssault/issues/1144

extends GdUnitTestSuite

const MAIN_MENU_PATH: String = "res://scenes/main_menu.tscn"
const NOTICE_PATH: String = "VideoStreamPlayer/SettingsResetNotice"
const START_BUTTON_PATH: String = "VideoStreamPlayer/Panel/VBoxContainer/StartButton"

var _original_notice_pending: bool


func before_test() -> void:
	_original_notice_pending = Globals._settings_reset_notice_pending


func after_test() -> void:
	Globals._settings_reset_notice_pending = _original_notice_pending


## Creates the main menu with short intro and notice timings, then adds it to the tree.
func _add_main_menu(notice_duration: float) -> Node:
	var main_menu: Node = auto_free(load(MAIN_MENU_PATH).instantiate())
	main_menu.intro_delay = 0.1
	main_menu.fade_duration = 0.1
	main_menu.settings_reset_notice_duration = notice_duration
	add_child(main_menu)
	await await_idle_frame()
	return main_menu


## A pending reset shows the notice, consumes the flag, and hides the notice after its timeout.
func test_notice_shows_when_pending_and_hides_after_timeout() -> void:
	Globals._settings_reset_notice_pending = true

	var main_menu: Node = await _add_main_menu(0.2)
	var notice: Label = main_menu.get_node(NOTICE_PATH)

	assert_bool(notice.visible).is_true()
	assert_str(notice.text).is_equal("Settings could not be read and were reset.")
	assert_bool(Globals._settings_reset_notice_pending).is_false()

	await get_tree().create_timer(0.4).timeout
	await await_idle_frame()

	assert_bool(notice.visible).is_false()


## Without a pending reset the notice stays hidden.
func test_notice_stays_hidden_when_not_pending() -> void:
	Globals._settings_reset_notice_pending = false

	var main_menu: Node = await _add_main_menu(0.2)
	var notice: Label = main_menu.get_node(NOTICE_PATH)
	assert_bool(notice.visible).is_false()

	await get_tree().create_timer(0.4).timeout
	await await_idle_frame()

	assert_bool(notice.visible).is_false()


## The menu's first button keeps focus while the notice shows, and the notice can't take
## focus or catch mouse clicks.
func test_start_button_keeps_focus_while_notice_shows() -> void:
	Globals._settings_reset_notice_pending = true

	var main_menu: Node = await _add_main_menu(5.0)
	var notice: Label = main_menu.get_node(NOTICE_PATH)
	var start_button: Button = main_menu.get_node(START_BUTTON_PATH)

	assert_int(notice.focus_mode).is_equal(Control.FOCUS_NONE)
	assert_int(notice.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)

	# Intro (0.1 s) and fade (0.1 s) finish, then StartButton gets focus.
	await get_tree().create_timer(0.4).timeout
	await await_idle_frame()

	assert_bool(notice.visible).is_true()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(start_button)


## Recreating the menu must not redisplay a notice consumed by the previous instance.
func test_notice_is_not_repeated_on_menu_reload() -> void:
	Globals._settings_reset_notice_pending = true
	var first_menu: Node = await _add_main_menu(5.0)
	assert_bool((first_menu.get_node(NOTICE_PATH) as Label).visible).is_true()
	first_menu.queue_free()
	await await_idle_frame()

	var second_menu: Node = await _add_main_menu(5.0)

	assert_bool((second_menu.get_node(NOTICE_PATH) as Label).visible).is_false()
	assert_bool(Globals.consume_settings_reset_notice()).is_false()


## The exported minimum duration still consumes the notice and hides it on the next tick.
func test_zero_duration_notice_hides_after_timer_tick() -> void:
	Globals._settings_reset_notice_pending = true
	var main_menu: Node = auto_free(load(MAIN_MENU_PATH).instantiate())
	main_menu.intro_delay = 0.0
	main_menu.fade_duration = 0.0
	main_menu.settings_reset_notice_duration = 0.0
	add_child(main_menu)
	var notice: Label = main_menu.get_node(NOTICE_PATH)

	assert_bool(notice.visible).is_true()
	assert_bool(Globals.consume_settings_reset_notice()).is_false()
	await get_tree().create_timer(0.1).timeout
	await await_idle_frame()
	assert_bool(notice.visible).is_false()


## A timeout after the menu leaves the tree must not raise an error, and the consumed
## notice must not come back.
func test_notice_timeout_after_menu_leaves_tree() -> void:
	Globals._settings_reset_notice_pending = true
	var main_menu: Node = await _add_main_menu(0.2)
	remove_child(main_menu)

	await get_tree().create_timer(0.4).timeout
	await await_idle_frame()

	assert_bool(Globals.consume_settings_reset_notice()).override_failure_message(
		"the notice must stay consumed"
	).is_false()


## Removing the label while its timer runs must not cause access to a freed instance.
func test_notice_timeout_after_label_is_freed() -> void:
	Globals._settings_reset_notice_pending = true
	var main_menu: Node = await _add_main_menu(0.2)
	var notice: Label = main_menu.get_node(NOTICE_PATH)
	notice.queue_free()
	await await_idle_frame()

	await get_tree().create_timer(0.4).timeout
	await await_idle_frame()

	assert_bool(is_instance_valid(notice)).is_false()
	assert_bool(main_menu.is_inside_tree()).is_true()
	assert_bool(Globals.consume_settings_reset_notice()).is_false()
