## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_events_match_meta.gd
## Regression tests: events_match must treat Meta (Cmd/Win) as a distinct modifier.
##
## Background (Sourcery review on PR #1024): [method Settings.events_match] compared
## [code]physical_keycode[/code], Shift, Ctrl and Alt, but not [code]meta_pressed[/code]. Two key
## events that differed only by Meta were treated as the same binding, so on macOS (where Meta is
## Cmd) a binding such as Cmd+Q collided with plain Q. That had two visible effects:
## [br]- The remap UI reported a false conflict between Cmd+Q and Q.
## [br]- On load, [method Settings.apply_config_to_input_map] passed the false conflict to
## [code]_remove_event_from_conflicts[/code], which silently unbound the other action.
##
## The rest of Settings already handles Meta: [method Settings.serialize_event] writes
## [code]:meta[/code], [method Settings.deserialize_event] reads it back, and
## [method Settings.get_event_label] prints a "Meta+" prefix. These tests pin
## [method Settings.events_match] to the same rule.
##
## Coverage:
## [br]- Meta+key and the plain key are different bindings (the original bug).
## [br]- Meta+key still matches itself, so the fix did not make Meta bindings unmatchable.
## [br]- [method Settings.get_conflicting_actions] does not report Meta+key as conflicting with
## the plain key (the user-visible symptom in the remap UI).
## [br]- Meta survives a serialize/deserialize round trip and still matches the original event.
##
## Expected result without the fix: the first and third tests fail; the second and fourth pass.
## Q is used because the default [code]next_weapon[/code] binding is Q, which mirrors the real
## Cmd+Q vs Q case. Every test that changes the global InputMap restores it in
## [method after_each].

extends "res://addons/gut/test.gd"

## Snapshot of the "fire" events taken in [method before_each], restored in [method after_each].
var _saved_fire: Array[InputEvent] = []
## Snapshot of the "next_weapon" events, the action the conflict test rebinds.
var _saved_next_weapon: Array[InputEvent] = []


## Saves the events of every action a test may modify.
##
## InputMap is global and shared with every other test in the run, so changes must not leak.
## The arrays are duplicated so later edits to InputMap cannot change the snapshot.
func before_each() -> void:
	_saved_fire = InputMap.action_get_events("fire").duplicate()
	_saved_next_weapon = InputMap.action_get_events("next_weapon").duplicate()


## Restores the actions saved in [method before_each].
##
## Erases each action first, so events added by a test are removed rather than kept next to the
## restored ones, then re-adds the saved events in their original order.
func after_each() -> void:
	for pair: Array in [["fire", _saved_fire], ["next_weapon", _saved_next_weapon]]:
		InputMap.action_erase_events(pair[0])
		for ev: InputEvent in pair[1]:
			InputMap.action_add_event(pair[0], ev)


## Builds a key event the same way Settings stores bindings.
##
## Only [code]physical_keycode[/code] is set, matching how [method Settings.deserialize_event]
## and the defaults create events. Shift, Ctrl and Alt stay [code]false[/code] so the only
## difference between two events under test is Meta.
##
## [param code]: Physical key to bind, e.g. [code]KEY_Q[/code].
## [param meta]: Whether the Meta (Cmd/Win) modifier is held. Defaults to [code]false[/code].
## Returns a new, unbound [code]InputEventKey[/code].
func _key(code: Key, meta: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.meta_pressed = meta
	return ev


## Verifies the original bug: Meta+Q and plain Q must not be the same binding.
##
## Fails without the fix, because the Meta modifier was not compared.
func test_meta_and_plain_key_do_not_match() -> void:
	assert_false(
		Settings.events_match(_key(KEY_Q, true), _key(KEY_Q)),
		"Meta+Q and Q must be different bindings"
	)


## Verifies the fix did not overshoot: two Meta+Q events must still match.
##
## Guards against a fix that compares Meta incorrectly (e.g. always returning false when Meta
## is held), which would let duplicate Meta bindings through conflict detection.
func test_meta_keys_match_each_other() -> void:
	assert_true(
		Settings.events_match(_key(KEY_Q, true), _key(KEY_Q, true)), "Meta+Q must match Meta+Q"
	)


## Verifies the user-visible symptom: no false conflict between Meta+Q and Q.
##
## Binds plain Q to "next_weapon", then asks which other actions already use Meta+Q while
## "fire" is being remapped. "next_weapon" must not be returned. Without the fix it is, which
## is what made the remap UI show a false conflict and made loading unbind the action.
func test_meta_binding_is_not_a_conflict_with_plain_key() -> void:
	InputMap.action_erase_events("next_weapon")
	InputMap.action_add_event("next_weapon", _key(KEY_Q))
	var conflicts: Array[String] = Settings.get_conflicting_actions(_key(KEY_Q, true), "fire")
	assert_false(conflicts.has("next_weapon"), "Meta+Q must not be reported as conflicting with Q")


## Verifies Meta survives saving and loading.
##
## Serializes Meta+Q (expected [code]key:<code>:meta[/code]), deserializes it, and checks that
## the restored event still matches the original. This passes even without the fix, because the
## old comparison ignored Meta entirely. It protects the persistence path now that Meta matters:
## if serialization ever dropped [code]:meta[/code], this test would fail.
func test_meta_round_trips_through_serialization() -> void:
	var original: InputEventKey = _key(KEY_Q, true)
	var restored: InputEvent = Settings.deserialize_event(Settings.serialize_event(original))
	assert_true(
		Settings.events_match(original, restored), "Serialized Meta+Q must restore as Meta+Q"
	)
