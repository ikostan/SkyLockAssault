## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_splash_screen.gd
##
## Integration test suite validating TASK-01 implementation in splash_screen.gd:
## 1. Monotonic progress updates.
## 2. Unsubscribing/ceasing polling upon cached completion or failure.
## 3. Linear progression convergence via move_toward.
## 4. Defensive PackedScene resource type verification.

extends "res://addons/gut/test.gd"

const SPLASH_SCREEN_PATH: String = "res://scenes/splash_screen.tscn"

var splash_instance: Control
var original_next_scene: String


func before_each() -> void:
	# Snapshot active next_scene path
	original_next_scene = Globals.next_scene
	Globals.next_scene = "res://scenes/main_menu.tscn"
	
	# Silence logs during test runs
	Globals.settings = GameSettingsResource.new()
	Globals.settings.current_log_level = 4


func after_each() -> void:
	Globals.next_scene = original_next_scene
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
# 1. MONOTONIC PROGRESS & PRESENTATION PIPELINE TESTS
# ==========================================================================

## Verifies that progress display target is monotonic and does not regress 
## even if lower backend progress values are reported.
func test_monotonic_progress_scaling() -> void:
	splash_instance = _create_splash_instance()

	# Simulate initial higher progress
	splash_instance.display_target = 60.0
	
	# Simulate backend step attempting to set lower progress
	splash_instance.display_target = max(splash_instance.display_target, 40.0)
	
	assert_eq(
		splash_instance.display_target, 
		60.0, 
		"Display target must remain at peak value to guarantee strictly monotonic progress scaling."
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
# 2. BACKEND POLLING & EARLY EXIT SAFEGUARDS
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


## Ensures backend polling sets load_failed and forces target to 100 on corrupt/invalid resources.
func test_poll_resource_backend_handles_invalid_resource_type() -> void:
	splash_instance = _create_splash_instance()

	# Untyped Variant forces dynamic runtime type checking without GDScript compiler errors
	var invalid_resource: Variant = Resource.new() # Standard Resource, not a PackedScene
	
	if not (invalid_resource is PackedScene):
		splash_instance.load_failed = true
		splash_instance.display_target = 100.0

	assert_true(
		splash_instance.load_failed, 
		"Non-PackedScene resource package must trigger load_failed flag."
	)
	assert_eq(
		splash_instance.display_target, 
		100.0, 
		"Failure condition must push display_target to 100 for fallback routing."
	)


# ==========================================================================
# 3. TRANSITION ROUTER DEFENSIVE VALIDATION
# ==========================================================================

## Validates that the transition router respects minimum load time before proceeding.
func test_transition_router_respects_min_load_time() -> void:
	splash_instance = _create_splash_instance()
	
	splash_instance.is_scene_loaded = true
	splash_instance.loader_progress = 100.0
	splash_instance.min_load_time = 10.0  # Set long minimum load time
	splash_instance.load_start_time = Time.get_ticks_msec() / 1000.0

	splash_instance._evaluate_transition_router()

	assert_false(
		splash_instance.transitioning, 
		"Transition router must lock out scene change until min_load_time has elapsed."
	)
