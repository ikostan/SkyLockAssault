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
	var anim_l: AnimatedSprite2D = _player.rotor_left.get_node("AnimatedSprite2D")
	
	# Empty the tank so the real flameout handler stops the engine
	_player.fuel_resource.current_fuel = 0.0
	assert_true(_player.fuel_timer.is_stopped(), "Precondition: flameout must stop the fuel timer.")
	assert_false(anim_l.is_playing(), "Precondition: flameout must stop the rotors.")
	
	# Refuel through the player's FuelResource, the source of truth for fuel state (#1142)
	_player.fuel_resource.current_fuel = 50.0 
	
	assert_false(_player.fuel_timer.is_stopped(), "Fuel timer must reignite on refuel.")
	assert_true(anim_l.is_playing(), "Rotors must automatically resume spinning.")


## test_settings_writes_do_not_reach_fuel_resource | Fuel Ownership
## Rewritten from the #1142 bridge test: #1143 removed the settings -> player fuel bridge,
## so no settings write can refuel the player or reignite the engine. Refueling goes
## through FuelResource only (see test_engine_reignites_on_refuel).
## :rtype: void
func test_settings_writes_do_not_reach_fuel_resource() -> void:
	gut.p("Testing: Settings writes cannot refuel the player or reignite the engine.")
	var anim_l: AnimatedSprite2D = _player.rotor_left.get_node("AnimatedSprite2D")
	
	# Empty the tank so the real flameout handler stops the engine
	_player.fuel_resource.current_fuel = 0.0
	assert_true(_player.fuel_timer.is_stopped(), "Precondition: flameout must stop the fuel timer.")
	assert_false(anim_l.is_playing(), "Precondition: flameout must stop the rotors.")
	
	assert_false("current_fuel" in Globals.settings, "The settings resource must not hold live fuel.")
	Globals.settings.max_fuel = 50.0
	Globals.settings.difficulty = 1.5
	
	assert_eq(_player.fuel_resource.current_fuel, 0.0, "Settings writes must not change live fuel.")
	assert_true(_player.fuel_timer.is_stopped(), "Settings writes must not reignite the engine.")
	assert_false(anim_l.is_playing(), "Settings writes must not restart the rotors.")


## test_fuel_resource_change_leaves_settings_untouched | Fuel Ownership
## Rewritten from the #1142 bridge test: #1143 removed the FuelResource -> settings
## mirror, so a fuel change must not notify settings observers or change any setting.
## :rtype: void
func test_fuel_resource_change_leaves_settings_untouched() -> void:
	gut.p("Testing: A FuelResource change no longer touches the settings resource.")
	var max_fuel_before: float = Globals.settings.max_fuel
	watch_signals(Globals.settings)
	
	_player.fuel_resource.current_fuel = 42.0
	
	assert_eq(_player.fuel_resource.current_fuel, 42.0, "FuelResource must hold the new fuel level.")
	assert_signal_not_emitted(Globals.settings, "setting_changed", "Fuel changes must not notify settings observers.")
	assert_eq(Globals.settings.max_fuel, max_fuel_before, "Fuel changes must not change max_fuel.")


## test_full_fuel_run_emits_no_setting_changed | Fuel Ownership (#1143)
## Drains the tank through the real fuel timer callback, then refuels. Before #1143 every
## tick emitted setting_changed("current_fuel", ...); now none of it reaches the settings.
## :rtype: void
func test_full_fuel_run_emits_no_setting_changed() -> void:
	gut.p("Testing: Draining and refueling the tank never emits setting_changed.")
	# Full speed and a high consumption rate empty the tank in a few ticks.
	_player.current_speed = _player.speed_resource.max_speed
	_player.fuel_resource.base_consumption_rate = 25.0
	watch_signals(Globals.settings)
	watch_signals(_player.fuel_resource)
	
	var ticks: int = 0
	while _player.fuel_resource.current_fuel > 0.0 and ticks < 100:
		_player._on_fuel_timer_timeout()
		ticks += 1
	
	assert_eq(_player.fuel_resource.current_fuel, 0.0, "Precondition: the tank must run dry.")
	assert_gt(ticks, 1, "Precondition: the drain must take several ticks.")
	assert_signal_emit_count(_player.fuel_resource, "fuel_depleted", 1, "The tank must run dry exactly once.")
	assert_true(_player.fuel_timer.is_stopped(), "Precondition: flameout must stop the fuel timer.")
	
	_player.fuel_resource.current_fuel = _player.fuel_resource.max_fuel
	
	assert_false(_player.fuel_timer.is_stopped(), "Refueling must reignite the engine.")
	assert_signal_emitted(_player.fuel_resource, "fuel_changed", "Fuel changes must go through FuelResource.")
	assert_signal_not_emitted(Globals.settings, "setting_changed", "A full fuel run must not emit setting_changed.")


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
