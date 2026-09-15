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


# --- Internal State ---
var fuel_stat: StatManager
var speed_stat: StatManager

var _settings: GameSettingsResource = null
var _current_speed: float = 250.0

var _fuel_bar_style: StyleBoxFlat
var _speed_bar_style: StyleBoxFlat
var _connected_player: Node2D = null  # NEW: Track the player for clean disconnects

# --- Node References ---
# Paths assume this script is attached directly to "PlayerStatsPanel"
@onready var fuel_bar: ProgressBar = $Stats/Fuel/FuelBar
@onready var fuel_label: Label = $Stats/Fuel/FuelLabel
@onready var fuel_blink_timer: Timer = $Stats/Fuel/FuelLabel/BlinkTimer

@onready var speed_bar: ProgressBar = $Stats/Speed/SpeedBar
@onready var speed_label: Label = $Stats/Speed/SpeedLabel
@onready var speed_blink_timer: Timer = $Stats/Speed/SpeedLabel/BlinkTimer


## Called when the node enters the scene tree for the first time.
## Initializes UI styles, establishes local states, and connects to global settings.
## @return: void
func _ready() -> void:
	_settings = Globals.settings if is_instance_valid(Globals) else null

	if not is_instance_valid(_settings):
		# FIX 1: Use Globals logger or print to bypass GUT engine-level warning captures
		if is_instance_valid(Globals):
			Globals.log_message(
				"HUD couldn't find Globals.settings! Creating fallback settings resource.",
				Globals.LogLevel.WARNING
			)
		else:
			print(
				"WARNING: HUD couldn't find Globals.settings! Creating fallback settings resource."
			)

		_settings = GameSettingsResource.new()
		if is_instance_valid(Globals):
			Globals.settings = _settings

	# FIX 2: Add connection guards to prevent ERR_INVALID_PARAMETER if _ready runs multiple times
	if not _settings.setting_changed.is_connected(_on_setting_changed):
		_settings.setting_changed.connect(_on_setting_changed)
	if not _settings.fuel_depleted.is_connected(_on_player_out_of_fuel):
		_settings.fuel_depleted.connect(_on_player_out_of_fuel)

	# --- Fuel UI Setup ---
	_fuel_bar_style = StyleBoxFlat.new()
	set_bar_fill_style(fuel_bar, _fuel_bar_style)
	fuel_bar.max_value = _settings.max_fuel

	fuel_stat = StatManager.new(
		fuel_label,
		fuel_blink_timer,
		get_label_text_color(fuel_label),
		Color.RED.lerp(DARK_RED, 1.0)
	)

	if fuel_blink_timer:
		fuel_blink_timer.wait_time = BLINK_INTERVAL
		fuel_blink_timer.one_shot = false
		# FIX 2: Connection guard
		if not fuel_blink_timer.timeout.is_connected(_on_fuel_blink_timer_timeout):
			fuel_blink_timer.timeout.connect(_on_fuel_blink_timer_timeout)

	# --- Speed UI Setup ---
	_speed_bar_style = StyleBoxFlat.new()
	set_bar_fill_style(speed_bar, _speed_bar_style)
	speed_bar.max_value = _settings.max_speed  # Pull directly from resource!

	speed_stat = StatManager.new(
		speed_label,
		speed_blink_timer,
		get_label_text_color(speed_label),
		Color.RED.lerp(DARK_RED, 1.0)
	)

	if speed_blink_timer:
		speed_blink_timer.wait_time = BLINK_INTERVAL
		speed_blink_timer.one_shot = false
		# FIX 2: Connection guard
		if not speed_blink_timer.timeout.is_connected(_on_speed_blink_timer_timeout):
			speed_blink_timer.timeout.connect(_on_speed_blink_timer_timeout)

	# Initial UI Draw
	update_fuel_bar()
	update_speed_bar()


## Wires the HUD to the Player node's exported signals.
## Call this from your main level script when instantiating the player and UI.
## @param player_node: The Player Node2D instance.
## @return: void
func setup_hud(player_node: Node2D) -> void:
	if not is_instance_valid(player_node):
		push_error("HUD setup failed: Invalid player node.")
		return

	# NEW FIX: Verify the signal actually exists before attempting to access it!
	if not player_node.has_signal("speed_changed"):
		push_error("HUD setup failed: Provided node lacks 'speed_changed' signal.")
		return

	# Safely disconnect the old player if we are hot-swapping nodes
	if is_instance_valid(_connected_player) and _connected_player != player_node:
		if _connected_player.speed_changed.is_connected(_on_player_speed_changed):
			_connected_player.speed_changed.disconnect(_on_player_speed_changed)

	_connected_player = player_node

	# Connection guard for external wiring
	if not _connected_player.speed_changed.is_connected(_on_player_speed_changed):
		_connected_player.speed_changed.connect(_on_player_speed_changed)

	Globals.log_message("HUD successfully wired to Player signals.", Globals.LogLevel.DEBUG)


## Retrieves the effective text color of a Label, considering theme overrides.
func get_label_text_color(label: Label) -> Color:
	if label.has_theme_color_override("font_color"):
		return label.get("theme_override_colors/font_color")
	return label.get_theme_color("font_color", "Label")


## Lifecycle callback triggered right before the node is removed from the tree.
## Safely disconnects global resource signals to prevent memory leaks.
## @return: void
func _exit_tree() -> void:
	# NEW FIX: Explicitly sever the connection to the player
	if is_instance_valid(_connected_player):
		if _connected_player.speed_changed.is_connected(_on_player_speed_changed):
			_connected_player.speed_changed.disconnect(_on_player_speed_changed)

	if is_instance_valid(_settings):
		if _settings.setting_changed.is_connected(_on_setting_changed):
			_settings.setting_changed.disconnect(_on_setting_changed)
		if _settings.fuel_depleted.is_connected(_on_player_out_of_fuel):
			_settings.fuel_depleted.disconnect(_on_player_out_of_fuel)


# ==========================================
# SIGNAL HANDLERS
# ==========================================


## Callback triggered externally by the Player node when its speed changes.
## @param new_speed: The current forward speed of the player.
## @param max_speed: The absolute maximum speed limit.
## @return: void
func _on_player_speed_changed(new_speed: float, max_speed: float) -> void:
	_current_speed = new_speed
	speed_bar.max_value = max_speed
	update_speed_bar()
	check_speed_warning()


## Observer pattern callback to react to updates from the global settings resource.
## @param setting_name: The name of the property that was modified.
## @param _new_value: The updated value of the property (unused directly here).
## @return: void
func _on_setting_changed(setting_name: String, _new_value: Variant) -> void:
	if not is_instance_valid(_settings):
		return

	# --- Handle Fuel Updates ---
	if (
		setting_name
		in [
			"current_fuel",
			"max_fuel",
			"high_fuel_threshold",
			"medium_fuel_threshold",
			"low_fuel_threshold",
			"no_fuel_threshold"
		]
	):
		if setting_name == "max_fuel":
			fuel_bar.max_value = _settings.max_fuel

		update_fuel_bar()
		check_fuel_warning()

	# --- Handle Speed Updates ---
	# NEW FIX: React immediately to dynamic threshold or speed limit changes
	elif setting_name in ["max_speed", "min_speed", "high_yellow_fraction", "low_yellow_fraction"]:
		if setting_name == "max_speed":
			speed_bar.max_value = _settings.max_speed

		update_speed_bar()
		check_speed_warning()


## Signal handler for global engine failure.
## Triggers immediate UI feedback for a flameout state.
## @return: void
func _on_player_out_of_fuel() -> void:
	_current_speed = 0.0
	update_speed_bar()
	check_speed_warning()


# ==========================================
# UI UPDATE LOGIC
# ==========================================


## Updates the fuel bar's visual fill and color based on the current fuel level.
## @return: void
func update_fuel_bar() -> void:
	if not is_instance_valid(_settings):
		return

	var cur_fuel: float = _settings.current_fuel
	var m_fuel: float = _settings.max_fuel

	fuel_bar.value = cur_fuel
	var fuel_percent: float = 0.0 if m_fuel <= 0.0 else (cur_fuel / m_fuel) * 100.0
	var factor: float = 0.0

	var high: float = _settings.high_fuel_threshold
	var medium: float = _settings.medium_fuel_threshold
	var low: float = _settings.low_fuel_threshold
	var no_fuel: float = _settings.no_fuel_threshold

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
	if not is_instance_valid(_settings):
		return

	speed_bar.value = _current_speed
	var factor: float = 0.0

	# Dynamically calculate thresholds from the Resource
	var max_s: float = _settings.max_speed
	var min_s: float = _settings.min_speed
	var high_red_thresh: float = max_s * HIGH_RED_FRACTION
	var high_yellow_thresh: float = max_s * _settings.high_yellow_fraction
	var low_yellow_thresh: float = min_s + (max_s - min_s) * _settings.low_yellow_fraction
	var low_red_thresh: float = min_s

	if _current_speed >= high_red_thresh:
		factor = clamp((_current_speed - high_red_thresh) / (max_s - high_red_thresh), 0.0, 1.0)
		_speed_bar_style.bg_color = Color.YELLOW.lerp(DARK_RED, factor)
	elif _current_speed >= high_yellow_thresh:
		factor = clamp(
			(_current_speed - high_yellow_thresh) / (high_red_thresh - high_yellow_thresh), 0.0, 1.0
		)
		_speed_bar_style.bg_color = Color.GREEN.lerp(Color.YELLOW, factor)
	elif _current_speed <= low_red_thresh:
		_speed_bar_style.bg_color = DARK_RED
	elif _current_speed <= low_yellow_thresh:
		factor = clamp(
			(low_yellow_thresh - _current_speed) / (low_yellow_thresh - low_red_thresh), 0.0, 1.0
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
	if not is_instance_valid(_settings):
		return

	var fuel_percent: float = (
		0.0 if _settings.max_fuel <= 0.0 else (_settings.current_fuel / _settings.max_fuel) * 100.0
	)

	if fuel_percent <= _settings.low_fuel_threshold and not fuel_stat.is_blinking:
		fuel_stat.start_blinking()
	elif fuel_percent > _settings.low_fuel_threshold and fuel_stat.is_blinking:
		fuel_stat.stop_blinking()


## Checks speed and starts/stops label blinking if approaching or exceeding limits.
## @return: void
func check_speed_warning() -> void:
	if not is_instance_valid(_settings):
		return

	# Dynamically calculate thresholds from the Resource
	var high_yellow_thresh: float = _settings.max_speed * _settings.high_yellow_fraction
	var low_yellow_thresh: float = (
		_settings.min_speed
		+ (_settings.max_speed - _settings.min_speed) * _settings.low_yellow_fraction
	)

	if (
		(_current_speed < low_yellow_thresh or _current_speed > high_yellow_thresh)
		and not speed_stat.is_blinking
	):
		speed_stat.start_blinking()
	elif (
		(low_yellow_thresh <= _current_speed and _current_speed <= high_yellow_thresh)
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


## Retrieves the current forward speed cached by the HUD.
## @return: float - The player's current speed value.
func get_current_speed() -> float:
	return _current_speed


## Retrieves the active game settings resource driving the HUD's logic.
## @return: GameSettingsResource - The global settings data container.
func get_settings() -> GameSettingsResource:
	return _settings


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
