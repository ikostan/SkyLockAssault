# gdlint: disable=max-public-methods
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
## Each Back / exit test puts a freed entry on top of a live menu: the function must finish
## (menu freed / state reset) and show the live menu. The failed-load rollbacks
## (HMS-11, 13, 14) undo only their own push, so another screen's menu stays on the stack.
## Key Mapping and SettingsMenuBase are covered by KM-WEB-10, SMB-09 and SMB-14.
##
## HMS-15 to HMS-25 cover the edges: consecutive pops over freed and null entries, what
## Globals._roll_back_hidden_menu() promises when called directly, Options exit handling
## with only freed entries or a newer live instance, and Back followed by the menu's own tree
## exit, which must restore only one menu.

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


## Leaves another screen's hidden live menu on the stack with a freed entry above it, as a
## failed load finds it. Returns the live menu.
func _push_unrelated_with_freed_above() -> Panel:
	var unrelated: Panel = _push_live_menu("UnrelatedMenu")
	_push_freed_menu()
	return unrelated


## A visible menu in the tree for a load to hide.
func _new_caller() -> Panel:
	var caller: Panel = Panel.new()
	caller.name = "CallerMenu"
	add_child_autofree(caller)
	return caller


## The failed load removed only its own entry (and showed its caller again); the unrelated
## menu and the freed entry above it are still on the stack, and the unrelated menu stays
## hidden.
func _assert_only_own_entry_rolled_back(unrelated: Panel, caller: Panel, case: String) -> void:
	assert_eq(Globals.hidden_menus.size(), 2, case + ": unrelated + freed entries left alone")
	assert_eq(Globals.hidden_menus[0], unrelated, case + ": unrelated menu still on the stack")
	assert_false(unrelated.visible, case + ": unrelated menu not shown")
	if caller != null:
		assert_true(caller.visible, case + ": caller shown again")
		assert_false(Globals.hidden_menus.has(caller), case + ": caller's entry removed")


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


## HMS-11 | load_key_mapping() with no Key Mapping scene: the rollback undoes only this
## load's push. A freed entry above another screen's live menu doesn't make it pop and show
## that menu, with or without a caller to hide
func test_hms_11_load_key_mapping_rollback_keeps_unrelated_menu() -> void:
	Globals.settings.key_mapping_scene = null
	for with_caller: bool in [false, true]:
		var case := "with caller" if with_caller else "null caller"
		var unrelated := _push_unrelated_with_freed_above()
		var caller: Panel = _new_caller() if with_caller else null

		Globals.load_key_mapping(caller)

		_assert_only_own_entry_rolled_back(unrelated, caller, case)
		Globals.hidden_menus.clear()


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


## HMS-13 | load_options() with no Options scene: the rollback undoes only this load's push
## and leaves another screen's live menu on the stack, with or without a caller to hide
func test_hms_13_load_options_missing_scene_rollback_keeps_unrelated_menu() -> void:
	Globals.settings.options_scene = null
	for with_caller: bool in [false, true]:
		var case := "with caller" if with_caller else "null caller"
		var unrelated := _push_unrelated_with_freed_above()
		var caller: Panel = _new_caller() if with_caller else null

		Globals.load_options(caller)

		_assert_only_own_entry_rolled_back(unrelated, caller, case)
		assert_false(Globals.options_open, case + ": options_open stays false")
		Globals.hidden_menus.clear()


## HMS-14 | load_options() whose scene fails to instantiate: the rollback undoes only this
## load's push, leaves another screen's live menu on the stack and resets options_open
func test_hms_14_load_options_instantiate_failure_rollback_keeps_unrelated_menu() -> void:
	Globals.settings.options_scene = PackedScene.new()  # Empty: instantiate() returns null
	for with_caller: bool in [false, true]:
		var case := "with caller" if with_caller else "null caller"
		var unrelated := _push_unrelated_with_freed_above()
		var caller: Panel = _new_caller() if with_caller else null

		Globals.load_options(caller)

		assert_engine_error("Failed to instantiate scene state")
		_assert_only_own_entry_rolled_back(unrelated, caller, case)
		assert_false(Globals.options_open, case + ": options_open is reset")
		assert_null(Globals.options_instance, case)
		Globals.hidden_menus.clear()


# ==============================================================================
# ROLLBACK AND OPTIONS EXIT BOUNDARIES
# ==============================================================================


## HMS-15 | Consecutive pops over freed and null entries: each returns the next live menu in
## LIFO order, keeps the entries below it, and shows nothing; popping an empty stack is safe
func test_hms_15_pop_mixed_stack_preserves_lifo_order_without_showing_menus() -> void:
	var lower: Panel = _push_live_menu("LowerMenu")
	_push_freed_menu()
	var upper: Panel = _push_live_menu("UpperMenu")
	Globals.hidden_menus.push_back(null)
	_push_freed_menu()

	assert_eq(Globals.pop_hidden_menu(), upper)
	assert_eq(Globals.hidden_menus.size(), 2, "Entries below the returned menu stay queued")
	assert_false(upper.visible, "Popping must leave visibility to the caller")
	assert_eq(Globals.pop_hidden_menu(), lower)
	assert_false(lower.visible)
	assert_null(Globals.pop_hidden_menu(), "Repeated pops after exhaustion are safe")
	assert_true(Globals.hidden_menus.is_empty())


## HMS-16 | Rollback when the load pushed nothing: even a live menu on top is left on the
## stack and hidden
func test_hms_16_rollback_null_preserves_unrelated_live_top() -> void:
	var unrelated: Panel = _push_live_menu()

	assert_false(Globals._roll_back_hidden_menu(null))
	assert_eq(Globals.hidden_menus, [unrelated])
	assert_false(unrelated.visible)


## HMS-17 | Rollback of a menu that isn't on the stack: returns false, pops nothing and
## shows neither that menu nor the one on the stack
func test_hms_17_rollback_absent_menu_leaves_stack_and_caller_untouched() -> void:
	var unrelated: Panel = _push_live_menu()
	var absent: Panel = _new_caller()
	absent.hide()

	assert_false(Globals._roll_back_hidden_menu(absent))
	assert_eq(Globals.hidden_menus, [unrelated])
	assert_false(unrelated.visible)
	assert_false(absent.visible, "An entry that was never pushed is not restored")


## HMS-18 | Rollback with the caller on the stack twice: only its last entry is removed, and
## a menu pushed after it stays on the stack and hidden. Checks the helper's contract
## directly; in the game a failed load rolls back right after its own push.
func test_hms_18_rollback_removes_last_matching_entry_only() -> void:
	var caller: Panel = _push_live_menu("Caller")
	var middle: Panel = _push_live_menu("Middle")
	Globals.hidden_menus.push_back(caller)
	var top: Panel = _push_live_menu("Top")

	assert_true(Globals._roll_back_hidden_menu(caller))
	assert_eq(Globals.hidden_menus, [caller, middle, top])
	assert_true(caller.visible)
	assert_false(middle.visible)
	assert_false(top.visible, "A later screen's entry must not be shown by rollback")


## HMS-19 | Rollback with a freed entry above the caller: the caller's entry is removed from
## the middle, the freed entry and the menu below are kept, and only the caller is shown.
## Checks the helper's contract directly; in the game the caller is on top.
func test_hms_19_rollback_preserves_freed_entries_above_caller() -> void:
	var lower: Panel = _push_live_menu("Lower")
	var caller: Panel = _push_live_menu("Caller")
	_push_freed_menu()

	assert_true(Globals._roll_back_hidden_menu(caller))
	assert_true(caller.visible)
	assert_eq(Globals.hidden_menus.size(), 2)
	assert_eq(Globals.hidden_menus[0], lower)
	assert_false(is_instance_valid(Globals.hidden_menus[1]))
	assert_false(lower.visible)


## HMS-20 | A second rollback of the same menu does nothing: the menu below stays on the
## stack and hidden
func test_hms_20_rollback_twice_does_not_consume_previous_menu() -> void:
	var lower: Panel = _push_live_menu("Lower")
	var caller: Panel = _push_live_menu("Caller")

	assert_true(Globals._roll_back_hidden_menu(caller))
	caller.hide()
	assert_false(Globals._roll_back_hidden_menu(caller))
	assert_eq(Globals.hidden_menus, [lower])
	assert_false(lower.visible)
	assert_false(caller.visible)


## HMS-21 | Options exits unexpectedly with only freed entries: they are discarded and
## options_open / options_instance are still reset
func test_hms_21_options_unexpected_exit_with_only_freed_entries_resets_state() -> void:
	Globals.options_open = true
	Globals.options_instance = null
	_push_freed_menu()
	_push_freed_menu()

	Globals._on_options_exited_unexpectedly()

	assert_true(Globals.hidden_menus.is_empty())
	assert_false(Globals.options_open)
	assert_null(Globals.options_instance)


## HMS-22 | An older Options exit while a newer instance is in the tree: the handler leaves
## the Options state, the stack (freed entry included) and the live menu alone
func test_hms_22_options_unexpected_exit_preserves_current_live_instance() -> void:
	var current: CanvasLayer = CanvasLayer.new()
	add_child_autofree(current)
	Globals.options_instance = current
	Globals.options_open = true
	var live: Panel = _push_live_menu()
	_push_freed_menu()

	Globals._on_options_exited_unexpectedly()

	assert_eq(Globals.options_instance, current)
	assert_true(Globals.options_open)
	assert_eq(Globals.hidden_menus.size(), 2)
	assert_eq(Globals.hidden_menus[0], live)
	assert_false(is_instance_valid(Globals.hidden_menus[1]))
	assert_false(live.visible)


# ==============================================================================
# BACK FOLLOWED BY TREE EXIT
# ==============================================================================


## HMS-23 | Audio Back, then Audio's own tree exit: Back skips the freed entries and shows the
## nearest menu; the intentional exit doesn't pop and show the menu below it
func test_hms_23_audio_back_then_tree_exit_keeps_lower_menu_hidden() -> void:
	var audio: Control = load(GamePaths.AUDIO_SETTINGS_SCENE).instantiate()
	add_child(audio)
	var lower: Panel = _push_live_menu("Lower")
	var nearest: Panel = _push_live_menu("Nearest")
	_push_freed_menu()
	_push_freed_menu()

	audio._on_back_button_pressed()
	await get_tree().process_frame

	assert_false(is_instance_valid(audio))
	assert_true(nearest.visible)
	assert_false(lower.visible, "Intentional tree exit must not restore a second ancestor")
	assert_eq(Globals.hidden_menus, [lower])


## HMS-24 | Advanced Back, then Advanced's own tree exit: Back skips the freed entries and
## shows the nearest menu; the intentional exit doesn't pop and show the menu below it
func test_hms_24_advanced_back_then_tree_exit_keeps_lower_menu_hidden() -> void:
	var advanced: Control = load(ADVANCED_SETTINGS_SCENE).instantiate()
	add_child(advanced)
	var lower: Panel = _push_live_menu("Lower")
	var nearest: Control = _push_options_like_menu()
	_push_freed_menu()
	_push_freed_menu()

	advanced._on_advanced_back_button_pressed()
	await get_tree().process_frame

	assert_false(is_instance_valid(advanced))
	assert_true(nearest.visible)
	assert_false(lower.visible, "Intentional tree exit must not restore a second ancestor")
	assert_eq(Globals.hidden_menus, [lower])


## HMS-25 | Options Back, then Options' own tree exit, opened through Globals.load_options() so
## Globals' tree_exited handler is connected as in the game: teardown runs once, shows the
## nearest menu and resets the Options state; neither the second teardown nor Globals' exit
## handler pops the menu below it
func test_hms_25_options_back_then_tree_exit_keeps_lower_menu_hidden() -> void:
	var lower: Panel = _push_live_menu("Lower")
	var nearest: Panel = _push_live_menu("Nearest")
	_push_freed_menu()
	_push_freed_menu()
	Globals.load_options(null)  # Nearest is already hidden and on the stack
	var options: CanvasLayer = Globals.options_instance
	assert_true(
		options.tree_exited.is_connected(Globals._on_options_exited_unexpectedly),
		"Options is wired as in the game"
	)
	await get_tree().process_frame  # let _ready()'s deferred focus calls run

	options._on_options_back_button_pressed()
	await get_tree().process_frame

	assert_false(is_instance_valid(options))
	assert_true(nearest.visible)
	assert_false(lower.visible, "Repeated teardown must not consume a second ancestor")
	assert_eq(Globals.hidden_menus, [lower])
	assert_false(Globals.options_open)
	assert_null(Globals.options_instance)
