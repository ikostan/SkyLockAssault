## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_splash_screen.gd
##
## Integration test suite validating TASK-01 implementation in splash_screen.gd:
## 1. Monotonic progress updates driven through _poll_resource_backend.
## 2. Unsubscribing/ceasing polling upon cached completion or failure.
## 3. Linear progression convergence via move_toward.
## 4. Defensive PackedScene resource type verification via _poll_resource_backend.
## 5. Automatic initialization of load_start_time on _ready().

extends "res://addons/gut/test.gd"

const SPLASH_SCREEN_PATH: String = "res://scenes/splash_screen.tscn"

var splash_instance: Control
var original_next_scene: String
var original_settings: GameSettingsResource


func before_each() -> void:
	original_next_scene = Globals.next_scene
	Globals.next_scene = "res://scenes/main_menu.tscn"
	original_settings = Globals.settings

	# Silence logs during test runs
	Globals.settings = GameSettingsResource.new()
	Globals.settings.current_log_level = 4


func after_each() -> void:
	Globals.next_scene = original_next_scene
	Globals.settings = original_settings
	if is_instance_valid(splash_instance):
		splash_instance.queue_free()


## Factory helper to safely instantiate the full scene layout and resolve @onready nodes
func _create_splash_instance() -> Control:
	assert_true(
		FileAccess.file_exists(SPLASH_SCREEN_PATH), 
		"File integrity check: Scene path '%s' must exist." % SPLASH_SCREEN_PATH
	)
	var scene := load(SPLASH_SCREEN_PATH) as PackedScene
	assert_not_null(scene, "Failed to load splash screen scene from path: %s" % SPLASH_SCREEN_PATH)
	
	var instance := scene.instantiate() as Control
	assert_not_null(instance, "Failed to instantiate splash screen scene layout.")
	add_child_autofree(instance)
	return instance


# ==========================================================================
# 1. LIFECYCLE & INITIALIZATION TESTS
# ==========================================================================

## Asserts that load_start_time is initialized upon entering the scene tree (_ready).
func test_load_start_time_initialized_on_ready() -> void:
	splash_instance = _create_splash_instance()

	assert_gt(
		splash_instance.load_start_time,
		0.0,
		"Regression: load_start_time must be initialized via _ready() upon entering tree."
	)


# ==========================================================================
# 2. MONOTONIC PROGRESS & PRESENTATION PIPELINE TESTS
# ==========================================================================

## Verifies that progress display target is monotonic and does not regress 
## when _poll_resource_backend processes lower progress values from the loader.
func test_monotonic_progress_scaling() -> void:
	splash_instance = _create_splash_instance()
	Globals.next_scene = "res://scenes/main_menu.tscn"

	# Simulate initial higher progress target
	splash_instance.display_target = 60.0
	
	# Request threaded loading to create an active IN_PROGRESS status
	ResourceLoader.load_threaded_request(Globals.next_scene)
	
	# Execute polling; initial loader progress (<60%) must not decrease display_target
	splash_instance._poll_resource_backend()
	
	assert_eq(
		splash_instance.display_target, 
		60.0, 
		"Display target must remain at peak value when _poll_resource_backend runs."
	)


## Verifies that move_toward smoothly steps progress forward deterministically based on delta.
func test_presentation_handler_linear_convergence() -> void:
	splash_instance = _create_splash_instance()
	
	splash_instance.loader_progress = 0.0
	splash_instance.display_target = 100.0
	splash_instance.presentation_speed = 50.0  # 50 units per second

	# Advance by 0.5 seconds -> expected move_toward step = 25.0
	splash_instance._update_presentation_handler(0.5)
	
	assert_eq(
		splash_instance.loader_progress, 
		25.0, 
		"Presentation handler must step progress linearly according to delta * presentation_speed."
	)
	assert_eq(
		splash_instance.progress_bar.value, 
		25.0, 
		"ProgressBar UI value must reflect updated loader_progress."
	)


# ==========================================================================
# 3. BACKEND POLLING & EARLY EXIT SAFEGUARDS
# ==========================================================================

## Ensures backend polling early-returns when the scene is already marked as loaded.
func test_poll_resource_backend_stops_when_loaded() -> void:
	splash_instance = _create_splash_instance()
	
	splash_instance.is_scene_loaded = true
	splash_instance.display_target = 100.0

	# Act: Call backend polling
	splash_instance._poll_resource_backend()

	# Assert display_target was unmodified by any ResourceLoader query
	assert_eq(
		splash_instance.display_target, 
		100.0, 
		"Backend polling must exit immediately when is_scene_loaded flag is true."
	)


## Ensures backend polling sets load_failed and forces target to 100 on non-PackedScene resources.
## Ensures backend polling sets load_failed and forces target to 100 on non-PackedScene resources.
func test_poll_resource_backend_handles_invalid_resource_type() -> void:
	splash_instance = _create_splash_instance()

	# Resolve valid non-PackedScene resource path on disk
	var non_packed_path := "res://scripts/ui/screens/splash_screen.gd"
	if not FileAccess.file_exists(non_packed_path):
		non_packed_path = "res://scripts/splash_screen.gd"

	Globals.next_scene = non_packed_path

	var err := ResourceLoader.load_threaded_request(Globals.next_scene)
	assert_eq(err, OK, "Threaded load request for non-PackedScene resource must succeed.")

	# Wait until threaded loader finishes loading the GDScript resource
	var status: int = ResourceLoader.load_threaded_get_status(Globals.next_scene)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(Globals.next_scene)

	# Execute production backend polling logic
	splash_instance._poll_resource_backend()

	assert_true(
		splash_instance.load_failed,
		"Non-PackedScene resource package must trigger load_failed flag in _poll_resource_backend."
	)
	assert_eq(
		splash_instance.display_target,
		100.0,
		"Failure condition in _poll_resource_backend must push display_target to 100."
	)


# ==========================================================================
# 4. TRANSITION ROUTER DEFENSIVE VALIDATION
# ==========================================================================

## Validates that the transition router respects minimum load time before proceeding.
func test_transition_router_respects_min_load_time() -> void:
	splash_instance = _create_splash_instance()
	
	splash_instance.is_scene_loaded = true
	splash_instance.loader_progress = 100.0
	splash_instance.min_load_time = 10.0  # Set long minimum load time

	splash_instance._evaluate_transition_router()

	assert_false(
		splash_instance.transitioning, 
		"Transition router must lock out scene change until min_load_time has elapsed."
	)
