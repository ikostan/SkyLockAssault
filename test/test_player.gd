# test_player.gd
# Unit tests for player.gd using GdUnit4 in Godot 4.4
# All tests now use manual scene instantiation (no GdUnitSceneRunner)
# This avoids version-specific API issues and gives full control.

extends GdUnitTestSuite

const TestHelpers = preload("res://test/test_helpers.gd")

@warning_ignore("unused_parameter")
@warning_ignore("return_value_discarded")

func before() -> void:
	Globals.difficulty = 2.0

func after() -> void:
	pass


## Tests shared helper calculates depletion correctly.
## @return: void
func test_shared_depletion_helper() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root: Node = main_scene.get_node("Player")
	Globals.difficulty = 2.0
	
	var expected: float = player_root.base_fuel_drain * (player_root.speed["speed"] / player_root.MAX_SPEED) * Globals.difficulty
	assert_float(TestHelpers.calculate_expected_depletion(player_root, Globals.difficulty)).is_equal_approx(expected, 0.001)


# Test: Player node exists and is visible
func test_player_present() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root : Node2D = main_scene.get_node("Player")
	assert_object(player_root).is_not_null()
	assert_bool(player_root.visible).is_true()
	assert_bool(player_root.is_inside_tree()).is_true()

# Test: Screen boundary clamping
# test_player.gd - Fixed clamping test: use float asserts with approx + epsilon
# test_player.gd - Final fix for test_clamping: use approx comparison for floats
# test_player.gd - Fixed is_equal_approx() error in test_clamping
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
	
	var player_root : Node = main_scene.get_node("Player")
	var fuel_bar : ProgressBar = player_root.fuel["bar"]
	
	# High fuel → Green
	player_root.fuel["fuel"] = 95.0
	player_root.update_fuel_bar()
	var style_1 : StyleBoxFlat = fuel_bar.get_theme_stylebox("fill").duplicate()
	assert_that(style_1.bg_color).is_equal(Color.GREEN)
		
	# Low fuel → Dark Red (consistent with gradual depletion)
	player_root.fuel["fuel"] = 10.0
	player_root.update_fuel_bar()
	var style_2 : StyleBoxFlat = fuel_bar.get_theme_stylebox("fill").duplicate()
	assert_that(style_2.bg_color).is_equal(Color(0.5, 0, 0, 1.0))  # Or Color(0.5, 0.0, 0.0) if using floats


# Test: Smooth color lerp between thresholds
func test_fuel_colors_fixed() -> void:
	var main_scene: Node= auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root : Node = main_scene.get_node("Player")
	var fuel_bar : ProgressBar = player_root.fuel["bar"]
	
	# Still full → Green
	player_root.fuel["fuel"] = 95.0
	player_root.update_fuel_bar()
	var style : StyleBoxFlat =  player_root.fuel["bar"].get_theme_stylebox("fill").duplicate()
	assert_that(style.bg_color).is_equal(Color.GREEN)
	
	# Between 90% and 50% → Lerp green → yellow
	player_root.fuel["fuel"] = 70.0
	player_root.update_fuel_bar()
	style = fuel_bar.get_theme_stylebox("fill").duplicate()
	var expected := Color.GREEN.lerp(Color.YELLOW, (90.0 - 70.0) / (90.0 - 50.0))
	assert_bool(style.bg_color.is_equal_approx(expected)).is_true()


# Test: Gradual fuel color change to dark red
func test_fuel_gradual_depletion_colors() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root: Node = main_scene.get_node("Player")
	
	# Start at 30% (should be red)
	player_root.fuel["fuel"] = 30.0
	player_root.update_fuel_bar()
	var style: StyleBoxFlat = player_root.fuel["bar"].get_theme_stylebox("fill").duplicate()
	assert_that(style.bg_color).is_equal(Color.RED)
	
	# Drop to 15% (dark red)
	player_root.fuel["fuel"] = 15.0
	player_root.update_fuel_bar()
	style = player_root.fuel["bar"].get_theme_stylebox("fill").duplicate()
	assert_that(style.bg_color).is_equal(Color(0.5, 0, 0))
	
	# Drop to 10% (still dark red)
	player_root.fuel["fuel"] = 10.0
	player_root.update_fuel_bar()
	style = player_root.fuel["bar"].get_theme_stylebox("fill").duplicate()
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
# Test: Independent blinking for fuel and speed labels
func test_independent_blinking() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root: Node = main_scene.get_node("Player")
	
	# Force low fuel and high speed to trigger both
	player_root.fuel["fuel"] = 10.0
	player_root.speed["speed"] = player_root.speed["max"] * 0.95
	player_root.check_fuel_warning()
	player_root.check_speed_warning()
	
	# Assert both are now at warning color after initial blink start
	assert_that(player_root.get_label_text_color(player_root.fuel["label"])).is_equal(player_root.fuel["warning_color"])
	assert_that(player_root.get_label_text_color(player_root.speed["label"])).is_equal(player_root.speed["warning_color"])
	
	# Toggle one, other unchanged
	player_root._toggle_label(player_root.fuel)
	assert_that(player_root.get_label_text_color(player_root.fuel["label"])).is_equal(player_root.fuel["base_color"])
	assert_that(player_root.get_label_text_color(player_root.speed["label"])).is_equal(player_root.speed["warning_color"])


# Test: get_label_text_color returns override if set, else theme default
# Test: get_label_text_color_override returns override if set, else theme default
func test_get_label_text_color_override() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root: Node = main_scene.get_node("Player")
	var fuel_label: Label = player_root.fuel["label"]
	
	# Clear any editor-set override to test from clean theme default
	fuel_label.remove_theme_color_override("font_color")
	
	# Assume initial is theme default (not black transparent)
	var initial_color: Color = player_root.get_label_text_color(fuel_label)
	assert_bool(initial_color.is_equal_approx(Color(0, 0, 0, 0))).is_false()
	
	# Set override
	var override_color: Color = Color.BLUE
	fuel_label.add_theme_color_override("font_color", override_color)
	
	# Assert returns override
	assert_that(player_root.get_label_text_color(fuel_label)).is_equal(override_color)
	
	# Remove override
	fuel_label.remove_theme_color_override("font_color")
	
	# Assert back to initial
	assert_that(player_root.get_label_text_color(fuel_label)).is_equal(initial_color)


# Test: rotor_start/stop logs warning on missing AnimatedSprite2D
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
	
	var player_root: Node = main_scene.get_node("Player")
	
	# Normal speed: no blink
	player_root.speed["speed"] = (player_root.speed["min"] + player_root.HIGH_YELLOW_THRESHOLD) / 2.0
	player_root.check_speed_warning()
	assert_bool(player_root.speed["blinking"]).is_false()
	
	# Low yellow: start blink
	player_root.speed["speed"] = player_root.LOW_YELLOW_THRESHOLD - 10.0
	player_root.check_speed_warning()
	assert_bool(player_root.speed["blinking"]).is_true()
	
	# Low red: remains blinking
	player_root.speed["speed"] = player_root.speed["min"] - 1.0
	player_root.check_speed_warning()
	assert_bool(player_root.speed["blinking"]).is_true()
	
	# Back to normal: stop blink
	player_root.speed["speed"] = (player_root.LOW_YELLOW_THRESHOLD + player_root.HIGH_YELLOW_THRESHOLD) / 2.0
	player_root.check_speed_warning()
	assert_bool(player_root.speed["blinking"]).is_false()
	
	# High yellow: start blink
	player_root.speed["speed"] = player_root.HIGH_YELLOW_THRESHOLD + 10.0
	player_root.check_speed_warning()
	assert_bool(player_root.speed["blinking"]).is_true()
	
	# High red: remains blinking
	player_root.speed["speed"] = player_root.HIGH_RED_THRESHOLD + 10.0
	player_root.check_speed_warning()
	assert_bool(player_root.speed["blinking"]).is_true()
	
	# Back to normal: stop blink
	player_root.speed["speed"] = (player_root.LOW_YELLOW_THRESHOLD + player_root.HIGH_YELLOW_THRESHOLD) / 2.0
	player_root.check_speed_warning()
	assert_bool(player_root.speed["blinking"]).is_false()


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
	var initial_speed: float = player_root.speed["speed"]
	Input.action_press("speed_up")
	player_root._physics_process(1.0/60.0)
	assert_float(player_root.speed["speed"]).is_greater(initial_speed)  # Increases speed var
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


# Test: Speed bar colors at various thresholds (fix Color.DARK_RED to custom)
func test_speed_colors() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root: Node = main_scene.get_node("Player")
	var speed_bar: ProgressBar = player_root.speed["bar"]
	
	# Normal (green) - derive mid-safe speed from min/max
	player_root.speed["speed"] = (player_root.speed["min"] + player_root.speed["max"]) / 2.0
	player_root.update_speed_bar()
	var style: StyleBoxFlat = speed_bar.get_theme_stylebox("fill").duplicate()
	assert_that(style.bg_color).is_equal(Color.GREEN)
	
	# Approaching high (yellow lerp) - derive thresholds from fractions
	var high_yellow: float = player_root.MAX_SPEED * player_root.HIGH_YELLOW_FRACTION
	var high_red: float = player_root.MAX_SPEED * player_root.HIGH_RED_FRACTION
	var mid_high_yellow: float = high_yellow + (high_red - high_yellow) / 2.0  # Derive mid-point
	player_root.speed["speed"] = mid_high_yellow
	player_root.update_speed_bar()
	style = speed_bar.get_theme_stylebox("fill").duplicate()
	assert_bool(style.bg_color.is_equal_approx(Color.GREEN.lerp(Color.YELLOW, 0.5))).is_true()
	
	# Overspeed (red lerp) - derive from max
	var mid_high_red: float = high_red + (player_root.speed["max"] - high_red) / 2.0  # Derive mid-point
	player_root.speed["speed"] = mid_high_red
	player_root.update_speed_bar()
	style = speed_bar.get_theme_stylebox("fill").duplicate()
	assert_bool(style.bg_color.is_equal_approx(Color.YELLOW.lerp(player_root.DARK_RED, 0.5))).is_true()
	
	# Approaching low (yellow lerp) - derive low thresholds from fractions
	var low_yellow: float = player_root.MIN_SPEED + (player_root.MAX_SPEED - player_root.MIN_SPEED) * player_root.LOW_YELLOW_FRACTION
	var low_red: float = player_root.MIN_SPEED
	var mid_low_yellow: float = low_yellow - (low_yellow - low_red) / 2.0  # Derive mid-point
	player_root.speed["speed"] = mid_low_yellow
	player_root.update_speed_bar()
	style = speed_bar.get_theme_stylebox("fill").duplicate()
	assert_bool(style.bg_color.is_equal_approx(Color.GREEN.lerp(Color.YELLOW, 0.5))).is_true()
	
	# Low red at min
	player_root.speed["speed"] = player_root.MIN_SPEED
	player_root.update_speed_bar()
	style = speed_bar.get_theme_stylebox("fill").duplicate()
	assert_that(style.bg_color).is_equal(player_root.DARK_RED)


# Test: Fuel initialization and depletion logic
func test_fuel_depletion() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root: Node = main_scene.get_node("Player")
	
	# Initial state
	assert_float(player_root.fuel["fuel"]).is_equal(player_root.fuel["max"])
	assert_float(player_root.fuel["bar"].value).is_equal(100.0)
	
	# Simulate one timer tick (derive expected from constants)
	var normalized_speed: float = player_root.speed["speed"] / player_root.MAX_SPEED
	var expected_depletion: float = player_root.base_fuel_drain * normalized_speed * Globals.difficulty
	player_root._on_fuel_timer_timeout()
	assert_float(player_root.fuel["fuel"]).is_equal_approx(player_root.fuel["max"] - expected_depletion, 0.01)  # Larger delta for float precision
	assert_float(player_root.fuel["bar"].value).is_equal_approx(100.0 - expected_depletion, 0.01)  # Normalized to percent
	
	# Force zero fuel
	player_root.fuel["fuel"] = 0.0
	player_root._on_fuel_timer_timeout()
	assert_float(player_root.speed["speed"]).is_equal(0.0)
	assert_bool(player_root.fuel_timer.is_stopped()).is_true()
