## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## player_stats_resource.gd
##
## DATA CONTAINER: Holds static, developer-authored tuning values for the player ship.
## Authored configuration: values are meant to be set in the editor (or on a resource
## assigned to the player), not changed during play. It stores no runtime state and emits
## no signals. player.gd reads these values once in _ready() to compute the movement
## bounds, so changes made at runtime are not picked up until the player is spawned again.
## Shipped defaults live in res://config_resources/default_player_stats.tres.

class_name PlayerStatsResource
extends Resource

## Fraction of the sprite size used as the margin between the plane and the screen edges
## when computing movement bounds. Smaller values let the plane get closer to the edges.
@export_range(0.0, 1.0, 0.01) var hitbox_scale: float = 0.25

## Sprite size (in pixels) used for the movement bounds only when the player sprite has
## no texture. When a texture is present, its own size takes priority.
@export var fallback_sprite_size: Vector2 = Vector2(174.0, 132.0)
