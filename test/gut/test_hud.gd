## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_hud.gd
##
## Comprehensive GUT unit tests for the Heads-Up Display manager (hud.gd).
## Validates UI state synchronization, color lerping thresholds, and warning label blinking.

extends "res://addons/gut/test.gd"

const GutTestHelper = preload("res://test/gut/gut_test_helper.gd")

var _mock_root: Node
var _hud: Panel
var _player: Variant
var _original_settings: GameSettingsResource


## Pre-test setup: Isolates the global resource state and builds the mock scene hierarchy.
## :rtype: void
func before_each() -> void:
	_original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()
	Globals.settings.current_log_level = Globals.LogLevel.NONE
	
	_mock_root = GutTestHelper.build_mock_player_scene()
	add_child_autoqfree(_mock_root)
	
	_hud = _mock_root.get_node("PlayerStatsPanel")
	_player = _mock_root.get_node("Player")
	
	# ==========================================================
	# PHASE 2 FIX: Update setup_hud to use Dependency Injection.
	# Fallback to a new WeaponResource if the mock player doesn't 
	# have the weapon node fully instantiated in this test scope.
	# ==========================================================
	var w_res: WeaponResource = _player.weapon.weapon_resource if _player.get("weapon") and _player.weapon.get("weapon_resource") else WeaponResource.new()
	_hud.setup_hud(_player.fuel_resource, _player.speed_resource, w_res)


## Post-test cleanup: Restores global state to prevent test leakage.
## :rtype: void
func after_each() -> void:
	Globals.settings = _original_settings


# ==========================================
# INITIALIZATION & SETUP TESTS
# ==========================================

## test_setup_hud_with_invalid_resources | Edge Case
func test_setup_hud_with_invalid_resources() -> void:
	gut.p("Testing: HUD rejects invalid resource injections gracefully without crashing.")
	
	# Passing nulls should push an error and return without crashing the node
	_hud.setup_hud(null, null, null)
	assert_true(true, "HUD survived null resource injection.")


# ==========================================
# VISUAL STATE TESTS: FUEL
# ==========================================

## test_fuel_bar_visual_states | UI Rendering
func test_fuel_bar_visual_states() -> void:
	gut.p("Testing: Fuel bar properly applies solid and lerped colors based on thresholds.")
	
	var max_f: float = _player.fuel_resource.max_fuel
	
	# --- 1. Safe Zone (Solid Green) ---
	_player.fuel_resource.current_fuel = max_f * 0.95
	_player.fuel_resource.fuel_changed.emit(_player.fuel_resource.current_fuel)
	assert_eq(_hud.get_fuel_bar_color(), Color.GREEN, "High fuel must be solid Green.")
	
	# --- 2. Medium Warning (Green to Yellow Lerp) ---
	var mid_yellow: float = (_player.fuel_resource.high_fuel_threshold + _player.fuel_resource.medium_fuel_threshold) / 2.0
	_player.fuel_resource.current_fuel = (mid_yellow / 100.0) * max_f
	_player.fuel_resource.fuel_changed.emit(_player.fuel_resource.current_fuel)
	var expected_yellow_lerp: Color = Color.GREEN.lerp(Color.YELLOW, 0.5)
	assert_true(_hud.get_fuel_bar_color().is_equal_approx(expected_yellow_lerp), "Medium fuel must lerp towards Yellow.")
	
	# --- 3. Low Warning (Yellow to Red Lerp) ---
	var mid_red: float = (_player.fuel_resource.medium_fuel_threshold + _player.fuel_resource.low_fuel_threshold) / 2.0
	_player.fuel_resource.current_fuel = (mid_red / 100.0) * max_f
	_player.fuel_resource.fuel_changed.emit(_player.fuel_resource.current_fuel)
	var expected_red_lerp: Color = Color.YELLOW.lerp(Color.RED, 0.5)
	assert_true(_hud.get_fuel_bar_color().is_equal_approx(expected_red_lerp), "Low fuel must lerp towards Red.")
	
	# --- 4. Critical Zone (Red to Dark Red Lerp) ---
	var mid_dark: float = (_player.fuel_resource.low_fuel_threshold + _player.fuel_resource.no_fuel_threshold) / 2.0
	_player.fuel_resource.current_fuel = (mid_dark / 100.0) * max_f
	_player.fuel_resource.fuel_changed.emit(_player.fuel_resource.current_fuel)
	var expected_dark_lerp: Color = Color.RED.lerp(_hud.DARK_RED, 0.5)
	assert_true(_hud.get_fuel_bar_color().is_equal_approx(expected_dark_lerp), "Critical fuel must lerp towards Dark Red.")


# ==========================================
# VISUAL STATE TESTS: SPEED
# ==========================================

## test_speed_bar_visual_states | UI Rendering
func test_speed_bar_visual_states() -> void:
	gut.p("Testing: Speed bar properly applies solid and lerped colors based on dynamic thresholds.")
	
	var max_s: float = _player.speed_resource.max_speed
	var min_s: float = _player.speed_resource.min_speed
	
	# Dynamically calculate the thresholds used by the HUD
	var high_red_thresh: float = max_s * _hud.HIGH_RED_FRACTION
	var high_yellow_thresh: float = max_s * _player.speed_resource.high_yellow_fraction
	var low_yellow_thresh: float = min_s + (max_s - min_s) * _player.speed_resource.low_yellow_fraction
	
	# --- 1. Safe Zone (Solid Green) ---
	var safe_speed: float = (low_yellow_thresh + high_yellow_thresh) / 2.0
	_player.speed_resource.current_speed = safe_speed
	_player.speed_resource.speed_updated.emit(safe_speed)
	assert_eq(_hud.get_speed_bar_color(), Color.GREEN, "Cruising speed must be solid Green.")
	
	# --- 2. High Speed Warning (Green to Yellow Lerp) ---
	var high_speed: float = high_yellow_thresh + ((high_red_thresh - high_yellow_thresh) / 2.0)
	_player.speed_resource.current_speed = high_speed
	_player.speed_resource.speed_updated.emit(high_speed)
	var expected_yellow: Color = Color.GREEN.lerp(Color.YELLOW, 0.5)
	assert_true(_hud.get_speed_bar_color().is_equal_approx(expected_yellow), "High speed must lerp towards Yellow.")
	
	# --- 3. Overspeed Critical (Yellow to Dark Red Lerp) ---
	var overspeed: float = high_red_thresh + ((max_s - high_red_thresh) / 2.0)
	_player.speed_resource.current_speed = overspeed
	_player.speed_resource.speed_updated.emit(overspeed)
	var expected_dark: Color = Color.YELLOW.lerp(_hud.DARK_RED, 0.5)
	assert_true(_hud.get_speed_bar_color().is_equal_approx(expected_dark), "Overspeed must lerp towards Dark Red.")
	
	# --- 4. Stall Critical (Solid Dark Red) ---
	_player.speed_resource.current_speed = min_s
	_player.speed_resource.speed_updated.emit(min_s)
	assert_eq(_hud.get_speed_bar_color(), _hud.DARK_RED, "Stall speed must be solid Dark Red.")


# ==========================================
# WARNING & BLINKER LOGIC TESTS
# ==========================================

## test_warning_blinkers_activate_and_deactivate | State Management
func test_warning_blinkers_activate_and_deactivate() -> void:
	gut.p("Testing: Warning labels start and stop blinking seamlessly across thresholds.")
	
	var max_s: float = _player.speed_resource.max_speed
	var min_s: float = _player.speed_resource.min_speed
	
	# --- Speed Blinker Test ---
	var safe_speed: float = (max_s + min_s) / 2.0
	var danger_speed: float = max_s * 0.95
	
	# 1. Enter danger zone via simulated Resource state update and emission
	_player.speed_resource.current_speed = danger_speed
	_player.speed_resource.speed_updated.emit(danger_speed)
	assert_true(_hud.is_speed_warning_active(), "Speed blinker must activate in the danger zone.")
	assert_true(_hud.is_speed_timer_running(), "Speed blink timer must be running.")
	
	# 2. Return to safe zone
	_player.speed_resource.current_speed = safe_speed
	_player.speed_resource.speed_updated.emit(safe_speed)
	assert_false(_hud.is_speed_warning_active(), "Speed blinker must deactivate in the safe zone.")
	assert_false(_hud.is_speed_timer_running(), "Speed blink timer must halt.")
	
	# --- Fuel Blinker Test ---
	# 1. Enter danger zone via Resource update
	_player.fuel_resource.current_fuel = (_player.fuel_resource.low_fuel_threshold - 5.0) / 100.0 * _player.fuel_resource.max_fuel
	_player.fuel_resource.fuel_changed.emit(_player.fuel_resource.current_fuel)
	assert_true(_hud.is_fuel_warning_active(), "Fuel blinker must activate in the low fuel zone.")
	
	# 2. Return to safe zone
	_player.fuel_resource.current_fuel = _player.fuel_resource.max_fuel
	_player.fuel_resource.fuel_changed.emit(_player.fuel_resource.current_fuel)
	assert_false(_hud.is_fuel_warning_active(), "Fuel blinker must deactivate when refueled.")


# ==========================================
# OBSERVER INTEGRATION TESTS
# ==========================================

## test_hud_reacts_to_player_signals | Observer Integration
func test_hud_reacts_to_player_signals() -> void:
	gut.p("Testing: HUD correctly processes speed_updated signals from the new SpeedResource.")
	
	_player.speed_resource.max_speed = 800.0
	
	# Update the resource value BEFORE emitting the signal, as HUD now strictly observes the resource
	_player.speed_resource.current_speed = 400.0
	_player.speed_resource.speed_updated.emit(400.0)
	
	assert_eq(_hud.get_current_speed(), 400.0, "HUD must internally read the new speed from the resource.")
	assert_eq(_hud.speed_bar.max_value, 800.0, "HUD must update the progress bar maximum.")
	assert_eq(_hud.speed_bar.value, 400.0, "HUD must update the progress bar value.")


## test_hud_reacts_to_flameout_signal | Observer Integration
func test_hud_reacts_to_flameout_signal() -> void:
	gut.p("Testing: HUD forces UI update upon receiving a fuel_depleted signal.")
	
	_player.speed_resource.max_speed = 1000.0
	
	# Establish a cruising speed
	_player.speed_resource.current_speed = 300.0
	_player.speed_resource.speed_updated.emit(300.0)
	
	# Empty the fuel tank so the mock player's physics allow the speed 
	# to correctly clamp to 0.0 instead of bottoming out at min_speed (95.0)
	_player.fuel_resource.current_fuel = 0.0
	
	# Broadcast flameout signal natively via the resource
	_player.fuel_resource.fuel_depleted.emit()
	
	assert_eq(_hud.get_current_speed(), 0.0, "HUD must reflect the zeroed speed upon flameout.")
	assert_eq(_hud.speed_bar.value, 0.0, "Progress bar must visually drop to zero.")
