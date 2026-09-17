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

# --- State Properties ---

@export var max_speed: float = 713.0:
	set(value):
		# Prevent max_speed from ever dropping below 1.0, and respect min_speed
		var new_max: float = max(min_speed, max(1.0, value))
		if max_speed == new_max:
			return

		max_speed = new_max
		_enforce_current_speed_bounds()

@export var min_speed: float = 95.0:
	set(value):
		# Prevent min_speed from dropping below 0.0, and respect max_speed
		var new_min: float = clamp(value, 0.0, max_speed)
		if min_speed == new_min:
			return

		min_speed = new_min
		_enforce_current_speed_bounds()

@export var current_speed: float = 250.0:
	set(value):
		var old_speed: float = current_speed
		var new_speed: float = clamp(value, min_speed, max_speed)

		if old_speed == new_speed:
			return

		current_speed = new_speed
		speed_updated.emit(current_speed)

		var low_thresh: float = min_speed + (max_speed - min_speed) * low_yellow_fraction
		if old_speed > low_thresh and current_speed <= low_thresh:
			speed_low.emit()

		if old_speed < max_speed and current_speed == max_speed:
			speed_maxed.emit()

# --- Tuning Properties ---

@export var acceleration: float = 200.0:
	set(value):
		acceleration = max(0.0, value)

@export var deceleration: float = 100.0:
	set(value):
		deceleration = max(0.0, value)

@export var lateral_speed: float = 250.0:
	set(value):
		lateral_speed = max(0.0, value)

@export var high_yellow_fraction: float = 0.80:
	set(value):
		var new_val: float = clamp(value, 0.0, 1.0)
		if high_yellow_fraction == new_val:
			return
		high_yellow_fraction = new_val

		if low_yellow_fraction > high_yellow_fraction:
			self.low_yellow_fraction = high_yellow_fraction

@export var low_yellow_fraction: float = 0.10:
	set(value):
		var new_val: float = clamp(value, 0.0, high_yellow_fraction)
		if low_yellow_fraction == new_val:
			return
		low_yellow_fraction = new_val


func _init() -> void:
	current_speed = clamp(250.0, min_speed, max_speed)


## Internal helper to ensure current_speed remains valid if boundaries shift.
func _enforce_current_speed_bounds() -> void:
	if current_speed < min_speed or current_speed > max_speed:
		# Using 'self.' intentionally triggers the setter to handle clamps and signals
		self.current_speed = current_speed
