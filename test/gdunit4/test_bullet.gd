## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

extends GdUnitTestSuite

var bullet_scene := preload("res://scenes/bullet.tscn")


class DamageTarget extends Area2D:
	var received_damage: int = -1

	func take_damage(amount: int) -> void:
		received_damage = amount


func test_bullet_collision() -> void:
	var firer: Node2D = auto_free(bullet_scene.instantiate())
	firer.config = BulletResource.new()
	firer.config.damage = 23
	var original_filter := get_viewport().canvas_item_default_texture_filter
	get_tree().root.add_child(firer)
	get_viewport().canvas_item_default_texture_filter = original_filter
	var existing_projectiles := get_tree().get_nodes_in_group("bullets")
	firer.spawn_projectile()
	var spawned: Array[Node] = []
	for node in get_tree().get_nodes_in_group("bullets"):
		if node not in existing_projectiles:
			spawned.append(auto_free(node))
	assert_int(spawned.size()).is_equal(1)
	if spawned.size() != 1:
		return
	var projectile := spawned[0]
	var target: DamageTarget = auto_free(DamageTarget.new())

	# Collision belongs to the spawned projectile; the firer is now only a factory.
	var areas := projectile.find_children("*", "Area2D", false, false)
	assert_int(areas.size()).is_equal(1)
	if areas.size() != 1:
		return
	var hit_area := areas[0] as Area2D
	hit_area.area_entered.emit(target)

	assert_int(target.received_damage).is_equal(23)
	assert_that(projectile).is_queued_for_deletion()
	assert_bool(firer.is_queued_for_deletion()).is_false()


## Physics-body enemy with a real collision shape (#1139).
class EnemyBody extends StaticBody2D:
	var received: Array[int] = []

	func take_damage(amount: int) -> void:
		received.append(amount)


## Builds a 40 x 40 static body on the given layer bits at a global position.
func _make_body_target(layer_bits: int, at: Vector2) -> EnemyBody:
	var target := EnemyBody.new()
	target.collision_layer = layer_bits
	target.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40, 40)
	shape.shape = rect
	target.add_child(shape)
	target.position = at
	return target


## Spawns one stationary projectile at [param at] and returns it.
func _spawn_stationary_projectile(at: Vector2, damage: int) -> Node:
	var firer: Node2D = auto_free(bullet_scene.instantiate())
	firer.config = BulletResource.new()
	firer.config.damage = damage
	firer.config.projectile_speed = 0.0
	firer.config.muzzle_offset = Vector2.ZERO
	get_tree().root.add_child(firer)
	firer.global_position = at
	var existing := get_tree().get_nodes_in_group("bullets")
	firer.spawn_projectile()
	for node in get_tree().get_nodes_in_group("bullets"):
		if node not in existing:
			return node
	return null


func _await_physics_frames(count: int) -> void:
	for i in range(count):
		await get_tree().physics_frame


## #1139: a real overlap, not an emitted signal. A projectile overlapping a physics body on
## the enemies layer damages it once and is freed.
func test_projectile_damages_physics_body_on_enemies_layer() -> void:
	var at := Vector2(320, 240)
	var target: EnemyBody = auto_free(_make_body_target(1 << 1, at))
	get_tree().root.add_child(target)
	await _await_physics_frames(2)

	var projectile := _spawn_stationary_projectile(at, 29)
	assert_object(projectile).is_not_null()
	await _await_physics_frames(6)

	assert_array(target.received).is_equal([29])
	assert_bool(is_instance_valid(projectile)).is_false()


## #1139: HitArea only watches the enemies layer, so a body on the player layer is not hit
## and the projectile keeps flying.
func test_projectile_ignores_physics_body_on_player_layer() -> void:
	var at := Vector2(160, 120)
	var target: EnemyBody = auto_free(_make_body_target(1 << 0, at))
	get_tree().root.add_child(target)
	await _await_physics_frames(2)

	var projectile := _spawn_stationary_projectile(at, 29)
	assert_object(projectile).is_not_null()
	await _await_physics_frames(6)

	assert_array(target.received).is_empty()
	assert_bool(is_instance_valid(projectile)).is_true()
	if is_instance_valid(projectile):
		assert_bool(projectile.is_queued_for_deletion()).is_false()
		projectile.free()
