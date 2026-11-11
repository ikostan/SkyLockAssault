## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_player_fuel_logic.gd
## GUT unit tests for Player fuel consumption, engine states, and UI Reactivity.
extends "res://addons/gut/test.gd"

const GutTestHelper = preload("res://test/gut/gut_test_helper.gd")

var _mock_root: Node
var _player: Variant # CHANGED: Use Variant to allow dynamic property access to player.gd variables
var _original_settings: GameSettingsResource
var _added_actions: Array[String] = []

## Per-test setup.
## :rtype: void
func before_each() -> void:
	_original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()
	Globals.settings.current_log_level = Globals.LogLevel.NONE
	
	for action: String in ["speed_up", "speed_down", "move_left", "move_right"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			_added_actions.append(action)
			
	# NEW: Call the shared static builder
	_mock_root = GutTestHelper.build_mock_player_scene()
	add_child_autoqfree(_mock_root)
	_player = _mock_root.get_node("Player")

## Per-test cleanup.
## :rtype: void
func after_each() -> void:
	Globals.settings = _original_settings
	
	# Ensure ALL mocked actions are explicitly released to prevent test leakage
	for action: String in ["speed_up", "speed_down", "move_left", "move_right"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)
			
	for action: String in _added_actions:
		InputMap.erase_action(action)
	_added_actions.clear()

## test_ui_updates_automatically_on_resource_change | Observer Pattern
## :rtype: void
func test_ui_updates_automatically_on_resource_change() -> void:
	gut.p("Testing: Player UI responds seamlessly to external fuel updates.")
	
	var hud_panel: Variant = _mock_root.get_node("PlayerStatsPanel")
	
	# Explicitly inject the three required resources instead of the raw player node
	var dummy_weapon_res: WeaponResource = WeaponResource.new()
	hud_panel.setup_hud(_player.fuel_resource, _player.speed_resource, dummy_weapon_res)
	
	var fuel_bar: ProgressBar = hud_panel.fuel_bar
	
	# FIX: Mutate the injected Resource directly, not Globals.settings!
	_player.fuel_resource.max_fuel = 200.0
	_player.fuel_resource.current_fuel = 150.0 
	
	assert_eq(fuel_bar.max_value, 200.0, "Fuel Bar max_value must sync with Resource max.")
	assert_eq(fuel_bar.value, 150.0, "Fuel Bar value must sync automatically.")


## test_engine_stops_on_zero_fuel | Component State
## :rtype: void
func test_engine_stops_on_zero_fuel() -> void:
	gut.p("Testing: Zero fuel stops timers and rotor animations immediately.")
	
	_player.fuel_timer.start()
	var anim_r: AnimatedSprite2D = _player.rotor_right.get_node("AnimatedSprite2D")
	anim_r.play("default")
	
	_player._on_player_out_of_fuel()
	
	assert_true(_player.fuel_timer.is_stopped(), "Fuel timer must stop running on flameout.")
	assert_false(anim_r.is_playing(), "Rotors must stop animating when fuel is empty.")

## test_engine_reignites_on_refuel | Component State
## :rtype: void
func test_engine_reignites_on_refuel() -> void:
	gut.p("Testing: Refueling from an empty tank restarts rotors and timers.")
	
	# Simulate dead engine
	_player.fuel_timer.stop()
	var anim_l: AnimatedSprite2D = _player.rotor_left.get_node("AnimatedSprite2D")
	anim_l.stop()
	
	# Refuel through the player's FuelResource, the source of truth for fuel state (#1142)
	_player.fuel_resource.current_fuel = 50.0 
	
	assert_false(_player.fuel_timer.is_stopped(), "Fuel timer must reignite on refuel.")
	assert_true(anim_l.is_playing(), "Rotors must automatically resume spinning.")

## test_bridge_settings_fuel_write_reaches_fuel_resource | Compatibility Bridge
## BRIDGE TEST (#1143): legacy writes to Globals.settings.current_fuel still reach the
## player's FuelResource (and reignite the engine). #1143 removes the bridge; rewrite this
## test to confirm the settings write no longer exists or no longer affects the player.
## :rtype: void
func test_bridge_settings_fuel_write_reaches_fuel_resource() -> void:
	gut.p("Testing: Bridge copies a Globals.settings fuel write into the FuelResource.")
	
	_player.fuel_timer.stop()
	var anim_l: AnimatedSprite2D = _player.rotor_left.get_node("AnimatedSprite2D")
	anim_l.stop()
	
	Globals.settings.current_fuel = 50.0
	
	assert_eq(_player.fuel_resource.current_fuel, 50.0, "Bridge must copy settings fuel into FuelResource.")
	assert_false(_player.fuel_timer.is_stopped(), "Fuel timer must reignite on a bridged refuel.")
	assert_true(anim_l.is_playing(), "Rotors must resume spinning on a bridged refuel.")


## test_bridge_fuel_resource_change_mirrors_to_settings | Compatibility Bridge
## BRIDGE TEST (#1143): FuelResource changes are mirrored into Globals.settings.current_fuel.
## #1143 removes the mirror; rewrite this test to confirm settings no longer change.
## :rtype: void
func test_bridge_fuel_resource_change_mirrors_to_settings() -> void:
	gut.p("Testing: Bridge mirrors a FuelResource change back into Globals.settings.")
	
	_player.fuel_resource.current_fuel = 42.0
	
	assert_eq(Globals.settings.current_fuel, 42.0, "Bridge must mirror FuelResource fuel into settings.")


## test_lateral_movement_blocked_without_fuel | Movement Constraints
## :rtype: void
func test_lateral_movement_blocked_without_fuel() -> void:
	gut.p("Testing: Lateral turning is disabled if fuel is completely empty.")
	
	_player.fuel_resource.current_fuel = 0.0
	_player.current_speed = 150.0 
	_player.player.velocity.x = 0.0
	
	Input.action_press("move_left")
	_player._physics_process(0.1)
	
	assert_eq(float(_player.player.velocity.x), 0.0, "Plane must not turn without fuel, ignoring inputs.")
