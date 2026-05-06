## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
# weapon.gd - FIXED with debug logs for null current_weapon
extends Node2D

@export var weapon_types: Array[PackedScene] = []  # Drag bullet.tscn...

var current_weapon: Node2D
var current_index: int = 0


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
		Globals.log_message("Switched to " + current_weapon.name, Globals.LogLevel.INFO)
	else:
		push_error(
			"Failed to instantiate weapon_types[" + str(index) + "] - check scene/script errors!"
		)
		current_weapon = null  # Explicit


func fire() -> void:
	if current_weapon and current_weapon.has_method("fire"):
		Globals.log_message(
			"Weapon.fire() delegating to " + current_weapon.name, Globals.LogLevel.DEBUG
		)
		current_weapon.fire()
	else:
		push_error(
			(
				"Weapon.fire(): current_weapon null or no 'fire()' method! Types: "
				+ str(weapon_types.size())
			)
		)


func get_num_weapons() -> int:
	return weapon_types.size()
