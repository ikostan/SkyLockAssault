## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## bullet_resource.gd
##
## Tuning data for one projectile weapon. The single source of fire_rate and damage (#1146):
## bullet.gd reads them for the cooldown and for hits, and nothing copies them elsewhere.
## default_bullet.tres is shared by every bullet without its own config, so code must not
## write to a config at runtime. Asset choices (texture, sound) live in the data file, not in
## script defaults (#1150).
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
## Sprite of the projectile. No default (#1150): data files such as default_bullet.tres
## assign it, so loading this class doesn't load the asset. Null spawns a projectile
## without a texture.
@export var projectile_texture: Texture2D
## Sound played on each shot. No default (#1150), as with [member projectile_texture].
## Null fires silently.
@export var shot_sound: AudioStream

# Added specifically for Issue #284 requirements
@export var scale: Vector2 = Vector2(0.25, 0.25)
@export var collision_radius: float = 3.0
