## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## fuel_resource.gd
##
## DATA CONTAINER: Manages the player's fuel state and thresholds.
## Operates as an independent, platform-agnostic Subject in the Observer Pattern.
class_name FuelResource
extends Resource

## Emitted strictly when the effective fuel value changes.
signal fuel_changed(new_value: float)

## Emitted strictly when crossing from previous_fuel > 0.0 to new_fuel == 0.0.
signal fuel_depleted

# --- Backing Fields ---
var _max_fuel: float = 100.0
var _current_fuel: float = _max_fuel
var _high_fuel_threshold: float = 90.0
var _medium_fuel_threshold: float = 50.0
var _low_fuel_threshold: float = 30.0
var _no_fuel_threshold: float = 15.0

# --- State Properties ---

@export var max_fuel: float = 100.0:
	set(value):
		# Invariant: tank size cannot drop below 1.0
		var new_max: float = max(1.0, value)

		if _max_fuel == new_max:
			return

		_max_fuel = new_max

		# Invariant: Shrinking max_fuel must clamp current_fuel.
		# Assigning via `self.` triggers the current_fuel setter,
		# which handles the clamp and emits fuel_changed automatically.
		if _current_fuel > _max_fuel:
			self.current_fuel = _max_fuel
	get:
		return _max_fuel

@export var current_fuel: float = 100.0:
	set(value):
		var old_fuel: float = _current_fuel
		var new_fuel: float = clamp(value, 0.0, _max_fuel)

		# Invariant: Do not emit signals if the effective value hasn't changed
		if old_fuel == new_fuel:
			return

		_current_fuel = new_fuel
		fuel_changed.emit(_current_fuel)

		# Invariant: Deterministic crossing semantics for flameout
		if old_fuel > 0.0 and _current_fuel == 0.0:
			fuel_depleted.emit()
	get:
		return _current_fuel

@export var base_consumption_rate: float = 1.0

# --- Threshold Properties ---

@export var high_fuel_threshold: float = 90.0:
	set(value):
		var new_val: float = max(value, _medium_fuel_threshold + 1.0)
		if _high_fuel_threshold == new_val:
			return
		_high_fuel_threshold = new_val
	get:
		return _high_fuel_threshold

@export var medium_fuel_threshold: float = 50.0:
	set(value):
		var new_val: float = clamp(value, _low_fuel_threshold + 1.0, _high_fuel_threshold - 1.0)
		if _medium_fuel_threshold == new_val:
			return
		_medium_fuel_threshold = new_val
	get:
		return _medium_fuel_threshold

@export var low_fuel_threshold: float = 30.0:
	set(value):
		var new_val: float = clamp(value, _no_fuel_threshold + 1.0, _medium_fuel_threshold - 1.0)
		if _low_fuel_threshold == new_val:
			return
		_low_fuel_threshold = new_val
	get:
		return _low_fuel_threshold

@export var no_fuel_threshold: float = 15.0:
	set(value):
		var new_val: float = min(value, _low_fuel_threshold - 1.0)
		if _no_fuel_threshold == new_val:
			return
		_no_fuel_threshold = new_val
	get:
		return _no_fuel_threshold


func _init() -> void:
	_current_fuel = _max_fuel


## Helper method to safely increase fuel.
func refuel(amount: float) -> void:
	if amount > 0:
		self.current_fuel += amount
