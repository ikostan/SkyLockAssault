## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## speed_resource.gd
##
## DATA CONTAINER: Manages the player's speed state, limits, and acceleration profiles.
## Operates as an independent, platform-agnostic Subject in the Observer Pattern.
class_name SpeedResource
extends Resource

## Emitted when visual fraction thresholds are modified.
signal thresholds_changed

## Emitted strictly when the effective speed value changes.
##
## [param new_speed]: The updated effective speed value.
signal speed_updated(new_speed: float)

## Emitted strictly when crossing from previous_speed > low_threshold to new_speed <= low_threshold.
signal speed_low

## Emitted strictly when crossing from previous_speed < max_speed to new_speed == max_speed.
signal speed_maxed

# --- State Properties ---

## Top speed. Setting it alone keeps it at least 1 and at least [member min_speed];
## use [method set_speed_limits] to change both limits at once.
@export var max_speed: float = 713.0:
	set(value):
		# Prevent max_speed from ever dropping below 1.0, and respect min_speed
		var new_max: float = max(_min_speed, max(1.0, value))
		if _max_speed == new_max:
			return

		_max_speed = new_max
		_enforce_current_speed_bounds()
	get:
		return _max_speed

## Lowest speed while fueled. Setting it alone clamps it between 0 and [member max_speed];
## use [method set_speed_limits] to change both limits at once.
@export var min_speed: float = 95.0:
	set(value):
		# Prevent min_speed from dropping below 0.0, and respect max_speed
		var new_min: float = clamp(value, 0.0, _max_speed)
		if _min_speed == new_min:
			return

		_min_speed = new_min
		_enforce_current_speed_bounds()
	get:
		return _min_speed

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
		thresholds_changed.emit()

		if low_yellow_fraction > high_yellow_fraction:
			self.low_yellow_fraction = high_yellow_fraction

@export var low_yellow_fraction: float = 0.10:
	set(value):
		var new_val: float = clamp(value, 0.0, high_yellow_fraction)
		if low_yellow_fraction == new_val:
			return
		low_yellow_fraction = new_val
		thresholds_changed.emit()

# Backing fields, so set_speed_limits() can store a validated pair without going through
# the single-value clamps, whose result depends on the order of assignment (#1148).
var _max_speed: float = 713.0
var _min_speed: float = 95.0


func _init() -> void:
	current_speed = clamp(250.0, min_speed, max_speed)


## Internal helper to ensure current_speed remains valid if boundaries shift.
func _enforce_current_speed_bounds() -> void:
	if current_speed < min_speed or current_speed > max_speed:
		# Using 'self.' intentionally triggers the setter to handle clamps and signals
		self.current_speed = current_speed


## Sets both speed limits at once. Returns false and changes nothing when invalid.
## Requires 0 <= new_min <= new_max and new_max >= 1, both finite.
##
## Unlike setting [member min_speed] and [member max_speed] one at a time, the result
## doesn't depend on the current limits: a valid pair applies exactly as written (#1148).
## [member current_speed] is then clamped into the new range.
##
## [param new_min]: New [member min_speed].
## [param new_max]: New [member max_speed].
func set_speed_limits(new_min: float, new_max: float) -> bool:
	# NaN fails every comparison, so it's rejected too
	var valid: bool = (
		is_finite(new_min)
		and is_finite(new_max)
		and new_min >= 0.0
		and new_max >= new_min
		and new_max >= 1.0
	)
	if not valid:
		push_warning(
			(
				"SpeedResource: rejected speed limits (min %s, max %s). " % [new_min, new_max]
				+ "Need 0 <= min <= max and max >= 1. Keeping the current limits."
			)
		)
		return false

	_min_speed = new_min
	_max_speed = new_max
	_enforce_current_speed_bounds()
	return true
