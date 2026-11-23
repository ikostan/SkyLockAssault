## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_weapon_slots.gd
##
## Weapon keeps one WeaponFirer per slot, so swapping can't bypass a cooldown (#1138).
## Mock firers mirror BulletFirer's can_fire/CooldownTimer pattern without spawning projectiles.

extends "res://addons/gut/test.gd"

const WEAPON_SCRIPT: GDScript = preload("res://scripts/entities/weapon.gd")
const COOLDOWN: float = 0.3

var weapon: Weapon


class CooldownFirer extends WeaponFirer:
	var can_fire: bool = true
	var shots: int = 0
	var timer: Timer

	func _ready() -> void:
		timer = Timer.new()
		timer.one_shot = true
		timer.name = "CooldownTimer"
		add_child(timer)
		timer.timeout.connect(func() -> void: can_fire = true)

	func fire() -> bool:
		if not can_fire:
			return false
		can_fire = false
		shots += 1
		timer.start(0.3)  # COOLDOWN; inner classes can't read the outer constant
		return true


func before_each() -> void:
	weapon = WEAPON_SCRIPT.new()
	weapon.weapon_resource.current_ammo = 100


func after_each() -> void:
	if is_instance_valid(weapon):
		weapon.free()


func _pack(node: Node2D, weapon_name: String = "") -> PackedScene:
	if node is WeaponFirer and weapon_name != "":
		(node as WeaponFirer).weapon_name = weapon_name
	var packed := PackedScene.new()
	assert_eq(packed.pack(node), OK)
	node.free()
	return packed


## Puts the weapon in the tree with [param count] cooldown slots; _ready() equips slot 0.
func _arm(count: int) -> void:
	var types: Array[PackedScene] = []
	for i: int in count:
		types.append(_pack(CooldownFirer.new(), "Gun %d" % i))
	weapon.weapon_types.assign(types)
	add_child(weapon)


func _firers() -> Array[WeaponFirer]:
	var found: Array[WeaponFirer] = []
	for child: Node in weapon.get_children():
		if child is WeaponFirer:
			found.append(child)
	return found


func test_swap_away_and_back_cannot_fire_until_cooldown_ends() -> void:
	_arm(2)
	var first: CooldownFirer = weapon.current_weapon
	weapon.fire()
	weapon.switch_to(1)
	weapon.switch_to(0)
	weapon.fire()

	assert_eq(weapon.current_weapon, first)
	assert_eq(first.shots, 1, "the swap must not reset the first slot's cooldown")
	assert_false(first.can_fire)
	assert_eq(weapon.weapon_resource.current_ammo, 99, "only the real shot uses ammo")

	await wait_seconds(COOLDOWN + 0.15)
	weapon.fire()
	assert_eq(first.shots, 2, "the slot fires again once its own cooldown ends")


func test_slot_that_has_not_fired_can_fire_straight_after_a_swap() -> void:
	_arm(2)
	weapon.fire()
	weapon.switch_to(1)
	var second: CooldownFirer = weapon.current_weapon
	weapon.fire()

	assert_eq(second.shots, 1)
	assert_eq(weapon.weapon_resource.current_ammo, 98)


func test_cooldown_that_ends_while_slot_is_inactive_stays_ended() -> void:
	_arm(2)
	var first: CooldownFirer = weapon.current_weapon
	weapon.fire()
	weapon.switch_to(1)

	await wait_seconds(COOLDOWN + 0.15)
	assert_true(first.can_fire, "the hidden slot's timer keeps running")

	weapon.switch_to(0)
	weapon.fire()
	assert_eq(first.shots, 2)


func test_swapping_reuses_the_same_instance_per_slot() -> void:
	_arm(2)
	var first: WeaponFirer = weapon.current_weapon
	weapon.switch_to(1)
	var second: WeaponFirer = weapon.current_weapon
	for i: int in 3:
		weapon.switch_to(0)
		assert_same(weapon.current_weapon, first)
		weapon.switch_to(1)
		assert_same(weapon.current_weapon, second)

	assert_ne(first, second)
	assert_eq(_firers().size(), 2, "one instance per slot, no extras")


func test_unselected_slots_are_not_instantiated() -> void:
	_arm(3)
	assert_eq(_firers().size(), 1, "only slot 0 is created by _ready()")
	weapon.switch_to(2)
	assert_eq(_firers().size(), 2, "slot 1 is still not created")


func test_only_the_active_firer_is_visible_and_receives_fire() -> void:
	_arm(2)
	var first: CooldownFirer = weapon.current_weapon
	weapon.switch_to(1)
	var second: CooldownFirer = weapon.current_weapon

	assert_false(first.visible)
	assert_true(second.visible)
	weapon.fire()
	assert_eq(first.shots, 0)
	assert_eq(second.shots, 1)

	weapon.switch_to(0)
	assert_true(first.visible)
	assert_false(second.visible)


func test_resource_index_updates_on_every_swap() -> void:
	_arm(3)
	watch_signals(weapon.weapon_resource)
	for index: int in [1, 2, 0, 2]:
		weapon.switch_to(index)
		assert_eq(weapon.weapon_resource.current_index, index)

	assert_signal_emit_count(weapon.weapon_resource, "weapon_swapped", 4)
	assert_signal_emitted_with_parameters(weapon.weapon_resource, "weapon_swapped", [1, "Gun 1"], 0)
	assert_signal_emitted_with_parameters(weapon.weapon_resource, "weapon_swapped", [2, "Gun 2"], 1)
	assert_signal_emitted_with_parameters(weapon.weapon_resource, "weapon_swapped", [0, "Gun 0"], 2)


func test_switch_to_next_wraps_around() -> void:
	_arm(3)
	for expected: int in [1, 2, 0, 1]:
		weapon.switch_to_next()
		assert_eq(weapon.weapon_resource.current_index, expected)


func test_switch_to_next_does_nothing_with_one_weapon() -> void:
	_arm(1)
	var only: WeaponFirer = weapon.current_weapon
	watch_signals(weapon.weapon_resource)
	weapon.switch_to_next()

	assert_same(weapon.current_weapon, only)
	assert_eq(weapon.weapon_resource.current_index, 0)
	assert_signal_not_emitted(weapon.weapon_resource, "weapon_swapped")


func test_switch_to_next_does_nothing_without_weapons() -> void:
	weapon.switch_to_next()
	assert_null(weapon.current_weapon)
	assert_eq(weapon.weapon_resource.current_index, 0)


func test_out_of_range_and_negative_indexes_leave_weapon_unchanged() -> void:
	_arm(2)
	weapon.switch_to(1)
	var active: WeaponFirer = weapon.current_weapon
	watch_signals(weapon.weapon_resource)

	for bad: int in [2, 99, -1, -5]:
		weapon.switch_to(bad)
		assert_same(weapon.current_weapon, active, "index %d" % bad)
		assert_eq(weapon.weapon_resource.current_index, 1, "index %d" % bad)

	assert_push_warning_count(4)
	assert_signal_not_emitted(weapon.weapon_resource, "weapon_swapped")
	assert_eq(_firers().size(), 2)


func test_invalid_scene_type_logs_error_and_leaves_weapon_unchanged() -> void:
	weapon.weapon_types.assign([_pack(CooldownFirer.new(), "Gun 0"), _pack(Node2D.new())])
	add_child(weapon)
	var active: WeaponFirer = weapon.current_weapon
	watch_signals(weapon.weapon_resource)
	weapon.switch_to(1)

	assert_push_error("not a WeaponFirer")
	assert_same(weapon.current_weapon, active)
	assert_true(active.visible)
	assert_eq(weapon.weapon_resource.current_index, 0)
	assert_signal_not_emitted(weapon.weapon_resource, "weapon_swapped")
	assert_eq(weapon.get_child_count(), 1, "the rejected instance must be freed")


func test_empty_slot_logs_error_and_leaves_weapon_unchanged() -> void:
	weapon.weapon_types.assign([_pack(CooldownFirer.new(), "Gun 0"), null])
	add_child(weapon)
	var active: WeaponFirer = weapon.current_weapon
	weapon.switch_to(1)

	assert_push_error("is empty")
	assert_same(weapon.current_weapon, active)
	assert_eq(weapon.weapon_resource.current_index, 0)


func test_switch_to_next_keeps_weapon_when_next_slot_is_invalid() -> void:
	weapon.weapon_types.assign([_pack(CooldownFirer.new(), "Gun 0"), _pack(Node2D.new())])
	add_child(weapon)
	var active: WeaponFirer = weapon.current_weapon
	weapon.switch_to_next()

	assert_push_error("not a WeaponFirer")
	assert_same(weapon.current_weapon, active)
	assert_eq(weapon.weapon_resource.current_index, 0)


func test_freeing_weapon_frees_cached_slots() -> void:
	_arm(3)
	weapon.switch_to(1)
	weapon.switch_to(2)
	var firers: Array = _firers()  # Untyped: it holds freed instances after weapon.free()
	assert_eq(firers.size(), 3)

	weapon.free()
	for firer: Variant in firers:
		assert_false(is_instance_valid(firer), "cached slots are freed with Weapon")


## #1140: Weapon._ready() equips slot 0 before the level injects its projectile container,
## so the slot that already exists must get it on injection.
func test_projectile_parent_reaches_slot_created_before_injection() -> void:
	_arm(2)
	var first: WeaponFirer = weapon.current_weapon
	assert_null(first.projectile_parent, "No parent until the level injects one.")
	var container: Node2D = add_child_autofree(Node2D.new())

	weapon.set_projectile_parent(container)

	assert_same(first.projectile_parent, container)


## #1140: a slot first selected after injection gets the same container.
func test_projectile_parent_reaches_slot_created_after_injection() -> void:
	_arm(3)
	var container: Node2D = add_child_autofree(Node2D.new())
	weapon.set_projectile_parent(container)

	weapon.switch_to(2)
	weapon.switch_to(1)

	assert_eq(_firers().size(), 3)
	for firer: WeaponFirer in _firers():
		assert_same(firer.projectile_parent, container, firer.weapon_name + " has the container.")


## #1140: injecting again replaces the container on every slot, and null clears it.
func test_projectile_parent_can_be_replaced_and_cleared() -> void:
	_arm(2)
	weapon.switch_to(1)
	var first_container: Node2D = add_child_autofree(Node2D.new())
	var second_container: Node2D = add_child_autofree(Node2D.new())

	weapon.set_projectile_parent(first_container)
	weapon.set_projectile_parent(second_container)
	for firer: WeaponFirer in _firers():
		assert_same(firer.projectile_parent, second_container)

	weapon.set_projectile_parent(null)
	for firer: WeaponFirer in _firers():
		assert_null(firer.projectile_parent)


## #1140: injecting before any slot exists is kept for the first slot.
func test_projectile_parent_injected_before_ready_reaches_first_slot() -> void:
	var container: Node2D = add_child_autofree(Node2D.new())
	weapon.set_projectile_parent(container)
	_arm(1)
	assert_same(weapon.current_weapon.projectile_parent, container)


## #1140: a slot created after the parent was replaced or cleared gets the current value,
## not the first one injected.
func test_lazily_created_slots_use_the_latest_projectile_parent() -> void:
	_arm(3)
	var original: Node2D = add_child_autofree(Node2D.new())
	var replacement: Node2D = add_child_autofree(Node2D.new())

	weapon.set_projectile_parent(original)
	weapon.set_projectile_parent(replacement)
	weapon.switch_to(1)
	assert_same(weapon.current_weapon.projectile_parent, replacement)

	weapon.set_projectile_parent(null)
	weapon.switch_to(2)
	assert_null(
		weapon.current_weapon.projectile_parent, "A new slot must not inherit a stale parent."
	)
