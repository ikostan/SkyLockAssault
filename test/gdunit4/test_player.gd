## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
# test_player.gd
# Unit tests for player.gd using GdUnit4 in Godot 4.4
# All tests now use manual scene instantiation (no GdUnitSceneRunner)
# This avoids version-specific API issues and gives full control.
extends GdUnitTestSuite

const TestHelpers = preload("res://test/gdunit4/test_helpers.gd")

@warning_ignore("unused_parameter")
@warning_ignore("return_value_discarded")

var original_difficulty: float  # Snapshot holder

func before_test() -> void:
	original_difficulty = Globals.settings.difficulty  # Snapshot before each test

func after_test() -> void:
	Globals.settings.difficulty = original_difficulty  # Restore after each test


func test_shared_depletion_helper() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root: Node = main_scene.get_node("Player")
	Globals.settings.difficulty = 2.0
	
	# CHANGED: Use current_speed instead of speed["speed"]
	var expected: float = Globals.settings.base_consumption_rate * (player_root.current_speed / Globals.settings.max_speed) * Globals.settings.difficulty
	assert_float(TestHelpers.calculate_expected_depletion(player_root, Globals.settings.difficulty)).is_equal_approx(expected, 0.001)


# Test: Player node exists and is visible
func test_player_present() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root : Node2D = main_scene.get_node("Player")
	assert_object(player_root).is_not_null()
	assert_bool(player_root.visible).is_true()
	assert_bool(player_root.is_inside_tree()).is_true()


func test_clamping() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root: Node = main_scene.get_node("Player")
	var body: CharacterBody2D = player_root.player
	
	# Test left/top bounds - use is_equal_approx with explicit tolerance
	body.position = Vector2(-1000, -1000)
	player_root._physics_process(1.0/60.0)
	assert_float(body.position.x).is_equal_approx(player_root.player_x_min, 0.001)
	assert_float(body.position.y).is_equal_approx(player_root.player_y_min, 0.001)
	
	# Test right/bottom bounds
	body.position = Vector2(2000, 2000)
	player_root._physics_process(1.0/60.0)
	assert_float(body.position.x).is_equal_approx(player_root.player_x_max, 0.001)
	assert_float(body.position.y).is_equal_approx(player_root.player_y_max, 0.001)


# Test: Fuel bar color changes at thresholds
func test_fuel_colors() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var hud: Panel = main_scene.get_node("PlayerStatsPanel")
	
	# High fuel → Green
	Globals.settings.current_fuel = Globals.settings.max_fuel * 0.95
	hud.update_fuel_bar()
	var style_1 : StyleBoxFlat = hud.fuel_bar.get_theme_stylebox("fill").duplicate()
	assert_that(style_1.bg_color).is_equal(Color.GREEN)
		
	# Low fuel → Dark Red
	Globals.settings.current_fuel = Globals.settings.max_fuel * 0.10
	hud.update_fuel_bar()
	var style_2 : StyleBoxFlat = hud.fuel_bar.get_theme_stylebox("fill").duplicate()
	assert_that(style_2.bg_color).is_equal(Color(0.5, 0, 0, 1.0))


# Test: Smooth color lerp between thresholds
func test_fuel_colors_fixed() -> void:
	var main_scene: Node= auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var hud: Panel = main_scene.get_node("PlayerStatsPanel")
	
	# Still full → Green
	Globals.settings.current_fuel = Globals.settings.max_fuel * 0.95
	hud.update_fuel_bar()
	var style : StyleBoxFlat =  hud.fuel_bar.get_theme_stylebox("fill").duplicate()
	assert_that(style.bg_color).is_equal(Color.GREEN)
	
	# Between 90% and 50% → Lerp green → yellow
	Globals.settings.current_fuel = Globals.settings.max_fuel * 0.70
	hud.update_fuel_bar()
	style = hud.fuel_bar.get_theme_stylebox("fill").duplicate()
	var expected := Color.GREEN.lerp(Color.YELLOW, (0.90 - 0.70) / (0.90 - 0.50))
	assert_bool(style.bg_color.is_equal_approx(expected)).is_true()


# Test: Gradual fuel color change to dark red
func test_fuel_gradual_depletion_colors() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var hud: Panel = main_scene.get_node("PlayerStatsPanel")
	
	# Start at 30% (should be red)
	Globals.settings.current_fuel = Globals.settings.max_fuel * 0.30
	hud.update_fuel_bar()
	var style: StyleBoxFlat = hud.fuel_bar.get_theme_stylebox("fill").duplicate()
	assert_that(style.bg_color).is_equal(Color.RED)
	
	# Drop to 15% (dark red)
	Globals.settings.current_fuel = Globals.settings.max_fuel * 0.15
	hud.update_fuel_bar()
	style = hud.fuel_bar.get_theme_stylebox("fill").duplicate()
	assert_that(style.bg_color).is_equal(Color(0.5, 0, 0))
	
	# Drop to 10% (still dark red)
	Globals.settings.current_fuel = Globals.settings.max_fuel * 0.10
	hud.update_fuel_bar()
	style = hud.fuel_bar.get_theme_stylebox("fill").duplicate()
	assert_that(style.bg_color).is_equal(Color(0.5, 0, 0))


# Test: Rotor start/stop handles null SFX without crash
func test_rotor_null_sfx() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root: Node2D = main_scene.get_node("Player")
	
	# Force null SFX
	player_root.rotor_left_sfx = null
	player_root.rotor_right_sfx = null
	
	# Call start/stop - no crash expected
	player_root.rotor_start(player_root.rotor_left, player_root.rotor_left_sfx)
	player_root.rotor_start(player_root.rotor_right, player_root.rotor_right_sfx)
	player_root.rotor_stop(player_root.rotor_left, player_root.rotor_left_sfx)
	player_root.rotor_stop(player_root.rotor_right, player_root.rotor_right_sfx)
	
	# Assert animation started/stopped
	assert_bool(player_root.rotor_left.get_node("AnimatedSprite2D").is_playing()).is_false()
	assert_bool(player_root.rotor_right.get_node("AnimatedSprite2D").is_playing()).is_false()


# Test: Independent blinking for fuel and speed labels
func test_independent_blinking() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var hud: Panel = main_scene.get_node("PlayerStatsPanel")
	
	# Force low fuel and high speed to trigger both
	Globals.settings.current_fuel = Globals.settings.max_fuel * 0.10
	hud._current_speed = Globals.settings.max_speed * 0.95
	hud.check_fuel_warning()
	hud.check_speed_warning()
	
	# Assert both are now at warning color after initial blink start
	assert_that(hud.get_label_text_color(hud.fuel_label)).is_equal(hud._fuel_state["warning_color"])
	assert_that(hud.get_label_text_color(hud.speed_label)).is_equal(hud._speed_state["warning_color"])
	
	# Toggle one, other unchanged
	hud._toggle_label(hud._fuel_state)
	assert_that(hud.get_label_text_color(hud.fuel_label)).is_equal(hud._fuel_state["base_color"])
	assert_that(hud.get_label_text_color(hud.speed_label)).is_equal(hud._speed_state["warning_color"])


# Test: get_label_text_color_override returns override if set, else theme default
func test_get_label_text_color_override() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var hud: Panel = main_scene.get_node("PlayerStatsPanel")
	var fuel_label: Label = hud.fuel_label
	
	# Clear any editor-set override to test from clean theme default
	fuel_label.remove_theme_color_override("font_color")
	
	var initial_color: Color = hud.get_label_text_color(fuel_label)
	assert_bool(initial_color.is_equal_approx(Color(0, 0, 0, 0))).is_false()
	
	# Set override
	var override_color: Color = Color.BLUE
	fuel_label.add_theme_color_override("font_color", override_color)
	
	# Assert returns override
	assert_that(hud.get_label_text_color(fuel_label)).is_equal(override_color)
	
	# Remove override
	fuel_label.remove_theme_color_override("font_color")
	
	# Assert back to initial
	assert_that(hud.get_label_text_color(fuel_label)).is_equal(initial_color)


# Test: rotor_start/stop logs warning on missing AnimatedSprite2D
func test_rotor_missing_anim_sprite() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root: Node2D = main_scene.get_node("Player")
	
	# Temporarily remove AnimatedSprite2D from left rotor
	var left_rotor: Node2D = player_root.rotor_left
	var anim_sprite: AnimatedSprite2D = left_rotor.get_node("AnimatedSprite2D")
	left_rotor.remove_child(anim_sprite)
	
	# Call start/stop - expect warning log, no crash or Godot error
	player_root.rotor_start(left_rotor, player_root.rotor_left_sfx)
	player_root.rotor_stop(left_rotor, player_root.rotor_left_sfx)
	
	# Restore for cleanup
	left_rotor.add_child(anim_sprite)
	
	# Assert animation is still playing (unchanged, since missing during calls)
	assert_bool(player_root.rotor_left.get_node("AnimatedSprite2D").is_playing()).is_true()


# Test: Blinking starts in yellow/red zones, stops in normal
func test_speed_blinking_thresholds() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var hud: Panel = main_scene.get_node("PlayerStatsPanel")
	
	# NEW: Calculate thresholds dynamically using the Resource
	var max_s: float = Globals.settings.max_speed
	var min_s: float = Globals.settings.min_speed
	var high_yellow_thresh: float = max_s * Globals.settings.high_yellow_fraction
	var high_red_thresh: float = max_s * hud.HIGH_RED_FRACTION
	var low_yellow_thresh: float = min_s + (max_s - min_s) * Globals.settings.low_yellow_fraction
	
	# Normal speed: no blink
	hud._current_speed = (Globals.settings.min_speed + high_yellow_thresh) / 2.0
	hud.check_speed_warning()
	assert_bool(hud._speed_state["blinking"]).is_false()
	
	# Low yellow: start blink
	hud._current_speed = low_yellow_thresh - 10.0
	hud.check_speed_warning()
	assert_bool(hud._speed_state["blinking"]).is_true()
	
	# Low red: remains blinking
	hud._current_speed = Globals.settings.min_speed - 1.0
	hud.check_speed_warning()
	assert_bool(hud._speed_state["blinking"]).is_true()
	
	# Back to normal: stop blink
	hud._current_speed = (low_yellow_thresh + high_yellow_thresh) / 2.0
	hud.check_speed_warning()
	assert_bool(hud._speed_state["blinking"]).is_false()
	
	# High yellow: start blink
	hud._current_speed = high_yellow_thresh + 10.0
	hud.check_speed_warning()
	assert_bool(hud._speed_state["blinking"]).is_true()
	
	# High red: remains blinking
	hud._current_speed = high_red_thresh + 10.0
	hud.check_speed_warning()
	assert_bool(hud._speed_state["blinking"]).is_true()
	
	# Back to normal: stop blink
	hud._current_speed = (low_yellow_thresh + high_yellow_thresh) / 2.0
	hud.check_speed_warning()
	assert_bool(hud._speed_state["blinking"]).is_false()


# Test: Player movement with input actions (updated for lateral-only refactor)
func test_movement() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root: Node = main_scene.get_node("Player")
	var body: CharacterBody2D = player_root.player
	
	# Left movement (x only now)
	Input.action_press("move_left")
	player_root._physics_process(1.0/60.0)
	assert_vector(body.velocity).is_equal(Vector2(-250.0, 0.0))
	Input.action_release("move_left")
	
	# Speed up (no velocity change, just speed var)
	# CHANGED: Use current_speed
	var initial_speed: float = player_root.current_speed
	Input.action_press("speed_up")
	player_root._physics_process(1.0/60.0)
	assert_float(player_root.current_speed).is_greater(initial_speed)  # Increases speed var
	assert_vector(body.velocity).is_equal(Vector2(0.0, 0.0))  # No y velocity
	Input.action_release("speed_up")


## Tests helper consistency across difficulties.
## @return: void
func test_depletion_helper_difficulties() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root: Node = main_scene.get_node("Player")
	
	# Difficulty 1.0
	var dep_1: float = TestHelpers.calculate_expected_depletion(player_root, 1.0)
	assert_float(dep_1).is_equal_approx(0.350631, 0.001)  # Real calc: 1 * (250/713) * 1
	
	# Difficulty 2.0
	var dep_2: float = TestHelpers.calculate_expected_depletion(player_root, 2.0)
	assert_float(dep_2).is_equal_approx(0.701262, 0.001)  # 1 * (250/713) * 2
	
	# Difficulty 0.5
	var dep_05: float = TestHelpers.calculate_expected_depletion(player_root, 0.5)
	assert_float(dep_05).is_equal_approx(0.175315, 0.001)  # 1 * (250/713) * 0.5


# Test: Speed bar colors at various thresholds
func test_speed_colors() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var hud: Panel = main_scene.get_node("PlayerStatsPanel")
	var speed_bar: ProgressBar = hud.speed_bar
	
	# NEW: Calculate thresholds dynamically using the Resource
	var max_s: float = Globals.settings.max_speed
	var min_s: float = Globals.settings.min_speed
	
	# Normal (green) - derive mid-safe speed 
	hud._current_speed = (min_s + max_s) / 2.0
	hud.update_speed_bar()
	var style: StyleBoxFlat = speed_bar.get_theme_stylebox("fill").duplicate()
	assert_that(style.bg_color).is_equal(Color.GREEN)
	
	# Approaching high (yellow lerp)
	var high_yellow: float = max_s * Globals.settings.high_yellow_fraction
	var high_red: float = max_s * hud.HIGH_RED_FRACTION
	var mid_high_yellow: float = high_yellow + (high_red - high_yellow) / 2.0 
	hud._current_speed = mid_high_yellow
	hud.update_speed_bar()
	style = speed_bar.get_theme_stylebox("fill").duplicate()
	assert_bool(style.bg_color.is_equal_approx(Color.GREEN.lerp(Color.YELLOW, 0.5))).is_true()
	
	# Overspeed (red lerp)
	var mid_high_red: float = high_red + (max_s - high_red) / 2.0
	hud._current_speed = mid_high_red
	hud.update_speed_bar()
	style = speed_bar.get_theme_stylebox("fill").duplicate()
	assert_bool(style.bg_color.is_equal_approx(Color.YELLOW.lerp(hud.DARK_RED, 0.5))).is_true()
	
	# Approaching low (yellow lerp)
	var low_yellow: float = min_s + (max_s - min_s) * Globals.settings.low_yellow_fraction
	var low_red: float = min_s
	var mid_low_yellow: float = low_yellow - (low_yellow - low_red) / 2.0
	hud._current_speed = mid_low_yellow
	hud.update_speed_bar()
	style = speed_bar.get_theme_stylebox("fill").duplicate()
	assert_bool(style.bg_color.is_equal_approx(Color.GREEN.lerp(Color.YELLOW, 0.5))).is_true()
	
	# Low red at min
	hud._current_speed = min_s
	hud.update_speed_bar()
	style = speed_bar.get_theme_stylebox("fill").duplicate()
	assert_that(style.bg_color).is_equal(hud.DARK_RED)


# Test: Fuel initialization and depletion logic
func test_fuel_depletion() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root: Node = main_scene.get_node("Player")
	var hud: Panel = main_scene.get_node("PlayerStatsPanel")
	
	# Initial state
	assert_float(Globals.settings.current_fuel).is_equal(Globals.settings.max_fuel)
	assert_float(hud.fuel_bar.value).is_equal(Globals.settings.max_fuel)
	
	# Simulate one timer tick
	# CHANGED: Use current_speed
	var normalized_speed: float = player_root.current_speed / Globals.settings.max_speed
	var expected_depletion: float = Globals.settings.base_consumption_rate * normalized_speed * Globals.settings.difficulty
	
	player_root._on_fuel_timer_timeout()
	
	assert_float(Globals.settings.current_fuel).is_equal_approx(Globals.settings.max_fuel - expected_depletion, 0.1)
	assert_float(hud.fuel_bar.value).is_equal_approx(Globals.settings.max_fuel - expected_depletion, 0.1) 
	
	# Force zero fuel
	Globals.settings.current_fuel = 0.0
	
	player_root._on_fuel_timer_timeout()
	# CHANGED: Use current_speed
	assert_float(player_root.current_speed).is_equal(0.0)
	assert_bool(player_root.fuel_timer.is_stopped()).is_true()
