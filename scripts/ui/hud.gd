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
var _settings: GameSettingsResource = null
var _current_speed: float = 250.0

var _fuel_state: Dictionary = {}
var _speed_state: Dictionary = {}

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

	_fuel_state = {
		"label": fuel_label,
		"timer": fuel_blink_timer,
		"blinking": false,
		"base_color": get_label_text_color(fuel_label),
		"warning_color": Color.RED.lerp(DARK_RED, 1.0)
	}

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

	_speed_state = {
		"label": speed_label,
		"timer": speed_blink_timer,
		"blinking": false,
		"base_color": get_label_text_color(speed_label),
		"warning_color": Color.RED.lerp(DARK_RED, 1.0)
	}

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

	if fuel_percent <= _settings.low_fuel_threshold and not _fuel_state["blinking"]:
		start_blinking(_fuel_state)
	elif fuel_percent > _settings.low_fuel_threshold and _fuel_state["blinking"]:
		stop_blinking(_fuel_state)


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
		and not _speed_state["blinking"]
	):
		start_blinking(_speed_state)
	elif (
		(low_yellow_thresh <= _current_speed and _current_speed <= high_yellow_thresh)
		and _speed_state["blinking"]
	):
		stop_blinking(_speed_state)


## Initiates the blinking effect for a specific UI state dictionary.
## @param state: The target state dictionary.
## @return: void
func start_blinking(state: Dictionary) -> void:
	if state["label"] and state["timer"]:
		state["blinking"] = true
		state["timer"].start()
		_toggle_label(state)


## Halts the blinking effect for a specific UI state dictionary and restores its base color.
## @param state: The target state dictionary.
## @return: void
func stop_blinking(state: Dictionary) -> void:
	if state["label"] and state["timer"]:
		state["blinking"] = false
		state["timer"].stop()
		set_label_text_color(state["label"], state["base_color"])


## Timer callback that toggles the visual state of the fuel warning label.
## @return: void
func _on_fuel_blink_timer_timeout() -> void:
	if _fuel_state["blinking"] and _fuel_state["label"]:
		_toggle_label(_fuel_state)


## Timer callback that toggles the visual state of the speed warning label.
## @return: void
func _on_speed_blink_timer_timeout() -> void:
	if _speed_state["blinking"] and _speed_state["label"]:
		_toggle_label(_speed_state)


## Swaps the text color of the given UI dictionary's label between its base and warning colors.
## @param state: The target state dictionary.
## @return: void
func _toggle_label(state: Dictionary) -> void:
	if get_label_text_color(state["label"]) == state["base_color"]:
		set_label_text_color(state["label"], state["warning_color"])
	else:
		set_label_text_color(state["label"], state["base_color"])


# ==========================================
# STYLING HELPERS
# ==========================================


## Retrieves the effective text color of a Label, considering theme overrides.
## @param label: The Label node to query.
## @return: The effective font color.
func get_label_text_color(label: Label) -> Color:
	if label.has_theme_color_override("font_color"):
		return label.get("theme_override_colors/font_color")
	return label.get_theme_color("font_color", "Label")


## Applies a dynamic font color override to a specified label.
## @param label: The Label node to modify.
## @param new_color: The target Color to apply.
## @return: void
func set_label_text_color(label: Label, new_color: Color) -> void:
	if label:
		label.add_theme_color_override("font_color", new_color)


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
	return _fuel_state.get("blinking", false)


## Checks if the speed warning label is currently in a blinking state.
## @return: bool - True if the speed warning is active and blinking, false otherwise.
func is_speed_warning_active() -> bool:
	return _speed_state.get("blinking", false)


## Verifies if the underlying SceneTree Timer for the speed blinker is actively running.
## @return: bool - True if the timer node is valid and not stopped, false otherwise.
func is_speed_timer_running() -> bool:
	var timer: Timer = _speed_state.get("timer")
	return is_instance_valid(timer) and not timer.is_stopped()
