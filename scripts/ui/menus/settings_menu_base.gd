## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## res://scripts/ui/menus/settings_menu_base.gd
##
## Shared base class for settings sub-menus (Gameplay today; Audio and Advanced next).
##
## Owns the boilerplate every settings menu used to repeat:
##   * Signal cleanup: connections made through safe_connect() are tracked and removed on
##     teardown. safe_disconnect() tolerates a freed emitter or a missing connection.
##   * Web overlays: update_web_overlays() shows/hides DOM elements through the bridge.
##   * Menu stack: one Globals.hidden_menus entry is popped and re-shown on exit.
##   * Focus: _grab_initial_focus() routes through Globals.ensure_initial_focus().
##
## Exit paths (both pop the stack exactly once):
##   Back button -> _go_back(): sets _intentional_exit, pops and shows the previous menu,
##                  swaps overlays, queue_free(). The tree_exited that follows does NOT pop.
##   Unexpected  -> tree_exited -> _teardown(): pops and shows the previous menu on every
##                  platform, then swaps overlays (web only).
##
## Teardown runs at most once per instance: the subclass _cleanup() hook first, then the
## tracked signals are disconnected, then the stack/overlay handling above.
##
## Subclasses call super() at the top of _ready() and override the virtual hooks below
## (_get_menu_name, _get_overlay_ids, _get_initial_focus_control, _get_focus_controls,
## _on_previous_menu_restored, _cleanup) as needed.

class_name SettingsMenuBase
extends Control

## DOM overlays of the Options menu, which is the menu every settings sub-menu returns to.
const OPTIONS_MENU_OVERLAY_IDS: Array[String] = [
	"controls-button", "audio-button", "advanced-button", "gameplay-button", "options-back-button"
]

## The wrappers abstract the JavaScriptBridge and OS singletons so tests can inject doubles.
var js_bridge_wrapper: JavaScriptBridgeWrapper = JavaScriptBridgeWrapper.new()
var os_wrapper: OSWrapper = OSWrapper.new()
## JS `window` interface; only set on web. Variant so tests can inject a Dictionary.
var js_window: Variant
## True once the exit was requested through the Back button (_go_back()).
var _intentional_exit: bool = false
## True once _teardown() has run; makes repeated tree_exited / direct calls no-ops.
var _torn_down: bool = false
## True once the subclass _cleanup() hook has run.
var _cleanup_done: bool = false
## Connections made through safe_connect(): [{"signal": Signal, "callable": Callable}, ...]
var _tracked_connections: Array[Dictionary] = []


func _ready() -> void:
	## Common setup. Subclasses must call super() first in their own _ready().
	process_mode = Node.PROCESS_MODE_ALWAYS  # Settings menus are usable while paused.
	if not tree_exited.is_connected(_on_tree_exited):
		tree_exited.connect(_on_tree_exited)


# ==============================================================================
# SIGNAL HELPERS
# ==============================================================================


## Connects signal_obj to callable once and tracks it for automatic teardown cleanup.
##
## :param signal_obj: The signal to connect, e.g. `button.pressed`.
## :type signal_obj: Signal
## :param callable: The handler to connect.
## :type callable: Callable
## :param flags: Optional Object.ConnectFlags.
## :type flags: int
## :rtype: void
func safe_connect(signal_obj: Signal, callable: Callable, flags: int = 0) -> void:
	if signal_obj.is_null() or not callable.is_valid():
		_log("safe_connect: null signal or invalid callable - skipping.", Globals.LogLevel.WARNING)
		return
	if not signal_obj.is_connected(callable):
		signal_obj.connect(callable, flags)
	for entry: Dictionary in _tracked_connections:
		if entry["signal"] == signal_obj and entry["callable"] == callable:
			return
	_tracked_connections.append({"signal": signal_obj, "callable": callable})


## Disconnects callable from signal_obj if, and only if, that is safe.
##
## Safe when the emitter has already been freed (Signal only stores the object ID, so
## get_object() returns null) and when the connection does not exist.
##
## :param signal_obj: The signal to disconnect from.
## :type signal_obj: Signal
## :param callable: The connected handler.
## :type callable: Callable
## :returns: True if a connection was actually removed.
## :rtype: bool
func safe_disconnect(signal_obj: Signal, callable: Callable) -> bool:
	if signal_obj.is_null():
		return false
	var emitter: Object = signal_obj.get_object()
	if emitter == null or not is_instance_valid(emitter):
		return false
	if not signal_obj.is_connected(callable):
		return false
	signal_obj.disconnect(callable)
	return true


## Disconnects every connection registered through safe_connect(), newest first.
## :rtype: void
func _disconnect_tracked_signals() -> void:
	for i: int in range(_tracked_connections.size() - 1, -1, -1):
		var entry: Dictionary = _tracked_connections[i]
		safe_disconnect(entry["signal"], entry["callable"])
	_tracked_connections.clear()


# ==============================================================================
# WEB OVERLAY HELPERS
# ==============================================================================


## Shows visible_ids and hides hidden_ids in the DOM with a single eval() call.
##
## No-op off web, without a bridge, or when both lists are empty. IDs must be plain DOM
## ids (they are interpolated into single-quoted JS strings).
##
## :param visible_ids: DOM element ids to set to display 'block'.
## :type visible_ids: Array
## :param hidden_ids: DOM element ids to set to display 'none'.
## :type hidden_ids: Array
## :rtype: void
func update_web_overlays(visible_ids: Array, hidden_ids: Array) -> void:
	if visible_ids.is_empty() and hidden_ids.is_empty():
		return
	if not _is_web():
		return
	js_bridge_wrapper.eval(_build_overlay_js(visible_ids, hidden_ids), true)


## True when running on web with a usable JS bridge.
## :rtype: bool
func _is_web() -> bool:
	return os_wrapper != null and os_wrapper.has_feature("web") and js_bridge_wrapper != null


## Builds the DOM display toggles used by update_web_overlays().
## :rtype: String
static func _build_overlay_js(visible_ids: Array, hidden_ids: Array) -> String:
	var lines: PackedStringArray = []
	for id: Variant in visible_ids:
		lines.append("document.getElementById('%s').style.display = 'block';" % str(id))
	for id: Variant in hidden_ids:
		lines.append("document.getElementById('%s').style.display = 'none';" % str(id))
	return "\n".join(lines)


# ==============================================================================
# NAVIGATION & TEARDOWN
# ==============================================================================


## Back-button exit path. Call this from the subclass Back handler (Godot and JS).
##
## Marks the exit intentional, restores exactly one previous menu, swaps the overlays and
## frees the menu. Repeated calls before the node is freed are ignored, so a double click
## (or Godot + DOM Back in the same frame) cannot pop a second menu.
## :rtype: void
func _go_back() -> void:
	if _intentional_exit:
		_log(_get_menu_name() + ": Back already requested - ignoring.", Globals.LogLevel.DEBUG)
		return
	_intentional_exit = true
	_log(_get_menu_name() + ": Back button pressed.", Globals.LogLevel.DEBUG)

	var prev_menu: Node = _restore_previous_menu()
	if prev_menu != null:
		_on_previous_menu_restored(prev_menu)
		update_web_overlays(_get_previous_menu_overlay_ids(), _get_overlay_ids())
	else:
		_log("No hidden menu to show.", Globals.LogLevel.INFO)
		update_web_overlays([], _get_overlay_ids())

	queue_free()


func _on_tree_exited() -> void:
	## Unexpected removal, or the tree_exited that follows _go_back()'s queue_free().
	_teardown()


## Single, idempotent teardown shared by both exit paths.
##
## Order: subclass _cleanup() -> tracked signal disconnects -> (unexpected exit only) menu
## stack restore -> overlay swap.
## :rtype: void
func _teardown() -> void:
	if _torn_down:
		return
	_torn_down = true
	_log(_get_menu_name() + ": teardown on tree exit.", Globals.LogLevel.DEBUG)

	_run_cleanup()
	_disconnect_tracked_signals()

	var prev_menu: Node = null
	if not _intentional_exit:
		prev_menu = _restore_previous_menu()
		if prev_menu != null:
			_log(
				_get_menu_name() + " exited unexpectedly; restored menu: " + prev_menu.name,
				Globals.LogLevel.DEBUG
			)

	var visible_ids: Array = _get_previous_menu_overlay_ids() if prev_menu != null else []
	update_web_overlays(visible_ids, _get_overlay_ids())


## Runs the subclass _cleanup() hook at most once.
## :rtype: void
func _run_cleanup() -> void:
	if _cleanup_done:
		return
	_cleanup_done = true
	_cleanup()


## Pops the top of Globals.hidden_menus and makes it visible.
##
## :returns: The restored menu, or null if the stack was empty, the popped entry was
##   already freed, or Globals is unavailable.
## :rtype: Node
func _restore_previous_menu() -> Node:
	if not is_instance_valid(Globals) or Globals.hidden_menus.is_empty():
		return null
	# Pop into a Variant first: assigning a freed instance straight to a typed Node var
	# raises "Trying to assign invalid previously freed instance" and aborts the function.
	var popped: Variant = Globals.hidden_menus.pop_back()
	if not is_instance_valid(popped):
		return null
	var prev_menu: Node = popped
	prev_menu.visible = true
	_log("Showing menu: " + prev_menu.name, Globals.LogLevel.DEBUG)
	return prev_menu


# ==============================================================================
# FOCUS
# ==============================================================================


## Gives initial keyboard/gamepad focus to _get_initial_focus_control().
## :rtype: void
func _grab_initial_focus() -> void:
	var candidate: Control = _get_initial_focus_control()
	if candidate == null or not is_instance_valid(Globals):
		return
	Globals.ensure_initial_focus(candidate, _get_focus_controls(), _get_menu_name())


# ==============================================================================
# VIRTUAL HOOKS (override in subclasses)
# ==============================================================================


## Human-readable menu name used in logs and focus context.
## :rtype: String
func _get_menu_name() -> String:
	return str(name)


## DOM overlay ids owned by this menu (shown on open, hidden on exit).
## :rtype: Array[String]
func _get_overlay_ids() -> Array[String]:
	return []


## DOM overlay ids of the menu restored from the stack.
## :rtype: Array[String]
func _get_previous_menu_overlay_ids() -> Array[String]:
	return OPTIONS_MENU_OVERLAY_IDS


## Control that receives initial focus; null skips the focus grab.
## :rtype: Control
func _get_initial_focus_control() -> Control:
	return null


## Controls that count as "focus already inside this menu".
## :rtype: Array[Control]
func _get_focus_controls() -> Array[Control]:
	return []


## Called on the Back path only, right after the previous menu is shown.
## Use it to restore focus in that menu.
## :param _prev_menu: The menu that was just restored.
## :type _prev_menu: Node
## :rtype: void
func _on_previous_menu_restored(_prev_menu: Node) -> void:
	pass


## Subclass teardown: release JS callbacks and any state the base does not track.
## Runs once, before the base disconnects tracked signals.
## :rtype: void
func _cleanup() -> void:
	pass


# ==============================================================================
# INTERNAL
# ==============================================================================


## Logs through Globals when it is still alive (it may be gone during shutdown).
## :rtype: void
func _log(message: String, level: Globals.LogLevel) -> void:
	if is_instance_valid(Globals):
		Globals.log_message(message, level)
