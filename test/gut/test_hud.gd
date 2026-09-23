## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_hud.gd
##
## Comprehensive GUT unit tests for the Heads-Up Display manager (hud.gd).
## Validates UI state synchronization, color lerping thresholds, warning label blinking,
## and rigorous resource dependency injection isolation (idempotency & hot-swapping).

extends "res://addons/gut/test.gd"

var _hud: Panel
var _fuel: FuelResource
var _speed: SpeedResource
var _weapon: WeaponResource

var _original_settings: GameSettingsResource


## Pre-test setup: Builds a purely programmatic mock UI tree to guarantee absolute 
## isolation from Player node hierarchies and physical scene trees.
## :rtype: void
func before_each() -> void:
	_original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()
	Globals.settings.current_log_level = Globals.LogLevel.NONE
	
	_hud = _build_isolated_hud_tree()
	add_child_autoqfree(_hud)
	
	# Force ready to initialize the HUD's internal @onready variables
	_hud._ready()
	
	# Instantiate authoritative test resources directly
	_fuel = FuelResource.new()
	_speed = SpeedResource.new()
	_weapon = WeaponResource.new()
	
	_hud.setup_hud(_fuel, _speed, _weapon)


## Post-test cleanup: Restores global state to prevent test leakage.
## :rtype: void
func after_each() -> void:
	Globals.settings = _original_settings


## Helper: Constructs the required Panel/VBox/HBox hierarchy purely in code.
## Severely decouples the HUD tests from the main_scene.tscn or player mocks.
func _build_isolated_hud_tree() -> Panel:
	var root: Panel = Panel.new()
	root.set_script(preload("res://scripts/ui/hud.gd"))
	
	var stats: VBoxContainer = VBoxContainer.new()
	stats.name = "Stats"
	root.add_child(stats)
	
	# Fuel Hierarchy
	var fuel: HBoxContainer = HBoxContainer.new()
	fuel.name = "Fuel"
	stats.add_child(fuel)
	var f_label: Label = Label.new()
	f_label.name = "FuelLabel"
	fuel.add_child(f_label)
	var f_timer: Timer = Timer.new()
	f_timer.name = "BlinkTimer"
	f_label.add_child(f_timer)
	var f_bar: ProgressBar = ProgressBar.new()
	f_bar.name = "FuelBar"
	fuel.add_child(f_bar)
	
	# Speed Hierarchy
	var speed: HBoxContainer = HBoxContainer.new()
	speed.name = "Speed"
	stats.add_child(speed)
	var s_label: Label = Label.new()
	s_label.name = "SpeedLabel"
	speed.add_child(s_label)
	var s_timer: Timer = Timer.new()
	s_timer.name = "BlinkTimer"
	s_label.add_child(s_timer)
	var s_bar: ProgressBar = ProgressBar.new()
	s_bar.name = "SpeedBar"
	speed.add_child(s_bar)
	
	# Weapon Hierarchy
	var weapon: HBoxContainer = HBoxContainer.new()
	weapon.name = "Weapon"
	stats.add_child(weapon)
	var w_label: Label = Label.new()
	w_label.name = "WeaponLabel"
	weapon.add_child(w_label)
	
	# Ammo Hierarchy
	var ammo: HBoxContainer = HBoxContainer.new()
	ammo.name = "Ammo"
	stats.add_child(ammo)
	var a_bar: ProgressBar = ProgressBar.new()
	a_bar.name = "AmmoBar"
	ammo.add_child(a_bar)
	
	return root


# ==========================================
# INITIALIZATION & SETUP TESTS
# ==========================================

## test_setup_hud_with_invalid_resources | Edge Case
func test_setup_hud_with_invalid_resources() -> void:
	gut.p("Testing: HUD rejects invalid resource injections gracefully without crashing.")
	
	# Passing nulls should push an error log and return without crashing the node
	_hud.setup_hud(null, null, null)
	assert_true(true, "HUD survived null resource injection.")


# ==========================================
# ISOLATION & IDEMPOTENCY TESTS (PHASE 2)
# ==========================================

## test_resource_replacement_isolation | Dependency Injection
func test_resource_replacement_isolation() -> void:
	gut.p("Testing: All replaced resources become inert, while new resources correctly drive telemetry (Bi-directional).")
	
	var new_speed: SpeedResource = SpeedResource.new()
	new_speed.max_speed = 1000.0
	new_speed.current_speed = 100.0
	
	var new_fuel: FuelResource = FuelResource.new()
	new_fuel.max_fuel = 500.0
	new_fuel.current_fuel = 50.0
	
	var new_weapon: WeaponResource = WeaponResource.new()
	new_weapon.max_ammo = 500
	new_weapon.current_ammo = 100
	
	# =========================================
	# FORWARD SWAP: Original -> New
	# =========================================
	_hud.setup_hud(new_fuel, new_speed, new_weapon)
	
	# 1. Mutate the old, now inert resources
	_speed.current_speed = 500.0
	_fuel.current_fuel = 300.0
	_weapon.current_ammo = 999
	
	# Verify HUD ignored the old resources completely
	assert_eq(_hud.get_current_speed(), 100.0, "HUD must ignore speed mutations from replaced inert resources.")
	assert_eq(_hud.fuel_bar.value, 50.0, "HUD must ignore fuel mutations from replaced inert resources.")
	assert_eq(_hud.ammo_bar.value, 100.0, "HUD must ignore ammo mutations from replaced inert resources.")
	
	# 2. Mutate the newly injected active resources
	new_speed.current_speed = 800.0
	new_fuel.current_fuel = 450.0
	new_weapon.current_ammo = 200
	
	# Verify HUD followed the new resources
	assert_eq(_hud.get_current_speed(), 800.0, "HUD must react immediately to new speed resource.")
	assert_eq(_hud.fuel_bar.value, 450.0, "HUD must react immediately to new fuel resource.")
	assert_eq(_hud.ammo_bar.value, 200.0, "HUD must react immediately to new weapon resource.")

	# =========================================
	# REVERSE SWAP: New -> Original
	# =========================================
	_hud.setup_hud(_fuel, _speed, _weapon)
	
	# 3. Mutate the temporary 'new' resources, which should now be inert
	new_speed.current_speed = 200.0
	new_fuel.current_fuel = 150.0
	new_weapon.current_ammo = 50
	
	# Verify HUD ignored the now-inert 'new' resources
	assert_eq(_hud.get_current_speed(), 500.0, "HUD must ignore mutations from second set after swapping back.")
	assert_eq(_hud.fuel_bar.value, 300.0, "HUD must ignore mutations from second set after swapping back.")
	assert_eq(_hud.ammo_bar.value, 999.0, "HUD must ignore mutations from second set after swapping back.")
	
	# 4. Mutate the original resources to prove they resumed control
	_speed.current_speed = 600.0
	_fuel.current_fuel = 200.0
	_weapon.current_ammo = 500
	
	assert_eq(_hud.get_current_speed(), 600.0, "HUD must resume tracking original speed resource.")
	assert_eq(_hud.fuel_bar.value, 200.0, "HUD must resume tracking original fuel resource.")
	assert_eq(_hud.ammo_bar.value, 500.0, "HUD must resume tracking original weapon resource.")


## test_setup_hud_idempotency | Dependency Injection
func test_setup_hud_idempotency() -> void:
	gut.p("Testing: Repeated injection of identical instances does not duplicate signal connections for any resource.")
	
	# Helper lambda to count active connections directed to the HUD
	var count_conns = func(sig: Signal) -> int:
		var count: int = 0
		for conn in sig.get_connections():
			if conn["callable"].get_object() == _hud:
				count += 1
		return count
		
	# Count baseline connections explicitly wired to our HUD instance
	assert_eq(count_conns.call(_speed.speed_updated), 1, "Speed should have exactly 1 connection to speed_updated initially.")
	assert_eq(count_conns.call(_fuel.fuel_changed), 1, "Fuel should have exactly 1 connection to fuel_changed initially.")
	assert_eq(count_conns.call(_weapon.ammo_updated), 1, "Weapon should have exactly 1 connection to ammo_updated initially.")
	
	# Spam the injection method to simulate heavy level reloading or scene churn
	_hud.setup_hud(_fuel, _speed, _weapon)
	_hud.setup_hud(_fuel, _speed, _weapon)
	_hud.setup_hud(_fuel, _speed, _weapon)
	
	# Assert counts remain strictly at 1 across all data layers
	assert_eq(count_conns.call(_speed.speed_updated), 1, "Repeated setup must not duplicate Speed connections.")
	assert_eq(count_conns.call(_fuel.fuel_changed), 1, "Repeated setup must not duplicate Fuel connections.")
	assert_eq(count_conns.call(_weapon.ammo_updated), 1, "Repeated setup must not duplicate Weapon connections.")


# ==========================================
# VISUAL STATE TESTS: FUEL
# ==========================================

## test_fuel_bar_visual_states | UI Rendering
func test_fuel_bar_visual_states() -> void:
	gut.p("Testing: Fuel bar applies solid and lerped colors by driving public resource properties.")
	
	var max_f: float = _fuel.max_fuel
	
	# --- 1. Safe Zone (Solid Green) ---
	_fuel.current_fuel = max_f * 0.95
	assert_eq(_hud.get_fuel_bar_color(), Color.GREEN, "High fuel must be solid Green.")
	
	# --- 2. Medium Warning (Green to Yellow Lerp) ---
	var mid_yellow: float = (_fuel.high_fuel_threshold + _fuel.medium_fuel_threshold) / 2.0
	_fuel.current_fuel = (mid_yellow / 100.0) * max_f
	var expected_yellow_lerp: Color = Color.GREEN.lerp(Color.YELLOW, 0.5)
	assert_true(_hud.get_fuel_bar_color().is_equal_approx(expected_yellow_lerp), "Medium fuel must lerp towards Yellow.")
	
	# --- 3. Low Warning (Yellow to Red Lerp) ---
	var mid_red: float = (_fuel.medium_fuel_threshold + _fuel.low_fuel_threshold) / 2.0
	_fuel.current_fuel = (mid_red / 100.0) * max_f
	var expected_red_lerp: Color = Color.YELLOW.lerp(Color.RED, 0.5)
	assert_true(_hud.get_fuel_bar_color().is_equal_approx(expected_red_lerp), "Low fuel must lerp towards Red.")
	
	# --- 4. Critical Zone (Red to Dark Red Lerp) ---
	var mid_dark: float = (_fuel.low_fuel_threshold + _fuel.no_fuel_threshold) / 2.0
	_fuel.current_fuel = (mid_dark / 100.0) * max_f
	var expected_dark_lerp: Color = Color.RED.lerp(_hud.DARK_RED, 0.5)
	assert_true(_hud.get_fuel_bar_color().is_equal_approx(expected_dark_lerp), "Critical fuel must lerp towards Dark Red.")


# ==========================================
# VISUAL STATE TESTS: SPEED
# ==========================================

## test_speed_bar_visual_states | UI Rendering
func test_speed_bar_visual_states() -> void:
	gut.p("Testing: Speed bar applies solid and lerped colors by driving public resource properties.")
	
	var max_s: float = _speed.max_speed
	var min_s: float = _speed.min_speed
	
	var high_red_thresh: float = max_s * _hud.HIGH_RED_FRACTION
	var high_yellow_thresh: float = max_s * _speed.high_yellow_fraction
	var low_yellow_thresh: float = min_s + (max_s - min_s) * _speed.low_yellow_fraction
	
	# --- 1. Safe Zone (Solid Green) ---
	var safe_speed: float = (low_yellow_thresh + high_yellow_thresh) / 2.0
	_speed.current_speed = safe_speed
	assert_eq(_hud.get_speed_bar_color(), Color.GREEN, "Cruising speed must be solid Green.")
	
	# --- 2. High Speed Warning (Green to Yellow Lerp) ---
	var high_speed: float = high_yellow_thresh + ((high_red_thresh - high_yellow_thresh) / 2.0)
	_speed.current_speed = high_speed
	var expected_yellow: Color = Color.GREEN.lerp(Color.YELLOW, 0.5)
	assert_true(_hud.get_speed_bar_color().is_equal_approx(expected_yellow), "High speed must lerp towards Yellow.")
	
	# --- 3. Overspeed Critical (Yellow to Dark Red Lerp) ---
	var overspeed: float = high_red_thresh + ((max_s - high_red_thresh) / 2.0)
	_speed.current_speed = overspeed
	var expected_dark: Color = Color.YELLOW.lerp(_hud.DARK_RED, 0.5)
	assert_true(_hud.get_speed_bar_color().is_equal_approx(expected_dark), "Overspeed must lerp towards Dark Red.")


# ==========================================
# WARNING & BLINKER LOGIC TESTS
# ==========================================

## test_warning_blinkers_activate_and_deactivate | State Management
func test_warning_blinkers_activate_and_deactivate() -> void:
	gut.p("Testing: Warning labels start and stop blinking seamlessly across thresholds via resource setters.")
	
	var max_s: float = _speed.max_speed
	var min_s: float = _speed.min_speed
	
	# --- Speed Blinker Test ---
	var safe_speed: float = (max_s + min_s) / 2.0
	var danger_speed: float = max_s * 0.95
	
	# 1. Enter danger zone via property mutation
	_speed.current_speed = danger_speed
	assert_true(_hud.is_speed_warning_active(), "Speed blinker must activate in the danger zone.")
	assert_true(_hud.is_speed_timer_running(), "Speed blink timer must be running.")
	
	# 2. Return to safe zone
	_speed.current_speed = safe_speed
	assert_false(_hud.is_speed_warning_active(), "Speed blinker must deactivate in the safe zone.")
	assert_false(_hud.is_speed_timer_running(), "Speed blink timer must halt.")
	
	# --- Fuel Blinker Test ---
	# 1. Enter danger zone via property mutation
	_fuel.current_fuel = (_fuel.low_fuel_threshold - 5.0) / 100.0 * _fuel.max_fuel
	assert_true(_hud.is_fuel_warning_active(), "Fuel blinker must activate in the low fuel zone.")
	
	# 2. Return to safe zone
	_fuel.current_fuel = _fuel.max_fuel
	assert_false(_hud.is_fuel_warning_active(), "Fuel blinker must deactivate when refueled.")


# ==========================================
# END-TO-END OBSERVER INTEGRATION TESTS
# ==========================================

## test_hud_reacts_to_resource_mutations | Observer Integration
func test_hud_reacts_to_resource_mutations() -> void:
	gut.p("Testing: HUD correctly processes speed_updated signals end-to-end via resource mutation.")
	
	_speed.max_speed = 800.0
	_speed.current_speed = 400.0
	
	assert_eq(_hud.get_current_speed(), 400.0, "HUD must strictly read the speed from the injected resource.")
	assert_eq(_hud.speed_bar.max_value, 800.0, "HUD must update the progress bar maximum.")
	assert_eq(_hud.speed_bar.value, 400.0, "HUD must update the progress bar value.")


## test_hud_reacts_to_flameout_signal | Observer Integration
func test_hud_reacts_to_flameout_signal() -> void:
	gut.p("Testing: HUD forces UI update upon fuel depletion.")
	
	_speed.max_speed = 1000.0
	_speed.current_speed = 300.0
	
	# Simulate the physics reaction to a flameout by dropping the min bound and zeroing speed
	_speed.min_speed = 0.0
	_speed.current_speed = 0.0
	
	# Empty the fuel tank to trigger the fuel_depleted observer cascade
	_fuel.current_fuel = 0.0
	_fuel.fuel_depleted.emit()
	
	assert_eq(_hud.get_current_speed(), 0.0, "HUD must reflect the zeroed speed upon flameout.")
	assert_eq(_hud.speed_bar.value, 0.0, "Progress bar must visually drop to zero.")


## test_hud_reacts_to_weapon_swapped | Observer Integration
func test_hud_reacts_to_weapon_swapped() -> void:
	gut.p("Testing: HUD formats and updates the weapon label strictly observing weapon_swapped.")
	
	# Mutate the resource to trigger the weapon_swapped signal
	_weapon.available_weapons = ["Plasma Cannon"]
	
	# The HUD format rules dictate uppercase, spaces replaced by equals, and curly brackets
	var expected_text: String = "{PLASMA=CANNON}"
	assert_eq(_hud.weapon_label.text, expected_text, "HUD must format the text correctly to '{PLASMA=CANNON}'.")


## test_hud_reacts_to_ammo_updated | Observer Integration
func test_hud_reacts_to_ammo_updated() -> void:
	gut.p("Testing: HUD correctly updates the ammo progress bar observing ammo_updated.")
	
	# Mutate resource to trigger ammo_updated signals
	_weapon.max_ammo = 500
	_weapon.current_ammo = 250
	
	assert_eq(_hud.ammo_bar.max_value, 500.0, "HUD must dynamically sync the ammo bar maximum value.")
	assert_eq(_hud.ammo_bar.value, 250.0, "HUD must dynamically sync the ammo bar current value.")
