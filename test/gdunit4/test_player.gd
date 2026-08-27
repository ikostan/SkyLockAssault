## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_player.gd
##
## GdUnit4 unit tests for player behavior, fuel depletion, movement physics,
## and HUD synchronization under Godot 4.7.1.

extends GdUnitTestSuite

const PlayerScene: PackedScene = preload("res://scenes/Player.tscn")
const PlayerScript = preload("res://scripts/entities/player.gd")
const HUDScript = preload("res://scripts/ui/hud.gd")
const GameSettingsResource = preload("res://scripts/resources/game_settings_resource.gd")
const TestHelpers = preload("res://test/gdunit4/test_helpers.gd")

var original_difficulty: float


func before_test() -> void:
	var settings: GameSettingsResource = Globals.settings as GameSettingsResource
	original_difficulty = settings.difficulty


func after_test() -> void:
	var settings: GameSettingsResource = Globals.settings as GameSettingsResource
	settings.difficulty = original_difficulty


## Validates that the shared calculation helper produces expected depletion values.
func test_shared_depletion_helper() -> void:
	var settings: GameSettingsResource = Globals.settings as GameSettingsResource
	var player_root: PlayerScript = auto_free(PlayerScene.instantiate()) as PlayerScript
	add_child(player_root)
	await await_idle_frame()

	settings.difficulty = 2.0

	var normalized_speed: float = float(player_root.current_speed) / float(settings.max_speed)
	var expected: float = float(settings.base_consumption_rate) * normalized_speed * float(settings.difficulty)
	assert_float(TestHelpers.calculate_expected_depletion(player_root, settings.difficulty)).is_equal_approx(expected, 0.001)


## Verifies that the Player node instantiates properly and enters the scene tree.
func test_player_present() -> void:
	var player_root: PlayerScript = auto_free(PlayerScene.instantiate()) as PlayerScript
	add_child(player_root)
	await await_idle_frame()

	assert_object(player_root).is_not_null()
	assert_bool(player_root.visible).is_true()
	assert_bool(player_root.is_inside_tree()).is_true()


## Verifies boundary clamping physics on the Player CharacterBody2D.
func test_clamping() -> void:
	var main_scene: Node2D = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()

	var player_root: PlayerScript = main_scene.get_node("Player") as PlayerScript
	var body: CharacterBody2D = player_root.player

	# Test left/top bounds
	body.position = Vector2(-1000, -1000)
	player_root._physics_process(1.0 / 60.0)
	assert_float(body.position.x).is_equal_approx(player_root.player_x_min, 0.001)
	assert_float(body.position.y).is_equal_approx(player_root.player_y_min, 0.001)

	# Test right/bottom bounds
	body.position = Vector2(2000, 2000)
	player_root._physics_process(1.0 / 60.0)
	assert_float(body.position.x).is_equal_approx(player_root.player_x_max, 0.001)
	assert_float(body.position.y).is_equal_approx(player_root.player_y_max, 0.001)


## Validates fuel bar stylebox background colors at high and low fuel thresholds.
func test_fuel_colors() -> void:
	var settings: GameSettingsResource = Globals.settings as GameSettingsResource
	var main_scene: Node2D = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()

	var hud: HUDScript = main_scene.get_node("PlayerStatsPanel") as HUDScript

	# High fuel → Green
	settings.current_fuel = settings.max_fuel * 0.95
	hud.update_fuel_bar()
	var style_1: StyleBoxFlat = hud.fuel_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	assert_that(style_1.bg_color).is_equal(Color.GREEN)

	# Low fuel → Dark Red
	settings.current_fuel = settings.max_fuel * 0.10
	hud.update_fuel_bar()
	var style_2: StyleBoxFlat = hud.fuel_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	assert_that(style_2.bg_color).is_equal(Color(0.5, 0, 0, 1.0))


## Validates fuel bar color interpolation between warning thresholds.
func test_fuel_colors_fixed() -> void:
	var settings: GameSettingsResource = Globals.settings as GameSettingsResource
	var main_scene: Node2D = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()

	var hud: HUDScript = main_scene.get_node("PlayerStatsPanel") as HUDScript

	# Full fuel → Green
	settings.current_fuel = settings.max_fuel * 0.95
	hud.update_fuel_bar()
	var style: StyleBoxFlat = hud.fuel_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	assert_that(style.bg_color).is_equal(Color.GREEN)

	# Between 90% and 50% → Lerp green to yellow
	settings.current_fuel = settings.max_fuel * 0.70
	hud.update_fuel_bar()
	style = hud.fuel_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	var expected: Color = Color.GREEN.lerp(Color.YELLOW, (0.90 - 0.70) / (0.90 - 0.50))
	assert_bool(style.bg_color.is_equal_approx(expected)).is_true()


## Validates fuel bar transitions to dark red under critical thresholds.
func test_fuel_gradual_depletion_colors() -> void:
	var settings: GameSettingsResource = Globals.settings as GameSettingsResource
	var main_scene: Node2D = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()

	var hud: HUDScript = main_scene.get_node("PlayerStatsPanel") as HUDScript

	# 30% fuel → Red
	settings.current_fuel = settings.max_fuel * 0.30
	hud.update_fuel_bar()
	var style: StyleBoxFlat = hud.fuel_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	assert_that(style.bg_color).is_equal(Color.RED)

	# 15% fuel → Dark Red
	settings.current_fuel = settings.max_fuel * 0.15
	hud.update_fuel_bar()
	style = hud.fuel_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	assert_that(style.bg_color).is_equal(Color(0.5, 0, 0))

	# 10% fuel → Dark Red
	settings.current_fuel = settings.max_fuel * 0.10
	hud.update_fuel_bar()
	style = hud.fuel_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	assert_that(style.bg_color).is_equal(Color(0.5, 0, 0))


## Ensures rotor starting and stopping executes safely when SFX streams are null.
func test_rotor_null_sfx() -> void:
	var main_scene: Node2D = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()

	var player_root: PlayerScript = main_scene.get_node("Player") as PlayerScript

	player_root.rotor_left_sfx = null
	player_root.rotor_right_sfx = null

	player_root.rotor_start(player_root.rotor_left, player_root.rotor_left_sfx)
	player_root.rotor_start(player_root.rotor_right, player_root.rotor_right_sfx)
	player_root.rotor_stop(player_root.rotor_left, player_root.rotor_left_sfx)
	player_root.rotor_stop(player_root.rotor_right, player_root.rotor_right_sfx)

	assert_bool(player_root.rotor_left.get_node("AnimatedSprite2D").is_playing()).is_false()
	assert_bool(player_root.rotor_right.get_node("AnimatedSprite2D").is_playing()).is_false()


## Validates that fuel and speed warning labels can blink independently.
func test_independent_blinking() -> void:
	var settings: GameSettingsResource = Globals.settings as GameSettingsResource
	var main_scene: Node2D = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()

	var hud: HUDScript = main_scene.get_node("PlayerStatsPanel") as HUDScript

	settings.current_fuel = settings.max_fuel * 0.10
	hud._current_speed = settings.max_speed * 0.95
	hud.check_fuel_warning()
	hud.check_speed_warning()

	assert_that(hud.get_label_text_color(hud.fuel_label)).is_equal(hud._fuel_state["warning_color"])
	assert_that(hud.get_label_text_color(hud.speed_label)).is_equal(hud._speed_state["warning_color"])

	hud._toggle_label(hud._fuel_state)
	assert_that(hud.get_label_text_color(hud.fuel_label)).is_equal(hud._fuel_state["base_color"])
	assert_that(hud.get_label_text_color(hud.speed_label)).is_equal(hud._speed_state["warning_color"])


## Validates color resolution when theme overrides are applied to HUD labels.
func test_get_label_text_color_override() -> void:
	var main_scene: Node2D = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()

	var hud: HUDScript = main_scene.get_node("PlayerStatsPanel") as HUDScript
	var fuel_label: Label = hud.fuel_label

	fuel_label.remove_theme_color_override("font_color")
	var initial_color: Color = hud.get_label_text_color(fuel_label)
	assert_bool(initial_color.is_equal_approx(Color(0, 0, 0, 0))).is_false()

	var override_color: Color = Color.BLUE
	fuel_label.add_theme_color_override("font_color", override_color)
	assert_that(hud.get_label_text_color(fuel_label)).is_equal(override_color)

	fuel_label.remove_theme_color_override("font_color")
	assert_that(hud.get_label_text_color(fuel_label)).is_equal(initial_color)


## Validates graceful handling when AnimatedSprite2D is missing during rotor start/stop.
func test_rotor_missing_anim_sprite() -> void:
	var main_scene: Node2D = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()

	var player_root: PlayerScript = main_scene.get_node("Player") as PlayerScript

	var left_rotor: Node2D = player_root.rotor_left
	var anim_sprite: AnimatedSprite2D = left_rotor.get_node("AnimatedSprite2D")
	left_rotor.remove_child(anim_sprite)

	player_root.rotor_start(left_rotor, player_root.rotor_left_sfx)
	player_root.rotor_stop(left_rotor, player_root.rotor_left_sfx)

	left_rotor.add_child(anim_sprite)
	assert_bool(player_root.rotor_left.get_node("AnimatedSprite2D").is_playing()).is_true()


## Verifies speed blinking behavior across normal, yellow, and red zone thresholds.
func test_speed_blinking_thresholds() -> void:
	var settings: GameSettingsResource = Globals.settings as GameSettingsResource
	var main_scene: Node2D = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()

	var hud: HUDScript = main_scene.get_node("PlayerStatsPanel") as HUDScript

	var max_s: float = settings.max_speed
	var min_s: float = settings.min_speed
	var high_yellow_thresh: float = max_s * settings.high_yellow_fraction
	var high_red_thresh: float = max_s * hud.HIGH_RED_FRACTION
	var low_yellow_thresh: float = min_s + (max_s - min_s) * settings.low_yellow_fraction

	# Normal speed
	hud._current_speed = (settings.min_speed + high_yellow_thresh) / 2.0
	hud.check_speed_warning()
	assert_bool(hud._speed_state["blinking"]).is_false()

	# Low yellow
	hud._current_speed = low_yellow_thresh - 10.0
	hud.check_speed_warning()
	assert_bool(hud._speed_state["blinking"]).is_true()

	# Low red
	hud._current_speed = settings.min_speed - 1.0
	hud.check_speed_warning()
	assert_bool(hud._speed_state["blinking"]).is_true()

	# Normal speed
	hud._current_speed = (low_yellow_thresh + high_yellow_thresh) / 2.0
	hud.check_speed_warning()
	assert_bool(hud._speed_state["blinking"]).is_false()

	# High yellow
	hud._current_speed = high_yellow_thresh + 10.0
	hud.check_speed_warning()
	assert_bool(hud._speed_state["blinking"]).is_true()

	# High red
	hud._current_speed = high_red_thresh + 10.0
	hud.check_speed_warning()
	assert_bool(hud._speed_state["blinking"]).is_true()

	# Normal speed
	hud._current_speed = (low_yellow_thresh + high_yellow_thresh) / 2.0
	hud.check_speed_warning()
	assert_bool(hud._speed_state["blinking"]).is_false()


## Validates lateral movement and forward acceleration input actions.
func test_movement() -> void:
	var main_scene: Node2D = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()

	var player_root: PlayerScript = main_scene.get_node("Player") as PlayerScript
	var body: CharacterBody2D = player_root.player

	# Left movement
	Input.action_press("move_left")
	player_root._physics_process(1.0 / 60.0)
	assert_vector(body.velocity).is_equal(Vector2(-250.0, 0.0))
	Input.action_release("move_left")

	# Speed up
	var initial_speed: float = player_root.current_speed
	Input.action_press("speed_up")
	player_root._physics_process(1.0 / 60.0)
	assert_float(player_root.current_speed).is_greater(initial_speed)
	assert_vector(body.velocity).is_equal(Vector2(0.0, 0.0))
	Input.action_release("speed_up")


## Verifies calculation consistency across varying difficulty levels.
func test_depletion_helper_difficulties() -> void:
	var main_scene: Node2D = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()

	var player_root: PlayerScript = main_scene.get_node("Player") as PlayerScript

	var dep_1: float = TestHelpers.calculate_expected_depletion(player_root, 1.0)
	assert_float(dep_1).is_equal_approx(0.350631, 0.001)

	var dep_2: float = TestHelpers.calculate_expected_depletion(player_root, 2.0)
	assert_float(dep_2).is_equal_approx(0.701262, 0.001)

	var dep_05: float = TestHelpers.calculate_expected_depletion(player_root, 0.5)
	assert_float(dep_05).is_equal_approx(0.175315, 0.001)


## Validates fuel depletion timer ticks and engine shutdown on empty fuel.
func test_fuel_depletion() -> void:
	var settings: GameSettingsResource = Globals.settings as GameSettingsResource
	var main_scene: Node2D = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()

	var player_root: PlayerScript = main_scene.get_node("Player") as PlayerScript
	var hud: HUDScript = main_scene.get_node("PlayerStatsPanel") as HUDScript

	assert_float(settings.current_fuel).is_equal(settings.max_fuel)
	assert_float(hud.fuel_bar.value).is_equal(settings.max_fuel)

	# Simulate timer tick
	var normalized_speed: float = player_root.current_speed / settings.max_speed
	var expected_depletion: float = settings.base_consumption_rate * normalized_speed * settings.difficulty

	player_root._on_fuel_timer_timeout()
	assert_float(settings.current_fuel).is_equal_approx(settings.max_fuel - expected_depletion, 0.1)
	assert_float(hud.fuel_bar.value).is_equal_approx(settings.max_fuel - expected_depletion, 0.1)

	# Force zero fuel
	settings.current_fuel = 0.0
	player_root._on_fuel_timer_timeout()
	assert_float(player_root.current_speed).is_equal(0.0)
	assert_bool(player_root.fuel_timer.is_stopped()).is_true()


## Validates speed bar color transitions across normal, yellow, and red thresholds.
func test_speed_colors() -> void:
	var settings: GameSettingsResource = Globals.settings as GameSettingsResource
	var main_scene: Node2D = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()

	var hud: HUDScript = main_scene.get_node("PlayerStatsPanel") as HUDScript
	var speed_bar: ProgressBar = hud.speed_bar

	var max_s: float = settings.max_speed
	var min_s: float = settings.min_speed

	# Normal (green) – mid-safe speed
	hud._current_speed = (min_s + max_s) / 2.0
	hud.update_speed_bar()
	var style: StyleBoxFlat = speed_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	assert_that(style.bg_color).is_equal(Color.GREEN)

	# Approaching high (green → yellow lerp)
	var high_yellow: float = max_s * settings.high_yellow_fraction
	var high_red: float = max_s * hud.HIGH_RED_FRACTION
	var mid_high_yellow: float = high_yellow + (high_red - high_yellow) / 2.0
	hud._current_speed = mid_high_yellow
	hud.update_speed_bar()
	style = speed_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	assert_bool(style.bg_color.is_equal_approx(Color.GREEN.lerp(Color.YELLOW, 0.5))).is_true()

	# Overspeed (yellow → dark red lerp)
	var mid_high_red: float = high_red + (max_s - high_red) / 2.0
	hud._current_speed = mid_high_red
	hud.update_speed_bar()
	style = speed_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	assert_bool(style.bg_color.is_equal_approx(Color.YELLOW.lerp(hud.DARK_RED, 0.5))).is_true()

	# Approaching low (green → yellow lerp)
	var low_yellow: float = min_s + (max_s - min_s) * settings.low_yellow_fraction
	var low_red: float = min_s
	var mid_low_yellow: float = low_yellow - (low_yellow - low_red) / 2.0
	hud._current_speed = mid_low_yellow
	hud.update_speed_bar()
	style = speed_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	assert_bool(style.bg_color.is_equal_approx(Color.GREEN.lerp(Color.YELLOW, 0.5))).is_true()

	# Low red at minimum speed
	hud._current_speed = min_s
	hud.update_speed_bar()
	style = speed_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	assert_that(style.bg_color).is_equal(hud.DARK_RED)
