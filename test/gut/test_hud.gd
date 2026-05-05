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
	
	# Wire the HUD to the Player as main_scene.gd would
	_hud.setup_hud(_player)

## Post-test cleanup: Restores global state to prevent test leakage.
## :rtype: void
func after_each() -> void:
	Globals.settings = _original_settings


# ==========================================
# INITIALIZATION & SETUP TESTS
# ==========================================

## test_initialization_with_missing_globals | Edge Case
func test_initialization_with_missing_globals() -> void:
	gut.p("Testing: HUD creates a fallback GameSettingsResource if Globals is null.")
	
	# Force a missing resource state
	Globals.settings = null
	
	# Manually trigger _ready to force the HUD to re-evaluate its state
	_hud._ready()
	
	assert_not_null(_hud.get_settings(), "HUD must instantiate a fallback GameSettingsResource.")
	assert_not_null(Globals.settings, "HUD must assign the fallback resource back to Globals.")


# ==========================================
# VISUAL STATE TESTS: FUEL
# ==========================================

## test_fuel_bar_visual_states | UI Rendering
func test_fuel_bar_visual_states() -> void:
	gut.p("Testing: Fuel bar properly applies solid and lerped colors based on thresholds.")
	
	var max_f: float = Globals.settings.max_fuel
	
	# --- 1. Safe Zone (Solid Green) ---
	Globals.settings.current_fuel = max_f * 0.95
	assert_eq(_hud.get_fuel_bar_color(), Color.GREEN, "High fuel must be solid Green.")
	
	# --- 2. Medium Warning (Green to Yellow Lerp) ---
	var mid_yellow: float = (Globals.settings.high_fuel_threshold + Globals.settings.medium_fuel_threshold) / 2.0
	Globals.settings.current_fuel = (mid_yellow / 100.0) * max_f
	var expected_yellow_lerp: Color = Color.GREEN.lerp(Color.YELLOW, 0.5)
	assert_true(_hud.get_fuel_bar_color().is_equal_approx(expected_yellow_lerp), "Medium fuel must lerp towards Yellow.")
	
	# --- 3. Low Warning (Yellow to Red Lerp) ---
	var mid_red: float = (Globals.settings.medium_fuel_threshold + Globals.settings.low_fuel_threshold) / 2.0
	Globals.settings.current_fuel = (mid_red / 100.0) * max_f
	var expected_red_lerp: Color = Color.YELLOW.lerp(Color.RED, 0.5)
	assert_true(_hud.get_fuel_bar_color().is_equal_approx(expected_red_lerp), "Low fuel must lerp towards Red.")
	
	# --- 4. Critical Zone (Red to Dark Red Lerp) ---
	var mid_dark: float = (Globals.settings.low_fuel_threshold + Globals.settings.no_fuel_threshold) / 2.0
	Globals.settings.current_fuel = (mid_dark / 100.0) * max_f
	var expected_dark_lerp: Color = Color.RED.lerp(_hud.DARK_RED, 0.5)
	assert_true(_hud.get_fuel_bar_color().is_equal_approx(expected_dark_lerp), "Critical fuel must lerp towards Dark Red.")


# ==========================================
# VISUAL STATE TESTS: SPEED
# ==========================================

## test_speed_bar_visual_states | UI Rendering
func test_speed_bar_visual_states() -> void:
	gut.p("Testing: Speed bar properly applies solid and lerped colors based on dynamic thresholds.")
	
	var max_s: float = Globals.settings.max_speed
	var min_s: float = Globals.settings.min_speed
	
	# Dynamically calculate the thresholds used by the HUD
	var high_red_thresh: float = max_s * _hud.HIGH_RED_FRACTION
	var high_yellow_thresh: float = max_s * Globals.settings.high_yellow_fraction
	var low_yellow_thresh: float = min_s + (max_s - min_s) * Globals.settings.low_yellow_fraction
	
	# --- 1. Safe Zone (Solid Green) ---
	var safe_speed: float = (low_yellow_thresh + high_yellow_thresh) / 2.0
	_player.speed_changed.emit(safe_speed, max_s)
	assert_eq(_hud.get_speed_bar_color(), Color.GREEN, "Cruising speed must be solid Green.")
	
	# --- 2. High Speed Warning (Green to Yellow Lerp) ---
	var high_speed: float = high_yellow_thresh + ((high_red_thresh - high_yellow_thresh) / 2.0)
	_player.speed_changed.emit(high_speed, max_s)
	var expected_yellow: Color = Color.GREEN.lerp(Color.YELLOW, 0.5)
	assert_true(_hud.get_speed_bar_color().is_equal_approx(expected_yellow), "High speed must lerp towards Yellow.")
	
	# --- 3. Overspeed Critical (Yellow to Dark Red Lerp) ---
	var overspeed: float = high_red_thresh + ((max_s - high_red_thresh) / 2.0)
	_player.speed_changed.emit(overspeed, max_s)
	var expected_dark: Color = Color.YELLOW.lerp(_hud.DARK_RED, 0.5)
	assert_true(_hud.get_speed_bar_color().is_equal_approx(expected_dark), "Overspeed must lerp towards Dark Red.")
	
	# --- 4. Stall Critical (Solid Dark Red) ---
	_player.speed_changed.emit(min_s, max_s)
	assert_eq(_hud.get_speed_bar_color(), _hud.DARK_RED, "Stall speed must be solid Dark Red.")


# ==========================================
# WARNING & BLINKER LOGIC TESTS
# ==========================================

## test_warning_blinkers_activate_and_deactivate | State Management
func test_warning_blinkers_activate_and_deactivate() -> void:
	gut.p("Testing: Warning labels start and stop blinking seamlessly across thresholds.")
	
	# --- Speed Blinker Test ---
	var safe_speed: float = (Globals.settings.max_speed + Globals.settings.min_speed) / 2.0
	var danger_speed: float = Globals.settings.max_speed * 0.95
	
	# 1. Enter danger zone via simulated Player emission
	_player.speed_changed.emit(danger_speed, Globals.settings.max_speed)
	assert_true(_hud.is_speed_warning_active(), "Speed blinker must activate in the danger zone.")
	assert_true(_hud.is_speed_timer_running(), "Speed blink timer must be running.")
	
	# 2. Return to safe zone
	_player.speed_changed.emit(safe_speed, Globals.settings.max_speed)
	assert_false(_hud.is_speed_warning_active(), "Speed blinker must deactivate in the safe zone.")
	assert_false(_hud.is_speed_timer_running(), "Speed blink timer must halt.")
	
	# --- Fuel Blinker Test ---
	# 1. Enter danger zone via Resource update
	Globals.settings.current_fuel = (Globals.settings.low_fuel_threshold - 5.0) / 100.0 * Globals.settings.max_fuel
	assert_true(_hud.is_fuel_warning_active(), "Fuel blinker must activate in the low fuel zone.")
	
	# 2. Return to safe zone
	Globals.settings.current_fuel = Globals.settings.max_fuel
	assert_false(_hud.is_fuel_warning_active(), "Fuel blinker must deactivate when refueled.")


# ==========================================
# OBSERVER INTEGRATION TESTS
# ==========================================

## test_hud_reacts_to_player_signals | Observer Integration
func test_hud_reacts_to_player_signals() -> void:
	gut.p("Testing: HUD correctly processes speed_changed signals from the Player.")
	
	# Simulate the Player broadcasting a new speed natively
	_player.speed_changed.emit(400.0, 800.0)
	
	assert_eq(_hud.get_current_speed(), 400.0, "HUD must internally cache the new speed.")
	assert_eq(_hud.speed_bar.max_value, 800.0, "HUD must update the progress bar maximum.")
	assert_eq(_hud.speed_bar.value, 400.0, "HUD must update the progress bar value.")

## test_hud_reacts_to_flameout_signal | Observer Integration
func test_hud_reacts_to_flameout_signal() -> void:
	gut.p("Testing: HUD forces speed to 0.0 upon receiving a fuel_depleted signal.")
	
	# Establish a cruising speed
	_player.speed_changed.emit(300.0, Globals.settings.max_speed)
	
	# Broadcast flameout globally
	Globals.settings.current_fuel = 0.0
	
	assert_eq(_hud.get_current_speed(), 0.0, "HUD must recognize that a flameout instantly zeroes the speed.")
	assert_eq(_hud.speed_bar.value, 0.0, "Progress bar must visually drop to zero.")
