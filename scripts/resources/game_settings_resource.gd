## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## game_settings_resource.gd
##
## DATA CONTAINER: This Resource serves as the central "Source of Truth" for game configuration.
## It decouples static data from logic found in Globals.gd.

@tool
class_name GameSettingsResource
extends Resource

## Emitted when a setting with a notifying setter changes value.
##
## Core observer signal. Allows external systems to react to data changes without explicit
## persistence calls. Setting a property to its current value does not emit it.
##
## Plain exported properties have no setter and never emit it: the speed tuning values
## ([member max_speed], [member min_speed], [member lateral_speed], [member acceleration],
## [member deceleration], [member high_yellow_fraction], [member low_yellow_fraction]),
## the fuel tuning values ([member base_consumption_rate] and the four fuel thresholds),
## [member remap_prompt_keyboard], [member remap_prompt_gamepad], [member key_mapping_scene]
## and [member options_scene].
##
## [param setting_name]: Name of the setting that was changed.
## [param new_value]: The updated value assigned to the setting.
signal setting_changed(setting_name: String, new_value: Variant)

@export_group("Speed System")
# Plain tuning values, copied into the player's SpeedResource at spawn. SpeedResource
# validates them; this resource stores them as written (#1148).

## Top speed, copied with [member min_speed] through [method SpeedResource.set_speed_limits].
@export var max_speed: float = 713.0
## Lowest speed while fueled, copied with [member max_speed] as a pair.
@export var min_speed: float = 95.0
## Sideways speed, copied into [member SpeedResource.lateral_speed].
@export var lateral_speed: float = 250.0
## Forward acceleration, copied into [member SpeedResource.acceleration].
@export var acceleration: float = 200.0
## Forward deceleration, copied into [member SpeedResource.deceleration].
@export var deceleration: float = 100.0
## Fraction of [member max_speed] (0-1) at or above which the HUD speed warning blinks.
@export var high_yellow_fraction: float = 0.80
## Fraction of the min-to-max speed range (0-1, at most [member high_yellow_fraction])
## at or below which the HUD speed warning blinks.
@export var low_yellow_fraction: float = 0.10

@export_group("Fuel System")

## Maximum fuel capacity, copied into the player's [FuelResource] at spawn.
##
## Live fuel is runtime state and lives only on [FuelResource] (#1143).
@export var max_fuel: float = 100.0:
	set(value):
		# NEW: Enforce a logical minimum capacity of 1.0. This prevents a misconfigured
		# save file or options slider from shrinking the tank to 0.0 and
		# accidentally triggering a runtime "Game Over" flameout.
		var new_max: float = max(1.0, value)

		if _max_fuel == new_max:
			return
		_max_fuel = new_max
		setting_changed.emit("max_fuel", _max_fuel)
	get:
		return _max_fuel

## Base rate of fuel consumption per second.
@export var base_consumption_rate: float = 1.0

# Plain tuning values: all four are percentages of max_fuel (0-100), copied into the
# player's FuelResource with FuelResource.set_thresholds(), which validates them as a
# group (#1147). This resource stores them as written (#1148).

## Percent of [member max_fuel] above which the HUD fuel bar is solid green.
@export var high_fuel_threshold: float = 90.0
## Percent of [member max_fuel] at which the HUD fuel bar reaches yellow.
@export var medium_fuel_threshold: float = 50.0
## Percent of [member max_fuel] at or below which the HUD low-fuel warning blinks.
@export var low_fuel_threshold: float = 30.0
## Percent of [member max_fuel] below which the HUD fuel bar is solid dark red.
@export var no_fuel_threshold: float = 15.0

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
@export var show_fps: bool = false:
	set(value):
		var new_val: bool = bool(value)
		if _show_fps == new_val:
			return
		_show_fps = new_val
		setting_changed.emit("show_fps", _show_fps)
	get:
		return _show_fps

# Backing fields for the settings that validate and notify. They must be declared before
# the properties that reference them are used.
var _max_fuel: float = 100.0
var _current_log_level: int = 1
var _difficulty: float = 1.0
var _enable_debug_logging: bool = false
var _show_fps: bool = false
