## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## game_settings_resource.gd
##
## DATA CONTAINER: This Resource serves as the central "Source of Truth" for game configuration.
## It decouples static data from logic found in Globals.gd.
class_name GameSettingsResource
extends Resource

## SIGNAL: setting_changed(setting_name: String, new_value: Variant)
##
## This signal is the core of the Observer Pattern for game settings.
## It is automatically emitted by property setters whenever a value is updated.
## This allows external systems (like Globals.gd) to react to data changes
## without the UI having to explicitly call persistence or logging methods.
signal setting_changed(setting_name: String, new_value: Variant)

@export_group("Logging")
# Current log level: 0=DEBUG, 1=INFO, 2=WARNING, 3=ERROR, 4=NONE
@export_range(0, 4, 1) var current_log_level: int = 1:
	set(value):
		_current_log_level = value
		setting_changed.emit("current_log_level", value)
	get:
		return _current_log_level

@export var enable_debug_logging: bool = false:
	set(value):
		enable_debug_logging = value
		setting_changed.emit("enable_debug_logging", value)

@export_group("Gameplay")
# Multiplier: 1.0=Normal, <1=Easy, >1=Hard
@export var difficulty: float = 1.0:
	set(value):
		_difficulty = clamp(value, 0.5, 2.0)
		setting_changed.emit("difficulty", _difficulty)
	get:
		return _difficulty

@export_group("UI & Scenes")
@export var remap_prompt_keyboard: String = "Press a key..."
@export var remap_prompt_gamepad: String = "Press a gamepad button/axis..."
@export var key_mapping_scene: PackedScene = preload("res://scenes/key_mapping_menu.tscn")
@export var options_scene: PackedScene = preload("res://scenes/options_menu.tscn")

# Private member variables moved to bottom to satisfy class-definitions-order
var _current_log_level: int = 1
var _difficulty: float = 1.0
