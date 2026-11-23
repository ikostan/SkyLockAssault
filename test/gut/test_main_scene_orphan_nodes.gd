## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_main_scene_orphan_nodes.gd

extends "res://addons/gut/test.gd"

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

func verify_no_orphan_leaks(baseline_orphans: int, context: String) -> void:
	var current_orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	assert_eq(current_orphans, baseline_orphans, context)

func test_teardown_memory_sync() -> void:
	var baseline_orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	
	main_scene.setup_bushes_layer(viewport_mock)
	main_scene.setup_decor_layer(viewport_mock)
	
	await get_tree().process_frame
	
	# FIX: Free manually AND nullify so after_each ignores it
	GutHelper.safe_hard_free(main_scene)
	main_scene = null 
	
	await get_tree().process_frame
	verify_no_orphan_leaks(baseline_orphans, "Expected orphans to return to baseline.")

func test_repeated_setup_call_stability() -> void:
	var baseline_orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	for i in range(50):
		main_scene.setup_bushes_layer(viewport_mock)
	await get_tree().process_frame
	verify_no_orphan_leaks(baseline_orphans, "No accumulated orphans after 50 calls.")

## Immediate Rebuild Integrity Test |
func test_immediate_rebuild_integrity() -> void:
	await get_tree().process_frame
	main_scene.setup_bushes_layer(viewport_mock)
	
	# Added -> bool to the lambda
	var initial_active_count: int = main_scene.bushes_layer.get_children().filter(
		func(c: Node) -> bool: return not c.is_queued_for_deletion()
	).size()
	
	main_scene.setup_bushes_layer(viewport_mock)
	
	# Added -> bool to the lambda
	var new_active_count: int = main_scene.bushes_layer.get_children().filter(
		func(c: Node) -> bool: return not c.is_queued_for_deletion()
	).size()
	
	assert_eq(new_active_count, initial_active_count, "Child count should remain stable.")

func test_layer_isolation() -> void:
	main_scene.setup_bushes_layer(viewport_mock)
	main_scene.setup_decor_layer(viewport_mock)
	await get_tree().process_frame
	
	var initial_decor: int = main_scene.decor_layer.get_child_count()
	main_scene.setup_bushes_layer(viewport_mock)
	await get_tree().process_frame
	assert_eq(main_scene.decor_layer.get_child_count(), initial_decor, "Decor count stable.")

func test_scene_reload_lifecycle() -> void:
	var baseline_orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	
	# FIX: Use safe_hard_free and nullify baseline scene
	GutHelper.safe_hard_free(main_scene)
	main_scene = null
	await get_tree().process_frame
	
	var reloaded_scene: MainScene = preload(GamePaths.MAIN_SCENE).instantiate()
	add_child(reloaded_scene)
	reloaded_scene.setup_bushes_layer(viewport_mock)
	await get_tree().process_frame
	
	# Clean up the reloaded instance manually too
	GutHelper.safe_hard_free(reloaded_scene)
	await get_tree().process_frame
	verify_no_orphan_leaks(baseline_orphans, "Clean teardown after reload.")

func test_stress_input_simulation() -> void:
	var baseline_orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	for i in range(10):
		main_scene.setup_bushes_layer(viewport_mock)
		main_scene.setup_decor_layer(viewport_mock)
		await get_tree().process_frame
	verify_no_orphan_leaks(baseline_orphans, "Stable memory after stress.")

## #1138: Weapon keeps a hidden firer per slot instead of freeing it on a swap. Freeing the
## level with several cached slots must still return the orphan count to its baseline.
func test_freeing_level_with_cached_weapon_slots_leaves_no_orphans() -> void:
	var weapon: Weapon = main_scene.player.weapon
	weapon.weapon_types.append(preload("res://scenes/bullet.tscn"))
	weapon.switch_to(1)
	weapon.switch_to(0)
	await get_tree().process_frame
	assert_eq(
		weapon.get_children().filter(func(c: Node) -> bool: return c is WeaponFirer).size(),
		2,
		"Both slots should be cached before the level is freed."
	)
	var baseline_orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)

	GutHelper.safe_hard_free(main_scene)
	main_scene = null
	await get_tree().process_frame
	verify_no_orphan_leaks(baseline_orphans, "Cached weapon slots are freed with the level.")


## Projectiles fired by the real level's player, found by ancestry so leftovers from other
## suites don't count.
func _level_projectiles(level: Node) -> Array[Node]:
	var result: Array[Node] = []
	for node: Node in get_tree().get_nodes_in_group("bullets"):
		if level.is_ancestor_of(node):
			result.append(node)
	return result


## Fires the player's weapon once, letting earlier cooldowns end first.
func _fire_player_weapon(level: MainScene) -> void:
	var weapon: Weapon = level.player.weapon
	weapon.weapon_resource.current_ammo = max(weapon.weapon_resource.current_ammo, 10)
	var firer := weapon.current_weapon as BulletFirer
	if firer and not firer.can_fire:
		firer.timer.stop()
		firer.timer.timeout.emit()
	weapon.fire()


## #1140: the level injects its Projectiles container, so shots are its children and never
## the scene root's.
func test_projectiles_spawn_under_the_level_container() -> void:
	_fire_player_weapon(main_scene)
	var fired := _level_projectiles(main_scene)
	assert_eq(fired.size(), 1, "One shot should be in flight.")
	for projectile: Node in fired:
		assert_eq(projectile.get_parent(), main_scene.projectiles)
	assert_same(main_scene.player.weapon.current_weapon.projectile_parent, main_scene.projectiles)


## #1140: the Projectiles container keeps the default process mode, so a shot in a paused
## level stops processing, its lifetime timer included, and starts again on resume.
func test_level_projectile_stops_processing_while_tree_is_paused() -> void:
	_fire_player_weapon(main_scene)
	var fired := _level_projectiles(main_scene)
	assert_eq(fired.size(), 1, "One shot should be in flight.")
	if fired.size() != 1:
		return

	var projectile: Node = fired[0]
	var tree := get_tree()
	var was_paused := tree.paused
	tree.paused = true
	var processes_while_paused := projectile.can_process()
	tree.paused = false
	var processes_when_resumed := projectile.can_process()
	tree.paused = was_paused

	assert_false(processes_while_paused, "The level's projectile should stop processing on pause.")
	assert_true(processes_when_resumed, "The projectile should process again on resume.")


## #1140: projectiles still in flight are freed with the level, and the orphan count returns
## to its baseline.
func test_freeing_level_with_in_flight_projectiles_leaves_no_orphans() -> void:
	_fire_player_weapon(main_scene)
	_fire_player_weapon(main_scene)
	await get_tree().process_frame
	var fired: Array = _level_projectiles(main_scene)  # Untyped: holds freed instances later
	assert_eq(fired.size(), 2, "Both shots should still be in flight.")
	var baseline_orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)

	GutHelper.safe_hard_free(main_scene)
	main_scene = null
	await get_tree().process_frame

	for projectile: Variant in fired:
		assert_false(is_instance_valid(projectile), "In-flight shots are freed with the level.")
	verify_no_orphan_leaks(baseline_orphans, "In-flight projectiles leave no orphans.")


## #1140: after the level is replaced, none of the old level's projectiles remain.
func test_replacing_level_leaves_no_old_projectiles() -> void:
	_fire_player_weapon(main_scene)
	var fired: Array = _level_projectiles(main_scene)
	assert_eq(fired.size(), 1)
	var bullets_before_replace: int = get_tree().get_nodes_in_group("bullets").size()

	GutHelper.safe_hard_free(main_scene)
	main_scene = preload(GamePaths.MAIN_SCENE).instantiate()
	add_child(main_scene)
	await get_tree().process_frame

	for projectile: Variant in fired:
		assert_false(is_instance_valid(projectile), "Old projectiles don't outlive their level.")
	assert_eq(_level_projectiles(main_scene).size(), 0, "The new level starts without shots.")
	assert_lt(
		get_tree().get_nodes_in_group("bullets").size(),
		bullets_before_replace,
		"Replacing the level removes its projectiles from the bullets group."
	)
