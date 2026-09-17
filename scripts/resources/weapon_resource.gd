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
		# 1. Cache the old active weapon name
		var old_name: String = "None"
		if (
			not available_weapons.is_empty()
			and current_index >= 0
			and current_index < available_weapons.size()
		):
			old_name = available_weapons[current_index]

		# 2. Update the array (with duplicate() to prevent reference mutation)
		if value.is_empty():
			available_weapons = ["None"]
		else:
			available_weapons = value.duplicate()

		# 3. Check for clamping or silent swaps
		if current_index >= available_weapons.size():
			# The array shrank. Triggering self.current_index will handle clamping
			# and automatically emit the signal since the index number is changing.
			self.current_index = max(0, available_weapons.size() - 1)
		else:
			# The index stayed the same. Did the weapon name at this index change?
			var new_name: String = available_weapons[current_index]
			if old_name != new_name:
				weapon_swapped.emit(current_index, new_name)
	get:
		# Protect the output boundary: return a copy so external callers cannot
		# mutate the internal array by reference and bypass the setter validations.
		return available_weapons.duplicate()

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
