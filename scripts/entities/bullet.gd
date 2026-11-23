## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## bullet.gd
##
## The projectile weapon a [code]Weapon[/code] slot equips (root of bullet.tscn). It fires
## projectiles but isn't one itself. Its cooldown lives here and keeps running while
## [code]Weapon[/code] has another slot active (#1138).
##
## Each shot instantiates projectile.tscn (#1139) under the level's projectile container
## (#1140) and plays its sound through the [code]SfxManager[/code] pool on the Weapon bus
## (#1141), so firing adds no audio node.

class_name BulletFirer
extends WeaponFirer

## Shared config for firers without their own. Code must never write to it.
const DEFAULT_BULLET_CONFIG: BulletResource = preload("res://config_resources/default_bullet.tres")

## Scene instantiated for every shot.
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")

## Projectile tuning for this firer, injected via the Inspector (.tres).
## Null falls back to [constant DEFAULT_BULLET_CONFIG].
@export var config: BulletResource

var can_fire: bool = true
var timer: Timer


func _ready() -> void:
	# Load the shared default configuration to save memory across all default bullets.
	if not config:
		config = DEFAULT_BULLET_CONFIG

	timer = Timer.new()
	timer.one_shot = true
	timer.name = "CooldownTimer"
	add_child(timer)
	timer.timeout.connect(_reset_can_fire)


func _reset_can_fire() -> void:
	can_fire = true


## Initiates a projectile firing sequence if allowed.
##
## Checks firing readiness, applies scaled cooldown timers, logs debug info, spawns
## projectiles, and plays sound effects.
## Returns true if successfully fired, false otherwise.
func fire() -> bool:
	if not can_fire:
		return false
	can_fire = false

	var scaled_cooldown: float = config.fire_rate * Globals.settings.difficulty
	timer.start(scaled_cooldown)

	# LOG
	Globals.log_message(
		"Firing with scaled cooldown: " + str(scaled_cooldown), Globals.LogLevel.DEBUG
	)

	spawn_projectile()
	play_shot_sound()

	return true


## Plays the configured shot sound through the [code]SfxManager[/code] pool on the Weapon bus.
##
## The pooled players are non-positional, so the shot sounds the same anywhere on screen,
## and no player node is created per shot. A null [member BulletResource.shot_sound] fires
## silently.
func play_shot_sound() -> void:
	if not config.shot_sound:
		return
	SfxManager.play_stream(config.shot_sound, AudioConstants.BUS_SFX_WEAPON)


## Instantiates projectile.tscn, adds it to the projectile parent, and configures it.
##
## The parent is the level's [code]Projectiles[/code] container injected through
## [member WeaponFirer.projectile_parent], so projectiles are freed with their level (#1140).
## A firer without a valid injected parent, such as one in an isolated test, falls back to
## the scene root.
##
## The projectile spawns at this firer's global position plus
## [member BulletResource.muzzle_offset], and frees itself on its first hit or when its
## lifetime ends. It's configured after [method Node.add_child], so the spawn position is
## applied in global coordinates under any parent transform.
func spawn_projectile() -> void:
	var projectile := PROJECTILE_SCENE.instantiate() as Projectile
	_get_spawn_parent().add_child(projectile)
	projectile.configure(config, global_position + config.muzzle_offset)


# The injected projectile parent, or the scene root when none is set or it was freed.
func _get_spawn_parent() -> Node:
	if is_instance_valid(projectile_parent):
		return projectile_parent
	return get_tree().root
