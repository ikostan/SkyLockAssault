## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

extends "res://addons/gut/test.gd"

const BULLET_SCENE: PackedScene = preload("res://scenes/bullet.tscn")
const DEFAULT_BULLET: BulletResource = preload("res://config_resources/default_bullet.tres")
const LASER_TEXTURE_PATH: String = "res://files/sprite/laser_sprites/01.png"
const LASER_SOUND_PATH: String = "res://files/sounds/sfx/retro-laser-1-236669.mp3"
const LASER_TEXTURE: Texture2D = preload(LASER_TEXTURE_PATH)
const LASER_SOUND: AudioStream = preload(LASER_SOUND_PATH)


## Numeric defaults are unchanged. Since #1150 the default assets come from
## default_bullet.tres, not from script defaults.
func test_defaults_preserve_existing_projectile_behavior() -> void:
	var config := BulletResource.new()
	assert_eq(config.fire_rate, 0.15)
	assert_eq(config.muzzle_offset, Vector2(0, -25))
	assert_eq(config.projectile_speed, 400.0)
	assert_eq(config.projectile_lifetime, 5.0)
	assert_eq(config.damage, 10)
	assert_eq(config.scale, Vector2(0.25, 0.25))
	assert_eq(config.collision_radius, 3.0)
	assert_eq(DEFAULT_BULLET.projectile_texture, LASER_TEXTURE)
	assert_eq(DEFAULT_BULLET.shot_sound, LASER_SOUND)


## #1150: the script no longer preloads assets, so a new resource has none.
func test_new_resource_has_no_default_assets() -> void:
	var config := BulletResource.new()
	assert_null(config.projectile_texture, "BulletResource.new() must not load a texture.")
	assert_null(config.shot_sound, "BulletResource.new() must not load a sound.")


## #1150: default_bullet.tres assigns both assets itself instead of relying on script
## defaults, and keeps the same numeric tuning as a new resource.
func test_default_bullet_tres_assigns_assets() -> void:
	var source: String = FileAccess.get_file_as_string("res://config_resources/default_bullet.tres")
	assert_string_contains(source, "projectile_texture = ExtResource(")
	assert_string_contains(source, "shot_sound = ExtResource(")
	assert_eq(DEFAULT_BULLET.projectile_texture.resource_path, LASER_TEXTURE_PATH)
	assert_eq(DEFAULT_BULLET.shot_sound.resource_path, LASER_SOUND_PATH)
	var fresh := BulletResource.new()
	assert_eq(DEFAULT_BULLET.muzzle_offset, fresh.muzzle_offset)
	assert_eq(DEFAULT_BULLET.projectile_speed, fresh.projectile_speed)
	assert_eq(DEFAULT_BULLET.projectile_lifetime, fresh.projectile_lifetime)
	assert_eq(DEFAULT_BULLET.scale, fresh.scale)
	assert_eq(DEFAULT_BULLET.collision_radius, fresh.collision_radius)


## #1150: the class script itself has no asset preloads left.
func test_bullet_resource_script_does_not_preload_assets() -> void:
	var source: String = (load("res://scripts/resources/bullet_resource.gd") as GDScript).source_code
	assert_false(source.contains("preload("), "bullet_resource.gd must not preload assets.")


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


## Rewritten for #1150: new resources start without assets, so the test assigns them
## before checking that changing one resource leaves the other unchanged.
func test_new_resources_do_not_share_mutable_tuning() -> void:
	var first := BulletResource.new()
	var second := BulletResource.new()
	first.projectile_texture = LASER_TEXTURE
	first.shot_sound = LASER_SOUND
	second.projectile_texture = LASER_TEXTURE
	second.shot_sound = LASER_SOUND
	first.damage = 0
	first.muzzle_offset.x = 90
	first.scale.y = 2.0
	first.projectile_texture = null
	first.shot_sound = null

	assert_eq(second.damage, 10)
	assert_eq(second.muzzle_offset, Vector2(0, -25))
	assert_eq(second.scale, Vector2(0.25, 0.25))
	assert_eq(second.projectile_texture, LASER_TEXTURE)
	assert_eq(second.shot_sound, LASER_SOUND)


## #1146: BulletResource validates its own tuning. fire_rate below 0.01 clamps to 0.01.
func test_fire_rate_below_minimum_clamps(value: float = use_parameters([0.0, -1.0, 0.005])) -> void:
	var config := BulletResource.new()
	config.fire_rate = value
	assert_eq(config.fire_rate, 0.01, "fire_rate %s must clamp to 0.01" % value)


## #1146: negative damage clamps to 0.
func test_negative_damage_clamps_to_zero(value: int = use_parameters([-1, -50])) -> void:
	var config := BulletResource.new()
	config.damage = value
	assert_eq(config.damage, 0, "damage %d must clamp to 0" % value)


## #1146: valid values, including the bounds, are stored unchanged.
func test_valid_tuning_is_unchanged() -> void:
	var config := BulletResource.new()
	config.fire_rate = 0.01
	assert_eq(config.fire_rate, 0.01, "minimum fire_rate is valid")
	config.fire_rate = 0.7
	assert_eq(config.fire_rate, 0.7)
	config.damage = 0
	assert_eq(config.damage, 0, "zero damage is valid")
	config.damage = 42
	assert_eq(config.damage, 42)


## #1146: default_bullet.tres loads with the same tuning as before the setters were added.
func test_default_bullet_tres_tuning_loads_unchanged() -> void:
	assert_eq(DEFAULT_BULLET.fire_rate, 0.15)
	assert_eq(DEFAULT_BULLET.damage, 10)


## Clamping must not latch the resource at its lower bounds after an invalid assignment.
func test_valid_tuning_can_replace_previously_clamped_values() -> void:
	var config := BulletResource.new()
	config.fire_rate = -10.0
	config.damage = -10
	assert_eq(config.fire_rate, 0.01)
	assert_eq(config.damage, 0)

	config.fire_rate = 2.5
	config.damage = 1000
	assert_eq(config.fire_rate, 2.5)
	assert_eq(config.damage, 1000)


## The fire-rate boundary must preserve nearby valid values without rounding them down.
func test_fire_rate_immediately_above_minimum_is_preserved() -> void:
	var config := BulletResource.new()
	config.fire_rate = 0.010001
	assert_eq(config.fire_rate, 0.010001)


## Asset choices remain independent when a configuration is packed and instantiated.
func test_optional_assets_survive_scene_packing(
	assets: Array = use_parameters([[false, false], [true, false], [false, true]])
) -> void:
	var config := BulletResource.new()
	if assets[0]:
		config.projectile_texture = GradientTexture2D.new()
	if assets[1]:
		config.shot_sound = AudioStreamWAV.new()
	var source: Node2D = autofree(BULLET_SCENE.instantiate())
	source.config = config
	var packed := PackedScene.new()
	assert_eq(packed.pack(source), OK)
	var restored: Node2D = autofree(packed.instantiate())
	assert_not_null(restored.config)
	if restored.config:
		assert_eq(restored.config.projectile_texture, config.projectile_texture)
		assert_eq(restored.config.shot_sound, config.shot_sound)
		# #1150: an asset left unassigned stays null after packing instead of
		# coming back as a script default.
		if not assets[0]:
			assert_null(restored.config.projectile_texture)
		if not assets[1]:
			assert_null(restored.config.shot_sound)
