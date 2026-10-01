## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later

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
