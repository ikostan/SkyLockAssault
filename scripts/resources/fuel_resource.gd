## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## fuel_resource.gd
##
## DATA CONTAINER: Manages the player's fuel state and thresholds.
## Operates as an independent, platform-agnostic Subject in the Observer Pattern.
class_name FuelResource
extends Resource

## Emitted strictly when the effective fuel value changes.
##
## [param new_value]: The updated fuel value.
signal fuel_changed(new_value: float)

## Emitted strictly when crossing from previous_fuel > 0.0 to new_fuel == 0.0.
signal fuel_depleted

## Lowest allowed fuel threshold, in percent of [member max_fuel].
const THRESHOLD_MIN_PERCENT: float = 0.0
## Highest allowed fuel threshold, in percent of [member max_fuel].
const THRESHOLD_MAX_PERCENT: float = 100.0
## Smallest allowed gap between neighbouring thresholds, in percentage points.
const MIN_THRESHOLD_GAP: float = 1.0

# --- State Properties ---

@export var max_fuel: float = 100.0:
	set(value):
		var new_max: float = max(1.0, value)

		if max_fuel == new_max:
			return

		max_fuel = new_max

		if current_fuel > max_fuel:
			self.current_fuel = max_fuel

@export var current_fuel: float = 100.0:
	set(value):
		var old_fuel: float = current_fuel
		var new_fuel: float = clamp(value, 0.0, max_fuel)

		if old_fuel == new_fuel:
			return

		current_fuel = new_fuel
		fuel_changed.emit(current_fuel)

		if old_fuel > 0.0 and current_fuel == 0.0:
			fuel_depleted.emit()

@export var base_consumption_rate: float = 1.0

# --- Threshold Properties ---
# All four thresholds are percentages of max_fuel (0-100), not fuel amounts: the HUD
# compares them with current_fuel / max_fuel * 100 (#1147). They must stay ordered as
# 0 <= no_fuel < low < medium < high <= 100, each at least MIN_THRESHOLD_GAP apart.

## Percent of [member max_fuel] above which the HUD fuel bar is solid green.
## Between [member medium_fuel_threshold] and this value it fades from green to yellow.
## Setting it alone clamps it between [member medium_fuel_threshold] + 1 and 100;
## use [method set_thresholds] to change several thresholds at once.
@export var high_fuel_threshold: float = 90.0:
	set(value):
		_high_fuel_threshold = clamp(
			value, _medium_fuel_threshold + MIN_THRESHOLD_GAP, THRESHOLD_MAX_PERCENT
		)
	get:
		return _high_fuel_threshold

## Percent of [member max_fuel] at which the HUD fuel bar reaches yellow.
## Between [member low_fuel_threshold] and this value it fades from yellow to red.
## Setting it alone clamps it between its neighbours, at least 1 apart from each.
@export var medium_fuel_threshold: float = 50.0:
	set(value):
		_medium_fuel_threshold = clamp(
			value, _low_fuel_threshold + MIN_THRESHOLD_GAP, _high_fuel_threshold - MIN_THRESHOLD_GAP
		)
	get:
		return _medium_fuel_threshold

## Percent of [member max_fuel] at or below which the HUD low-fuel warning blinks.
## Between [member no_fuel_threshold] and this value the bar fades from red to dark red.
## Setting it alone clamps it between its neighbours, at least 1 apart from each.
@export var low_fuel_threshold: float = 30.0:
	set(value):
		_low_fuel_threshold = clamp(
			value,
			_no_fuel_threshold + MIN_THRESHOLD_GAP,
			_medium_fuel_threshold - MIN_THRESHOLD_GAP
		)
	get:
		return _low_fuel_threshold

## Percent of [member max_fuel] below which the HUD fuel bar is solid dark red.
## Setting it alone clamps it between 0 and [member low_fuel_threshold] - 1.
@export var no_fuel_threshold: float = 15.0:
	set(value):
		_no_fuel_threshold = clamp(
			value, THRESHOLD_MIN_PERCENT, _low_fuel_threshold - MIN_THRESHOLD_GAP
		)
	get:
		return _no_fuel_threshold

# Backing fields, so set_thresholds() can store a validated set without going through
# the single-value clamps, whose result depends on the order of assignment (#1147).
var _high_fuel_threshold: float = 90.0
var _medium_fuel_threshold: float = 50.0
var _low_fuel_threshold: float = 30.0
var _no_fuel_threshold: float = 15.0


func _init() -> void:
	current_fuel = max_fuel


## Safely increase fuel by the specified amount.
##
## Helper method to safely increase fuel when the amount is positive.
##
## [param amount]: The floating-point value to add to the current fuel.
func refuel(amount: float) -> void:
	if amount > 0:
		self.current_fuel += amount


## Sets all fuel thresholds at once. Values are percentages of max fuel.
## Requires 0 <= no_fuel < low < medium < high <= 100, each at least 1 apart.
## Returns false and changes nothing when the set is invalid.
##
## Unlike the single-value setters, the result doesn't depend on the current values:
## a valid set applies exactly as written (#1147).
##
## [param high]: New [member high_fuel_threshold], in percent.
## [param medium]: New [member medium_fuel_threshold], in percent.
## [param low]: New [member low_fuel_threshold], in percent.
## [param no_fuel]: New [member no_fuel_threshold], in percent.
func set_thresholds(high: float, medium: float, low: float, no_fuel: float) -> bool:
	if not _is_valid_threshold_set(high, medium, low, no_fuel):
		var values: String = "high %s, medium %s, low %s, no_fuel %s" % [high, medium, low, no_fuel]
		push_warning(
			(
				"FuelResource: rejected fuel thresholds (%s). " % values
				+ "Need 0 <= no_fuel < low < medium < high <= 100, each at least 1 apart. "
				+ "Keeping the current values."
			)
		)
		return false

	_high_fuel_threshold = high
	_medium_fuel_threshold = medium
	_low_fuel_threshold = low
	_no_fuel_threshold = no_fuel
	return true


## Returns true when the four thresholds form a valid set for [method set_thresholds].
## NaN fails every comparison, so it's rejected too.
static func _is_valid_threshold_set(high: float, medium: float, low: float, no_fuel: float) -> bool:
	return (
		no_fuel >= THRESHOLD_MIN_PERCENT
		and high <= THRESHOLD_MAX_PERCENT
		and low - no_fuel >= MIN_THRESHOLD_GAP
		and medium - low >= MIN_THRESHOLD_GAP
		and high - medium >= MIN_THRESHOLD_GAP
	)
