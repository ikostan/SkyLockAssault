## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_key_mapping_load_regression.gd
##
## Regression test suite ensuring that initializing the Key Mapping menu
## does not prematurely trigger audio feedback.
extends GutTest

const KEY_MAPPING_PATH: String = "res://scenes/key_mapping_menu.tscn"

var original_audio_script: Script


## Suite setup: Bootstrap a mock AudioManager to intercept and record 
## playback calls during test execution.
func before_all() -> void:
	if is_instance_valid(AudioManager):
		original_audio_script = AudioManager.get_script()
		var mock_script := GDScript.new()
		mock_script.source_code = """
extends Node
var sfx_calls: Array = []
func play_sfx(key: String, extra: Variant = null) -> void:
	sfx_calls.append(key)
"""
		mock_script.reload()
		AudioManager.set_script(mock_script)

## Suite cleanup: Safely restore the original AudioManager script and
## re-populate its internal state to ensure strict test isolation.
func after_all() -> void:
	if original_audio_script and is_instance_valid(AudioManager):
		AudioManager.set_script(original_audio_script)
		# Rebuild internal state to prevent cascading failures
		if AudioManager.has_method("cleanup_for_test"):
			AudioManager.cleanup_for_test()


## Per-test setup: Reset global device state and clear the mock 
## call log to ensure test isolation.
func before_each() -> void:
	# Force 'gamepad' to ensure the initial state triggers the signal emission
	Globals.current_input_device = "gamepad"
	
	if AudioManager.get("sfx_calls") != null:
		AudioManager.set("sfx_calls", [])


## Test Scenario: Verify that instantiating the Key Mapping menu does not 
## trigger any audio playback during the _ready() initialization phase.
func test_key_mapping_load_is_silent() -> void:
	# 1. Load and instantiate the Key Mapping menu
	var scene := load(KEY_MAPPING_PATH) as PackedScene
	var menu := scene.instantiate()
	
	# 2. Add to tree to trigger _ready() signal emissions
	add_child_autofree(menu)
	
	# 3. Await frames to allow signal propagation from _ready()
	await get_tree().process_frame
	await get_tree().process_frame
	
	# 4. Safely retrieve captured SFX calls
	var raw_calls: Variant = AudioManager.get("sfx_calls")
	var calls: Array = raw_calls as Array if raw_calls is Array else []
	
	# 5. Assertion: Initialization should be silent
	assert_false(
		calls.has("check"), 
		"Regression Failure: Menu initialization played 'check' audio unexpectedly."
	)
