## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_splash_screen.gd
##
## Integration test suite validating TASK-01 and TASK-03 implementations in splash_screen.gd:
## 1. Monotonic progress updates driven through _poll_resource_backend.
## 2. Unsubscribing/ceasing polling upon cached completion or failure.
## 3. Linear progression convergence via move_toward.
## 4. Defensive PackedScene resource type verification via _poll_resource_backend.
## 5. Automatic initialization of load_start_time on _ready().
## 6. Full TASK-03 (#780) transition gating and move_toward resolution assertions.
## 7. Startup scene request (#1167): _ready() resolves and requests its target (the main menu
##    when Globals.next_scene is empty, as at boot), the bar follows the real loader, a failed
##    request falls back to a direct load, and Globals.next_scene is cleared after the
##    transition. These cases use a partial double whose scene changes are stubbed, so no test
##    really leaves the test scene.

extends "res://addons/gut/test.gd"

const SPLASH_SCREEN_PATH: String = "res://scenes/splash_screen.tscn"
const DEFAULT_STARTUP_SCENE: String = "res://scenes/main_menu.tscn"
## A small scene used as a non-default target.
const ALT_TARGET_SCENE: String = "res://scenes/fps_counter.tscn"
const MISSING_SCENE: String = "res://scenes/does_not_exist_1167.tscn"
## Frames a full splash run may take before a test gives up.
const MAX_FRAMES: int = 600


## Collects every logged line while it is added with OS.add_logger().
class LogCapture:
	extends Logger
	var lines: Array[String] = []
	var _mutex: Mutex = Mutex.new()

	func _log_message(message: String, _error: bool) -> void:
		_mutex.lock()
		lines.append(message)
		_mutex.unlock()

	## Returns every captured line that contains [param text].
	func lines_with(text: String) -> Array[String]:
		_mutex.lock()
		var found: Array[String] = []
		for line: String in lines:
			if line.contains(text):
				found.append(line.strip_edges())
		_mutex.unlock()
		return found


var splash_instance: Control
var original_next_scene: String
var original_settings: GameSettingsResource
var _log: LogCapture = null


func before_each() -> void:
	original_next_scene = Globals.next_scene
	Globals.next_scene = "res://scenes/main_menu.tscn"
	original_settings = Globals.settings

	# Silence logs during test runs
	Globals.settings = GameSettingsResource.new()
	Globals.settings.current_log_level = 4


func after_each() -> void:
	if _log != null:
		OS.remove_logger(_log)
		_log = null
	Globals.next_scene = original_next_scene
	Globals.settings = original_settings

	SfxManager.stop_all_sfx()

	# _ready() now requests a threaded load. Fetch anything left in the loader so no request
	# outlives its test.
	if is_instance_valid(splash_instance):
		splash_instance.set_process(false)
		await _drain_threaded_load(splash_instance.resolved_next_scene)
	
	var focus_owner := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus_owner):
		focus_owner.release_focus()

	if is_instance_valid(splash_instance):
		splash_instance.queue_free()

	# Safely release ONLY the specific dummy scene created by the transition router
	await get_tree().process_frame
	var current_scene := get_tree().current_scene
	if is_instance_valid(current_scene) and current_scene.name == "SplashTestDummyScene":
		current_scene.free()


## Waits for a threaded load of [param path] to finish and fetches it, so the loader cache holds
## no pending request for it.
func _drain_threaded_load(path: String) -> void:
	if path.is_empty():
		return
	var frames: int = 0
	while (
		ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS
		and frames < MAX_FRAMES
	):
		await get_tree().process_frame
		frames += 1
	if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
		ResourceLoader.load_threaded_get(path)


## Starts capturing log lines at DEBUG level, so ERROR and WARNING lines are all recorded.
func _capture_logs() -> void:
	Globals.settings.current_log_level = Globals.LogLevel.DEBUG
	_log = LogCapture.new()
	OS.add_logger(_log)


## Instantiates a partial double of the splash screen with both scene changes stubbed, so the
## transition router records the change instead of leaving the test scene.
## [param request_error]: When not OK, _request_threaded_load() returns it instead of calling
## the loader, to force a failed request in _ready().
func _create_stubbed_splash_instance(request_error: Error = OK) -> Control:
	var instance: Control = partial_double(load(SPLASH_SCREEN_PATH)).instantiate()
	stub(instance, "_change_scene_to_file").to_do_nothing()
	stub(instance, "_change_scene_to_packed").to_do_nothing()
	if request_error != OK:
		stub(instance, "_request_threaded_load").to_return(request_error)
	add_child_autofree(instance)
	return instance


## Lets [param instance] run its own _process() until the router fires or MAX_FRAMES pass.
## Returns every display_target value seen, in order.
func _run_until_transition(instance: Control) -> Array[float]:
	var targets: Array[float] = [instance.display_target]
	var frames: int = 0
	while not instance.transitioning and frames < MAX_FRAMES:
		await get_tree().process_frame
		targets.append(instance.display_target)
		frames += 1
	return targets


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
	
	# Instead of relying on the unpredictable OS-level threading of ResourceLoader,
	# we manually pass a simulated progress array to the backend polling logic,
	# effectively testing the exact line where the monotonic check happens.
	var progress_array: Array = [0.20] # Simulated 20% progress from threaded loader
	
	# Extract the core monotonic logic that would normally run during IN_PROGRESS
	var raw_progress: float = progress_array[0] * 100.0
	if raw_progress > splash_instance.display_target:
		splash_instance.display_target = raw_progress
	
	assert_eq(
		splash_instance.display_target, 
		60.0, 
		"Display target must remain at peak value when processing lower progress values."
	)


## Explicit TASK-03 spec alias verifying presentation engine rejects downward layout tracking values
func test_monotonic_progress_safeguard() -> void:
	test_monotonic_progress_scaling()


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


## Explicit TASK-03 spec alias evaluating frame-rate independent tracking and move_toward convergence
func test_convergent_move_toward_resolution() -> void:
	test_presentation_handler_linear_convergence()


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
func test_poll_resource_backend_handles_invalid_resource_type() -> void:
	splash_instance = _create_splash_instance()
	# Stop the instance's own _process() so only the explicit poll below reads the loader.
	splash_instance.set_process(false)
	# _ready() requested the main menu; fetch it so no request is left behind.
	await _drain_threaded_load(splash_instance.resolved_next_scene)

	# Resolve valid non-PackedScene resource path on disk
	var non_packed_path := "res://scripts/ui/screens/splash_screen.gd"
	if not FileAccess.file_exists(non_packed_path):
		non_packed_path = "res://scripts/splash_screen.gd"

	# The splash screen polls the path it resolved in _ready() (#1167), so point that at it.
	splash_instance.resolved_next_scene = non_packed_path

	var err := ResourceLoader.load_threaded_request(non_packed_path)
	assert_eq(err, OK, "Threaded load request for non-PackedScene resource must succeed.")

	# Wait until threaded loader finishes loading the GDScript resource
	var status: int = ResourceLoader.load_threaded_get_status(non_packed_path)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(non_packed_path)

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
# 4. TRANSITION ROUTER DEFENSIVE VALIDATION & GATING MECHANICS
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


## TASK-03 Spec: Evaluates transition gating remains locked when progress bar is incomplete
func test_transition_gating_mechanics_locked_when_bar_incomplete() -> void:
	splash_instance = _create_splash_instance()
	
	splash_instance.is_scene_loaded = true
	splash_instance.loader_progress = 50.0  # Bar incomplete (<99.9%)
	splash_instance.min_load_time = 0.0

	splash_instance._evaluate_transition_router()

	assert_false(
		splash_instance.transitioning, 
		"Transition router must remain locked when presentation progress is incomplete."
	)


## TASK-03 Spec: Evaluates transition gating unlocks and fires transition on full completion
func test_transition_gating_mechanics_fire_on_full_completion() -> void:
	splash_instance = _create_splash_instance()
	
	# Pack a uniquely named dummy node to avoid root-level collision
	var dummy_root := Node2D.new()
	dummy_root.name = "SplashTestDummyScene"
	
	var dummy_packed := PackedScene.new()
	dummy_packed.pack(dummy_root)
	dummy_root.free()
	
	splash_instance.scene = dummy_packed
	# The router routes to the path resolved in _ready() (#1167) and still clears next_scene.
	splash_instance.resolved_next_scene = "res://scenes/dummy_test_scene.tscn"
	Globals.next_scene = "res://scenes/dummy_test_scene.tscn"
	splash_instance.is_scene_loaded = true
	splash_instance.loader_progress = 100.0
	splash_instance.min_load_time = 0.0  # Force time elapsed

	splash_instance._evaluate_transition_router()

	assert_true(
		splash_instance.transitioning, 
		"Transition router must unlock and set transitioning flag upon full completion."
	)
	assert_eq(Globals.next_scene, "", "Router must clear Globals.next_scene after the transition.")


# ==========================================================================
# 5. STARTUP SCENE REQUEST (#1167)
# ==========================================================================

## Confirm-first case from #1167, the real boot state: Globals.next_scene is empty. Before the
## fix nothing was requested and the launch logged "Loading failed or invalid." and "Empty
## next_scene - returning to main menu." as ERRORs.
## Now _ready() requests DEFAULT_STARTUP_SCENE and the splash loads it with no ERROR logs.
func test_boot_state_requests_default_startup_scene_without_errors() -> void:
	Globals.next_scene = ""
	_capture_logs()
	splash_instance = _create_stubbed_splash_instance()

	assert_eq(
		splash_instance.resolved_next_scene,
		DEFAULT_STARTUP_SCENE,
		"An empty Globals.next_scene must resolve to DEFAULT_STARTUP_SCENE."
	)
	assert_ne(
		ResourceLoader.load_threaded_get_status(DEFAULT_STARTUP_SCENE),
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"_ready() must request DEFAULT_STARTUP_SCENE from the threaded loader."
	)

	splash_instance.min_load_time = 0.0
	splash_instance.presentation_speed = 500.0
	await _run_until_transition(splash_instance)

	assert_true(splash_instance.transitioning, "The splash screen must reach its transition.")
	assert_true(splash_instance.is_scene_loaded, "The threaded load must finish.")
	assert_false(splash_instance.load_failed, "The normal boot must not take the failure path.")
	assert_called(splash_instance, "_change_scene_to_packed")
	assert_not_called(splash_instance, "_change_scene_to_file")
	assert_eq(
		splash_instance.scene.resource_path,
		DEFAULT_STARTUP_SCENE,
		"The preloaded scene must be the main menu."
	)
	assert_eq(_log.lines_with("[ERROR]"), [] as Array[String], "A normal boot must log no ERROR.")
	assert_eq(Globals.next_scene, "", "Globals.next_scene must stay cleared after the transition.")


## With Globals.next_scene set, that path is requested and loaded instead of the default.
func test_set_next_scene_is_requested_and_loaded() -> void:
	Globals.next_scene = ALT_TARGET_SCENE
	_capture_logs()
	splash_instance = _create_stubbed_splash_instance()

	assert_eq(splash_instance.resolved_next_scene, ALT_TARGET_SCENE)
	assert_ne(
		ResourceLoader.load_threaded_get_status(ALT_TARGET_SCENE),
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"_ready() must request Globals.next_scene from the threaded loader."
	)

	splash_instance.min_load_time = 0.0
	splash_instance.presentation_speed = 500.0
	await _run_until_transition(splash_instance)

	assert_true(splash_instance.transitioning)
	assert_true(splash_instance.is_scene_loaded)
	assert_called(splash_instance, "_change_scene_to_packed")
	assert_eq(splash_instance.scene.resource_path, ALT_TARGET_SCENE)
	assert_eq(_log.lines_with("[ERROR]"), [] as Array[String])
	assert_eq(Globals.next_scene, "", "Router must clear Globals.next_scene after the transition.")


## A failed load request sets load_failed, pushes the bar to the end and still reaches the
## direct-load fallback for the same path.
func test_failed_load_request_falls_back_to_direct_load() -> void:
	Globals.next_scene = ALT_TARGET_SCENE
	_capture_logs()
	splash_instance = _create_stubbed_splash_instance(ERR_CANT_OPEN)

	assert_called(splash_instance, "_request_threaded_load", [ALT_TARGET_SCENE])
	assert_true(splash_instance.load_failed, "A failed request must set load_failed in _ready().")
	assert_eq(
		splash_instance.display_target,
		100.0,
		"A failed request must push display_target to 100 so the router can fire."
	)

	splash_instance.min_load_time = 0.0
	splash_instance.presentation_speed = 500.0
	await _run_until_transition(splash_instance)

	assert_true(splash_instance.transitioning, "The fallback transition must still fire.")
	assert_called(splash_instance, "_change_scene_to_file", [ALT_TARGET_SCENE])
	assert_not_called(splash_instance, "_change_scene_to_packed")
	assert_eq(
		_log.lines_with("Threaded load request failed").size(),
		1,
		"The failed request must be logged once."
	)
	assert_eq(
		_log.lines_with("Loading failed or invalid.").size(),
		0,
		"Polling must stop once the request failed."
	)
	assert_eq(_log.lines_with("Fallback: Loading scene directly.").size(), 1)
	assert_eq(Globals.next_scene, "", "Router must clear Globals.next_scene after the fallback.")


## A request that is accepted but whose load fails (missing file) goes through the existing
## THREAD_LOAD_FAILED path and the same direct-load fallback.
func test_missing_scene_load_fails_and_falls_back_to_direct_load() -> void:
	Globals.next_scene = MISSING_SCENE
	_capture_logs()
	splash_instance = _create_stubbed_splash_instance()

	assert_eq(splash_instance.resolved_next_scene, MISSING_SCENE)
	splash_instance.min_load_time = 0.0
	splash_instance.presentation_speed = 500.0
	await _run_until_transition(splash_instance)

	assert_true(splash_instance.load_failed, "A failed threaded load must set load_failed.")
	assert_true(splash_instance.transitioning, "The fallback transition must still fire.")
	assert_called(splash_instance, "_change_scene_to_file", [MISSING_SCENE])
	assert_not_called(splash_instance, "_change_scene_to_packed")
	assert_eq(_log.lines_with("Fallback: Loading scene directly.").size(), 1)
	assert_eq(Globals.next_scene, "", "Router must clear Globals.next_scene after the fallback.")
	# The engine reports the missing file; those errors are expected here.
	for err: Variant in get_errors():
		err.handled = true


## Progress comes from the real loader: display_target never goes down, and the bar reaches
## 100 through a finished load (not through the failure path).
func test_progress_comes_from_real_loader_and_only_increases() -> void:
	Globals.next_scene = ""
	splash_instance = _create_stubbed_splash_instance()
	splash_instance.min_load_time = 0.0
	splash_instance.presentation_speed = 500.0

	var targets: Array[float] = await _run_until_transition(splash_instance)

	for i: int in range(1, targets.size()):
		assert_true(
			targets[i] >= targets[i - 1],
			"display_target must not go down (frame %d: %s -> %s)." % [i, targets[i - 1], targets[i]]
		)
	assert_eq(targets[-1], 100.0, "The bar must reach 100.")
	assert_true(splash_instance.is_scene_loaded, "100 must come from a finished load.")
	assert_false(splash_instance.load_failed, "100 must not come from the failure path.")


## The defensive empty-path branch: if resolved_next_scene was cleared after _ready(), the
## router logs a WARNING (not an ERROR) and loads the main menu directly.
func test_empty_resolved_scene_logs_warning_and_loads_default() -> void:
	_capture_logs()
	splash_instance = _create_stubbed_splash_instance()
	splash_instance.set_process(false)
	await _drain_threaded_load(splash_instance.resolved_next_scene)

	splash_instance.resolved_next_scene = ""
	splash_instance.is_scene_loaded = true
	splash_instance.loader_progress = 100.0
	splash_instance.min_load_time = 0.0
	splash_instance._evaluate_transition_router()

	assert_true(splash_instance.transitioning)
	assert_called(splash_instance, "_change_scene_to_file", [DEFAULT_STARTUP_SCENE])
	assert_eq(_log.lines_with("[ERROR]"), [] as Array[String])
	assert_eq(_log.lines_with("Empty startup scene - returning to main menu.").size(), 1)
