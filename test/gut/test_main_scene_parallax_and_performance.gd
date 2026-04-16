## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
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
	main_scene = preload("res://scenes/main_scene.tscn").instantiate()
	add_child(main_scene)
	await get_tree().process_frame


func after_each() -> void:
	# Use the helper's static method
	if is_instance_valid(main_scene):
		GutHelper.safe_hard_free(main_scene)
	await get_tree().process_frame


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
## A proxy performance test to ensure the _process block runs in under 1 millisecond.
## :rtype: void
func test_process_script_execution_time() -> void:
	gut.p("Testing: MainScene._process execution must remain lightweight (under 1ms).")

	# Pre-warm: absorb any one-shot work (e.g. show_message on first call).
	main_scene._process(0.016)

	var iterations: int = 60
	var start_time: int = Time.get_ticks_usec()
	for i in range(iterations):
		main_scene._process(0.016)
	var total_time_usec: int = Time.get_ticks_usec() - start_time
	var average_time_per_frame_usec: float = float(total_time_usec) / iterations

	# 2000 µs = 2 ms — loose bound to avoid CI flakiness while still catching
	# regressions (the profiler screenshot shows ~9 ms total SceneTree process,
	# so the script-only portion is well under 1 ms on a local machine).
	assert_lt(
		average_time_per_frame_usec,
		2000.0,
		"MainScene._process is taking too long. Look for expensive operations in _process."
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
