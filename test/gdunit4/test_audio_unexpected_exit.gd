## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_audio_unexpected_exit.gd
## Unit test for audio menu unexpected exit flow.
##
## Simulates opening options, then audio, then unexpected removal.
## Verifies that the previous menu's visibility is correctly restored.
##
## Uses GdUnitTestSuite for assertions.

extends GdUnitTestSuite

var options_scene: PackedScene = preload("res://scenes/options_menu.tscn")
var audio_scene: PackedScene = preload("res://scenes/audio_settings.tscn")
var options_instance: CanvasLayer
var audio_instance: Control

func before_test() -> void:
	## Per-test setup: Instantiate menus, reset Globals.
	##
	## :rtype: void
	
	# Reset Globals
	Globals.hidden_menus = []
	Globals.options_open = false
	Globals.options_instance = null

	# Instantiate options
	options_instance = auto_free(options_scene.instantiate())
	add_child(options_instance)
	Globals.options_open = true
	Globals.options_instance = options_instance
	Globals.hidden_menus = []  # Ensure empty

func after_test() -> void:
	## Per-test cleanup: Free instances.
	##
	## :rtype: void
	if is_instance_valid(options_instance):
		options_instance.queue_free()
	if is_instance_valid(audio_instance):
		audio_instance.queue_free()
	Globals.hidden_menus = []

func test_unexpected_audio_exit_restores_menu() -> void:
	## Tests unexpected audio removal restores previous menu.
	##
	## :rtype: void
	Globals.log_message("Starting unexpected exit test.", Globals.LogLevel.DEBUG)

	# Instantiate audio (simulates opening from options)
	audio_instance = auto_free(audio_scene.instantiate())
	add_child(audio_instance)
	
	# Simulate the transition state where options is hidden
	Globals.hidden_menus.push_back(options_instance)
	options_instance.visible = false

	# Verify transition state was set correctly
	assert_bool(options_instance.visible).is_false()
	assert_bool(Globals.hidden_menus.is_empty()).is_false()

	# Simulate unexpected exit (e.g., node freed by crash or external closure)
	audio_instance.queue_free()
	await get_tree().process_frame  # Wait for tree exit

	# Verify restoration logic in _on_tree_exited() fired correctly
	assert_bool(options_instance.visible).is_true()
	assert_bool(Globals.hidden_menus.is_empty()).is_true()
	Globals.log_message("Menu successfully restored after unexpected exit.", Globals.LogLevel.DEBUG)
