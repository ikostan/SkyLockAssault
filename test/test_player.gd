# test_player.gd (updated for fuel, movement with new inputs, clamping, colors; tests isolated funcs/scene)
# Uses GdUnit4 (assume installed; install via AssetLib if not).
# Run via GdUnit Inspector or command line.
extends GdUnitTestSuite

@warning_ignore("unused_parameter")
@warning_ignore("return_value_discarded")

## Vars: Scene runner (GdUnitSceneRunner)
var runner: GdUnitSceneRunner

## Setup before all tests (e.g., mock globals)
func before() -> void:
	pass

## Teardown after all tests
func after() -> void:
	pass

# Test player node presence/visibility in main scene
func test_player_present() -> void:
	## Load/add main scene (PackedScene)
	var main_scene: Variant = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)  # Add to tree → _ready()
	await await_idle_frame()  # Await frame for @onready
	await await_millis(1300)  # Buffer for fades (adjust via logs)
	
	assert_object(main_scene).is_not_null()  # Scene loads
	## Get player node (Node2D)
	var player: Node2D = main_scene.get_node("Player")
	assert_object(player).is_instanceof(Node2D)
	assert_object(player).is_not_null()
	assert_bool(player.visible).is_true()  # Post-fade
	assert_bool(player.is_inside_tree()).is_true()  # Tree status

# Test fuel init/depletion (simulate _ready/timer)
func test_fuel_depletion() -> void:
	## Instance player isolated (Node2D)
	var player_scene: Variant = auto_free(load("res://scenes/player.tscn").instantiate())  # Assume player.tscn exists; adjust path
	add_child(player_scene)
	await await_idle_frame()
	
	## Assert init (float)
	assert_float(player_scene.current_fuel).is_equal(player_scene.max_fuel)  # 100.0
	assert_float(player_scene.fuel_bar.value).is_equal(100.0)
	
	## Simulate timer timeout (call _on_fuel_timer_timeout)
	player_scene._on_fuel_timer_timeout()
	assert_float(player_scene.current_fuel).is_equal(99.0)  # Depletes by 1 (from code)
	assert_float(player_scene.fuel_bar.value).is_equal(99.0)
	
	## Test zero fuel (set manually)
	player_scene.current_fuel = 0.0
	player_scene._on_fuel_timer_timeout()  # Should stop timer
	assert_float(player_scene.speed).is_equal(0.0)
	assert_bool(player_scene.fuel_timer.is_stopped()).is_true()

# Test movement with new inputs (simulate _physics_process)
func test_movement() -> void:
	## Instance player with runner (GdUnitSceneRunner)
	runner = scene_runner("res://scenes/player.tscn")  # Loads/instances scene
	await await_idle_frame()
	
	## Simulate action (left)
	runner.simulate_action_pressed("move_left")
	await await_idle_frame()
	runner.simulate_frame(0.016)  # Simulates _physics_process
	## Assert velocity (Vector2)
	var char_body: CharacterBody2D = runner.get_property("player")
	assert_vector(char_body.velocity).is_equal(Vector2(-250.0, 0.0))  # Left
	
	runner.simulate_action_released("move_left")
	runner.simulate_action_pressed("speed_up")
	await await_idle_frame()
	runner.simulate_frame(0.016)
	assert_vector(char_body.velocity).is_equal(Vector2(0.0, -250.0))  # Up (y negative?)
	
	# Add more for down/right/combos

# Test position clamping (simulate move_and_slide)
func test_clamping() -> void:
	## Instance player with runner (GdUnitSceneRunner)
	runner = scene_runner("res://scenes/player.tscn")
	await await_idle_frame()
	
	## Set bounds (from code; assume screen_size set in _ready)
	runner.set_property("screen_size", Vector2(1280, 720))  # Example
	runner.invoke("_ready")  # Re-call to update mins/maxes
	
	## Set out-of-bound position (Vector2)
	var char_body: CharacterBody2D = runner.get_property("player")
	char_body.position = Vector2(-100, -100)  # Direct set (no set_property for sub-node)
	runner.simulate_frame(0.016)  # Clamps in _physics_process
	assert_vector(char_body.position).is_equal(Vector2(runner.get_property("player_half_width"), runner.get_property("player_half_height")))  # Min clamp
	
	char_body.position = Vector2(1400, 800)
	runner.simulate_frame(0.016)
	assert_vector(char_body.position).is_equal(Vector2(1280 - runner.get_property("player_half_width"), 720 - runner.get_property("player_half_height")))  # Max

# Test fuel color changes (simulate _on_fuel_timer_timeout)
func test_fuel_colors() -> void:
	## Instance player with runner (GdUnitSceneRunner)
	runner = scene_runner("res://scenes/player.tscn")
	await await_idle_frame()
	
	## High fuel green (set float)
	runner.set_property("current_fuel", 95.0)
	runner.invoke("_on_fuel_timer_timeout")  # Updates color
	var fuel_bar: ProgressBar = runner.get_property("fuel_bar")
	var fill_style: StyleBoxFlat = fuel_bar.get_theme_stylebox("fill").duplicate()
	assert_that(fill_style.bg_color).is_equal_approx(Color.GREEN.lerp(Color(0,0,0,0), (100.0 - 95.0) / (100.0 - 90.0)))  # Lerp calc; adjust per code
	
	# Add tests for yellow/red thresholds
	runner.set_property("current_fuel", 10.0)
	runner.invoke("_on_fuel_timer_timeout")
	fill_style = fuel_bar.get_theme_stylebox("fill").duplicate()
	assert_that(fill_style.bg_color).is_equal(Color.RED)
