## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## projectile.gd
##
## One shot fired by a [code]BulletFirer[/code] (root of projectile.tscn, #1139).
##
## The scene holds the nodes every shot needs, so code no longer builds them per shot. All
## default-radius projectiles share the scene's [code]CircleShape2D[/code]. [method configure]
## applies a [code]BulletResource[/code] and the spawn position.
##
## Hits come from [code]HitArea[/code] on the [code]player_projectiles[/code] layer (3), which
## watches the [code]enemies[/code] layer (2). Both [code]area_entered[/code] and
## [code]body_entered[/code] go to one handler, so physics-body enemies and
## [code]Area2D[/code] hurtboxes can both be hit, and a projectile hits only once. The
## root body has no shape, so it never collides by itself.

class_name Projectile
extends RigidBody2D

## Sprite rotation for a shot travelling up the screen.
const UP_ROTATION: float = -PI / 2

var _damage: int = 0
var _has_hit: bool = false

@onready var _lifetime_timer: Timer = $LifetimeTimer


func _ready() -> void:
	_lifetime_timer.start()


## Applies a projectile config and places the projectile at its spawn point.
##
## Call it before or after adding the projectile to the tree. Sets the texture, sprite scale,
## upward velocity, position, rotation, lifetime and damage. The scene's shared shape is
## replaced with a copy only when the config asks for another radius, so the shared shape
## is never changed.
##
## [param config]: Tuning data for this shot. It is only read, never written.
## [param spawn_position]: Global position of the muzzle.
func configure(config: BulletResource, spawn_position: Vector2) -> void:
	var sprite := $Sprite2D as Sprite2D
	sprite.texture = config.projectile_texture
	sprite.scale = config.scale

	var collision := $HitArea/CollisionShape2D as CollisionShape2D
	var shared_shape := collision.shape as CircleShape2D
	if not is_equal_approx(shared_shape.radius, config.collision_radius):
		var own_shape := shared_shape.duplicate() as CircleShape2D
		own_shape.radius = config.collision_radius
		collision.shape = own_shape

	linear_velocity = Vector2(0, -config.projectile_speed)  # Negative y is up in Godot 2D
	global_position = spawn_position
	global_rotation = UP_ROTATION
	_damage = config.damage

	var lifetime_timer := $LifetimeTimer as Timer
	lifetime_timer.wait_time = config.projectile_lifetime
	if is_inside_tree():
		lifetime_timer.start()


## Handles the first hit: damages the target if it can take damage, then frees the projectile.
##
## [code]HitArea[/code] sends both [code]area_entered[/code] and [code]body_entered[/code]
## here. Later calls do nothing, so the projectile never damages two targets, or the same
## target twice when both signals fire for it.
func _on_hit(target: Node2D) -> void:
	if _has_hit:
		return
	_has_hit = true
	Globals.log_message("Projectile hit: " + target.name, Globals.LogLevel.DEBUG)
	# Duck typing stays until the enemy work defines a damage contract (#1139).
	if target.has_method("take_damage"):
		target.call("take_damage", _damage)
	queue_free()
