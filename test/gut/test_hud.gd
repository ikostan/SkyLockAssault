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
	
	# Prevent default clamping: expand the max limits of the original resources
	# so our test values are not truncated by the default 100.0 boundaries.
	_speed.max_speed = 1000.0
	_fuel.max_fuel = 1000.0
	_weapon.max_ammo = 1000
	
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


## test_fuel_bar_follows_percentages_with_larger_tank | UI Rendering (#1147)
## Thresholds are percentages of max_fuel, so doubling the tank doubles the fuel amount
## at which each color band and the low-fuel warning start.
func test_fuel_bar_follows_percentages_with_larger_tank() -> void:
	gut.p("Testing: With max_fuel = 200, colors and the warning follow percentages.")
	_fuel.max_fuel = 200.0
	
	# 95% of 200 is 190: above high (90%), so solid green
	_fuel.current_fuel = 190.0
	assert_eq(_hud.get_fuel_bar_color(), Color.GREEN, "95% must be solid Green.")
	assert_false(_hud.is_fuel_warning_active(), "95% must not warn.")
	
	# 70% is halfway between high (90%) and medium (50%)
	_fuel.current_fuel = 140.0
	var expected_yellow: Color = Color.GREEN.lerp(Color.YELLOW, 0.5)
	assert_true(_hud.get_fuel_bar_color().is_equal_approx(expected_yellow), "70% must be halfway to Yellow.")
	
	# 40% is halfway between medium (50%) and low (30%)
	_fuel.current_fuel = 80.0
	var expected_red: Color = Color.YELLOW.lerp(Color.RED, 0.5)
	assert_true(_hud.get_fuel_bar_color().is_equal_approx(expected_red), "40% must be halfway to Red.")
	assert_false(_hud.is_fuel_warning_active(), "40% is above low (30%), so no warning yet.")
	
	# 30% of 200 is 60: at low, the warning starts. As a raw amount, 60 would be "60%".
	_fuel.current_fuel = 60.0
	assert_true(_hud.is_fuel_warning_active(), "30% must start the low-fuel warning.")
	
	# 22.5% is halfway between low (30%) and no_fuel (15%)
	_fuel.current_fuel = 45.0
	var expected_dark: Color = Color.RED.lerp(_hud.DARK_RED, 0.5)
	assert_true(_hud.get_fuel_bar_color().is_equal_approx(expected_dark), "22.5% must be halfway to Dark Red.")
	
	# 10% is below no_fuel (15%)
	_fuel.current_fuel = 20.0
	assert_eq(_hud.get_fuel_bar_color(), _hud.DARK_RED, "10% must be solid Dark Red.")


## test_fuel_bar_uses_custom_thresholds | UI Rendering (#1147)
func test_fuel_bar_uses_custom_thresholds() -> void:
	gut.p("Testing: Custom thresholds (20, 15, 10, 5) produce the expected color bands.")
	assert_true(_fuel.set_thresholds(20.0, 15.0, 10.0, 5.0), "Precondition: the custom set must apply.")
	var max_f: float = _fuel.max_fuel
	
	# 50% is above high (20%): with the defaults this would be yellow
	_fuel.current_fuel = 0.50 * max_f
	assert_eq(_hud.get_fuel_bar_color(), Color.GREEN, "50% must be solid Green above a 20% high.")
	assert_false(_hud.is_fuel_warning_active(), "50% must not warn above a 10% low.")
	
	# 17.5% is halfway between high (20%) and medium (15%)
	_fuel.current_fuel = 0.175 * max_f
	var expected_yellow: Color = Color.GREEN.lerp(Color.YELLOW, 0.5)
	assert_true(_hud.get_fuel_bar_color().is_equal_approx(expected_yellow), "17.5% must be halfway to Yellow.")
	
	# 12.5% is halfway between medium (15%) and low (10%)
	_fuel.current_fuel = 0.125 * max_f
	var expected_red: Color = Color.YELLOW.lerp(Color.RED, 0.5)
	assert_true(_hud.get_fuel_bar_color().is_equal_approx(expected_red), "12.5% must be halfway to Red.")
	assert_false(_hud.is_fuel_warning_active(), "12.5% must not warn above a 10% low.")
	
	# 7.5% is halfway between low (10%) and no_fuel (5%), and below low, so it warns
	_fuel.current_fuel = 0.075 * max_f
	var expected_dark: Color = Color.RED.lerp(_hud.DARK_RED, 0.5)
	assert_true(_hud.get_fuel_bar_color().is_equal_approx(expected_dark), "7.5% must be halfway to Dark Red.")
	assert_true(_hud.is_fuel_warning_active(), "7.5% must warn below a 10% low.")
	
	# 2% is below no_fuel (5%)
	_fuel.current_fuel = 0.02 * max_f
	assert_eq(_hud.get_fuel_bar_color(), _hud.DARK_RED, "2% must be solid Dark Red.")


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


## test_hud_shows_initial_weapon_name | Deterministic Initial Sync (#1150)
## setup_hud() reads the starting name with get_weapon_name() instead of copying the list.
func test_hud_shows_initial_weapon_name() -> void:
	assert_eq(_hud.weapon_label.text, "{MACHINE=GUN}", "The default weapon must show after setup.")


## test_hud_initial_sync_uses_current_index | Deterministic Initial Sync (#1150)
## A resource that is already past index 0 shows the weapon at its current index.
func test_hud_initial_sync_uses_current_index() -> void:
	var armed: WeaponResource = WeaponResource.new()
	armed.available_weapons = ["Cannon", "Heavy Missile"]
	armed.current_index = 1

	_hud.setup_hud(_fuel, _speed, armed)

	assert_eq(_hud.weapon_label.text, "{HEAVY=MISSILE}", "Setup must show the weapon at current_index.")


## test_hud_shows_swapped_weapon_after_resetup | Deterministic Initial Sync (#1150)
## After a swap, setting up the HUD again still shows the active weapon.
func test_hud_shows_swapped_weapon_after_resetup() -> void:
	_weapon.available_weapons = ["Cannon", "Laser"]
	_weapon.current_index = 1
	assert_eq(_hud.weapon_label.text, "{LASER}", "The swap must update the label.")

	_hud.weapon_label.text = ""
	_hud.setup_hud(_fuel, _speed, _weapon)

	assert_eq(_hud.weapon_label.text, "{LASER}", "Setup after a swap must show the active weapon.")


## test_hud_reacts_to_ammo_updated | Observer Integration
func test_hud_reacts_to_ammo_updated() -> void:
	gut.p("Testing: HUD correctly updates the ammo progress bar observing ammo_updated.")
	
	# Mutate resource to trigger ammo_updated signals
	_weapon.max_ammo = 500
	_weapon.current_ammo = 250
	
	assert_eq(_hud.ammo_bar.max_value, 500.0, "HUD must dynamically sync the ammo bar maximum value.")
	assert_eq(_hud.ammo_bar.value, 250.0, "HUD must dynamically sync the ammo bar current value.")


## Empty inventories must clear a previously displayed weapon during initial sync.
func test_initial_sync_of_empty_inventory_replaces_stale_label() -> void:
	var empty_weapon := WeaponResource.new()
	empty_weapon.available_weapons = []
	_hud.weapon_label.text = "{STALE}"

	_hud.setup_hud(_fuel, _speed, empty_weapon)

	assert_eq(_hud.weapon_label.text, "{NONE}")
	empty_weapon.available_weapons = ["Heavy Laser"]
	assert_eq(_hud.weapon_label.text, "{HEAVY=LASER}")


## Setup must show the clamped selection even when the clamp happened before wiring.
func test_initial_sync_after_inventory_shrink_uses_clamped_weapon() -> void:
	var armed := WeaponResource.new()
	armed.available_weapons = ["Cannon", "Missile", "Laser"]
	armed.current_index = 2
	armed.available_weapons = ["Heavy Cannon"]

	_hud.setup_hud(_fuel, _speed, armed)

	assert_eq(_hud.weapon_label.text, "{HEAVY=CANNON}")
	_weapon.available_weapons = ["Obsolete Weapon"]
	assert_eq(
		_hud.weapon_label.text, "{HEAVY=CANNON}", "The replaced resource must no longer drive the HUD."
	)


# ==========================================
# SHARED LOW THRESHOLD (#1151)
# ==========================================

## The HUD's low-speed color and warning switch at SpeedResource.get_low_threshold(), the
## same point where speed_low fires.
func test_hud_low_speed_states_switch_at_shared_threshold(
	case: Array = use_parameters([
		[95.0, 713.0, 0.10],
		[100.0, 500.0, 0.25],
		[0.0, 1000.0, 0.5],
	])
) -> void:
	assert_true(_speed.set_speed_limits(case[0], case[1]))
	_speed.low_yellow_fraction = case[2]
	var threshold: float = _speed.get_low_threshold()
	watch_signals(_speed)

	_speed.current_speed = threshold + 0.5
	assert_false(_hud.is_speed_warning_active(), "no warning just above the threshold")
	assert_eq(_hud.get_speed_bar_color(), Color.GREEN, "green just above the threshold")
	assert_signal_emit_count(_speed, "speed_low", 0, "no speed_low just above")

	_speed.current_speed = threshold
	assert_true(_hud.is_speed_warning_active(), "warning at the threshold")
	assert_signal_emit_count(_speed, "speed_low", 1, "speed_low at the threshold")
	if threshold > _speed.min_speed:
		assert_eq(
			_hud.get_speed_bar_color(), Color.GREEN, "the lerp toward yellow starts at the threshold"
		)
		_speed.current_speed = (threshold + _speed.min_speed) / 2.0
		assert_ne(_hud.get_speed_bar_color(), Color.GREEN, "below the threshold turns yellow")


# ==========================================
# SIGNAL CLEANUP AND SPEED BLINK (#1169)
# ==========================================

## Counts every connection on [param res], across all of its signals, whose target is
## [param hud].
func _count_hud_connections(res: Resource, hud: Object) -> int:
	var count: int = 0
	for sig: Dictionary in res.get_signal_list():
		for connection: Dictionary in res.get_signal_connection_list(sig["name"]):
			var callable: Callable = connection.get("callable", Callable())
			if callable.get_object() == hud:
				count += 1
	return count


## Disconnects every HUD handler from one signal of [param res], whatever its method name.
func _disconnect_hud_from(sig: Signal) -> void:
	for connection: Dictionary in sig.get_connections():
		var callable: Callable = connection.get("callable", Callable())
		if callable.get_object() == _hud:
			sig.disconnect(callable)


## Confirm-first point 2: speed blinking starts at low and maximum speed through
## check_speed_warning() alone, with no handler on speed_low or speed_maxed.
func test_speed_blink_needs_no_speed_low_or_maxed_handler() -> void:
	gut.p("Testing: speed_updated alone drives the speed blink at low and maximum speed.")
	_disconnect_hud_from(_speed.speed_low)
	_disconnect_hud_from(_speed.speed_maxed)

	# Normal range: no blink
	_speed.current_speed = (_speed.min_speed + _speed.max_speed) / 2.0
	assert_false(_hud.is_speed_warning_active(), "No blink in the normal range.")

	# Low threshold: speed_low fires here, but the HUD no longer listens to it
	_speed.current_speed = _speed.get_low_threshold()
	assert_true(_hud.is_speed_warning_active(), "Blink starts at the low threshold.")
	assert_true(_hud.is_speed_timer_running(), "Blink timer runs at the low threshold.")

	# Back to normal
	_speed.current_speed = (_speed.min_speed + _speed.max_speed) / 2.0
	assert_false(_hud.is_speed_warning_active(), "Blink stops back in the normal range.")
	assert_false(_hud.is_speed_timer_running(), "Blink timer stops in the normal range.")

	# Maximum speed: speed_maxed fires here
	_speed.current_speed = _speed.max_speed
	assert_true(_hud.is_speed_warning_active(), "Blink starts at maximum speed.")
	assert_true(_hud.is_speed_timer_running(), "Blink timer runs at maximum speed.")

	_speed.current_speed = (_speed.min_speed + _speed.max_speed) / 2.0
	assert_false(_hud.is_speed_warning_active(), "Blink stops after leaving maximum speed.")


## Maximum speed always reaches the high warning band, because high_yellow_fraction is
## clamped to 1.0, so check_speed_warning() covers every case _on_speed_maxed() covered.
func test_max_speed_is_always_inside_high_warning_band() -> void:
	_speed.high_yellow_fraction = 5.0
	assert_eq(_speed.high_yellow_fraction, 1.0, "high_yellow_fraction is clamped to 1.0.")
	_disconnect_hud_from(_speed.speed_maxed)
	_speed.current_speed = _speed.max_speed
	assert_true(_hud.is_speed_warning_active(), "Blink starts at maximum speed with fraction 1.0.")


## The HUD no longer listens to speed_low or speed_maxed.
func test_hud_does_not_connect_speed_low_or_maxed() -> void:
	for sig: Signal in [_speed.speed_low, _speed.speed_maxed]:
		var hud_connections: int = 0
		for connection: Dictionary in sig.get_connections():
			if connection.callable.get_object() == _hud:
				hud_connections += 1
		assert_eq(hud_connections, 0, "HUD must not connect to %s." % sig.get_name())


## Initial wiring connects exactly the expected handlers on each resource.
func test_setup_hud_connection_counts() -> void:
	# speed_updated, thresholds_changed
	assert_eq(_count_hud_connections(_speed, _hud), 2, "Speed: two HUD connections.")
	# fuel_changed, fuel_depleted
	assert_eq(_count_hud_connections(_fuel, _hud), 2, "Fuel: two HUD connections.")
	# weapon_swapped, ammo_updated
	assert_eq(_count_hud_connections(_weapon, _hud), 2, "Weapon: two HUD connections.")


## setup_hud() with the same resources disconnects nothing.
func test_setup_hud_with_same_resources_disconnects_nothing() -> void:
	var before: Array[int] = [
		_count_hud_connections(_speed, _hud),
		_count_hud_connections(_fuel, _hud),
		_count_hud_connections(_weapon, _hud),
	]
	_hud.setup_hud(_fuel, _speed, _weapon)
	assert_eq(_count_hud_connections(_speed, _hud), before[0], "Speed connections unchanged.")
	assert_eq(_count_hud_connections(_fuel, _hud), before[1], "Fuel connections unchanged.")
	assert_eq(_count_hud_connections(_weapon, _hud), before[2], "Weapon connections unchanged.")


## setup_hud() with one new resource disconnects only the replaced one, for each resource.
func test_setup_hud_disconnects_only_replaced_resources(
	case: String = use_parameters(["speed", "fuel", "weapon"])
) -> void:
	var new_fuel: FuelResource = _fuel
	var new_speed: SpeedResource = _speed
	var new_weapon: WeaponResource = _weapon
	match case:
		"speed":
			new_speed = SpeedResource.new()
		"fuel":
			new_fuel = FuelResource.new()
		"weapon":
			new_weapon = WeaponResource.new()

	_hud.setup_hud(new_fuel, new_speed, new_weapon)

	var old_speed_count: int = _count_hud_connections(_speed, _hud)
	var old_fuel_count: int = _count_hud_connections(_fuel, _hud)
	var old_weapon_count: int = _count_hud_connections(_weapon, _hud)
	assert_eq(old_speed_count, 0 if case == "speed" else 2, "Old speed connections.")
	assert_eq(old_fuel_count, 0 if case == "fuel" else 2, "Old fuel connections.")
	assert_eq(old_weapon_count, 0 if case == "weapon" else 2, "Old weapon connections.")
	assert_eq(_count_hud_connections(new_speed, _hud), 2, "Active speed is connected.")
	assert_eq(_count_hud_connections(new_fuel, _hud), 2, "Active fuel is connected.")
	assert_eq(_count_hud_connections(new_weapon, _hud), 2, "Active weapon is connected.")


## Leaving the tree disconnects every HUD signal from every resource.
func test_exit_tree_disconnects_every_hud_signal() -> void:
	remove_child(_hud)
	assert_eq(_count_hud_connections(_speed, _hud), 0, "No speed connections after exit.")
	assert_eq(_count_hud_connections(_fuel, _hud), 0, "No fuel connections after exit.")
	assert_eq(_count_hud_connections(_weapon, _hud), 0, "No weapon connections after exit.")
	# Back in the tree so autoqfree frees it as usual
	add_child(_hud)


## Freeing a HUD leaves no connections on the resources, and the resources keep working.
func test_freeing_hud_leaves_no_connections() -> void:
	var hud: Panel = _build_isolated_hud_tree()
	# Autofree is only a fallback if the test aborts early; the explicit free() below is
	# what this test checks. Autofree skips nodes that are already freed.
	add_child_autofree(hud)
	hud._ready()
	hud.setup_hud(_fuel, _speed, _weapon)
	assert_eq(_count_hud_connections(_speed, hud), 2, "Second HUD is connected.")

	hud.free()

	var connections: int = 0
	for res: Resource in [_speed, _fuel, _weapon]:
		for sig: Dictionary in res.get_signal_list():
			for connection: Dictionary in res.get_signal_connection_list(sig["name"]):
				if not is_instance_valid(connection.callable.get_object()):
					connections += 1
	assert_eq(connections, 0, "No connections to a freed HUD remain.")
	# The first HUD still follows the resources
	_speed.current_speed = _speed.max_speed
	assert_true(_hud.is_speed_warning_active(), "The remaining HUD still reacts.")
