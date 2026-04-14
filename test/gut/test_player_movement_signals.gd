## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_player_movement_signals.gd
## GUT unit tests for Player movement and the decoupled speed_changed signal.
extends "res://addons/gut/test.gd"

const GutTestHelper = preload("res://test/gut/gut_test_helper.gd")

var _mock_root: Node
var _player: Variant # CHANGED: Use Variant to allow dynamic property access to player.gd variables
var _original_settings: GameSettingsResource
var _added_actions: Array[String] = []

## Per-test setup: Isolate memory and establish mock hierarchy.
## :rtype: void
func before_each() -> void:
	_original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()
	Globals.settings.current_log_level = Globals.LogLevel.NONE
	
	# Guarantee required actions exist so simulated Input.action_press doesn't error
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
	for action: String in _added_actions:
		InputMap.erase_action(action)
	_added_actions.clear()
	
	# Force-release simulated inputs to prevent test leakage
	Input.action_release("speed_up")
	Input.action_release("speed_down")

## test_physics_emits_speed_changed_on_acceleration | Signal Behavior
## :rtype: void
func test_physics_emits_speed_changed_on_acceleration() -> void:
	gut.p("Testing: _physics_process emits speed_changed exactly once per frame when accelerating.")
	watch_signals(_player)
	
	Globals.settings.current_fuel = 100.0
	_player.speed["speed"] = 100.0
	
	# Simulate acceleration input
	Input.action_press("speed_up")
	_player._physics_process(1.0) # 1 second delta to cause noticeable change
	
	assert_signal_emitted(_player, "speed_changed", "Signal must fire when speed up increases value.")
	assert_gt(float(_player.speed["speed"]), 100.0, "Speed logic should have increased current speed.")

## test_physics_does_not_spam_speed_changed | Signal Efficiency
## :rtype: void
func test_physics_does_not_spam_speed_changed() -> void:
	gut.p("Testing: _physics_process suppresses speed_changed emissions when cruising.")
	watch_signals(_player)
	
	Globals.settings.current_fuel = 100.0
	_player.speed["speed"] = 250.0 
	
	# Process multiple frames without active input
	_player._physics_process(0.1)
	_player._physics_process(0.1)
	_player._physics_process(0.1)
	
	assert_signal_emit_count(_player, "speed_changed", 0, "Signal must not emit when speed is unchanged.")

## test_flameout_resets_speed_and_emits_signal | Edge Cases
## :rtype: void
func test_flameout_resets_speed_and_emits_signal() -> void:
	gut.p("Testing: Engine flameout halts the plane instantly and notifies UI.")
	watch_signals(_player)
	
	_player.speed["speed"] = 300.0
	
	# Actually empty the mock fuel tank so _set_speed() allows a 0.0 value!
	Globals.settings.current_fuel = 0.0 
	
	# Manually trigger the flameout handler
	_player._on_player_out_of_fuel()
	
	assert_eq(float(_player.speed["speed"]), 0.0, "Speed must forcibly reset to 0.0 on zero fuel.")
	assert_signal_emitted(_player, "speed_changed", "Flameout must broadcast the speed halt to UI.")

## test_ui_updates_on_speed_signal | UI Reactivity
## :rtype: void
func test_ui_updates_on_speed_signal() -> void:
	gut.p("Testing: Target UI updates instantly when speed_changed fires.")
	
	var hud_panel: Variant = _mock_root.get_node("PlayerStatsPanel")
	hud_panel.setup_hud(_player)
	
	hud_panel.speed_bar.value = 0.0
	_player.speed["speed"] = 500.0 # Force local sync
	
	# Fire the signal explicitly using the Global Resource setting
	_player.speed_changed.emit(500.0, Globals.settings.max_speed)
	
	assert_eq(hud_panel.speed_bar.value, 500.0, "Progress bar must sync tightly with speed_changed.")

## test_speed_clamps_to_max_and_min | Constraints
## :rtype: void
func test_speed_clamps_to_max_and_min() -> void:
	gut.p("Testing: Speed values obey MIN and MAX constraints.")
	
	Globals.settings.current_fuel = 100.0
	
	var max_cap: float = Globals.settings.max_speed
	var min_cap: float = Globals.settings.min_speed
	
	# --- 1. Test MAX Clamp ---
	_player.speed["speed"] = max_cap - 5.0
	
	Input.action_press("speed_up")
	# Force an extreme acceleration delta
	_player._physics_process(10.0) 
	
	assert_eq(float(_player.speed["speed"]), max_cap, "Speed must not exceed configured MAX_SPEED.")
	Input.action_release("speed_up") # Release the key for the next test phase
	
	# --- 2. Test MIN Clamp ---
	_player.speed["speed"] = min_cap + 5.0
	
	Input.action_press("speed_down")
	# Force an extreme deceleration delta
	_player._physics_process(10.0)
	
	assert_eq(float(_player.speed["speed"]), min_cap, "Speed must not fall below configured MIN_SPEED.")
	Input.action_release("speed_down") # Clean up
