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

@export_group("Speed System")

@export var max_speed: float = 713.0:
	set(value):
		var new_val: float = max(1.0, value)
		if _max_speed == new_val:
			return
		_max_speed = new_val

		# NEW FIX: Enforce invariant - push min_speed down if max_speed drops below it
		if _min_speed > _max_speed:
			self.min_speed = _max_speed

		setting_changed.emit("max_speed", _max_speed)
	get:
		return _max_speed

@export var min_speed: float = 95.0:
	set(value):
		# NEW FIX: Clamp new min_speed so it cannot exceed the current max_speed
		var new_val: float = clamp(value, 0.0, _max_speed)

		if _min_speed == new_val:
			return
		_min_speed = new_val
		setting_changed.emit("min_speed", _min_speed)
	get:
		return _min_speed

@export var lateral_speed: float = 250.0:
	set(value):
		if _lateral_speed == value:
			return
		_lateral_speed = value
		setting_changed.emit("lateral_speed", _lateral_speed)
	get:
		return _lateral_speed

@export var acceleration: float = 200.0:
	set(value):
		if _acceleration == value:
			return
		_acceleration = value
		setting_changed.emit("acceleration", _acceleration)
	get:
		return _acceleration

@export var deceleration: float = 100.0:
	set(value):
		if _deceleration == value:
			return
		_deceleration = value
		setting_changed.emit("deceleration", _deceleration)
	get:
		return _deceleration

@export var high_yellow_fraction: float = 0.80:
	set(value):
		var new_val: float = clamp(value, 0.0, 1.0)
		if _high_yellow_fraction == new_val:
			return
		_high_yellow_fraction = new_val
		setting_changed.emit("high_yellow_fraction", _high_yellow_fraction)
	get:
		return _high_yellow_fraction

@export var low_yellow_fraction: float = 0.10:
	set(value):
		var new_val: float = clamp(value, 0.0, 1.0)
		if _low_yellow_fraction == new_val:
			return
		_low_yellow_fraction = new_val
		setting_changed.emit("low_yellow_fraction", _low_yellow_fraction)
	get:
		return _low_yellow_fraction

@export_group("Fuel System")

## Maximum fuel capacity.
@export var max_fuel: float = 100.0:
	set(value):
		# NEW: Enforce a logical minimum capacity of 1.0. This prevents a misconfigured
		# save file or options slider from shrinking the tank to 0.0 and
		# accidentally triggering a runtime "Game Over" flameout.
		var new_max: float = max(1.0, value)

		if _max_fuel == new_max:
			return
		_max_fuel = new_max

		# Use the backing field for comparisons, but trigger the public
		# setter for current_fuel if needed
		if _current_fuel > _max_fuel:
			self.current_fuel = _max_fuel

		setting_changed.emit("max_fuel", _max_fuel)
	get:
		return _max_fuel

## Current fuel level. Clamped between 0.0 and max_fuel.
@export var current_fuel: float = 100.0:
	set(value):
		# NEW: Use private backing field to safely clamp and check values without recursion
		var old_value: float = _current_fuel
		var new_fuel: float = clamp(value, 0.0, _max_fuel)

		if _current_fuel == new_fuel:
			return

		_current_fuel = new_fuel

		if old_value > 0.0 and _current_fuel == 0.0:
			fuel_depleted.emit()

		setting_changed.emit("current_fuel", _current_fuel)
	get:
		# NEW: Return the backing field
		return _current_fuel

## Base rate of fuel consumption per second.
@export var base_consumption_rate: float = 1.0

# NEW: Migrated thresholds from player.gd to centralize all fuel configuration
@export var high_fuel_threshold: float = 90.0:
	set(value):
		var new_val: float = max(value, _medium_fuel_threshold + 1.0)  # Must be greater than medium
		if _high_fuel_threshold == new_val:
			return
		_high_fuel_threshold = new_val
		setting_changed.emit("high_fuel_threshold", _high_fuel_threshold)
	get:
		return _high_fuel_threshold

@export var medium_fuel_threshold: float = 50.0:
	set(value):
		var new_val: float = clamp(value, _low_fuel_threshold + 1.0, _high_fuel_threshold - 1.0)
		if _medium_fuel_threshold == new_val:
			return
		_medium_fuel_threshold = new_val
		setting_changed.emit("medium_fuel_threshold", _medium_fuel_threshold)
	get:
		return _medium_fuel_threshold

@export var low_fuel_threshold: float = 30.0:
	set(value):
		var new_val: float = clamp(value, _no_fuel_threshold + 1.0, _medium_fuel_threshold - 1.0)
		if _low_fuel_threshold == new_val:
			return
		_low_fuel_threshold = new_val
		setting_changed.emit("low_fuel_threshold", _low_fuel_threshold)
	get:
		return _low_fuel_threshold

@export var no_fuel_threshold: float = 15.0:
	set(value):
		var new_val: float = min(value, _low_fuel_threshold - 1.0)  # Must be lower than low
		if _no_fuel_threshold == new_val:
			return
		_no_fuel_threshold = new_val
		setting_changed.emit("no_fuel_threshold", _no_fuel_threshold)
	get:
		return _no_fuel_threshold

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
# NEW: GDScript requires backing fields to be declared BEFORE
# the properties that reference them.
# Moved these from the bottom of the script to the top to resolve
# the "Identifier not declared" scope error.
var _max_fuel: float = 100.0
var _current_fuel: float = _max_fuel  # ← Automatically syncs to whatever max_fuel is
var _current_log_level: int = 1
var _difficulty: float = 1.0
var _enable_debug_logging: bool = false
# NEW: Add backing fields
var _high_fuel_threshold: float = 90.0
var _medium_fuel_threshold: float = 50.0
var _low_fuel_threshold: float = 30.0
var _no_fuel_threshold: float = 15.0

# Speed Backing Fields
var _max_speed: float = 713.0
var _min_speed: float = 95.0
var _lateral_speed: float = 250.0
var _acceleration: float = 200.0
var _deceleration: float = 100.0
var _high_yellow_fraction: float = 0.80
var _low_yellow_fraction: float = 0.10


func _init() -> void:
	# This only runs if the values aren't already set (like in a .new() call)
	if not key_mapping_scene:
		key_mapping_scene = load("res://scenes/key_mapping_menu.tscn")
	if not options_scene:
		options_scene = load("res://scenes/options_menu.tscn")
	# NEW: Safely enforce the invariant that a brand new resource
	# always starts with a full tank, without bypassing the validation setters.
	_current_fuel = _max_fuel


## Helper method to increase fuel safely.
## Increases fuel level by specified amount, clamped to max_fuel.
func refuel(amount: float) -> void:
	if amount > 0:
		current_fuel += amount
