## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
# weapon.gd
extends Node2D

@export var weapon_types: Array[PackedScene] = []  # Drag bullet.tscn...

var current_weapon: Node2D
var current_index: int = 0
var weapon_resource: WeaponResource = WeaponResource.new()


func _ready() -> void:
	Globals.log_message(
		"Weapon _ready: Types size " + str(weapon_types.size()), Globals.LogLevel.DEBUG
	)
	if weapon_types.is_empty():
		push_error("Weapon: No weapon_types assigned!")
		return
	switch_to(0)


func switch_to(index: int) -> void:
	Globals.log_message(
		(
			"Switching to "
			+ str(index)
			+ ": "
			+ str(weapon_types[index].resource_path if index < weapon_types.size() else "INVALID")
		),
		Globals.LogLevel.DEBUG
	)
	if index < 0 or index >= weapon_types.size():
		push_warning("Weapon: Invalid index " + str(index))
		return
	if current_weapon:
		current_weapon.queue_free()
	current_weapon = weapon_types[index].instantiate()
	Globals.log_message("Instantiate result: " + str(current_weapon), Globals.LogLevel.DEBUG)
	if current_weapon:
		add_child(current_weapon)
		current_weapon.position = Vector2.ZERO
		current_index = index

		# 1. Safely extract a readable weapon name, falling back to "Machine Gun"
		# This allows future weapons (e.g., missiles) to define a custom 'weapon_name' variable.
		var safe_weapon_name: String = "Machine Gun"
		if current_weapon.get("weapon_name") != null:
			safe_weapon_name = String(current_weapon.get("weapon_name"))

		# 2. Sync the resource's available_weapons array
		# We pull the duplicate, resize if necessary, inject the safe name, and push it back.
		var updated_weapons: Array[String] = weapon_resource.available_weapons
		if updated_weapons.size() < weapon_types.size():
			updated_weapons.resize(weapon_types.size())
		updated_weapons[index] = safe_weapon_name
		weapon_resource.available_weapons = updated_weapons

		# 3. Update the resource index (this automatically triggers the weapon_swapped signal)
		weapon_resource.current_index = index

		Globals.log_message("Switched to " + safe_weapon_name, Globals.LogLevel.INFO)
	else:
		push_error(
			"Failed to instantiate weapon_types[" + str(index) + "] - check scene/script errors!"
		)
		current_weapon = null  # Explicit


func fire() -> void:
	if current_weapon and current_weapon.has_method("fire"):
		# Check if we have ammo before firing (assuming < 0 is infinite ammo)
		if weapon_resource.current_ammo > 0 or weapon_resource.max_ammo < 0:
			Globals.log_message(
				"Weapon.fire() delegating to " + str(current_weapon.name), Globals.LogLevel.DEBUG
			)
			
			# The child weapon's fire() method MUST return a boolean indicating success
			var shot_fired: bool = current_weapon.fire()

			# Deduct ammo ONLY if the weapon successfully fired a projectile
			if shot_fired and weapon_resource.max_ammo > 0:
				weapon_resource.current_ammo -= 1
		else:
			Globals.log_message("Weapon.fire(): Out of ammo!", Globals.LogLevel.WARNING)
	else:
		push_error(
			(
				"Weapon.fire(): current_weapon null or no 'fire()' method! Types: "
				+ str(weapon_types.size())
			)
		)


func get_num_weapons() -> int:
	return weapon_types.size()
