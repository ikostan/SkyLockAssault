## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_sprite_layer_setup.gd
##
## GUT tests for the shared bush and decor layer setup in MainScene (#1151).
## setup_bushes_layer() and setup_decor_layer() are thin wrappers around
## _populate_sprite_layer(). These tests pin what each layer must keep: two sprites per
## matching texture, uniform scales from 0.5 to 1.5, motion_scale (1, 0.5), vertical
## mirroring at parallax_screens_tall screens, and positions inside the layer. Decor-only
## rotation and flips are covered by test_decor_layer_transformations.gd.

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
	if is_instance_valid(main_scene):
		GutHelper.safe_hard_free(main_scene)
	main_scene = null
	await get_tree().process_frame


# ── Helpers ──────────────────────────────────────────────────────────────────


func _texture_count(prefix: String) -> int:
	var ids: Array = Array(main_scene.texture_preloader.get_resource_list()).filter(
		func(id: String) -> bool: return id.begins_with(prefix)
	)
	return ids.size()


func _sprites(layer: ParallaxLayer) -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	for child: Node in layer.get_children():
		if child is Sprite2D and not child.is_queued_for_deletion():
			out.append(child as Sprite2D)
	return out


func _textures_with_prefix(prefix: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for id: String in main_scene.texture_preloader.get_resource_list():
		if id.begins_with(prefix):
			out.append(main_scene.texture_preloader.get_resource(id))
	return out


## Checks everything the bush and decor layers share.
func _assert_layer_shape(layer: ParallaxLayer, prefix: String, label: String) -> void:
	var expected_count: int = _texture_count(prefix) * 2
	assert_gt(_texture_count(prefix), 0, label + ": the preloader has matching textures")
	var sprites: Array[Sprite2D] = _sprites(layer)
	assert_eq(sprites.size(), expected_count, label + ": two sprites per texture")

	var layer_height: float = viewport_mock.y * main_scene.parallax_screens_tall
	assert_eq(layer.motion_scale, Vector2(1, 0.5), label + ": motion_scale")
	assert_eq(layer.motion_mirroring, Vector2(0, layer_height), label + ": mirroring")

	var allowed: Array[Texture2D] = _textures_with_prefix(prefix)
	for sprite: Sprite2D in sprites:
		assert_false(sprite.centered, label + ": sprites are not centered")
		assert_true(allowed.has(sprite.texture), label + ": texture comes from its prefix")
		assert_true(is_equal_approx(sprite.scale.x, sprite.scale.y), label + ": uniform scale")
		assert_between(sprite.scale.x, 0.5, 1.5, label + ": scale range")
		var size: Vector2 = sprite.texture.get_size() * sprite.scale.x
		assert_between(sprite.position.x, 0.0, viewport_mock.x - size.x, label + ": x inside")
		assert_between(sprite.position.y, 0.0, layer_height - size.y, label + ": y inside")


# ── Shared shape ─────────────────────────────────────────────────────────────


## LAYER-01 | Bushes keep their count, scale range, motion scale and mirroring.
func test_layer_01_bushes_layer_shape() -> void:
	main_scene.setup_bushes_layer(viewport_mock)
	_assert_layer_shape(main_scene.bushes_layer, "bush_", "Bushes")


## LAYER-02 | Decor keeps its count, scale range, motion scale and mirroring.
func test_layer_02_decor_layer_shape() -> void:
	main_scene.setup_decor_layer(viewport_mock)
	_assert_layer_shape(main_scene.decor_layer, "decor_", "Decor")


## LAYER-03 | Bushes get no decor-only changes: no rotation and no flips.
func test_layer_03_bushes_are_not_rotated_or_flipped() -> void:
	main_scene.setup_bushes_layer(viewport_mock)
	for sprite: Sprite2D in _sprites(main_scene.bushes_layer):
		assert_eq(sprite.rotation, 0.0, "bush rotation")
		assert_false(sprite.flip_h, "bush flip_h")
		assert_false(sprite.flip_v, "bush flip_v")


## LAYER-04 | The layer height follows parallax_screens_tall.
func test_layer_04_layer_height_follows_screens_tall() -> void:
	main_scene.parallax_screens_tall = 3.0
	main_scene.setup_bushes_layer(viewport_mock)
	main_scene.setup_decor_layer(viewport_mock)
	_assert_layer_shape(main_scene.bushes_layer, "bush_", "Bushes (3 screens)")
	_assert_layer_shape(main_scene.decor_layer, "decor_", "Decor (3 screens)")


## LAYER-05 | The same seed gives the same layout, so the shared helper keeps the random
## calls in a fixed order.
func test_layer_05_same_seed_same_layout() -> void:
	seed(1151)
	main_scene.setup_decor_layer(viewport_mock)
	var first: Array = []
	for sprite: Sprite2D in _sprites(main_scene.decor_layer):
		first.append([sprite.texture, sprite.scale, sprite.rotation, sprite.flip_h, sprite.position])

	seed(1151)
	main_scene.setup_decor_layer(viewport_mock)
	var second: Array = []
	for sprite: Sprite2D in _sprites(main_scene.decor_layer):
		second.append([sprite.texture, sprite.scale, sprite.rotation, sprite.flip_h, sprite.position])

	assert_eq(second, first, "seeded rebuilds match")


# ── Empty layers ─────────────────────────────────────────────────────────────


## LAYER-06 | With no matching textures, both layers end up empty, even after an earlier
## build, and keep the motion settings they had.
func test_layer_06_no_matching_textures_leaves_layers_empty() -> void:
	main_scene.setup_bushes_layer(viewport_mock)
	main_scene.setup_decor_layer(viewport_mock)
	var bush_mirroring: Vector2 = main_scene.bushes_layer.motion_mirroring
	var decor_mirroring: Vector2 = main_scene.decor_layer.motion_mirroring

	var original_preloader: ResourcePreloader = main_scene.texture_preloader
	var empty_preloader: ResourcePreloader = ResourcePreloader.new()
	main_scene.texture_preloader = empty_preloader

	main_scene.setup_bushes_layer(viewport_mock)
	main_scene.setup_decor_layer(viewport_mock)

	assert_eq(main_scene.bushes_layer.get_child_count(), 0, "bushes emptied")
	assert_eq(main_scene.decor_layer.get_child_count(), 0, "decor emptied")
	assert_eq(main_scene.bushes_layer.motion_mirroring, bush_mirroring, "bush mirroring kept")
	assert_eq(main_scene.decor_layer.motion_mirroring, decor_mirroring, "decor mirroring kept")

	main_scene.texture_preloader = original_preloader
	empty_preloader.free()


## LAYER-07 | An unknown prefix clears the layer and adds nothing.
func test_layer_07_unknown_prefix_clears_layer() -> void:
	main_scene.setup_bushes_layer(viewport_mock)
	assert_gt(main_scene.bushes_layer.get_child_count(), 0, "precondition: layer has sprites")

	main_scene._populate_sprite_layer(
		main_scene.bushes_layer, "no_such_prefix_", viewport_mock, Callable()
	)

	assert_eq(main_scene.bushes_layer.get_child_count(), 0, "layer cleared")


## LAYER-08 | A null layer is ignored without errors.
func test_layer_08_null_layer_is_ignored() -> void:
	main_scene._populate_sprite_layer(null, "bush_", viewport_mock, Callable())
	assert_true(true, "no crash on a null layer")


# ── configure callback and rebuilds ──────────────────────────────────────────


## LAYER-09 | The configure callback runs once per sprite, and only for its own layer.
func test_layer_09_configure_runs_once_per_sprite() -> void:
	var seen: Array[Sprite2D] = []
	var count_sprite: Callable = func(sprite: Sprite2D) -> void: seen.append(sprite)

	main_scene._populate_sprite_layer(
		main_scene.bushes_layer, "bush_", viewport_mock, count_sprite
	)

	assert_eq(seen.size(), _texture_count("bush_") * 2, "one call per sprite")
	assert_eq(seen, _sprites(main_scene.bushes_layer), "called with the layer's own sprites")


## LAYER-10 | Rebuilding either layer replaces its sprites and leaves no orphan nodes.
func test_layer_10_rebuild_leaves_no_orphans() -> void:
	main_scene.setup_bushes_layer(viewport_mock)
	main_scene.setup_decor_layer(viewport_mock)
	await get_tree().process_frame
	var baseline: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)

	for i in range(5):
		main_scene.setup_bushes_layer(viewport_mock)
		main_scene.setup_decor_layer(viewport_mock)
	await get_tree().process_frame

	assert_eq(
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), baseline, "no orphans"
	)
	assert_eq(_sprites(main_scene.bushes_layer).size(), _texture_count("bush_") * 2)
	assert_eq(_sprites(main_scene.decor_layer).size(), _texture_count("decor_") * 2)


func test_rebuilding_decor_preserves_bush_sprites_and_mirroring() -> void:
	main_scene.setup_bushes_layer(viewport_mock)
	main_scene.setup_decor_layer(viewport_mock)
	var bushes: Array[int] = []
	for sprite: Sprite2D in _sprites(main_scene.bushes_layer):
		bushes.append(sprite.get_instance_id())
	var bush_mirroring := main_scene.bushes_layer.motion_mirroring
	var smaller_viewport := Vector2(viewport_mock.x, viewport_mock.y / 2.0)

	main_scene.setup_decor_layer(smaller_viewport)

	var remaining_bushes: Array[int] = []
	for sprite: Sprite2D in _sprites(main_scene.bushes_layer):
		remaining_bushes.append(sprite.get_instance_id())
	assert_eq(remaining_bushes, bushes, "the original bush sprites stay in place")
	assert_eq(main_scene.bushes_layer.motion_mirroring, bush_mirroring)
	assert_eq(main_scene.decor_layer.motion_mirroring, bush_mirroring / 2.0)
