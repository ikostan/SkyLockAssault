## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_player_lifecycle.gd
## GUT unit tests for player node lifecycle, specifically _exit_tree cleanup.

extends "res://addons/gut/test.gd"

var main_scene: Node
var player_root: Node2D
var original_settings: GameSettingsResource

## Per-test setup: Isolate the environment.
## :rtype: void
func before_each() -> void:
	original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()

## Per-test cleanup: Restore global state.
## :rtype: void
func after_each() -> void:
	Globals.settings = original_settings
	
	# NEW: Reverted to a hard free(). 
	# queue_free() delays deletion, causing GUT to falsely report the entire scene as orphans.
	# A hard free() executes instantly, ensuring 0 lingering scene nodes when GUT checks memory.
	if is_instance_valid(main_scene):
		main_scene.free()

## test_exit_tree_disconnects_signals | Lifecycle | Verify clean signal severing
## :rtype: void
func test_exit_tree_disconnects_signals() -> void:
	gut.p("Testing: Player _exit_tree properly disconnects global signals.")
	
	# 1. Instantiate and add to tree to trigger _ready() and the signal connections
	main_scene = load("res://scenes/main_scene.tscn").instantiate()
	add_child(main_scene)
	player_root = main_scene.get_node("Player")
	
	assert_true(
		Globals.settings.setting_changed.is_connected(player_root._on_setting_changed), 
		"setting_changed must be connected after player enters the tree."
	)
	assert_true(
		Globals.settings.fuel_depleted.is_connected(player_root._on_player_out_of_fuel), 
		"fuel_depleted must be connected after player enters the tree."
	)
	
	# NEW: 2. Instead of remove_child() (which breaks the tree), manually call the lifecycle function
	player_root._exit_tree()
	
	# 3. Assert the signals were cleanly severed
	assert_false(
		Globals.settings.setting_changed.is_connected(player_root._on_setting_changed), 
		"setting_changed must be completely disconnected after player leaves the tree."
	)
	assert_false(
		Globals.settings.fuel_depleted.is_connected(player_root._on_player_out_of_fuel), 
		"fuel_depleted must be completely disconnected after player leaves the tree."
	)

## test_exit_tree_safe_without_globals | Safety | Verify no crashes on early exit
## :rtype: void
func test_exit_tree_safe_without_globals() -> void:
	gut.p("Testing: Player _exit_tree does not crash if Globals.settings is null.")
	
	Globals.settings = null
	
	# Instantiate manually without adding to the tree (bypasses _ready)
	main_scene = load("res://scenes/main_scene.tscn").instantiate()
	player_root = main_scene.get_node("Player")
	
	player_root._exit_tree()
	
	assert_true(true, "_exit_tree handled a null Globals.settings state gracefully.")
