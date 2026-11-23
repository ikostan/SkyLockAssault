## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_main_scene_performance_limits.gd
##
## GUT unit tests for enforcing performance constraints on the MainScene
## to prevent BVH bloat and FPS drops.

extends "res://addons/gut/test.gd"

# Use your existing helper
const GutHelper = preload("res://test/gut/gut_test_helper.gd")

var main_scene: MainScene
var viewport_mock: Vector2 = Vector2(1920, 1080)


func before_each() -> void:
	await get_tree().process_frame
	main_scene = preload(GamePaths.MAIN_SCENE).instantiate()
	add_child(main_scene)
	await get_tree().process_frame


func after_each() -> void:
	# Use the helper's static method
	if is_instance_valid(main_scene):
		GutHelper.safe_hard_free(main_scene)
	await get_tree().process_frame


func test_main_scene_injects_player_resources_into_parallax() -> void:
	var player: Node2D = main_scene.player
	var background: ParallaxManager = main_scene.background as ParallaxManager

	assert_eq(background._speed_resource, player.speed_resource, "Background must observe the player's speed resource.")
	assert_eq(background._fuel_resource, player.fuel_resource, "Background must observe the player's fuel resource.")
	assert_eq(background._settings, Globals.settings, "Background must observe the active settings resource.")
	assert_eq(background._current_speed, player.speed_resource.current_speed, "Background must be primed from player speed.")

	player.speed_resource.current_speed = player.speed_resource.max_speed
	assert_eq(background._current_speed, player.speed_resource.current_speed, "Player speed updates must reach the background.")


## test_parallax_chunk_size_is_optimized |
## Enforces the 8-screen limit to prevent Bounding Volume Hierarchy (BVH) bloat.
## :rtype: void
func test_parallax_chunk_size_is_optimized() -> void:
	gut.p("Testing: Parallax layers must not exceed an 8-screen height limit.")
	
	main_scene.setup_bushes_layer(viewport_mock)
	main_scene.setup_decor_layer(viewport_mock)
	
	# The absolute maximum allowed height multiplier is 8.0
	var max_allowed_height: float = viewport_mock.y * 8.0
	
	assert_eq(
		main_scene.bushes_layer.motion_mirroring.y, 
		max_allowed_height, 
		"Bushes layer chunk size exceeds the 8-screen performance limit."
	)
	
	assert_eq(
		main_scene.decor_layer.motion_mirroring.y, 
		max_allowed_height, 
		"Decor layer chunk size exceeds the 8-screen performance limit."
	)


## test_parallax_sprite_density_is_optimized |
## Enforces the 2x sprite density multiplier to prevent draw call explosions.
## :rtype: void
func test_parallax_sprite_density_is_optimized() -> void:
	gut.p("Testing: Parallax sprite density must be strictly 2x the preloaded resource count.")
	
	main_scene.setup_bushes_layer(viewport_mock)
	main_scene.setup_decor_layer(viewport_mock)
	
	# --- Check Bushes ---
	var bush_ids: Array = Array(main_scene.texture_preloader.get_resource_list()).filter(
		func(id: String) -> bool: return id.begins_with("bush_")
	)
	var expected_bush_count: int = bush_ids.size() * 2
	
	var active_bushes: int = main_scene.bushes_layer.get_children().filter(
		func(c: Node) -> bool: return not c.is_queued_for_deletion()
	).size()
	
	assert_eq(
		active_bushes, 
		expected_bush_count, 
		"Bushes density multiplier must remain at 2x for performance stability."
	)
	
	# --- Check Decor ---
	var decor_ids: Array = Array(main_scene.texture_preloader.get_resource_list()).filter(
		func(id: String) -> bool: return id.begins_with("decor_")
	)
	var expected_decor_count: int = decor_ids.size() * 2
	
	var active_decor: int = main_scene.decor_layer.get_children().filter(
		func(c: Node) -> bool: return not c.is_queued_for_deletion()
	).size()
	
	assert_eq(
		active_decor, 
		expected_decor_count, 
		"Decor density multiplier must remain at 2x for performance stability."
	)


## test_process_script_execution_time |
## MainScene does no per-frame script work, and its event-driven unbound-controls check stays
## lightweight. The check used to run in _process every frame; it now runs on
## Settings.bindings_changed and Settings.input_device_changed (#1102).
## :rtype: void
func test_process_script_execution_time() -> void:
	gut.p("Testing: MainScene has no _process, and its unbound-controls check runs under 2 ms.")

	assert_false(
		main_scene.has_method("_process"),
		"MainScene must not poll per frame; react to Settings signals instead."
	)
	assert_false(main_scene.is_processing(), "MainScene must not be processing every frame.")

	# Pre-warm: absorb any one-shot work (e.g. show_message on first call).
	main_scene._on_bindings_changed()

	var iterations: int = 60
	var start_time: int = Time.get_ticks_usec()
	for i in range(iterations):
		main_scene._on_bindings_changed()
	var total_time_usec: int = Time.get_ticks_usec() - start_time
	var average_time_per_call_usec: float = float(total_time_usec) / iterations

	# 2000 µs = 2 ms, the same loose bound the old per-frame check had, to avoid CI flakiness.
	assert_lt(
		average_time_per_call_usec,
		2000.0,
		"MainScene's unbound-controls check is taking too long."
	)

## test_bushes_layer_chunk_size_and_density |
## Verify the bushes layer mirrors at exactly 8 screens tall and spawns 2x the sprites.
## :rtype: void
func test_bushes_layer_chunk_size_and_density() -> void:
	gut.p("Testing: Bushes layer should use an 8-screen chunk size and 2x density.")

	# 1. Re-run setup to use our specific mock viewport
	main_scene.setup_bushes_layer(viewport_mock)

	# 2. Verify Chunk Size (Height)
	var expected_height: float = viewport_mock.y * 8.0
	assert_eq(
		main_scene.bushes_layer.motion_mirroring.y, 
		expected_height, 
		"Bushes layer mirroring should be exactly 8 screens tall."
	)

	# 3. Calculate Expected Density based on the Preloader
	var bush_ids: Array = Array(main_scene.texture_preloader.get_resource_list()).filter(
		func(id: String) -> bool: return id.begins_with("bush_")
	)
	var expected_count: int = bush_ids.size() * 2

	# 4. Count only active nodes (filtering out anything queued for deletion from the _ready call)
	var active_children: int = main_scene.bushes_layer.get_children().filter(
		func(c: Node) -> bool: return not c.is_queued_for_deletion()
	).size()
	
	assert_eq(
		active_children, 
		expected_count, 
		"Bushes layer should spawn exactly 2 times the number of available bush sprites."
	)


## test_decor_layer_chunk_size_and_density |
## Verify the decor layer mirrors at exactly 8 screens tall and spawns 2x the sprites.
## :rtype: void
func test_decor_layer_chunk_size_and_density() -> void:
	gut.p("Testing: Decor layer should use an 8-screen chunk size and 2x density.")

	# 1. Re-run setup
	main_scene.setup_decor_layer(viewport_mock)

	# 2. Verify Chunk Size (Height)
	var expected_height: float = viewport_mock.y * 8.0
	assert_eq(
		main_scene.decor_layer.motion_mirroring.y, 
		expected_height, 
		"Decor layer mirroring should be exactly 8 screens tall."
	)

	# 3. Calculate Expected Density based on the Preloader
	var decor_ids: Array = Array(main_scene.texture_preloader.get_resource_list()).filter(
		func(id: String) -> bool: return id.begins_with("decor_")
	)
	var expected_count: int = decor_ids.size() * 2

	# 4. Filter out queued nodes
	var active_children: int = main_scene.decor_layer.get_children().filter(
		func(c: Node) -> bool: return not c.is_queued_for_deletion()
	).size()
	
	assert_eq(
		active_children, 
		expected_count, 
		"Decor layer should spawn exactly 2 times the number of available decor sprites."
	)


func test_legacy_signals_are_disconnected() -> void:
	gut.p("Testing: Main scene no longer relies on legacy player signals for parallax updates.")
	
	var player: Node2D = main_scene.player
	var background: ParallaxManager = main_scene.background as ParallaxManager
	
	# Fix: Assert the background is valid and correctly cast before inspecting connections
	assert_not_null(background, "Background node must exist and have the ParallaxManager script attached.")
	if background == null:
		return
	
	# Ensure legacy speed signal is not connected to the background
	if player.has_signal("speed_changed"):
		var speed_connections: Array = player.get_signal_connection_list("speed_changed")
		for conn in speed_connections:
			assert_ne(conn.callable.get_object(), background, "Legacy 'speed_changed' signal must not be connected to ParallaxManager.")
			
	# Ensure legacy fuel signal is not connected to the background
	if player.has_signal("fuel_depleted"):
		var fuel_connections: Array = player.get_signal_connection_list("fuel_depleted")
		for conn in fuel_connections:
			assert_ne(conn.callable.get_object(), background, "Legacy 'fuel_depleted' signal must not be connected to ParallaxManager.")
		
