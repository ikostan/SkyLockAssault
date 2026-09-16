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

@export var high_fuel_threshold: float = 90.0:
	set(value):
		var new_val: float = max(value, medium_fuel_threshold + 1.0)
		if high_fuel_threshold == new_val:
			return
		high_fuel_threshold = new_val

@export var medium_fuel_threshold: float = 50.0:
	set(value):
		var new_val: float = clamp(value, low_fuel_threshold + 1.0, high_fuel_threshold - 1.0)
		if medium_fuel_threshold == new_val:
			return
		medium_fuel_threshold = new_val

@export var low_fuel_threshold: float = 30.0:
	set(value):
		var new_val: float = clamp(value, no_fuel_threshold + 1.0, medium_fuel_threshold - 1.0)
		if low_fuel_threshold == new_val:
			return
		low_fuel_threshold = new_val

@export var no_fuel_threshold: float = 15.0:
	set(value):
		var new_val: float = min(value, low_fuel_threshold - 1.0)
		if no_fuel_threshold == new_val:
			return
		no_fuel_threshold = new_val


func _init() -> void:
	current_fuel = max_fuel


## Helper method to safely increase fuel.
func refuel(amount: float) -> void:
	if amount > 0:
		self.current_fuel += amount
