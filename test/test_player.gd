# test_player.gd
# Unit tests for player.gd using GdUnit4 in Godot 4.4
# All tests now use manual scene instantiation (no GdUnitSceneRunner)
# This avoids version-specific API issues and gives full control.

extends GdUnitTestSuite

@warning_ignore("unused_parameter")
@warning_ignore("return_value_discarded")

func before() -> void:
	Globals.difficulty = 2.0

func after() -> void:
	pass

# Test: Player node exists and is visible
func test_player_present() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root : Node2D = main_scene.get_node("Player")
	assert_object(player_root).is_not_null()
	assert_bool(player_root.visible).is_true()
	assert_bool(player_root.is_inside_tree()).is_true()

# Test: Fuel initialization and depletion logic
func test_fuel_depletion() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root: Node = main_scene.get_node("Player")
	
	# Initial state
	assert_float(player_root.current_fuel).is_equal(player_root.max_fuel)
	assert_float(player_root.fuel_bar.value).is_equal(100.0)
	
	# Simulate one timer tick
	player_root._on_fuel_timer_timeout()
	assert_float(player_root.current_fuel).is_equal(99.0)
	assert_float(player_root.fuel_bar.value).is_equal(99.0)
	
	# Force zero fuel
	player_root.current_fuel = 0.0
	player_root._on_fuel_timer_timeout()
	assert_float(player_root.speed).is_equal(0.0)
	assert_bool(player_root.fuel_timer.is_stopped()).is_true()

# Test: Player movement with input actions
func test_movement() -> void:
	var main_scene: Node= auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root : Node = main_scene.get_node("Player")
	var body : CharacterBody2D = player_root.player
	
	# Left movement
	Input.action_press("move_left")
	player_root._physics_process(1.0/60.0)
	assert_vector(body.velocity).is_equal(Vector2(-250.0, 0.0))
	Input.action_release("move_left")
	
	# Up movement
	Input.action_press("speed_up")
	player_root._physics_process(1.0/60.0)
	assert_vector(body.velocity).is_equal(Vector2(0.0, -250.0))
	Input.action_release("speed_up")

# Test: Screen boundary clamping
# test_player.gd - Fixed clamping test: use float asserts with approx + epsilon

func test_clamping() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root: Node = main_scene.get_node("Player")
	var body: CharacterBody2D = player_root.player
	
	# Test left/top bounds
	body.position = Vector2(-1000, -1000)
	player_root._physics_process(1.0/60.0)
	assert_float(body.position.x).is_equal(player_root.player_x_min)
	assert_float(body.position.y).is_equal(player_root.player_y_min)
	
	# Test right/bottom bounds
	body.position = Vector2(2000, 2000)
	player_root._physics_process(1.0/60.0)
	assert_float(body.position.x).is_equal(player_root.player_x_max)
	assert_float(body.position.y).is_equal(player_root.player_y_max)


# Test: Fuel bar color changes at thresholds
func test_fuel_colors() -> void:
	var main_scene: Node = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root : Node = main_scene.get_node("Player")
	var fuel_bar : ProgressBar = player_root.fuel_bar
	
	# High fuel → Green
	player_root.current_fuel = 95.0
	player_root._on_fuel_timer_timeout()
	var style : StyleBoxFlat = fuel_bar.get_theme_stylebox("fill").duplicate()
	assert_that(style.bg_color).is_equal(Color.GREEN)
	
	# Low fuel → Red
	player_root.current_fuel = 10.0
	player_root._on_fuel_timer_timeout()
	style = fuel_bar.get_theme_stylebox("fill").duplicate()
	assert_that(style.bg_color).is_equal(Color.RED)

# Test: Smooth color lerp between thresholds
func test_fuel_colors_fixed() -> void:
	var main_scene: Node= auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)
	await await_idle_frame()
	
	var player_root : Node = main_scene.get_node("Player")
	var fuel_bar : ProgressBar = player_root.fuel_bar
	
	# Still full → Green
	player_root.current_fuel = 95.0
	player_root._on_fuel_timer_timeout()
	var style : StyleBoxFlat = fuel_bar.get_theme_stylebox("fill").duplicate()
	assert_that(style.bg_color).is_equal(Color.GREEN)
	
	# Between 90% and 50% → Lerp green → yellow
	player_root.current_fuel = 70.0
	player_root._on_fuel_timer_timeout()
	style = fuel_bar.get_theme_stylebox("fill").duplicate()
	var expected := Color.GREEN.lerp(Color.YELLOW, (90.0 - 70.0) / (90.0 - 50.0))
	assert_bool(style.bg_color.is_equal_approx(expected)).is_true()
