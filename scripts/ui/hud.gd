## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## hud.gd
##
## Heads-Up Display manager for SkyLockAssault.
## Handles all visual player statistics, including the Fuel and Speed progress bars,
## threshold calculations, and warning label animations.
## Operates entirely via Observer Patterns, completely decoupled from physics logic.
extends Panel

# --- Speed Constants ---
# Fraction constants that are strictly visual can remain local.
const HIGH_RED_FRACTION: float = 0.90
const DARK_RED: Color = Color(0.5, 0.0, 0.0)
const BLINK_INTERVAL: float = 0.5

# --- Internal State ---
var fuel_stat: StatManager
var speed_stat: StatManager

# var _settings: GameSettingsResource = null
# var _current_speed: float = 250.0

var _fuel_bar_style: StyleBoxFlat
var _speed_bar_style: StyleBoxFlat

# --- Data Resource Injection Tracking ---
var _fuel_resource: FuelResource = null
var _speed_resource: SpeedResource = null
var _weapon_resource: WeaponResource = null

# --- Node References ---
# Paths assume this script is attached directly to "PlayerStatsPanel"
@onready var fuel_bar: ProgressBar = $Stats/Fuel/FuelBar
@onready var fuel_label: Label = $Stats/Fuel/FuelLabel
@onready var fuel_blink_timer: Timer = $Stats/Fuel/FuelLabel/BlinkTimer

@onready var speed_bar: ProgressBar = $Stats/Speed/SpeedBar
@onready var speed_label: Label = $Stats/Speed/SpeedLabel
@onready var speed_blink_timer: Timer = $Stats/Speed/SpeedLabel/BlinkTimer

@onready var weapon_label: Label = $Stats/Weapon/WeaponLabel
@onready var ammo_bar: ProgressBar = $Stats/Ammo/AmmoBar


## Encapsulates UI warning state for a specific statistic (e.g., fuel or speed).
## Manages the label's color toggling and the associated blink timer safely,
## fully isolated from external helper methods.
class StatManager:
	## Indicates whether the warning label is currently in an active blinking state.
	var is_blinking: bool = false
	## The default text color of the label when no warning is active.
	var base_color: Color
	## The alert text color of the label during a warning state.
	var warning_color: Color
	## The UI Label node being manipulated.
	var label: Label
	## The Timer node dictating the blink frequency.
	var timer: Timer

	## Initializes the manager with required node references and color states.
	## @param _label: The target Label node to manipulate.
	## @param _timer: The Timer node controlling the blink cycle.
	## @param _base: The default Color of the label text.
	## @param _warning: The active warning Color of the label text.
	## @return: void
	func _init(_label: Label, _timer: Timer, _base: Color, _warning: Color) -> void:
		label = _label
		timer = _timer
		base_color = _base
		warning_color = _warning

	## Activates the warning state, starting the timer and applying the initial color toggle.
	## Fails gracefully if node references have been queued for deletion.
	## @return: void
	func start_blinking() -> void:
		# Defensive check to ensure SceneTree nodes are still valid before manipulating
		if not is_instance_valid(label) or not is_instance_valid(timer):
			return

		is_blinking = true
		timer.start()
		toggle_label()

	## Deactivates the warning state, stops the timer, and restores the base color.
	## Handles cleanup defensively to ensure logical resets even if nodes are partially freed.
	## @return: void
	func stop_blinking() -> void:
		# Always reset the logical flag immediately
		is_blinking = false

		if is_instance_valid(timer):
			timer.stop()

		# Ensure the label is firmly restored to its non-warning visual state
		if is_instance_valid(label):
			label.add_theme_color_override("font_color", base_color)

	## Swaps the label's text color between base_color and warning_color.
	## Internally called by the timer's timeout mechanism.
	## @return: void
	func toggle_label() -> void:
		if not is_instance_valid(label):
			return

		var current_color: Color

		# Resolve the effective color by prioritizing local theme overrides over class defaults
		if label.has_theme_color_override("font_color"):
			current_color = label.get("theme_override_colors/font_color")
		else:
			current_color = label.get_theme_color("font_color", "Label")

		# Alternate the color based on the current visual state
		if current_color == base_color:
			label.add_theme_color_override("font_color", warning_color)
		else:
			label.add_theme_color_override("font_color", base_color)

	## Safely checks if the underlying SceneTree timer is actively ticking.
	## Useful for external state queries or unit tests.
	## @return: bool - True if the timer is valid and running, false otherwise.
	func is_timer_running() -> bool:
		return is_instance_valid(timer) and not timer.is_stopped()


## Called when the node enters the scene tree for the first time.
## Initializes UI styles and establishes local states.
## @return: void
func _ready() -> void:
	# --- Fuel UI Setup ---
	_fuel_bar_style = StyleBoxFlat.new()
	set_bar_fill_style(fuel_bar, _fuel_bar_style)

	fuel_stat = StatManager.new(
		fuel_label,
		fuel_blink_timer,
		get_label_text_color(fuel_label),
		Color.RED.lerp(DARK_RED, 1.0)
	)

	if fuel_blink_timer:
		fuel_blink_timer.wait_time = BLINK_INTERVAL
		fuel_blink_timer.one_shot = false
		if not fuel_blink_timer.timeout.is_connected(_on_fuel_blink_timer_timeout):
			fuel_blink_timer.timeout.connect(_on_fuel_blink_timer_timeout)

	# --- Speed UI Setup ---
	_speed_bar_style = StyleBoxFlat.new()
	set_bar_fill_style(speed_bar, _speed_bar_style)

	speed_stat = StatManager.new(
		speed_label,
		speed_blink_timer,
		get_label_text_color(speed_label),
		Color.RED.lerp(DARK_RED, 1.0)
	)

	if speed_blink_timer:
		speed_blink_timer.wait_time = BLINK_INTERVAL
		speed_blink_timer.one_shot = false
		if not speed_blink_timer.timeout.is_connected(_on_speed_blink_timer_timeout):
			speed_blink_timer.timeout.connect(_on_speed_blink_timer_timeout)


## Wires the HUD to the injected data resources.
## Call this from your main level script when instantiating the player and UI.
## @param fuel_res: The authoritative FuelResource instance.
## @param speed_res: The authoritative SpeedResource instance.
## @param weapon_res: The authoritative WeaponResource instance.
## @return: void
func setup_hud(
	fuel_res: FuelResource, speed_res: SpeedResource, weapon_res: WeaponResource
) -> void:
	if (
		not is_instance_valid(fuel_res)
		or not is_instance_valid(speed_res)
		or not is_instance_valid(weapon_res)
	):
		Globals.log_message("HUD setup failed: Invalid resource injection.", Globals.LogLevel.ERROR)
		return

	# ==========================================
	# STEP 1: Safely Disconnect Old Resources
	# ==========================================
	if is_instance_valid(_speed_resource) and _speed_resource != speed_res:
		if _speed_resource.speed_updated.is_connected(_on_speed_updated_bridge):
			_speed_resource.speed_updated.disconnect(_on_speed_updated_bridge)
		if _speed_resource.speed_low.is_connected(_on_speed_low):
			_speed_resource.speed_low.disconnect(_on_speed_low)
		if _speed_resource.speed_maxed.is_connected(_on_speed_maxed):
			_speed_resource.speed_maxed.disconnect(_on_speed_maxed)

	if is_instance_valid(_fuel_resource) and _fuel_resource != fuel_res:
		if _fuel_resource.fuel_changed.is_connected(_on_fuel_changed_bridge):
			_fuel_resource.fuel_changed.disconnect(_on_fuel_changed_bridge)
		if _fuel_resource.fuel_depleted.is_connected(_on_player_out_of_fuel):
			_fuel_resource.fuel_depleted.disconnect(_on_player_out_of_fuel)

	if is_instance_valid(_weapon_resource) and _weapon_resource != weapon_res:
		if _weapon_resource.weapon_swapped.is_connected(_on_weapon_swapped):
			_weapon_resource.weapon_swapped.disconnect(_on_weapon_swapped)
		if _weapon_resource.ammo_updated.is_connected(_on_ammo_updated):
			_weapon_resource.ammo_updated.disconnect(_on_ammo_updated)

	# ==========================================
	# STEP 2: Assign New Resource References
	# ==========================================
	_fuel_resource = fuel_res
	_speed_resource = speed_res
	_weapon_resource = weapon_res

	# ==========================================
	# STEP 3: Connect New Signals
	# ==========================================
	if not _speed_resource.speed_updated.is_connected(_on_speed_updated_bridge):
		_speed_resource.speed_updated.connect(_on_speed_updated_bridge)
	if not _speed_resource.speed_low.is_connected(_on_speed_low):
		_speed_resource.speed_low.connect(_on_speed_low)
	if not _speed_resource.speed_maxed.is_connected(_on_speed_maxed):
		_speed_resource.speed_maxed.connect(_on_speed_maxed)

	if not _fuel_resource.fuel_changed.is_connected(_on_fuel_changed_bridge):
		_fuel_resource.fuel_changed.connect(_on_fuel_changed_bridge)
	if not _fuel_resource.fuel_depleted.is_connected(_on_player_out_of_fuel):
		_fuel_resource.fuel_depleted.connect(_on_player_out_of_fuel)

	if not _weapon_resource.weapon_swapped.is_connected(_on_weapon_swapped):
		_weapon_resource.weapon_swapped.connect(_on_weapon_swapped)
	if not _weapon_resource.ammo_updated.is_connected(_on_ammo_updated):
		_weapon_resource.ammo_updated.connect(_on_ammo_updated)

	# ==========================================
	# STEP 4: Force Deterministic Initial Sync
	# ==========================================
	# Sync Fuel
	fuel_bar.max_value = _fuel_resource.max_fuel
	update_fuel_bar()
	check_fuel_warning()

	# Sync Speed
	update_speed_bar()
	check_speed_warning()  # <-- ADD THIS LINE

	# Sync Weapon & Ammo
	if _weapon_resource.available_weapons.size() > _weapon_resource.current_index:
		var initial_weapon: String = _weapon_resource.available_weapons[
			_weapon_resource.current_index
		]
		_on_weapon_swapped(_weapon_resource.current_index, initial_weapon)

	_on_ammo_updated(_weapon_resource.current_ammo, _weapon_resource.max_ammo)

	Globals.log_message("HUD successfully wired to all Data Resources.", Globals.LogLevel.DEBUG)


## Retrieves the effective text color of a Label, considering theme overrides.
func get_label_text_color(label: Label) -> Color:
	if label.has_theme_color_override("font_color"):
		return label.get("theme_override_colors/font_color")
	return label.get_theme_color("font_color", "Label")


## Lifecycle callback triggered right before the node is removed from the tree.
## Safely disconnects global resource signals to prevent memory leaks.
## @return: void
func _exit_tree() -> void:
	# Explicitly sever the connection to the data resources
	if is_instance_valid(_speed_resource):
		if _speed_resource.speed_updated.is_connected(_on_speed_updated_bridge):
			_speed_resource.speed_updated.disconnect(_on_speed_updated_bridge)
		if _speed_resource.speed_low.is_connected(_on_speed_low):
			_speed_resource.speed_low.disconnect(_on_speed_low)
		if _speed_resource.speed_maxed.is_connected(_on_speed_maxed):
			_speed_resource.speed_maxed.disconnect(_on_speed_maxed)

	if is_instance_valid(_fuel_resource):
		if _fuel_resource.fuel_changed.is_connected(_on_fuel_changed_bridge):
			_fuel_resource.fuel_changed.disconnect(_on_fuel_changed_bridge)
		if _fuel_resource.fuel_depleted.is_connected(_on_player_out_of_fuel):
			_fuel_resource.fuel_depleted.disconnect(_on_player_out_of_fuel)

	if is_instance_valid(_weapon_resource):
		if _weapon_resource.weapon_swapped.is_connected(_on_weapon_swapped):
			_weapon_resource.weapon_swapped.disconnect(_on_weapon_swapped)
		if _weapon_resource.ammo_updated.is_connected(_on_ammo_updated):
			_weapon_resource.ammo_updated.disconnect(_on_ammo_updated)


# ==========================================
# SIGNAL HANDLERS & BRIDGES
# ==========================================


## Compatibility bridge to route the new SpeedResource signal into the legacy logic.
## @param new_speed: The updated speed value from the resource.
## @return: void
func _on_speed_updated_bridge(_new_speed: float) -> void:
	# Route directly to the UI updaters instead of the legacy player pathway
	update_speed_bar()
	check_speed_warning()


## Signal handler for global engine failure.
## Triggers immediate UI feedback for a flameout state.
## @return: void
func _on_player_out_of_fuel() -> void:
	# The Player node sets the resource speed to 0.0. We just update the UI.
	update_speed_bar()
	check_speed_warning()


# ==========================================
# UI UPDATE LOGIC
# ==========================================


## Updates the fuel bar's visual fill and color based on the current fuel level.
## @return: void
func update_fuel_bar() -> void:
	if not is_instance_valid(_fuel_resource):
		return

	var cur_fuel: float = _fuel_resource.current_fuel
	var m_fuel: float = _fuel_resource.max_fuel

	# FIX: Dynamically sync the progress bar's maximum limit on UI draw
	fuel_bar.max_value = m_fuel
	fuel_bar.value = cur_fuel
	var fuel_percent: float = 0.0 if m_fuel <= 0.0 else (cur_fuel / m_fuel) * 100.0
	var factor: float = 0.0

	var high: float = _fuel_resource.high_fuel_threshold
	var medium: float = _fuel_resource.medium_fuel_threshold
	var low: float = _fuel_resource.low_fuel_threshold
	var no_fuel: float = _fuel_resource.no_fuel_threshold

	if fuel_percent > high:
		_fuel_bar_style.bg_color = Color.GREEN
	elif fuel_percent >= medium:
		var span: float = high - medium
		factor = 1.0 if span <= 0.0 else clamp((high - fuel_percent) / span, 0.0, 1.0)
		_fuel_bar_style.bg_color = Color.GREEN.lerp(Color.YELLOW, factor)
	elif fuel_percent >= low:
		var span: float = medium - low
		factor = 1.0 if span <= 0.0 else clamp((medium - fuel_percent) / span, 0.0, 1.0)
		_fuel_bar_style.bg_color = Color.YELLOW.lerp(Color.RED, factor)
	elif fuel_percent >= no_fuel:
		var span: float = low - no_fuel
		factor = 1.0 if span <= 0.0 else clamp((low - fuel_percent) / span, 0.0, 1.0)
		_fuel_bar_style.bg_color = Color.RED.lerp(DARK_RED, factor)
	else:
		_fuel_bar_style.bg_color = DARK_RED


## Updates the speed bar value and color based on current speed.
## @return: void
func update_speed_bar() -> void:
	if not is_instance_valid(_speed_resource):
		return

	var current_spd: float = _speed_resource.current_speed
	var max_s: float = _speed_resource.max_speed
	var min_s: float = _speed_resource.min_speed

	speed_bar.max_value = max_s
	speed_bar.value = current_spd
	var factor: float = 0.0

	var high_red_thresh: float = max_s * HIGH_RED_FRACTION
	var high_yellow_thresh: float = max_s * _speed_resource.high_yellow_fraction
	var low_yellow_thresh: float = min_s + (max_s - min_s) * _speed_resource.low_yellow_fraction
	var low_red_thresh: float = min_s

	if current_spd >= high_red_thresh:
		factor = clamp((current_spd - high_red_thresh) / (max_s - high_red_thresh), 0.0, 1.0)
		_speed_bar_style.bg_color = Color.YELLOW.lerp(DARK_RED, factor)
	elif current_spd >= high_yellow_thresh:
		factor = clamp(
			(current_spd - high_yellow_thresh) / (high_red_thresh - high_yellow_thresh), 0.0, 1.0
		)
		_speed_bar_style.bg_color = Color.GREEN.lerp(Color.YELLOW, factor)
	elif current_spd <= low_red_thresh:
		_speed_bar_style.bg_color = DARK_RED
	elif current_spd <= low_yellow_thresh:
		factor = clamp(
			(low_yellow_thresh - current_spd) / (low_yellow_thresh - low_red_thresh), 0.0, 1.0
		)
		_speed_bar_style.bg_color = Color.GREEN.lerp(Color.YELLOW, factor)
	else:
		_speed_bar_style.bg_color = Color.GREEN


# ==========================================
# WARNING & BLINK LOGIC
# ==========================================


## Checks if the current fuel has dropped below the low-fuel threshold.
## Activates or deactivates the UI warning blinker accordingly.
## @return: void
func check_fuel_warning() -> void:
	if not is_instance_valid(_fuel_resource):
		return

	var fuel_percent: float = (
		0.0
		if _fuel_resource.max_fuel <= 0.0
		else (_fuel_resource.current_fuel / _fuel_resource.max_fuel) * 100.0
	)

	if fuel_percent <= _fuel_resource.low_fuel_threshold and not fuel_stat.is_blinking:
		fuel_stat.start_blinking()
	elif fuel_percent > _fuel_resource.low_fuel_threshold and fuel_stat.is_blinking:
		fuel_stat.stop_blinking()


## Checks speed and starts/stops label blinking if approaching or exceeding limits.
## @return: void
func check_speed_warning() -> void:
	if not is_instance_valid(_speed_resource):
		return

	var current_spd: float = _speed_resource.current_speed
	var high_yellow_thresh: float = _speed_resource.max_speed * _speed_resource.high_yellow_fraction
	var low_yellow_thresh: float = (
		_speed_resource.min_speed
		+ (
			(_speed_resource.max_speed - _speed_resource.min_speed)
			* _speed_resource.low_yellow_fraction
		)
	)

	if (
		(current_spd < low_yellow_thresh or current_spd > high_yellow_thresh)
		and not speed_stat.is_blinking
	):
		speed_stat.start_blinking()
	elif (
		(low_yellow_thresh <= current_spd and current_spd <= high_yellow_thresh)
		and speed_stat.is_blinking
	):
		speed_stat.stop_blinking()


## Timer callback that toggles the visual state of the fuel warning label.
## @return: void
func _on_fuel_blink_timer_timeout() -> void:
	if fuel_stat != null and fuel_stat.is_blinking:
		fuel_stat.toggle_label()


## Timer callback that toggles the visual state of the speed warning label.
## @return: void
func _on_speed_blink_timer_timeout() -> void:
	if speed_stat != null and speed_stat.is_blinking:
		speed_stat.toggle_label()


# ==========================================
# STYLING HELPERS
# ==========================================


## Applies standard corner radiuses and assigns a custom stylebox to a ProgressBar.
## @param bar: The ProgressBar node to style.
## @param bar_fill_style: The StyleBoxFlat to configure and apply.
## @return: void
func set_bar_fill_style(bar: ProgressBar, bar_fill_style: StyleBoxFlat) -> void:
	var corner_radius: int = 10
	bar_fill_style.corner_radius_bottom_left = corner_radius
	bar_fill_style.corner_radius_top_left = corner_radius
	bar_fill_style.corner_radius_bottom_right = corner_radius
	bar_fill_style.corner_radius_top_right = corner_radius
	bar.add_theme_stylebox_override("fill", bar_fill_style)


# ==========================================
# PUBLIC ACCESSORS (TESTING & EXTERNAL QUERY)
# ==========================================


## Retrieves the current forward speed directly from the injected SpeedResource.
## @return: float - The player's current speed value.
func get_current_speed() -> float:
	if is_instance_valid(_speed_resource):
		return _speed_resource.current_speed
	return 0.0


## Retrieves the current computed background color of the fuel progress bar.
## Useful for verifying threshold lerping logic in unit tests.
## @return: Color - The current StyleBoxFlat background color, or Color.
## TRANSPARENT if uninitialized.
func get_fuel_bar_color() -> Color:
	if _fuel_bar_style:
		return _fuel_bar_style.bg_color
	return Color.TRANSPARENT


## Retrieves the current computed background color of the speed progress bar.
## Useful for verifying threshold lerping logic in unit tests.
## @return: Color - The current StyleBoxFlat background color, or Color.
## TRANSPARENT if uninitialized.
func get_speed_bar_color() -> Color:
	if _speed_bar_style:
		return _speed_bar_style.bg_color
	return Color.TRANSPARENT


## Checks if the fuel warning label is currently in a blinking state.
## @return: bool - True if the fuel warning is active and blinking, false otherwise.
func is_fuel_warning_active() -> bool:
	return fuel_stat != null and fuel_stat.is_blinking


## Checks if the speed warning label is currently in a blinking state.
## @return: bool - True if the speed warning is active and blinking, false otherwise.
func is_speed_warning_active() -> bool:
	return speed_stat != null and speed_stat.is_blinking


## Verifies if the underlying SceneTree Timer for the speed blinker is actively running.
## @return: bool - True if the timer node is valid and not stopped, false otherwise.
func is_speed_timer_running() -> bool:
	return speed_stat != null and speed_stat.is_timer_running()


## Compatibility bridge to route the new FuelResource signal into the UI updates.
## @param _new_fuel: The updated fuel value from the resource.
## @return: void
func _on_fuel_changed_bridge(_new_fuel: float) -> void:
	update_fuel_bar()
	check_fuel_warning()


## Callback triggered when the WeaponResource index changes.
## @param _index: The array index of the newly equipped weapon.
## @param weapon_name: The string identifier of the weapon.
## @return: void
func _on_weapon_swapped(_index: int, weapon_name: String) -> void:
	Globals.log_message("HUD: Weapon swapped to " + weapon_name, Globals.LogLevel.DEBUG)

	if is_instance_valid(weapon_label):
		# Format string to {MACHINE=GUN} by uppercase, replacing space, and wrapping
		var formatted_name: String = "{%s}" % weapon_name.to_upper().replace(" ", "=")
		weapon_label.text = formatted_name


## Callback triggered when the WeaponResource ammo count changes.
## @param current: The current ammo count.
## @param max_ammo: The maximum ammo capacity.
## @return: void
func _on_ammo_updated(current: int, max_ammo: int) -> void:
	if is_instance_valid(ammo_bar):
		ammo_bar.max_value = float(max_ammo)
		ammo_bar.value = float(current)


## Signal handler for extreme low speed (stall warning).
## Snaps the UI to a maximum dark red warning state.
## @return: void
func _on_speed_low() -> void:
	if speed_stat != null and not speed_stat.is_blinking:
		speed_stat.start_blinking()

	if _speed_bar_style != null:
		_speed_bar_style.bg_color = DARK_RED


## Signal handler for maximum forward velocity.
## Snaps the UI to a bright red warning state to indicate structural stress.
## @return: void
func _on_speed_maxed() -> void:
	if speed_stat != null and not speed_stat.is_blinking:
		speed_stat.start_blinking()

	if _speed_bar_style != null:
		_speed_bar_style.bg_color = Color.RED
