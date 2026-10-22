## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

extends "res://addons/gut/test.gd"

const WEAPON_SCRIPT: GDScript = preload("res://scripts/entities/weapon.gd")
const BULLET_SCENE: PackedScene = preload("res://scenes/bullet.tscn")

var weapon: Node2D
var child_weapon: FireResultWeapon


class FireResultWeapon extends Node2D:
	var succeeds: bool = true
	var fire_calls: int = 0

	func fire() -> bool:
		fire_calls += 1
		return succeeds


class TunedWeapon extends Node2D:
	@export var weapon_name: String = "Test Cannon"
	@export var fire_rate: float = 0.65
	@export var damage: float = 31.0


class RateOnlyWeapon extends Node2D:
	@export var fire_rate: float = 0.8


class DamageOnlyWeapon extends Node2D:
	@export var damage: float = 53.0


func before_each() -> void:
	# Keep the controller outside the tree: _ready requires an equipped scene.
	weapon = autofree(WEAPON_SCRIPT.new())
	child_weapon = FireResultWeapon.new()
	weapon.add_child(child_weapon)
	weapon.current_weapon = child_weapon
	weapon.weapon_resource.current_ammo = 3
	watch_signals(weapon)


func _pack(node: Node2D) -> PackedScene:
	var packed := PackedScene.new()
	assert_eq(packed.pack(node), OK)
	node.free()
	return packed


func test_successful_shot_emits_once_after_ammo_is_deducted() -> void:
	var observed_ammo: Array[int] = []
	weapon.weapon_fired.connect(
		func(_remaining: int) -> void: observed_ammo.append(weapon.weapon_resource.current_ammo)
	)
	weapon.fire()

	assert_eq(child_weapon.fire_calls, 1)
	assert_eq(weapon.weapon_resource.current_ammo, 2)
	assert_signal_emit_count(weapon, "weapon_fired", 1)
	assert_signal_emitted_with_parameters(weapon, "weapon_fired", [2])
	assert_eq(observed_ammo.size(), 1)
	assert_eq(observed_ammo[0], 2, "Signal listeners must observe the updated resource.")


func test_failed_shot_preserves_ammo_and_emits_nothing() -> void:
	child_weapon.succeeds = false
	weapon.fire()

	assert_eq(child_weapon.fire_calls, 1)
	assert_eq(weapon.weapon_resource.current_ammo, 3)
	assert_signal_not_emitted(weapon, "weapon_fired")


func test_empty_magazine_does_not_delegate_or_emit() -> void:
	weapon.weapon_resource.current_ammo = 0
	weapon.fire()

	assert_eq(child_weapon.fire_calls, 0)
	assert_eq(weapon.weapon_resource.current_ammo, 0)
	assert_signal_not_emitted(weapon, "weapon_fired")


func test_last_round_emits_zero_once_and_blocks_subsequent_shot() -> void:
	weapon.weapon_resource.current_ammo = 1
	weapon.fire()
	weapon.fire()

	assert_eq(child_weapon.fire_calls, 1)
	assert_eq(weapon.weapon_resource.current_ammo, 0)
	assert_signal_emit_count(weapon, "weapon_fired", 1)
	assert_signal_emitted_with_parameters(weapon, "weapon_fired", [0])


func test_failed_shot_between_successes_does_not_create_signal_or_ammo_gap() -> void:
	weapon.fire()
	child_weapon.succeeds = false
	weapon.fire()
	child_weapon.succeeds = true
	weapon.fire()

	assert_eq(child_weapon.fire_calls, 3)
	assert_eq(weapon.weapon_resource.current_ammo, 1)
	assert_signal_emit_count(weapon, "weapon_fired", 2)
	assert_signal_emitted_with_parameters(weapon, "weapon_fired", [2], 0)
	assert_signal_emitted_with_parameters(weapon, "weapon_fired", [1], 1)


func test_missing_active_weapon_does_not_emit() -> void:
	weapon.current_weapon = null
	weapon.fire()

	assert_push_error("current_weapon null or no 'fire()' method")
	assert_eq(weapon.weapon_resource.current_ammo, 3)
	assert_signal_not_emitted(weapon, "weapon_fired")


func test_active_node_without_fire_method_does_not_emit() -> void:
	var inert := Node2D.new()
	weapon.add_child(inert)
	weapon.current_weapon = inert
	weapon.fire()

	assert_push_error("current_weapon null or no 'fire()' method")
	assert_eq(weapon.weapon_resource.current_ammo, 3)
	assert_signal_not_emitted(weapon, "weapon_fired")


func test_switch_copies_direct_stats_without_replacing_shared_resource() -> void:
	weapon.weapon_types.assign([_pack(TunedWeapon.new())])
	var shared: WeaponResource = weapon.weapon_resource
	weapon.switch_to(0)

	assert_eq(weapon.weapon_resource, shared)
	assert_eq(shared.fire_rate, 0.65)
	assert_eq(shared.damage, 31.0)
	assert_eq(shared.current_ammo, 3)
	assert_signal_not_emitted(weapon, "weapon_fired")


func test_switch_updates_stats_again_for_next_weapon() -> void:
	var second := TunedWeapon.new()
	second.fire_rate = 1.2
	second.damage = 75.0
	weapon.weapon_types.assign([_pack(TunedWeapon.new()), _pack(second)])
	weapon.switch_to(0)
	weapon.switch_to(1)

	assert_eq(weapon.weapon_resource.fire_rate, 1.2)
	assert_eq(weapon.weapon_resource.damage, 75.0)
	assert_eq(weapon.weapon_resource.current_index, 1)
	assert_eq(weapon.weapon_resource.current_ammo, 3)
	assert_signal_not_emitted(weapon, "weapon_fired")


func test_switch_without_optional_stats_preserves_resource_values() -> void:
	weapon.weapon_resource.fire_rate = 0.9
	weapon.weapon_resource.damage = 19.0
	weapon.weapon_types.assign([_pack(Node2D.new())])
	weapon.switch_to(0)

	assert_eq(weapon.weapon_resource.fire_rate, 0.9)
	assert_eq(weapon.weapon_resource.damage, 19.0)


func test_switch_with_only_fire_rate_preserves_damage() -> void:
	weapon.weapon_resource.damage = 19.0
	weapon.weapon_types.assign([_pack(RateOnlyWeapon.new())])
	weapon.switch_to(0)

	assert_eq(weapon.weapon_resource.fire_rate, 0.8)
	assert_eq(weapon.weapon_resource.damage, 19.0)


func test_switch_with_only_damage_preserves_fire_rate() -> void:
	weapon.weapon_resource.fire_rate = 0.9
	weapon.weapon_types.assign([_pack(DamageOnlyWeapon.new())])
	weapon.switch_to(0)

	assert_eq(weapon.weapon_resource.fire_rate, 0.9)
	assert_eq(weapon.weapon_resource.damage, 53.0)


func test_switch_applies_resource_bounds_to_imported_stats() -> void:
	var invalid := TunedWeapon.new()
	invalid.fire_rate = 0.0
	invalid.damage = -5.0
	weapon.weapon_types.assign([_pack(invalid)])
	weapon.switch_to(0)

	assert_eq(weapon.weapon_resource.fire_rate, 0.01)
	assert_eq(weapon.weapon_resource.damage, 0.0)


func test_switch_to_configured_bullet_synchronizes_shared_stats() -> void:
	var bullet: Node2D = BULLET_SCENE.instantiate()
	var bullet_config := BulletResource.new()
	bullet_config.fire_rate = 0.75
	bullet_config.damage = 48
	bullet.config = bullet_config
	weapon.weapon_types.assign([_pack(bullet)])
	weapon.switch_to(0)

	# Regression: bullet tuning moved from node properties into BulletResource.
	assert_eq(weapon.weapon_resource.fire_rate, 0.75)
	assert_eq(weapon.weapon_resource.damage, 48.0)
	assert_eq(weapon.weapon_resource.current_ammo, 3)
