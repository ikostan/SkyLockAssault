## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## bullet_resource.gd
class_name BulletResource
extends Resource

@export var fire_rate: float = 0.15
@export var muzzle_offset: Vector2 = Vector2(0, -25)
@export var projectile_speed: float = 400.0
@export var projectile_lifetime: float = 5.0
@export var damage: int = 10
@export var projectile_texture: Texture2D = preload("res://files/sprite/laser_sprites/01.png")
@export var shot_sound: AudioStream = preload("res://files/sounds/sfx/retro-laser-1-236669.mp3")
