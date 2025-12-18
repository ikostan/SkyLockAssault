# test_player.gd (updated for fuel, movement with new inputs, clamping, colors; tests use main_scene for dependencies)
# Uses GdUnit4 (assume installed; install via AssetLib if not).
# Run via GdUnit Inspector or command line.
extends GdUnitTestSuite

@warning_ignore("unused_parameter")
@warning_ignore("return_value_discarded")

## Vars: Scene runner (GdUnitSceneRunner)
var runner: GdUnitSceneRunner

## Setup before all tests (e.g., mock globals)
func before() -> void:
	# float: Set for consistent depletion (0.5 * 2 = 1)
	Globals.difficulty = 2.0

## Teardown after all tests
func after() -> void:
	pass

# Test player node presence/visibility in main scene
func test_player_present() -> void:
	## Load/add main scene (PackedScene)
	var main_scene: Variant = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)  # Add to tree → _ready()
	await await_idle_frame()  # Await frame for @onready
	
	assert_object(main_scene).is_not_null()  # Scene loads
	## Get player node (Node2D) - assuming named "Player" (capital P)
	var player: Node2D = main_scene.get_node("Player")
	assert_object(player).is_instanceof(Node2D)
	assert_object(player).is_not_null()
	assert_bool(player.visible).is_true()  # Post-fade if any
	assert_bool(player.is_inside_tree()).is_true()  # Tree status

# Test fuel init/depletion (simulate _ready/timer)
func test_fuel_depletion() -> void:
	## Use runner on main_scene for fuel_bar dependency
	runner = scene_runner("res://scenes/main_scene.tscn")
	await await_idle_frame()
	
	## Find player root node
	var player_root: Node = runner.find_child("Player")
	assert_object(player_root).is_not_null()
	
	## Assert init (float)
	assert_float(player_root.get("current_fuel")).is_equal(player_root.get("max_fuel"))  # 100.0
	assert_float(player_root.get("fuel_bar").value).is_equal(100.0)
	
	## Simulate timer timeout (call _on_fuel_timer_timeout on player)
	player_root.call("_on_fuel_timer_timeout")
	assert_float(player_root.get("current_fuel")).is_equal(99.0)  # Depletes by 1 (from code)
	assert_float(player_root.get("fuel_bar").value).is_equal(99.0)
	
	## Test zero fuel (set manually)
	player_root.set("current_fuel", 0.0)
	player_root.call("_on_fuel_timer_timeout")  # Should stop timer
	assert_float(player_root.get("speed")).is_equal(0.0)
	assert_bool(player_root.get("fuel_timer").is_stopped()).is_true()

# Test movement with new inputs (simulate _physics_process)
func test_movement() -> void:
	## Use runner on main_scene
	runner = scene_runner("res://scenes/main_scene.tscn")
	await await_idle_frame()
	
	## Find player root
	var player_root: Node = runner.find_child("Player")
	
	## Simulate action (left)
	runner.simulate_action_pressed("move_left")
	await await_idle_frame()
	runner.simulate_frames(1)  # int: Simulates 1 frame (default delta 1/60)
	## Assert velocity (Vector2) on char_body ($CharacterBody2D)
	var char_body: CharacterBody2D = player_root.get("player")
	assert_vector(char_body.velocity).is_equal(Vector2(-250.0, 0.0))  # Left
	
	runner.simulate_action_released("move_left")
	runner.simulate_action_pressed("speed_up")
	await await_idle_frame()
	runner.simulate_frames(1)  # int: Simulates 1 frame (default delta 1/60)
	assert_vector(char_body.velocity).is_equal(Vector2(0.0, -250.0))  # Up (y negative in 2D)
	
	# Add more for down/right/combos if needed

# Test position clamping (simulate move_and_slide)
func test_clamping() -> void:
	## Use runner on main_scene
	runner = scene_runner("res://scenes/main_scene.tscn")
	await await_idle_frame()
	
	## Find player root and re-call _ready to ensure boundaries (viewport sets screen_size)
	var player_root: Node = runner.find_child("Player")
	player_root.call("_ready")  # Re-call to update mins/maxes
	
	## Get char_body
	var char_body: CharacterBody2D = player_root.get("player")
	
	## Set out-of-bound position (Vector2)
	char_body.position = Vector2(-100, -100)  # Direct set
	runner.simulate_frames(1)  # Simulate frame to trigger _physics_process clamps
	assert_vector(char_body.position).is_equal(Vector2(player_root.get("player_x_min"), player_root.get("player_y_min")))
	
	char_body.position = Vector2(1400, 800)
	runner.simulate_frames(1)
	assert_vector(char_body.position).is_equal(Vector2(player_root.get("player_x_max"), player_root.get("player_y_max")))

# Test fuel color changes (simulate _on_fuel_timer_timeout)
func test_fuel_colors() -> void:
	## Use runner on main_scene
	runner = scene_runner("res://scenes/main_scene.tscn")
	await await_idle_frame()
	
	## Find player root
	var player_root: Node = runner.find_child("Player")
	
	## High fuel green (set float)
	player_root.set("current_fuel", 95.0)
	player_root.call("_on_fuel_timer_timeout")  # Updates color
	var fuel_bar: ProgressBar = player_root.get("fuel_bar")
	var fill_style: StyleBoxFlat = fuel_bar.get_theme_stylebox("fill").duplicate()
	assert_that(fill_style.bg_color).is_equal(Color.GREEN)
	
	# Add tests for yellow/red thresholds
	player_root.set("current_fuel", 10.0)
	player_root.call("_on_fuel_timer_timeout")
	fill_style = fuel_bar.get_theme_stylebox("fill").duplicate()
	assert_that(fill_style.bg_color).is_equal(Color.RED)

# Test updated fuel bar color logic.
func test_fuel_colors_fixed() -> void:
	runner = scene_runner("res://scenes/main_scene.tscn")
	await await_idle_frame()
	
	## Find player root
	var player_root: Node = runner.find_child("Player")
	
	player_root.set("current_fuel", 95.0)  # >90
	player_root.call("_on_fuel_timer_timeout")
	var fill_style: StyleBoxFlat = player_root.get("fuel_bar").get_theme_stylebox("fill").duplicate()
	assert_that(fill_style.bg_color).is_equal(Color.GREEN)

	player_root.set("current_fuel", 70.0)  # 50-90
	player_root.call("_on_fuel_timer_timeout")
	fill_style = player_root.get("fuel_bar").get_theme_stylebox("fill").duplicate()
	var expected: Color = Color.GREEN.lerp(Color.YELLOW, (90 - 70) / (90 - 50))  # 0.5
	assert_that(fill_style.bg_color).is_equal_approx(expected)
