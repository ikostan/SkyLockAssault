## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_gameplay_settings_exit_paths.gd
##
## GS-EXIT: "Step 0" for #480 (SettingsMenuBase).
## Pins down how gameplay_settings.gd leaves the tree (Back button vs. unexpected
## removal) and what that does to Globals.hidden_menus and the web overlays, so the
## base-class extraction can be checked against today's behavior.
##
## Tests marked CHARACTERIZATION assert what the code does TODAY, including behavior
## that may be unintended. If #480 deliberately changes it, flip the assertion in the
## same PR and say so in the PR description.

extends "res://addons/gut/test.gd"

var gameplay_menu: Control
var _mock_js: Variant
var _mock_window: Dictionary


func before_each() -> void:
	Globals.settings = GameSettingsResource.new()
	Globals.hidden_menus.clear()


func after_each() -> void:
	Globals.hidden_menus.clear()


# --- HELPERS ---


## Builds a gameplay settings menu and waits for _ready().
## web = true injects doubled wrappers so the web branches run; the doubled bridge
## is kept in _mock_js so tests can inspect eval() calls.
func _spawn_menu(web: bool) -> Control:
	var menu: Control = load(GamePaths.GAMEPLAY_SETTINGS_SCENE).instantiate()
	if web:
		_mock_js = double(JavaScriptBridgeWrapper).new()
		var mock_os: Variant = double(OSWrapper).new()
		stub(mock_os, "has_feature").to_return(true)
		# Non-empty Dictionary: an empty one is falsy and would skip the js_window branches.
		_mock_window = {"valid": true}
		stub(_mock_js, "get_interface").to_return(_mock_window)
		menu.os_wrapper = mock_os
		menu.js_bridge_wrapper = _mock_js
	else:
		menu.os_wrapper = OSWrapper.new()
	add_child_autofree(menu)
	await get_tree().process_frame
	return menu


## Pushes a hidden stand-in for a previous menu onto the global stack.
func _push_hidden_menu(menu_name: String) -> Control:
	var menu := Control.new()
	menu.name = menu_name
	menu.visible = false
	autofree(menu)
	Globals.hidden_menus.push_back(menu)
	return menu


## JS source of the most recent eval() call on the doubled bridge.
func _last_eval_code() -> String:
	return str(get_call_parameters(_mock_js, "eval")[0])


# --- BACK BUTTON PATH ---


## GS-EXIT-01 | Back button (desktop): pops exactly one menu, marks the exit intentional,
## and the real tree_exited that follows queue_free() does not pop again.
func test_gs_exit_01_back_button_pops_once_non_web() -> void:
	gameplay_menu = await _spawn_menu(false)
	var lower := _push_hidden_menu("LowerMenu")
	var upper := _push_hidden_menu("UpperMenu")

	gameplay_menu._on_gameplay_back_button_pressed()

	assert_true(gameplay_menu._intentional_exit, "Back button must mark the exit intentional")
	assert_true(upper.visible, "Top-of-stack menu must be restored")
	assert_false(lower.visible, "Menu below the top must stay hidden")
	assert_eq(Globals.hidden_menus.size(), 1, "Exactly one menu popped")
	assert_true(gameplay_menu.is_queued_for_deletion(), "Menu must be queued for deletion")

	# Let queue_free() run so the real tree_exited fires.
	await get_tree().process_frame
	assert_eq(Globals.hidden_menus.size(), 1, "tree_exited after Back must not pop again")
	assert_false(lower.visible, "tree_exited after Back must not restore a second menu")


## GS-EXIT-02 | Back button (web): same stack behavior, and the final DOM state hides
## the gameplay overlays without re-showing the Options overlays.
func test_gs_exit_02_back_button_pops_once_web() -> void:
	gameplay_menu = await _spawn_menu(true)
	var options := _push_hidden_menu("OptionsMock")

	gameplay_menu._on_gameplay_back_button_pressed()
	await get_tree().process_frame  # queue_free -> real tree_exited

	assert_true(options.visible, "Previous menu must be restored")
	assert_eq(Globals.hidden_menus.size(), 0, "Stack must be empty, with no double pop")
	var code := _last_eval_code()
	assert_true(code.contains("'none'"), "Last eval must hide the gameplay overlays")
	assert_false(code.contains("controls-button"), "tree_exited after Back must not re-show Options overlays")


# --- UNEXPECTED REMOVAL PATH ---


## GS-EXIT-03 | CHARACTERIZATION: unexpected removal on a non-web platform.
## Today the menu-stack restore in _on_tree_exited() sits inside the web-only branch,
## so on desktop the previous menu stays hidden and the stack keeps its entry.
## Globals._on_options_exited_unexpectedly() restores regardless of platform, so this
## is probably unintended. Decide in #480 whether to fix it; if so, flip these asserts.
func test_gs_exit_03_unexpected_removal_non_web_characterization() -> void:
	gameplay_menu = await _spawn_menu(false)
	var prev := _push_hidden_menu("OptionsMock")

	gameplay_menu.get_parent().remove_child(gameplay_menu)
	await get_tree().process_frame

	assert_false(gameplay_menu._intentional_exit, "Unexpected removal must not set the flag")
	assert_false(prev.visible, "CURRENT BEHAVIOR: previous menu is NOT restored off-web")
	assert_eq(Globals.hidden_menus.size(), 1, "CURRENT BEHAVIOR: stack entry is left in place off-web")


## GS-EXIT-04 | Unexpected removal (web) through a real remove_child(), not a direct
## _on_tree_exited() call: restores the previous menu and re-shows Options overlays.
func test_gs_exit_04_unexpected_removal_web_restores_menu() -> void:
	gameplay_menu = await _spawn_menu(true)
	var prev := _push_hidden_menu("OptionsMock")

	gameplay_menu.get_parent().remove_child(gameplay_menu)
	await get_tree().process_frame

	assert_true(prev.visible, "Unexpected removal must restore the previous menu")
	assert_eq(Globals.hidden_menus.size(), 0, "Restored menu must be popped")
	var code := _last_eval_code()
	assert_true(code.contains("controls-button"), "Options overlays must be shown again")
	assert_true(code.contains("'none'"), "Gameplay overlays must be hidden")


## GS-EXIT-05 | Unexpected removal (web) with nothing on the stack: no crash, and the
## gameplay overlays are hidden without touching the Options overlays.
func test_gs_exit_05_unexpected_removal_web_empty_stack() -> void:
	gameplay_menu = await _spawn_menu(true)

	gameplay_menu.get_parent().remove_child(gameplay_menu)
	await get_tree().process_frame

	assert_eq(Globals.hidden_menus.size(), 0, "Stack stays empty")
	var code := _last_eval_code()
	assert_true(code.contains("'none'"), "Gameplay overlays must be hidden")
	assert_false(code.contains("controls-button"), "Options overlays must not be shown without a previous menu")


# --- IDEMPOTENCY ---


## GS-EXIT-06 | CHARACTERIZATION: running the tree-exit cleanup twice.
## Signal and JS cleanup are naturally safe to repeat, but the stack restore is not:
## each unintentional call pops another menu. #480 requires cleanup to be idempotent,
## so after the refactor the second call should leave `lower` hidden and the stack at 1.
## Flip the last two asserts when the guard flag lands.
func test_gs_exit_06_double_cleanup_pops_twice_characterization() -> void:
	gameplay_menu = await _spawn_menu(true)
	var lower := _push_hidden_menu("LowerMenu")
	var upper := _push_hidden_menu("UpperMenu")

	gameplay_menu._on_tree_exited()
	assert_true(upper.visible, "First call restores the top menu")
	assert_false(lower.visible)
	assert_eq(Globals.hidden_menus.size(), 1)

	gameplay_menu._on_tree_exited()
	assert_true(lower.visible, "CURRENT BEHAVIOR: second call restores another menu")
	assert_eq(Globals.hidden_menus.size(), 0, "CURRENT BEHAVIOR: second call pops again")
