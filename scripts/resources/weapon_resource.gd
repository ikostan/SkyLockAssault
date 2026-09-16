## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## weapon_resource.gd
##
## DATA CONTAINER: Manages weapon states, ammo, and firing configurations.
## Operates as an independent, platform-agnostic Subject in the Observer Pattern.
class_name WeaponResource
extends Resource

## Emitted strictly when the active weapon index changes.
signal weapon_swapped(index: int, weapon_name: String)

## Emitted strictly when the effective ammo count changes.
signal ammo_updated(current: int, max_ammo: int)

# --- State Properties ---

@export var available_weapons: Array[String] = ["Machine Gun"]:
	set(value):
		if value.is_empty():
			available_weapons = ["None"]
		else:
			available_weapons = value

		# Invariant: Clamp index if the new array is smaller than the current index
		if current_index >= available_weapons.size():
			# 'self.' explicitly triggers the current_index setter
			self.current_index = max(0, available_weapons.size() - 1)

@export var current_index: int = 0:
	set(value):
		# Invariant: Cannot select a weapon outside the available array bounds
		var new_index: int = clampi(value, 0, max(0, available_weapons.size() - 1))

		if current_index == new_index:
			return

		current_index = new_index

		var w_name: String = (
			available_weapons[current_index] if not available_weapons.is_empty() else "None"
		)
		weapon_swapped.emit(current_index, w_name)

@export var max_ammo: int = 1000:
	set(value):
		var new_max: int = maxi(1, value)
		if max_ammo == new_max:
			return

		max_ammo = new_max

		# Invariant: Shrinking max_ammo must clamp current_ammo
		if current_ammo > max_ammo:
			self.current_ammo = max_ammo

@export var current_ammo: int = 1000:
	set(value):
		var old_ammo: int = current_ammo
		var new_ammo: int = clampi(value, 0, max_ammo)

		if old_ammo == new_ammo:
			return

		current_ammo = new_ammo
		ammo_updated.emit(current_ammo, max_ammo)

# --- Tuning Properties ---

@export var fire_rate: float = 0.1:
	set(value):
		fire_rate = max(0.01, value)

@export var damage: float = 10.0:
	set(value):
		damage = max(0.0, value)


func _init() -> void:
	current_ammo = max_ammo
