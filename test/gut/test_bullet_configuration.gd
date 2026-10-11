## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

extends "res://addons/gut/test.gd"

const BULLET_SCENE: PackedScene = preload("res://scenes/bullet.tscn")

var firer: Node2D
var config: BulletResource
var original_settings: GameSettingsResource
var original_filter: int
var original_root_children: Array[Node]


class DamageTarget extends Area2D:
	var hits: Array[int] = []

	func take_damage(amount: int) -> void:
		hits.append(amount)


func before_each() -> void:
	original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()
	original_filter = get_viewport().canvas_item_default_texture_filter
	original_root_children = get_tree().root.get_children()
	config = BulletResource.new()
	config.fire_rate = 0.4
	config.muzzle_offset = Vector2(13, -41)
	config.projectile_speed = 720.0
	config.projectile_lifetime = 1.75
	config.damage = 37
	config.scale = Vector2(0.6, 0.4)
	config.collision_radius = 6.5
	config.projectile_texture = GradientTexture2D.new()
	config.shot_sound = null
	firer = autofree(BULLET_SCENE.instantiate())
	firer.config = config
	add_child(firer)


func after_each() -> void:
	# Projectiles and sound players are parented to root, outside GUT's fixture.
	for node in get_tree().root.get_children():
		if node not in original_root_children:
			if node is RigidBody2D or node is AudioStreamPlayer2D:
				node.free()
	Globals.settings = original_settings
	get_viewport().canvas_item_default_texture_filter = original_filter


func _projectiles() -> Array[Node]:
	var result: Array[Node] = []
	for node in get_tree().get_nodes_in_group("bullets"):
		if node not in original_root_children:
			result.append(node)
	return result


func _spawn_projectile() -> RigidBody2D:
	firer.spawn_projectile()
	var projectiles := _projectiles()
	assert_eq(projectiles.size(), 1, "One projectile should be created per spawn.")
	return projectiles[0] as RigidBody2D if projectiles.size() == 1 else null


func _sound_players() -> Array[AudioStreamPlayer2D]:
	var result: Array[AudioStreamPlayer2D] = []
	for node in get_tree().root.get_children():
		if node is AudioStreamPlayer2D and node not in original_root_children:
			result.append(node)
	return result


func _child_of_type(parent: Node, type_name: String) -> Node:
	# Runtime-created nodes have generated names; select by their role instead.
	var children := parent.find_children("*", type_name, false, false)
	assert_eq(children.size(), 1, "Expected one %s child." % type_name)
	return children[0] if children.size() == 1 else null


func test_unconfigured_scenes_receive_independent_default_resources() -> void:
	var first: Node2D = add_child_autofree(BULLET_SCENE.instantiate())
	var second: Node2D = add_child_autofree(BULLET_SCENE.instantiate())
	assert_true(first.config is BulletResource)
	assert_eq(first.config, second.config, "Default bullets share one preloaded resource.")
	assert_eq(second.config.fire_rate, 0.15)


func test_ready_preserves_injected_resource() -> void:
	assert_eq(firer.config, config, "Inspector configuration must not be replaced by defaults.")
	assert_eq(firer.config.damage, 37)
	assert_eq(firer.config.collision_radius, 6.5)


func test_fire_scales_configured_cooldown_with_difficulty(
	difficulty: float = use_parameters([0.5, 1.0, 2.0])
) -> void:
	Globals.settings.difficulty = difficulty
	assert_true(firer.fire())
	assert_almost_eq(firer.timer.wait_time, 0.4 * difficulty, 0.0001)
	assert_true(firer.timer.one_shot)
	assert_false(firer.timer.is_stopped())
	assert_false(firer.can_fire)
	assert_eq(_projectiles().size(), 1)


func test_cooldown_rejects_second_shot_until_timeout() -> void:
	assert_true(firer.fire())
	assert_false(firer.fire())
	assert_eq(_projectiles().size(), 1, "Rejected shots must not create another projectile.")
	# Drive the timeout deterministically instead of sleeping for a real cooldown.
	firer.timer.stop()
	firer.timer.timeout.emit()
	assert_true(firer.can_fire)
	assert_true(firer.fire())
	assert_eq(_projectiles().size(), 2)


func test_projectile_uses_configured_motion_and_global_muzzle_offset() -> void:
	var mount: Node2D = add_child_autofree(Node2D.new())
	firer.reparent(mount)
	mount.position = Vector2(80, 30)
	firer.position = Vector2(25, 50)
	var expected_position := firer.global_position + config.muzzle_offset
	var projectile := _spawn_projectile()
	if projectile == null:
		return
	assert_eq(projectile.global_position, expected_position)
	assert_eq(projectile.linear_velocity, Vector2(0, -720))
	assert_eq(projectile.gravity_scale, 0.0)
	assert_eq(projectile.get_parent(), get_tree().root)


func test_projectile_uses_configured_texture_scale_and_hitbox() -> void:
	var projectile := _spawn_projectile()
	if projectile == null:
		return
	var sprite := _child_of_type(projectile, "Sprite2D") as Sprite2D
	var area := _child_of_type(projectile, "Area2D")
	var collision := _child_of_type(area, "CollisionShape2D") as CollisionShape2D
	assert_eq(sprite.texture, config.projectile_texture)
	assert_eq(sprite.scale, Vector2(0.6, 0.4))
	assert_true(collision.shape is CircleShape2D)
	assert_eq(collision.shape.radius, 6.5)


func test_projectile_lifetime_uses_config_and_frees_only_projectile() -> void:
	var projectile := _spawn_projectile()
	if projectile == null:
		return
	var lifetime := _child_of_type(projectile, "Timer") as Timer
	assert_eq(lifetime.wait_time, 1.75)
	assert_true(lifetime.one_shot)
	assert_false(lifetime.is_stopped())
	lifetime.stop()
	lifetime.timeout.emit()
	assert_true(projectile.is_queued_for_deletion())
	assert_false(firer.is_queued_for_deletion())


func test_collision_delivers_configured_damage(damage: int = use_parameters([0, 37])) -> void:
	config.damage = damage
	var target: DamageTarget = autofree(DamageTarget.new())
	var projectile := _spawn_projectile()
	if projectile == null:
		return
	var area := _child_of_type(projectile, "Area2D") as Area2D
	area.area_entered.emit(target)
	assert_eq(target.hits.size(), 1)
	assert_eq(target.hits[0], damage)
	assert_true(projectile.is_queued_for_deletion())
	assert_false(firer.is_queued_for_deletion())


func test_collision_without_damage_receiver_still_removes_projectile() -> void:
	var target: Area2D = autofree(Area2D.new())
	var projectile := _spawn_projectile()
	if projectile == null:
		return
	var area := _child_of_type(projectile, "Area2D") as Area2D
	area.area_entered.emit(target)
	assert_true(projectile.is_queued_for_deletion())
	assert_false(target.is_queued_for_deletion())


func test_missing_texture_and_zero_speed_still_create_collision_projectile() -> void:
	config.projectile_texture = null
	config.projectile_speed = 0.0
	config.muzzle_offset = Vector2.ZERO
	var projectile := _spawn_projectile()
	if projectile == null:
		return
	var sprite := _child_of_type(projectile, "Sprite2D") as Sprite2D
	assert_null(sprite.texture)
	assert_eq(projectile.linear_velocity, Vector2.ZERO)
	assert_eq(projectile.global_position, firer.global_position)
	var area := _child_of_type(projectile, "Area2D")
	var collision := _child_of_type(area, "CollisionShape2D") as CollisionShape2D
	assert_not_null(collision.shape)


func test_null_sound_allows_silent_firing() -> void:
	assert_true(firer.fire())
	assert_eq(_projectiles().size(), 1)
	assert_eq(_sound_players().size(), 0)


func test_configured_sound_uses_weapon_bus_and_cleans_up_on_finish() -> void:
	var sound := AudioStreamWAV.new()
	sound.data = PackedByteArray([0, 0, 0, 0])
	config.shot_sound = sound
	firer.play_sfx_with_volume()
	var players := _sound_players()
	assert_eq(players.size(), 1)
	if players.size() != 1:
		return
	var player := players[0]
	assert_eq(player.stream, sound)
	assert_eq(player.bus, AudioConstants.BUS_SFX_WEAPON)
	assert_eq(player.volume_db, 0.0)
	assert_true(player.playing)
	player.finished.emit()
	assert_true(player.is_queued_for_deletion())
