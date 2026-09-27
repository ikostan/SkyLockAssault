## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later

extends "res://addons/gut/test.gd"

const BULLET_SCENE: PackedScene = preload("res://scenes/bullet.tscn")


func test_defaults_preserve_existing_projectile_behavior() -> void:
	var config := BulletResource.new()
	assert_eq(config.fire_rate, 0.15)
	assert_eq(config.muzzle_offset, Vector2(0, -25))
	assert_eq(config.projectile_speed, 400.0)
	assert_eq(config.projectile_lifetime, 5.0)
	assert_eq(config.damage, 10)
	assert_eq(config.scale, Vector2(0.25, 0.25))
	assert_eq(config.collision_radius, 3.0)
	assert_eq(config.projectile_texture, preload("res://files/sprite/laser_sprites/01.png"))
	assert_eq(config.shot_sound, preload("res://files/sounds/sfx/retro-laser-1-236669.mp3"))


func test_custom_configuration_survives_scene_packing() -> void:
	var config := BulletResource.new()
	config.fire_rate = 0.7
	config.muzzle_offset = Vector2(12, -60)
	config.projectile_speed = 850.0
	config.projectile_lifetime = 2.5
	config.damage = 42
	config.scale = Vector2(0.6, 0.4)
	config.collision_radius = 8.0
	config.projectile_texture = GradientTexture2D.new()
	config.shot_sound = AudioStreamWAV.new()
	var source: Node2D = autofree(BULLET_SCENE.instantiate())
	source.config = config
	var packed := PackedScene.new()
	assert_eq(packed.pack(source), OK)
	var restored: Node2D = autofree(packed.instantiate())
	var restored_config: BulletResource = restored.config

	# Exported configuration must reach scenes instantiated by the weapon controller.
	assert_not_null(restored_config)
	if restored_config == null:
		return
	assert_eq(restored_config.fire_rate, 0.7)
	assert_eq(restored_config.muzzle_offset, Vector2(12, -60))
	assert_eq(restored_config.projectile_speed, 850.0)
	assert_eq(restored_config.projectile_lifetime, 2.5)
	assert_eq(restored_config.damage, 42)
	assert_eq(restored_config.scale, Vector2(0.6, 0.4))
	assert_eq(restored_config.collision_radius, 8.0)
	assert_eq(restored_config.projectile_texture, config.projectile_texture)
	assert_eq(restored_config.shot_sound, config.shot_sound)


func test_new_resources_do_not_share_mutable_tuning() -> void:
	var first := BulletResource.new()
	var second := BulletResource.new()
	first.damage = 0
	first.muzzle_offset.x = 90
	first.scale.y = 2.0
	first.projectile_texture = null
	first.shot_sound = null

	assert_eq(second.damage, 10)
	assert_eq(second.muzzle_offset, Vector2(0, -25))
	assert_eq(second.scale, Vector2(0.25, 0.25))
	assert_not_null(second.projectile_texture)
	assert_not_null(second.shot_sound)
