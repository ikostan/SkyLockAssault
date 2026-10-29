## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_deserialize_event_key_tokens.gd
## Regression tests: Settings.deserialize_event must reject unknown tokens in key: strings (#1090).
##
## Background (Sourcery review on PR #1089): the [code]key:[/code] branch of
## [method Settings.deserialize_event] only validated the keycode. Modifiers were read with
## [code]"shift" in parts[/code] and similar, so every other token was silently ignored:
## [br]- [code]key:42:bogus[/code] loaded as a plain key 42 binding instead of being rejected.
## [br]- [code]key:42:shfit[/code] (typo) loaded as key 42 [b]without[/b] Shift, a different
## binding from the one the player saved, with no warning.
##
## [method Settings.serialize_event] only writes [code]key:<physical_keycode>[/code] followed by
## zero or more of [code]:shift[/code], [code]:ctrl[/code], [code]:alt[/code],
## [code]:meta[/code], so any other token means the saved binding is corrupt or hand-edited.
##
## Coverage:
## [br]- Unknown, empty and repeated tokens return null.
## [br]- Valid strings, including modifiers in a non-canonical order, still load.
## [br]- Every one of the 16 modifier combinations round-trips through serialization.
## [br]- [code]key:0[/code] is still rejected.
## [br]- A rejected binding falls back to the action's default keyboard binding on load.
##
## Expected result without the fix: the rejection tests and the fallback test fail; the others
## pass. Every test that changes the global InputMap restores it in [method after_each].

extends "res://addons/gut/test.gd"

## Keycode used throughout, matching the examples in #1090.
const CODE: int = 42

## Snapshot of every action in [constant Settings.ACTIONS], taken in [method before_each].
var _saved_events: Dictionary = {}


## Saves the events of every action a test may modify.
##
## The fallback test calls [method Settings.backfill_missing_defaults], which can add defaults
## to any action, so the whole action list is saved. The arrays are duplicated so later edits to
## InputMap cannot change the snapshot.
func before_each() -> void:
	_saved_events.clear()
	for action: String in Settings.ACTIONS:
		_saved_events[action] = InputMap.action_get_events(action).duplicate()


## Restores the actions saved in [method before_each].
##
## Erases each action first, so events added by a test are removed rather than kept next to the
## restored ones, then re-adds the saved events in their original order.
func after_each() -> void:
	for action: String in _saved_events:
		InputMap.action_erase_events(action)
		for ev: InputEvent in _saved_events[action]:
			InputMap.action_add_event(action, ev)


## Asserts that [param serialized] deserializes to null.
##
## [param serialized]: The key string under test.
## [param reason]: Why the string is invalid, used in the failure message.
func _assert_rejected(serialized: String, reason: String) -> void:
	assert_null(
		Settings.deserialize_event(serialized), "'%s' must be rejected: %s" % [serialized, reason]
	)


## Asserts that [param serialized] deserializes to key [constant CODE] with the given modifiers.
##
## [param serialized]: The key string under test.
## [param shift]: Expected Shift state.
## [param ctrl]: Expected Ctrl state.
## [param alt]: Expected Alt state.
## [param meta]: Expected Meta state.
func _assert_key(serialized: String, shift: bool, ctrl: bool, alt: bool, meta: bool) -> void:
	var ev: InputEvent = Settings.deserialize_event(serialized)
	assert_true(ev is InputEventKey, "'%s' must load as an InputEventKey" % serialized)
	if not ev is InputEventKey:
		return
	var key := ev as InputEventKey
	assert_eq(key.physical_keycode, CODE, "'%s' keycode" % serialized)
	assert_eq(key.shift_pressed, shift, "'%s' Shift" % serialized)
	assert_eq(key.ctrl_pressed, ctrl, "'%s' Ctrl" % serialized)
	assert_eq(key.alt_pressed, alt, "'%s' Alt" % serialized)
	assert_eq(key.meta_pressed, meta, "'%s' Meta" % serialized)


## Verifies the original bug: an unknown token after the keycode is rejected.
##
## Fails without the fix, because the token was ignored and key 42 was returned.
func test_unknown_token_is_rejected() -> void:
	_assert_rejected("key:42:bogus", "unknown token")


## Verifies a typo next to a valid modifier is rejected rather than half-applied.
##
## Without the fix, [code]key:42:shift:typo[/code] loaded as Shift+42 and the typo was dropped.
func test_unknown_token_after_valid_modifier_is_rejected() -> void:
	_assert_rejected("key:42:shift:typo", "unknown token after a valid modifier")


## Verifies a misspelled modifier is rejected instead of loading without that modifier.
##
## This is the case from the issue where the player silently got a different binding.
func test_misspelled_modifier_is_rejected() -> void:
	_assert_rejected("key:42:shfit", "misspelled modifier")


## Verifies an empty token between two colons is rejected.
func test_empty_token_is_rejected() -> void:
	_assert_rejected("key:42::shift", "empty token")


## Verifies a trailing colon (an empty last token) is rejected.
func test_trailing_colon_is_rejected() -> void:
	_assert_rejected("key:42:", "empty trailing token")


## Verifies a repeated modifier is rejected.
##
## [method Settings.serialize_event] writes each modifier at most once.
func test_duplicate_modifier_is_rejected() -> void:
	_assert_rejected("key:42:shift:shift", "duplicate modifier")


## Verifies modifier tokens are case-sensitive, as [method Settings.serialize_event] writes them.
func test_uppercase_modifier_is_rejected() -> void:
	_assert_rejected("key:42:SHIFT", "modifiers are lower-case")


## Verifies a plain key with no modifiers still loads.
func test_plain_key_loads() -> void:
	_assert_key("key:42", false, false, false, false)


## Verifies a single modifier still loads.
func test_single_modifier_loads() -> void:
	_assert_key("key:42:shift", true, false, false, false)


## Verifies all four modifiers in canonical order still load.
func test_all_modifiers_load() -> void:
	_assert_key("key:42:shift:ctrl:alt:meta", true, true, true, true)


## Verifies modifiers in a non-canonical order still load.
##
## Older builds or hand-edited files may use a different order; the fix only rejects unknown,
## empty or repeated tokens, not reordered ones.
func test_reordered_modifiers_load() -> void:
	_assert_key("key:42:meta:shift", true, false, false, true)


## Verifies every string [method Settings.serialize_event] can produce still round-trips.
##
## Builds all 16 combinations of Shift, Ctrl, Alt and Meta, serializes each one, deserializes
## the result, and checks that the restored event matches the original.
func test_every_modifier_combination_round_trips() -> void:
	for mask: int in range(16):
		var original := InputEventKey.new()
		original.physical_keycode = CODE
		original.shift_pressed = (mask & 1) != 0
		original.ctrl_pressed = (mask & 2) != 0
		original.alt_pressed = (mask & 4) != 0
		original.meta_pressed = (mask & 8) != 0
		var serialized: String = Settings.serialize_event(original)
		var restored: InputEvent = Settings.deserialize_event(serialized)
		assert_not_null(restored, "'%s' must deserialize" % serialized)
		if restored == null:
			continue
		assert_true(Settings.events_match(original, restored), "'%s' must round-trip" % serialized)


## Verifies keycode 0 is still rejected (existing behaviour, unchanged by the fix).
func test_zero_keycode_is_still_rejected() -> void:
	_assert_rejected("key:0", "keycode 0")


## Verifies a rejected saved binding falls back to the action's default instead of staying
## unbound or loading as the wrong key.
##
## Saves [code]key:42:bogus[/code] as the only "fire" binding and runs the same two steps as
## [method Settings.load_input_mappings]: apply the config, then backfill missing defaults.
## Without the fix, "fire" is bound to key 42. With it, the string is rejected and, because the
## saved entry is still a [code]key:[/code] string (not an explicit unbind), the default
## keyboard binding is restored.
func test_rejected_binding_falls_back_to_default() -> void:
	var config := ConfigFile.new()
	config.set_value("input", "fire", ["key:42:bogus"])

	Settings.apply_config_to_input_map(config, ["fire"] as Array[String])
	Settings.backfill_missing_defaults(config)

	var keys: Array[InputEventKey] = []
	for ev: InputEvent in InputMap.action_get_events("fire"):
		if ev is InputEventKey:
			keys.append(ev as InputEventKey)
	assert_eq(keys.size(), 1, "'fire' must have exactly one keyboard binding")
	if keys.is_empty():
		return
	assert_eq(
		keys[0].physical_keycode,
		Settings.DEFAULT_KEYBOARD["fire"] as Key,
		"'fire' must fall back to its default key, not key 42"
	)
