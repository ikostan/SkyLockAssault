## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## speed_resource.gd
##
## DATA CONTAINER: Manages the player's speed state, limits, and acceleration profiles.
## Operates as an independent, platform-agnostic Subject in the Observer Pattern.
class_name SpeedResource
extends Resource

## Emitted strictly when the effective speed value changes.
signal speed_updated(new_speed: float)

## Emitted strictly when crossing from previous_speed > low_threshold to new_speed <= low_threshold.
signal speed_low

## Emitted strictly when crossing from previous_speed < max_speed to new_speed == max_speed.
signal speed_maxed

# --- Backing Fields ---
var _max_speed: float = 713.0
var _min_speed: float = 95.0
var _current_speed: float = 250.0
var _acceleration: float = 200.0
var _deceleration: float = 100.0
var _lateral_speed: float = 250.0
var _high_yellow_fraction: float = 0.80
var _low_yellow_fraction: float = 0.10

# --- State Properties ---

@export var max_speed: float = 713.0:
	set(value):
		# Invariant: max_speed cannot drop below min_speed
		var new_max: float = max(_min_speed, value)
		if _max_speed == new_max:
			return

		_max_speed = new_max
		_enforce_current_speed_bounds()
	get:
		return _max_speed

@export var min_speed: float = 95.0:
	set(value):
		# Invariant: min_speed cannot exceed max_speed
		var new_min: float = min(value, _max_speed)
		if _min_speed == new_min:
			return

		_min_speed = new_min
		_enforce_current_speed_bounds()
	get:
		return _min_speed

@export var current_speed: float = 250.0:
	set(value):
		var old_speed: float = _current_speed
		var new_speed: float = clamp(value, _min_speed, _max_speed)

		# Invariant: Do not emit if the effective value hasn't changed
		if old_speed == new_speed:
			return

		_current_speed = new_speed
		speed_updated.emit(_current_speed)

		# Crossing Semantics: Low Speed
		var low_thresh: float = _min_speed + (_max_speed - _min_speed) * _low_yellow_fraction
		if old_speed > low_thresh and _current_speed <= low_thresh:
			speed_low.emit()

		# Crossing Semantics: Max Speed
		if old_speed < _max_speed and _current_speed == _max_speed:
			speed_maxed.emit()
	get:
		return _current_speed

# --- Tuning Properties ---

@export var acceleration: float = 200.0:
	set(value):
		_acceleration = max(0.0, value)
	get:
		return _acceleration

@export var deceleration: float = 100.0:
	set(value):
		_deceleration = max(0.0, value)
	get:
		return _deceleration

@export var lateral_speed: float = 250.0:
	set(value):
		_lateral_speed = max(0.0, value)
	get:
		return _lateral_speed

@export var high_yellow_fraction: float = 0.80:
	set(value):
		var new_val: float = clamp(value, 0.0, 1.0)
		if _high_yellow_fraction == new_val:
			return
		_high_yellow_fraction = new_val
		# Push low_yellow down if high_yellow drops below it
		if _low_yellow_fraction > _high_yellow_fraction:
			self.low_yellow_fraction = _high_yellow_fraction
	get:
		return _high_yellow_fraction

@export var low_yellow_fraction: float = 0.10:
	set(value):
		var new_val: float = clamp(value, 0.0, _high_yellow_fraction)
		if _low_yellow_fraction == new_val:
			return
		_low_yellow_fraction = new_val
	get:
		return _low_yellow_fraction


func _init() -> void:
	_current_speed = clamp(250.0, _min_speed, _max_speed)


## Internal helper to ensure current_speed remains valid if boundaries shift.
func _enforce_current_speed_bounds() -> void:
	if _current_speed < _min_speed or _current_speed > _max_speed:
		# Assigning via `self.` triggers the setter, handling clamps and signals
		self.current_speed = _current_speed
