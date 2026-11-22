## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_projectile.gd
##
## GUT unit tests for projectile.tscn and Projectile (#1139): one hit handler for physics
## bodies and Area2D targets, hit-once behavior, the shared collision shape, the named
## physics layers, and the lifetime timer.

extends "res://addons/gut/test.gd"

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")
const PLAYER_SCENE_PATH: String = "res://scenes/Player.tscn"

## Bit values of the named 2D physics layers (layer N is bit N - 1).
const LAYER_PLAYER: int = 1
const LAYER_ENEMIES: int = 1 << 1
const LAYER_PLAYER_PROJECTILES: int = 1 << 2

var config: BulletResource


## Physics-body enemy, as the first enemy is expected to be.
class BodyTarget extends StaticBody2D:
	var hits: Array[int] = []

	func take_damage(amount: int) -> void:
		hits.append(amount)


## Enemy hurtbox built as an Area2D.
class AreaTarget extends Area2D:
	var hits: Array[int] = []

	func take_damage(amount: int) -> void:
		hits.append(amount)


func before_each() -> void:
	config = BulletResource.new()
	config.damage = 17


## Instantiates, configures and adds a projectile under this test node.
func _spawn(spawn_config: BulletResource = null, position := Vector2(40, 60)) -> Projectile:
	var projectile := PROJECTILE_SCENE.instantiate() as Projectile
	projectile.configure(spawn_config if spawn_config else config, position)
	add_child_autofree(projectile)
	return projectile


func _hit_area(projectile: Projectile) -> Area2D:
	return projectile.get_node("HitArea") as Area2D


func _shape(projectile: Projectile) -> CircleShape2D:
	return projectile.get_node("HitArea/CollisionShape2D").shape as CircleShape2D


func test_scene_root_is_a_projectile_in_the_bullets_group() -> void:
	var projectile := _spawn()
	assert_true(projectile is Projectile)
	assert_true(projectile is RigidBody2D)
	assert_true(projectile.is_in_group("bullets"), "Cleanup and benchmarks query this group.")
	assert_eq(projectile.gravity_scale, 0.0)
	assert_not_null(projectile.get_node_or_null("Sprite2D"))
	assert_not_null(projectile.get_node_or_null("HitArea/CollisionShape2D"))
	assert_not_null(projectile.get_node_or_null("LifetimeTimer"))


func test_physics_body_target_takes_damage_and_projectile_is_freed() -> void:
	var target: BodyTarget = autofree(BodyTarget.new())
	var projectile := _spawn()
	_hit_area(projectile).body_entered.emit(target)
	assert_eq(target.hits, [17] as Array[int], "A physics-body enemy must take the configured damage.")
	assert_true(projectile.is_queued_for_deletion())


func test_area_target_with_take_damage_takes_damage_and_projectile_is_freed() -> void:
	var target: AreaTarget = autofree(AreaTarget.new())
	var projectile := _spawn()
	_hit_area(projectile).area_entered.emit(target)
	assert_eq(target.hits, [17] as Array[int], "An Area2D hurtbox must take the configured damage.")
	assert_true(projectile.is_queued_for_deletion())


func test_target_without_take_damage_frees_projectile_without_error(
	kind: String = use_parameters(["body", "area"])
) -> void:
	var projectile := _spawn()
	if kind == "body":
		var body: StaticBody2D = autofree(StaticBody2D.new())
		_hit_area(projectile).body_entered.emit(body)
		assert_false(body.is_queued_for_deletion(), "The target itself must not be freed.")
	else:
		var area: Area2D = autofree(Area2D.new())
		_hit_area(projectile).area_entered.emit(area)
		assert_false(area.is_queued_for_deletion(), "The target itself must not be freed.")
	# GUT fails the test on any unexpected engine or script error.
	assert_true(projectile.is_queued_for_deletion())


func test_both_signals_for_one_target_apply_damage_once() -> void:
	var target: AreaTarget = autofree(AreaTarget.new())
	var projectile := _spawn()
	var hit_area := _hit_area(projectile)
	hit_area.body_entered.emit(target)
	hit_area.area_entered.emit(target)
	assert_eq(target.hits.size(), 1, "One projectile must damage a target only once.")


func test_two_targets_in_the_same_tick_only_the_first_takes_damage() -> void:
	var first: BodyTarget = autofree(BodyTarget.new())
	var second: AreaTarget = autofree(AreaTarget.new())
	var projectile := _spawn()
	var hit_area := _hit_area(projectile)
	hit_area.body_entered.emit(first)
	hit_area.area_entered.emit(second)
	assert_eq(first.hits.size(), 1)
	assert_eq(second.hits.size(), 0, "One projectile must never damage two targets.")


## The first contact uses up the projectile even when the target can't take damage, so a
## damageable target touched afterwards takes no damage.
func test_first_contact_without_damage_handler_blocks_later_damage() -> void:
	var blocker: StaticBody2D = autofree(StaticBody2D.new())
	var enemy: AreaTarget = autofree(AreaTarget.new())
	var projectile := _spawn()
	var hit_area := _hit_area(projectile)

	hit_area.body_entered.emit(blocker)
	hit_area.area_entered.emit(enemy)

	assert_true(projectile.is_queued_for_deletion())
	assert_eq(enemy.hits.size(), 0, "A non-damageable contact still consumes the shot.")


## Real overlap, not an emitted signal: HitArea detects an Area2D hurtbox only on the enemies
## layer (2). Hurtboxes on the player (1) or player_projectiles (3) layer are ignored and the
## projectile stays alive.
func test_physics_detects_only_enemy_hurtboxes(
	layer: int = use_parameters([LAYER_ENEMIES, LAYER_PLAYER, LAYER_PLAYER_PROJECTILES])
) -> void:
	var target: AreaTarget = autofree(AreaTarget.new())
	target.collision_layer = layer
	target.collision_mask = 0
	target.monitoring = false
	var hitbox := CollisionShape2D.new()
	hitbox.shape = CircleShape2D.new()
	target.add_child(hitbox)
	target.position = Vector2(300, 200)
	add_child(target)

	config.projectile_speed = 0.0
	var projectile := _spawn(config, target.global_position)
	# Let the physics server register both shapes and dispatch the overlap signal.
	await wait_physics_frames(4)

	if layer == LAYER_ENEMIES:
		assert_eq(target.hits, [17] as Array[int])
		assert_false(is_instance_valid(projectile), "An enemy overlap removes the shot.")
	else:
		assert_eq(target.hits.size(), 0)
		assert_true(is_instance_valid(projectile), "A filtered overlap leaves the shot alive.")


func test_zero_damage_still_counts_as_the_hit() -> void:
	config.damage = 0
	var first: BodyTarget = autofree(BodyTarget.new())
	var second: BodyTarget = autofree(BodyTarget.new())
	var projectile := _spawn()
	_hit_area(projectile).body_entered.emit(first)
	_hit_area(projectile).body_entered.emit(second)
	assert_eq(first.hits, [0] as Array[int])
	assert_eq(second.hits.size(), 0)
	assert_true(projectile.is_queued_for_deletion())


func test_default_radius_projectiles_share_one_shape() -> void:
	var first := _spawn(BulletResource.new())
	var second := _spawn(BulletResource.new())
	assert_same(_shape(first), _shape(second), "Default-radius projectiles must share one shape.")
	assert_eq(_shape(first).radius, BulletResource.new().collision_radius)


func test_custom_radius_does_not_change_the_shared_shape() -> void:
	var default_projectile := _spawn(BulletResource.new())
	var shared := _shape(default_projectile)
	var shared_radius: float = shared.radius

	var custom := BulletResource.new()
	custom.collision_radius = shared_radius * 3.0
	var custom_projectile := _spawn(custom)

	assert_not_same(_shape(custom_projectile), shared, "A custom radius needs its own shape.")
	assert_eq(_shape(custom_projectile).radius, shared_radius * 3.0)
	assert_eq(shared.radius, shared_radius, "The shared shape must keep the scene's radius.")
	var later := _spawn(BulletResource.new())
	assert_same(_shape(later), shared, "Later default projectiles must still share the shape.")


func test_hit_area_uses_player_projectiles_layer_and_enemies_mask() -> void:
	var projectile := _spawn()
	var hit_area := _hit_area(projectile)
	assert_eq(hit_area.collision_layer, LAYER_PLAYER_PROJECTILES, "HitArea must be on layer 3 only.")
	assert_eq(hit_area.collision_mask, LAYER_ENEMIES, "HitArea must watch layer 2 only.")
	assert_true(hit_area.monitoring)


func test_projectile_body_has_no_collision_layers() -> void:
	var projectile := _spawn()
	assert_eq(projectile.collision_layer, 0, "The shapeless root body must not sit on any layer.")
	assert_eq(projectile.collision_mask, 0, "The shapeless root body must not watch any layer.")


func test_physics_layers_are_named_in_project_settings() -> void:
	assert_eq(ProjectSettings.get_setting("layer_names/2d_physics/layer_1"), "player")
	assert_eq(ProjectSettings.get_setting("layer_names/2d_physics/layer_2"), "enemies")
	assert_eq(ProjectSettings.get_setting("layer_names/2d_physics/layer_3"), "player_projectiles")


func test_player_body_keeps_layer_1_and_its_current_mask() -> void:
	var player_scene: PackedScene = load(PLAYER_SCENE_PATH)
	var player: Node = autofree(player_scene.instantiate())
	var body := player.get_node("CharacterBody2D") as CharacterBody2D
	assert_eq(body.collision_layer, LAYER_PLAYER, "The player's body must be on the player layer.")
	assert_eq(body.collision_mask, LAYER_PLAYER, "Naming the layers must not change the mask.")


func test_configure_applies_motion_visuals_and_lifetime() -> void:
	config.projectile_speed = 650.0
	config.projectile_lifetime = 2.5
	config.scale = Vector2(0.7, 0.3)
	config.projectile_texture = GradientTexture2D.new()
	var projectile := _spawn(config, Vector2(12, -8))
	assert_eq(projectile.global_position, Vector2(12, -8))
	assert_almost_eq(projectile.global_rotation, -PI / 2, 0.0001)
	assert_eq(projectile.linear_velocity, Vector2(0, -650))
	var sprite := projectile.get_node("Sprite2D") as Sprite2D
	assert_eq(sprite.texture, config.projectile_texture)
	assert_eq(sprite.scale, Vector2(0.7, 0.3))
	var lifetime := projectile.get_node("LifetimeTimer") as Timer
	assert_eq(lifetime.wait_time, 2.5)
	assert_true(lifetime.one_shot)
	assert_false(lifetime.is_stopped(), "The lifetime starts when the projectile enters the tree.")


func test_configure_after_entering_the_tree_restarts_the_lifetime() -> void:
	var projectile := PROJECTILE_SCENE.instantiate() as Projectile
	add_child_autofree(projectile)
	config.projectile_lifetime = 0.75
	projectile.configure(config, Vector2(5, 5))
	var lifetime := projectile.get_node("LifetimeTimer") as Timer
	assert_eq(lifetime.wait_time, 0.75)
	assert_false(lifetime.is_stopped())
	assert_almost_eq(lifetime.time_left, 0.75, 0.05, "The timer must run with the new lifetime.")
	assert_eq(projectile.global_position, Vector2(5, 5))


func test_unconfigured_projectile_still_frees_itself_after_its_lifetime() -> void:
	var projectile := PROJECTILE_SCENE.instantiate() as Projectile
	add_child_autofree(projectile)
	var lifetime := projectile.get_node("LifetimeTimer") as Timer
	assert_false(lifetime.is_stopped(), "A projectile must never live forever.")
	lifetime.stop()
	lifetime.timeout.emit()
	assert_true(projectile.is_queued_for_deletion())


func test_configure_does_not_write_to_the_config() -> void:
	var defaults: BulletResource = load("res://config_resources/default_bullet.tres")
	var radius_before: float = defaults.collision_radius
	var damage_before: int = defaults.damage
	var projectile := _spawn(defaults)
	var target: BodyTarget = autofree(BodyTarget.new())
	_hit_area(projectile).body_entered.emit(target)
	assert_eq(defaults.collision_radius, radius_before)
	assert_eq(defaults.damage, damage_before)
	assert_eq(target.hits, [damage_before] as Array[int])
