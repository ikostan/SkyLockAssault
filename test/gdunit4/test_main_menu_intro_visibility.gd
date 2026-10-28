## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## Unit tests for focus assignment at the end of the main-menu intro.

extends GdUnitTestSuite


## Runs the real intro without dialog, audio, video, or button-handler setup.
class IntroMenu:
	extends "res://scripts/ui/menus/main_menu.gd"

	var intro_finished: bool = false

	func _ready() -> void:
		pass

	func run_intro() -> void:
		await _run_fade_in_sequence()
		intro_finished = true

	func is_intro_finished() -> bool:
		return intro_finished

	func is_fading() -> bool:
		return menu.modulate.a > 0.0 and menu.modulate.a < 1.0


func after_test() -> void:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus_owner):
		focus_owner.release_focus()


## Local visibility is insufficient: any hidden ancestor must suppress intro focus.
func test_hidden_control_keeps_external_focus(
	hidden_path: String,
	_test_parameters := [
		["."],
		["VideoStreamPlayer/Panel"],
		["VideoStreamPlayer/Panel/VBoxContainer"],
		["VideoStreamPlayer/Panel/VBoxContainer/StartButton"],
	]
) -> void:
	var main_menu: IntroMenu = _create_menu()
	var external_button: Button = _focus_external_button()
	main_menu.run_intro()
	var hidden_control: Control = main_menu.get_node(hidden_path)
	hidden_control.hide()
	assert_bool(main_menu.start_button.is_visible_in_tree()).is_false()
	if hidden_control != main_menu.start_button:
		assert_bool(main_menu.start_button.visible).is_true()

	await _await_intro(main_menu)

	assert_object(get_viewport().gui_get_focus_owner()).is_same(external_button)
	assert_bool(external_button.is_visible_in_tree()).is_true()


## A visibility change after the delay must still be checked when the fade ends.
func test_hidden_during_fade_keeps_external_focus() -> void:
	var main_menu: IntroMenu = _create_menu(0.0, 0.3)
	var external_button: Button = _focus_external_button()
	main_menu.run_intro()
	await assert_func(main_menu, "is_fading").wait_until(1000).is_true()
	main_menu.menu.hide()

	await _await_intro(main_menu)

	assert_object(get_viewport().gui_get_focus_owner()).is_same(external_button)
	assert_bool(main_menu.start_button.is_visible_in_tree()).is_false()


## A hidden intro must not create a focus owner when there was none.
func test_hidden_menu_leaves_focus_unassigned() -> void:
	var main_menu: IntroMenu = _create_menu()
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus_owner):
		focus_owner.release_focus()
	main_menu.run_intro()
	main_menu.menu.hide()
	assert_object(get_viewport().gui_get_focus_owner()).is_null()

	await _await_intro(main_menu)

	assert_object(get_viewport().gui_get_focus_owner()).is_null()


## Only visibility at completion matters; a temporarily hidden panel can regain focus.
func test_menu_restored_before_intro_finishes_focuses_start() -> void:
	var main_menu: IntroMenu = _create_menu()
	_focus_external_button()
	main_menu.run_intro()
	main_menu.menu.hide()
	await await_idle_frame()
	assert_bool(main_menu.is_intro_finished()).is_false()
	main_menu.menu.show()

	await _await_intro(main_menu)

	assert_object(get_viewport().gui_get_focus_owner()).is_same(main_menu.start_button)


## Intro completion preserves a player's selection within the visible menu.
func test_visible_intro_preserves_existing_menu_focus(
	button_name: String, _test_parameters := [["OptionsButton"], ["QuitButton"]]
) -> void:
	var main_menu: IntroMenu = _create_menu()
	var selected_button: Button = main_menu.ui_container.get_node(button_name)
	selected_button.grab_focus()
	main_menu.run_intro()

	await _await_intro(main_menu)

	assert_object(get_viewport().gui_get_focus_owner()).is_same(selected_button)


## Exported durations permit zero; the visibility guard must still apply.
func test_zero_duration_intro_respects_visibility(
	hidden: bool, _test_parameters := [[false], [true]]
) -> void:
	var main_menu: IntroMenu = _create_menu(0.0, 0.0)
	var external_button: Button = _focus_external_button()
	main_menu.run_intro()
	main_menu.menu.visible = not hidden

	await _await_intro(main_menu)

	var expected_focus: Control = external_button if hidden else main_menu.start_button
	assert_object(get_viewport().gui_get_focus_owner()).is_same(expected_focus)


func _create_menu(delay: float = 0.1, duration: float = 0.0) -> IntroMenu:
	var main_menu: IntroMenu = auto_free(IntroMenu.new())
	main_menu.intro_delay = delay
	main_menu.fade_duration = duration
	# Supply only the nodes required by main_menu.gd's inherited @onready bindings.
	var video: VideoStreamPlayer = VideoStreamPlayer.new()
	video.name = "VideoStreamPlayer"
	main_menu.add_child(video)
	var panel: Panel = Panel.new()
	panel.name = "Panel"
	video.add_child(panel)
	var buttons: VBoxContainer = VBoxContainer.new()
	buttons.name = "VBoxContainer"
	panel.add_child(buttons)
	for button_name: String in ["StartButton", "OptionsButton", "QuitButton"]:
		var button: Button = Button.new()
		button.name = button_name
		buttons.add_child(button)
	var audio: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	audio.name = "AudioStreamPlayer2D"
	main_menu.add_child(audio)
	add_child(main_menu)
	return main_menu


func _focus_external_button() -> Button:
	var button: Button = auto_free(Button.new())
	add_child(button)
	button.grab_focus()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(button)
	return button


func _await_intro(main_menu: IntroMenu) -> void:
	await assert_func(main_menu, "is_intro_finished").wait_until(1000).is_true()
	# ensure_initial_focus() defers grab_focus(), so let it execute before asserting.
	await await_idle_frame()
