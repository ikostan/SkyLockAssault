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

## SIGNAL: fuel_depleted
##
## Emitted when current_fuel reaches exactly 0.0.
## External systems (like the Player or UI) can connect to this to trigger
## game-over states or low-fuel warnings without polling every frame.
signal fuel_depleted

@export_group("Fuel System")
## Maximum fuel capacity.
@export var max_fuel: float = 100.0:
	set(value):
		max_fuel = max(0.0, value)
		setting_changed.emit("max_fuel", max_fuel)

## Current fuel level. Clamped between 0.0 and max_fuel.
@export var current_fuel: float = 100.0:
	set(value):
		var old_value: float = current_fuel
		current_fuel = clamp(value, 0.0, max_fuel)
		if old_value > 0.0 and current_fuel == 0.0:
			fuel_depleted.emit()
		setting_changed.emit("current_fuel", current_fuel)

## Base rate of fuel consumption per second.
@export var base_consumption_rate: float = 1.0

@export_group("Logging")
# Current log level: 0=DEBUG, 1=INFO, 2=WARNING, 3=ERROR, 4=NONE
@export_range(0, 4, 1) var current_log_level: int = 1:
	set(value):
		var new_value: int = clampi(value, 0, 4)
		if _current_log_level == new_value:
			return
		_current_log_level = new_value
		setting_changed.emit("current_log_level", new_value)
	get:
		return _current_log_level

@export var enable_debug_logging: bool = false:
	set(value):
		var new_value: bool = bool(value)
		if _enable_debug_logging == new_value:
			return
		_enable_debug_logging = new_value
		setting_changed.emit("enable_debug_logging", new_value)
	get:
		return _enable_debug_logging

@export_group("Gameplay")
# Multiplier: 1.0=Normal, <1=Easy, >1=Hard
@export var difficulty: float = 1.0:
	set(value):
		var new_val: float = clamp(value, 0.5, 2.0)
		if _difficulty == new_val:
			return  # Break the recursion here
		_difficulty = new_val
		setting_changed.emit("difficulty", _difficulty)
	get:
		return _difficulty

@export_group("UI & Scenes")
@export var remap_prompt_keyboard: String = "Press a key..."
@export var remap_prompt_gamepad: String = "Press a gamepad button/axis..."

# Use type-hinting without forced preloading to break circular dependencies
@export var key_mapping_scene: PackedScene
@export var options_scene: PackedScene

# Private member variables moved to bottom to satisfy class-definitions-order
var _current_log_level: int = 1
var _difficulty: float = 1.0
var _enable_debug_logging: bool = false


func _init() -> void:
	# This only runs if the values aren't already set (like in a .new() call)
	if not key_mapping_scene:
		key_mapping_scene = load("res://scenes/key_mapping_menu.tscn")
	if not options_scene:
		options_scene = load("res://scenes/options_menu.tscn")

## Helper method to increase fuel safely.
## Increases fuel level by specified amount, clamped to max_fuel.
func refuel(amount: float) -> void:
	if amount > 0:
		current_fuel += amount
