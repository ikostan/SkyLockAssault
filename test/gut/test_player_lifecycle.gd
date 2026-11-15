## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_player_lifecycle.gd
## GUT unit tests for player node lifecycle, specifically _exit_tree cleanup.

extends "res://addons/gut/test.gd"

const PlayerScene: PackedScene = preload("res://scenes/Player.tscn")

var main_scene: Node
var player_root: Node2D
var original_settings: GameSettingsResource

## Per-test setup: Isolate the environment.
## :rtype: void
func before_each() -> void:
	original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()

## Per-test cleanup: Restore global state and aggressively free the scene.
## :rtype: void
func after_each() -> void:
	Globals.settings = original_settings
	
	# Use a hard free() instead of queue_free().
	# This instantly incinerates the scene, ensuring 0 lingering orphan nodes 
	# without needing to artificially pad the test time with frame flushes.
	if is_instance_valid(main_scene):
		main_scene.free()


## Returns true if any callable connected to [param sig] belongs to [param target].
## :rtype: bool
func _has_connection_to(sig: Signal, target: Object) -> bool:
	for conn: Dictionary in sig.get_connections():
		if conn["callable"].get_object() == target:
			return true
	return false


## test_exit_tree_disconnects_signals |
## Lifecycle | Verify clean signal severing without breaking the SceneTree
## :rtype: void
func test_exit_tree_disconnects_signals() -> void:
	gut.p("Testing: Player _exit_tree properly disconnects local and global signals.")
	
	# 1. Instantiate and add to tree to trigger _ready() and the signal connections
	main_scene = load(GamePaths.MAIN_SCENE).instantiate()
	add_child(main_scene)
	player_root = main_scene.get_node("Player")
	
	# Rewritten from the #1142 bridge check: #1143 removed the settings -> player fuel
	# bridge, so the player must not observe the settings resource at all.
	assert_false(
		player_root.has_method("_on_setting_changed"),
		"The settings -> player fuel bridge listener must be gone."
	)
	assert_false(
		_has_connection_to(Globals.settings.setting_changed, player_root),
		"The player must not connect to setting_changed."
	)
	# FIX: Assert against the authoritative Data Resource, not Globals.settings
	assert_true(
		player_root.fuel_resource.fuel_depleted.is_connected(player_root._on_player_out_of_fuel), 
		"fuel_depleted must be connected to the resource after player enters the tree."
	)
	assert_true(
		player_root.fuel_resource.fuel_changed.is_connected(player_root._on_fuel_changed), 
		"fuel_changed must be connected to the resource after player enters the tree."
	)
	
	# 2. CRITICAL FIX: Manually trigger the lifecycle function instead of using remove_child().
	player_root._exit_tree()
	
	# 3. Assert the signals were cleanly severed
	assert_false(
		_has_connection_to(Globals.settings.setting_changed, player_root),
		"The player must still have no setting_changed connection after _exit_tree."
	)
	assert_false(
		player_root.fuel_resource.fuel_depleted.is_connected(player_root._on_player_out_of_fuel), 
		"fuel_depleted must be completely disconnected from the resource."
	)
	assert_false(
		player_root.fuel_resource.fuel_changed.is_connected(player_root._on_fuel_changed), 
		"fuel_changed must be completely disconnected from the resource."
	)
	
	# 4. CRITICAL FIX: Flush the frame before GUT checks for orphans.
	# This allows the queue_free() calls triggered during MainScene._ready() 
	# to finish sweeping the detached parallax sprites.
	await get_tree().process_frame


## test_exit_tree_safe_without_globals |
## Safety | Verify no crashes on early exit
## :rtype: void
func test_exit_tree_safe_without_globals() -> void:
	gut.p("Testing: Player _exit_tree does not crash if Globals.settings is null.")
	
	Globals.settings = null
	
	# Instantiate manually without adding to the tree (bypasses _ready)
	main_scene = load(GamePaths.MAIN_SCENE).instantiate()
	player_root = main_scene.get_node("Player")
	
	# Safely call _exit_tree in isolation
	player_root._exit_tree()
	
	assert_true(true, "_exit_tree handled a null Globals.settings state gracefully.")


## test_fallback_settings_stay_local |
## Global State (#1143) | A player without Globals.settings must not replace global state
## :rtype: void
func test_fallback_settings_stay_local() -> void:
	gut.p("Testing: The player's fallback settings stay local and Globals.settings stays null.")
	
	Globals.settings = null
	
	# The real player scene, not the shared mock: the mock's HUD panel lacks weapon and
	# ammo nodes, and their engine errors would be charged to this test.
	var player: Variant = PlayerScene.instantiate()
	add_child_autoqfree(player)
	
	assert_push_error("Player couldn't find Globals.settings")
	assert_null(Globals.settings, "The player must not assign its fallback to Globals.settings.")
	assert_true(is_instance_valid(player._settings), "The player must run on a local fallback.")
	assert_eq(
		player.fuel_resource.current_fuel,
		player._settings.max_fuel,
		"The fallback must still fill the tank at spawn."
	)
