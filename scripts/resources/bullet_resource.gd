## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## bullet_resource.gd
##
## Tuning data for one projectile weapon. The single source of fire_rate and damage (#1146):
## bullet.gd reads them for the cooldown and for hits, and nothing copies them elsewhere.
## default_bullet.tres is shared by every bullet without its own config, so code must not
## write to a config at runtime.
class_name BulletResource
extends Resource

## Seconds between shots before difficulty scaling. Values below 0.01 are clamped to 0.01.
@export var fire_rate: float = 0.15:
	set(value):
		fire_rate = maxf(0.01, value)
@export var muzzle_offset: Vector2 = Vector2(0, -25)
@export var projectile_speed: float = 400.0
@export var projectile_lifetime: float = 5.0
## Damage per hit. Negative values are clamped to 0.
@export var damage: int = 10:
	set(value):
		damage = maxi(0, value)
@export var projectile_texture: Texture2D = preload("res://files/sprite/laser_sprites/01.png")
@export var shot_sound: AudioStream = preload("res://files/sounds/sfx/retro-laser-1-236669.mp3")

# Added specifically for Issue #284 requirements
@export var scale: Vector2 = Vector2(0.25, 0.25)
@export var collision_radius: float = 3.0
