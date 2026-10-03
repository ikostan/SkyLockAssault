## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_settings_menu_base.gd
##
## SMB: Unit tests for SettingsMenuBase (settings_menu_base.gd), issue #480.
## Uses a minimal probe subclass so the base contract is tested independently of any
## concrete menu scene. Gameplay-specific exit behavior lives in
## test_gameplay_settings_exit_paths.gd (GS-EXIT).

extends "res://addons/gut/test.gd"

const PROBE_SOURCE: String = """
extends "%s"

signal ping

var cleanup_calls: int = 0
var connected_during_cleanup: bool = false
var restored_menus: Array = []


func _ready() -> void:
	super()
	safe_connect(ping, _on_ping)


func _on_ping() -> void:
	pass


func _get_menu_name() -> String:
	return "Probe Menu"


func _get_overlay_ids() -> Array[String]:
	return ["probe-a", "probe-b"]


func _on_previous_menu_restored(prev_menu: Node) -> void:
	restored_menus.append(prev_menu)


func _cleanup() -> void:
	cleanup_calls += 1
	connected_during_cleanup = ping.is_connected(_on_ping)
"""

var _probe_script: GDScript
var _mock_js: Variant


func before_all() -> void:
	_probe_script = GDScript.new()
	_probe_script.source_code = PROBE_SOURCE % GamePaths.SETTINGS_MENU_BASE
	assert_eq(_probe_script.reload(), OK, "Probe subclass must compile")


func before_each() -> void:
	Globals.settings = GameSettingsResource.new()
	Globals.hidden_menus.clear()
	_mock_js = null


func after_each() -> void:
	Globals.hidden_menus.clear()


# --- HELPERS ---


## Builds a probe menu, adds it to the tree and waits for _ready().
## web = true injects doubled wrappers so the overlay branches run.
func _spawn_probe(web: bool = false) -> Control:
	var probe: Control = _probe_script.new()
	if web:
		_mock_js = double(JavaScriptBridgeWrapper).new()
		var mock_os: Variant = double(OSWrapper).new()
		stub(mock_os, "has_feature").to_return(true)
		probe.os_wrapper = mock_os
		probe.js_bridge_wrapper = _mock_js
	else:
		probe.os_wrapper = OSWrapper.new()
	add_child_autofree(probe)
	await get_tree().process_frame
	return probe


func _push_hidden_menu(menu_name: String) -> Control:
	var menu := Control.new()
	menu.name = menu_name
	menu.visible = false
	autofree(menu)
	Globals.hidden_menus.push_back(menu)
	return menu


func _last_eval_code() -> String:
	return str(get_call_parameters(_mock_js, "eval")[0])


# --- SETUP ---


## SMB-01 | Base _ready() configures pause-proof processing and the tree-exit hook.
func test_smb_01_ready_sets_process_mode_and_tree_exit_hook() -> void:
	var probe := await _spawn_probe()
	assert_eq(probe.process_mode, Node.PROCESS_MODE_ALWAYS, "Menu must ignore pause")
	assert_true(probe.tree_exited.is_connected(probe._on_tree_exited), "tree_exited hooked")


# --- SIGNAL HELPERS ---


## SMB-02 | safe_connect() is idempotent: one engine connection, one tracked entry.
func test_smb_02_safe_connect_is_idempotent() -> void:
	var probe := await _spawn_probe()
	var tracked_before: int = probe._tracked_connections.size()

	probe.safe_connect(probe.ping, probe._on_ping)

	assert_eq(probe.ping.get_connections().size(), 1, "Exactly one engine connection")
	assert_eq(probe._tracked_connections.size(), tracked_before, "No duplicate tracking")


## SMB-03 | safe_disconnect() removes a live connection once, then reports false.
func test_smb_03_safe_disconnect_live_then_missing() -> void:
	var probe := await _spawn_probe()

	assert_true(probe.safe_disconnect(probe.ping, probe._on_ping), "First call disconnects")
	assert_false(probe.ping.is_connected(probe._on_ping), "Connection removed")
	assert_false(probe.safe_disconnect(probe.ping, probe._on_ping), "Second call is a no-op")


## SMB-04 | safe_disconnect() and teardown tolerate an emitter that was already freed.
func test_smb_04_freed_emitter_is_safe() -> void:
	var probe := await _spawn_probe()
	var emitter := Button.new()
	add_child(emitter)
	var handler := func() -> void: pass
	probe.safe_connect(emitter.pressed, handler)
	var stale_signal: Signal = emitter.pressed

	emitter.free()

	assert_false(probe.safe_disconnect(stale_signal, handler), "Freed emitter -> false")
	probe._on_tree_exited()  # Tracked entry points at the freed emitter.
	assert_eq(probe._tracked_connections.size(), 0, "Tracked connections cleared")


## SMB-05 | Teardown order and idempotency: _cleanup() runs once, before tracked signals
## are disconnected, even when tree exit is reached twice (direct call + real exit).
func test_smb_05_cleanup_runs_once_before_disconnect() -> void:
	var probe := await _spawn_probe()

	probe._on_tree_exited()
	probe.get_parent().remove_child(probe)  # Real tree_exited -> second teardown attempt
	add_child(probe)  # Keep autofree's bookkeeping simple.

	assert_eq(probe.cleanup_calls, 1, "_cleanup() must run exactly once")
	assert_true(probe.connected_during_cleanup, "_cleanup() must run before disconnects")
	assert_false(probe.ping.is_connected(probe._on_ping), "Tracked signal disconnected")


# --- NAVIGATION ---


## SMB-06 | Back path: flag set, one menu restored, focus hook called, one overlay swap.
func test_smb_06_go_back_restores_and_swaps_overlays() -> void:
	var probe := await _spawn_probe(true)
	var options := _push_hidden_menu("OptionsMock")

	probe._go_back()

	assert_true(probe._intentional_exit, "Back marks the exit intentional")
	assert_true(options.visible, "Previous menu restored")
	assert_eq(Globals.hidden_menus.size(), 0, "Exactly one pop")
	assert_eq(probe.restored_menus, [options], "Focus hook receives the restored menu")
	assert_true(probe.is_queued_for_deletion(), "Menu queued for deletion")
	var code := _last_eval_code()
	assert_true(code.contains("getElementById('controls-button').style.display = 'block'"))
	assert_true(code.contains("getElementById('probe-a').style.display = 'none'"))


## SMB-07 | Unexpected exit: menu restored, but the Back-only focus hook is not called.
func test_smb_07_unexpected_exit_restores_without_focus_hook() -> void:
	var probe := await _spawn_probe(true)
	var options := _push_hidden_menu("OptionsMock")

	probe.get_parent().remove_child(probe)
	await get_tree().process_frame

	assert_true(options.visible, "Previous menu restored")
	assert_eq(Globals.hidden_menus.size(), 0, "Exactly one pop")
	assert_eq(probe.restored_menus.size(), 0, "Focus hook is Back-path only")
	var code := _last_eval_code()
	assert_true(code.contains("options-back-button"), "Options overlays shown")
	assert_true(code.contains("getElementById('probe-b').style.display = 'none'"))
	probe.free()


## SMB-08 | Back with an empty stack: no crash, own overlays hidden, menu still freed.
func test_smb_08_go_back_with_empty_stack() -> void:
	var probe := await _spawn_probe(true)

	probe._go_back()

	assert_true(probe.is_queued_for_deletion(), "Menu still freed")
	assert_eq(probe.restored_menus.size(), 0, "No hook without a restored menu")
	var code := _last_eval_code()
	assert_true(code.contains("'none'"), "Own overlays hidden")
	assert_false(code.contains("controls-button"), "Options overlays untouched")


## SMB-09 | A freed entry on the stack is popped but not treated as a restored menu.
func test_smb_09_freed_stack_entry_is_skipped() -> void:
	var probe := await _spawn_probe(true)
	var stale := Control.new()
	Globals.hidden_menus.push_back(stale)
	stale.free()

	probe._on_tree_exited()

	assert_eq(Globals.hidden_menus.size(), 0, "Stale entry popped")
	assert_false(_last_eval_code().contains("controls-button"), "No Options overlays")


# --- WEB OVERLAYS ---


## SMB-10 | update_web_overlays() is a no-op off web and with nothing to change.
func test_smb_10_update_web_overlays_no_ops() -> void:
	var probe := await _spawn_probe(true)
	var calls_before: int = get_call_count(_mock_js, "eval")

	probe.update_web_overlays([], [])
	assert_eq(get_call_count(_mock_js, "eval"), calls_before, "Empty lists -> no eval")

	probe.os_wrapper = OSWrapper.new()  # Headless runner: has_feature("web") is false.
	probe.update_web_overlays(["x"], ["y"])
	assert_eq(get_call_count(_mock_js, "eval"), calls_before, "Off web -> no eval")


## SMB-11 | Generated JS keeps the exact statement format the DOM/Playwright tests use.
func test_smb_11_overlay_js_format() -> void:
	var base_script: GDScript = load(GamePaths.SETTINGS_MENU_BASE)
	var code: String = base_script._build_overlay_js(["a"], ["b", "c"])
	assert_eq(
		code,
		(
			"document.getElementById('a').style.display = 'block';\n"
			+ "document.getElementById('b').style.display = 'none';\n"
			+ "document.getElementById('c').style.display = 'none';"
		)
	)


# --- DATA SAFETY ---


## SMB-12 | Neither exit path replaces or mutates Globals.settings.
func test_smb_12_exit_paths_do_not_touch_settings_resource() -> void:
	var settings_res: GameSettingsResource = Globals.settings
	var difficulty_before: float = settings_res.difficulty
	var probe := await _spawn_probe()
	_push_hidden_menu("OptionsMock")

	probe._go_back()
	await get_tree().process_frame

	assert_same(Globals.settings, settings_res, "Settings resource instance unchanged")
	assert_eq(Globals.settings.difficulty, difficulty_before, "Settings values unchanged")
