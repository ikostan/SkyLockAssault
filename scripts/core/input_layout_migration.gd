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
## Called once from [code]Settings._migrate_input_layout_v3()[/code]; kept apart from
## settings.gd because it is legacy repair code that can be deleted once old saves are gone.

extends RefCounted

const InputDefaults = preload("res://scripts/core/input_defaults.gd")
const DEVICES: Array[String] = ["keyboard", "gamepad"]


## Repairs the InputMap in place for every action in [code]settings.ACTIONS[/code].
##
## [br]1. Trims every action to one binding per device (the first one). Extra bindings are
## hidden: the key mapping menu shows and edits only one per device.
## [br]2. Restores the default for every device an action has no binding for, unless another
## action in its conflict group already uses that input.
##
## [param settings]: The Settings autoload, for its defaults and conflict checks.
## Returns [code]true[/code] if any binding was removed or added.
static func migrate(settings: Node) -> bool:
	var trimmed: bool = _trim_to_one_binding_per_device(settings)
	var restored: bool = _restore_missing_defaults(settings)
	return trimmed or restored


## Removes every binding after the first one per device from each action.
##
## [param settings]: The Settings autoload.
## Returns [code]true[/code] if any binding was removed.
static func _trim_to_one_binding_per_device(settings: Node) -> bool:
	var changed: bool = false
	for action: String in settings.ACTIONS:
		var seen: Dictionary = {}
		for ev: InputEvent in InputMap.action_get_events(action).duplicate():
			var device: String = settings.get_event_device_type(ev)
			if device not in DEVICES:
				continue
			if not seen.has(device):
				seen[device] = true
				continue
			InputMap.action_erase_event(action, ev)
			changed = true
			Globals.log_message(
				(
					"Migration v3: removed extra %s binding %s from %s"
					% [device, settings.get_event_label(ev), action]
				),
				Globals.LogLevel.INFO
			)
	return changed


## Adds the default binding for every device an action is missing, if it is free in its group.
##
## [param settings]: The Settings autoload.
## Returns [code]true[/code] if any default was added.
static func _restore_missing_defaults(settings: Node) -> bool:
	var changed: bool = false
	for action: String in settings.ACTIONS:
		for device: String in DEVICES:
			if has_binding_for_device(settings, action, device):
				continue
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


## Returns true if [param action] has at least one binding for [param device].
##
## [param settings]: The Settings autoload.
## [param action]: Action name in the InputMap.
## [param device]: [code]keyboard[/code] or [code]gamepad[/code].
static func has_binding_for_device(settings: Node, action: String, device: String) -> bool:
	for ev: InputEvent in InputMap.action_get_events(action):
		if settings.get_event_device_type(ev) == device:
			return true
	return false
