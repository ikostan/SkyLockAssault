## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## game_settings_resource.gd
##
## DATA CONTAINER: This Resource serves as the central "Source of Truth" for game configuration.
## It decouples static data (difficulty, paths, log levels) from logic found in Globals.gd.
## By using a Resource instead of hard-coded variables, settings can be swapped at runtime
## or modified visually via the Godot Inspector without touching the codebase.

class_name GameSettingsResource
extends Resource

@export_group("Logging")
# Current log level: 0=DEBUG, 1=INFO, 2=WARNING, 3=ERROR, 4=NONE
@export_range(0, 4, 1) var current_log_level: int = 1
@export var enable_debug_logging: bool = false

@export_group("Gameplay")
# Multiplier: 1.0=Normal, <1=Easy, >1=Hard
# In globals.gd, change the difficulty variable in the Resource script:
# game_settings_resource.gd
@export var difficulty: float = 1.0:
	set(value):
		difficulty = clamp(value, 0.5, 2.0)  # Use a setter to force clamping ALWAYS

@export_group("UI & Scenes")
@export var remap_prompt_keyboard: String = "Press a key..."
@export var remap_prompt_gamepad: String = "Press a gamepad button/axis..."
@export var key_mapping_scene: PackedScene = preload("res://scenes/key_mapping_menu.tscn")
@export var options_scene: PackedScene = preload("res://scenes/options_menu.tscn")
