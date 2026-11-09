## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## input_layout_migration.gd
## One-time repair (v3) for input saves written before the menu/gameplay input split.
##
## Older defaults bound the arrow keys to both the flight and the menu actions, and the left
## stick to both as well. The load-time conflict check then stripped one side, and
## keycode-only arrow events were saved as an invalid [code]key:0[/code], so the menu arrows
## ended up "Unbound" and speed/steering lost their stick.
##
## The repair only touches the exact bindings that bug left behind ([constant LEGACY_EXTRAS]
## and [constant BUG_STRIPPED]). Any other binding, extra binding or unbind is the player's
## and is kept.
##
## Called once from [code]Settings._migrate_input_layout_v3()[/code]; kept apart from
## settings.gd because it is legacy repair code that can be deleted once old saves are gone.

extends RefCounted

const InputDefaults = preload("res://scripts/core/input_defaults.gd")

## Hidden second bindings from the old defaults, in Settings' serialized format.
## Arrow keys on flight actions came from the old project.godot; left-stick axes on menu
## actions came from Godot's built-in ui_* actions.
const LEGACY_EXTRAS: Dictionary = {
	"speed_up": "key:4194320",  # Up arrow
	"speed_down": "key:4194322",  # Down arrow
	"move_left": "key:4194319",  # Left arrow
	"move_right": "key:4194321",  # Right arrow
	"ui_up": "joyaxis:1:-1.0:-1",  # Left Stick (Up)
	"ui_down": "joyaxis:1:1.0:-1",  # Left Stick (Down)
	"ui_left": "joyaxis:0:-1.0:-1",  # Left Stick (Left)
	"ui_right": "joyaxis:0:1.0:-1",  # Left Stick (Right)
}

## Device bindings the bug stripped on load: the menu arrows (rejected as key:0, then blocked
## by the flight arrows) and the flight left stick (removed as a conflict with ui_*).
const BUG_STRIPPED: Dictionary = {
	"ui_up": "keyboard",
	"ui_down": "keyboard",
	"ui_left": "keyboard",
	"ui_right": "keyboard",
	"speed_up": "gamepad",
	"speed_down": "gamepad",
	"move_left": "gamepad",
	"move_right": "gamepad",
}


## Repairs the InputMap in place.
##
## [br]1. Removes each [constant LEGACY_EXTRAS] binding, but only while the action has another
## binding for that device. The key mapping menu shows and edits one binding per device, so
## the legacy one was hidden and could be the one shown instead of a newer remap.
## [br]2. Restores the default for each [constant BUG_STRIPPED] slot that is empty, but only if
## the action still has a binding on its other device (the bug never cleared a whole action, so
## a fully unbound action is the player's choice) and the default is free in its conflict group.
##
## [param settings]: The Settings autoload, for event helpers and conflict checks.
## Returns [code]true[/code] if any binding was removed or added.
static func migrate(settings: Node) -> bool:
	var trimmed: bool = _remove_legacy_extras(settings)
	var restored: bool = _restore_stripped_defaults(settings)
	return trimmed or restored


## Removes the hidden legacy second bindings listed in [constant LEGACY_EXTRAS].
##
## [param settings]: The Settings autoload.
## Returns [code]true[/code] if any binding was removed.
static func _remove_legacy_extras(settings: Node) -> bool:
	var changed: bool = false
	for action: String in LEGACY_EXTRAS:
		var legacy: InputEvent = settings.deserialize_event(LEGACY_EXTRAS[action])
		var device: String = settings.get_event_device_type(legacy)
		if count_bindings_for_device(settings, action, device) < 2:
			continue  # The only binding for this device: the player kept or chose it.
		for ev: InputEvent in InputMap.action_get_events(action).duplicate():
			if settings.events_match(ev, legacy):
				InputMap.action_erase_event(action, ev)
				changed = true
				Globals.log_message(
					(
						"Migration v3: removed legacy %s binding %s from %s"
						% [device, settings.get_event_label(ev), action]
					),
					Globals.LogLevel.INFO
				)
	return changed


## Restores defaults for the slots in [constant BUG_STRIPPED] that the bug emptied.
##
## [param settings]: The Settings autoload.
## Returns [code]true[/code] if any default was added.
static func _restore_stripped_defaults(settings: Node) -> bool:
	var changed: bool = false
	for action: String in BUG_STRIPPED:
		var device: String = BUG_STRIPPED[action]
		if count_bindings_for_device(settings, action, device) > 0:
			continue
		if InputMap.action_get_events(action).is_empty():
			continue  # Fully unbound: an explicit unbind, not the bug.
		var ev: InputEvent = InputDefaults.make_event(action, device)
		if ev == null:
			continue
		var conflicts: Array[String] = settings.get_conflicting_actions(ev, action)
		if not conflicts.is_empty():
			Globals.log_message(
				(
					"Migration v3: not restoring default %s binding for %s: already used by %s"
					% [device, action, str(conflicts)]
				),
				Globals.LogLevel.WARNING
			)
			continue
		InputMap.action_add_event(action, ev)
		changed = true
		Globals.log_message(
			"Migration v3: restored default %s binding for %s" % [device, action],
			Globals.LogLevel.INFO
		)
	return changed


## Returns how many bindings [param action] has for [param device].
##
## [param settings]: The Settings autoload.
## [param action]: Action name in the InputMap.
## [param device]: [code]keyboard[/code] or [code]gamepad[/code].
static func count_bindings_for_device(settings: Node, action: String, device: String) -> int:
	var count: int = 0
	for ev: InputEvent in InputMap.action_get_events(action):
		if settings.get_event_device_type(ev) == device:
			count += 1
	return count
