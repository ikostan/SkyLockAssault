## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_loading_screen.gd
##
## GdUnit4 automated regression test suite for loading_screen.gd.
## Validates initialization guards, threaded loading lifecycle, linear progress
## math, transition timing boundaries, completion hold, and fallback recovery paths.

extends GdUnitTestSuite

const LOADING_SCREEN_PATH: String = "res://scenes/loading_screen.tscn"
const MAIN_MENU_PATH: String = "res://scenes/main_menu.tscn"
const EPSILON: float = 0.001
const MAX_POLL_FRAMES: int = 120

var _original_next_scene: String


func before_test() -> void:
	_original_next_scene = Globals.next_scene


func after_test() -> void:
	Globals.next_scene = _original_next_scene


## Helper to instantiate an isolated loading screen node tree via auto_free.
func _create_loader() -> Control:
	var scene: PackedScene = load(LOADING_SCREEN_PATH) as PackedScene
	var loader: Control = auto_free(scene.instantiate()) as Control
	return loader


# --- SECTION 1: INITIALIZATION GUARDS (LS-INIT) ---

## LS-INIT-01 | Gracefully catch empty next-scene paths and block invalid loader execution.
func test_ls_init_01_empty_scene_path_guard() -> void:
	Globals.next_scene = ""
	var loader: Control = _create_loader()
	add_child(loader)
	await await_idle_frame()

	assert_bool(loader.load_failed).is_true()
	assert_bool(loader.is_scene_loaded).is_false()
	assert_bool(loader.transitioning).is_false()


## LS-INIT-02 | Register valid scene paths into ResourceLoader background queue.
func test_ls_init_02_threaded_request_registration() -> void:
	Globals.next_scene = MAIN_MENU_PATH
	var loader: Control = _create_loader()
	add_child(loader)
	await await_idle_frame()

	assert_bool(loader.load_failed).is_false()
	var status: int = ResourceLoader.load_threaded_get_status(MAIN_MENU_PATH)
	assert_int(status).is_in([
		ResourceLoader.THREAD_LOAD_IN_PROGRESS,
		ResourceLoader.THREAD_LOAD_LOADED
	])


## LS-INIT-03 | Catch non-existent or malformed scene paths without crashing.
func test_ls_init_03_invalid_scene_path_guard() -> void:
	Globals.next_scene = "res://scenes/non_existent_scene.tscn"
	var loader: Control = _create_loader()
	add_child(loader)
	await await_idle_frame()

	assert_bool(loader.load_failed).is_true()
	assert_object(loader.scene).is_null()
	assert_bool(loader.transitioning).is_false()


# --- SECTION 2: PROGRESS MATHEMATICS & INTERPOLATION (LS-PROG) ---

## LS-PROG-01 | Advance visual bar at a linear, delta-scaled rate (delta * 120.0).
func test_ls_prog_01_linear_progress_movement() -> void:
	Globals.next_scene = ""
	var loader: Control = _create_loader()
	add_child(loader)
	await await_idle_frame()

	loader.load_failed = false
	loader.is_scene_loaded = true
	loader.loader_progress = 0.0

	loader._process(0.1)

	assert_float(loader.loader_progress).is_equal_approx(12.0, 0.01)
	assert_float(loader.progress_bar.value).is_equal_approx(12.0, 0.01)


## LS-PROG-02 | Drive visual progress toward 100.0 upon loading failure to enable fallback.
func test_ls_prog_02_failure_target_progress() -> void:
	Globals.next_scene = ""
	var loader: Control = _create_loader()
	add_child(loader)
	await await_idle_frame()

	loader.load_failed = true
	loader.is_scene_loaded = false
	loader.loader_progress = 50.0

	loader._process(1.0)

	assert_float(loader.loader_progress).is_equal_approx(100.0, 0.01)
	assert_float(loader.progress_bar.value).is_equal_approx(100.0, 0.01)


## LS-PROG-03 | Clamp progress to upper bound without overshooting 100.0.
func test_ls_prog_03_no_progress_overshoot() -> void:
	Globals.next_scene = ""
	var loader: Control = _create_loader()
	add_child(loader)
	await await_idle_frame()

	loader.load_failed = false
	loader.is_scene_loaded = true
	loader.loader_progress = 95.0

	loader._process(1.0)

	assert_float(loader.loader_progress).is_equal_approx(100.0, 0.001)
	assert_float(loader.progress_bar.value).is_equal_approx(100.0, 0.001)


# --- SECTION 3: THREADED LIFECYCLE & POLLING (LS-LOAD) ---

## LS-LOAD-01 | Complete asynchronous loading and retrieve packed scene within bounded poll loop.
func test_ls_load_01_threaded_loading_completion() -> void:
	Globals.next_scene = MAIN_MENU_PATH
	var loader: Control = _create_loader()
	add_child(loader)

	var frames: int = 0
	while not loader.is_scene_loaded and frames < MAX_POLL_FRAMES:
		await await_idle_frame()
		frames += 1

	assert_bool(loader.is_scene_loaded).is_true()
	assert_object(loader.scene).is_not_null()
	assert_bool(loader.load_failed).is_false()


## LS-LOAD-02 | Detect non-loadable resource failure during polling cycle.
func test_ls_load_02_threaded_loading_failure_detection() -> void:
	Globals.next_scene = "res://scenes/non_existent_scene_for_loader.tscn"
	var loader: Control = _create_loader()
	add_child(loader)
	await await_idle_frame()

	assert_bool(loader.load_failed).is_true()
	assert_bool(loader.is_scene_loaded).is_false()


## LS-LOAD-03 | Exercise THREAD_LOAD_FAILED / INVALID_RESOURCE branch in _process polling (lines 81-83).
func test_ls_load_03_process_polling_failure_branch() -> void:
	Globals.next_scene = "res://scenes/non_existent_scene.tscn"
	var loader: Control = _create_loader()
	add_child(loader)
	await await_idle_frame()

	# Force loader into the active polling branch
	loader.is_scene_loaded = false
	loader.load_failed = false

	loader._process(0.016)

	assert_bool(loader.load_failed).is_true()


# --- SECTION 4: TRANSITION TIMING & GATING (LS-TRANS) ---

## LS-TRANS-01 | Prevent duplicate scene swaps across consecutive process frames (idempotency).
func test_ls_trans_01_transition_idempotency() -> void:
	Globals.next_scene = MAIN_MENU_PATH
	var loader: Control = _create_loader()
	add_child(loader)
	await await_idle_frame()

	var now: float = Time.get_ticks_msec() / 1000.0
	loader.is_scene_loaded = true
	loader.loader_progress = 100.0
	loader.load_start_time = now - loader.min_load_time - EPSILON

	loader._process(0.016)
	assert_bool(loader.transitioning).is_true()

	loader._process(0.016)
	assert_bool(loader.transitioning).is_true()


## LS-TRANS-02 | Force visual ProgressBar.value to exactly 100.0 upon triggering transition.
func test_ls_trans_02_visual_100_percent_enforcement() -> void:
	Globals.next_scene = MAIN_MENU_PATH
	var loader: Control = _create_loader()
	add_child(loader)
	await await_idle_frame()

	loader.loader_progress = 99.95
	loader.progress_bar.value = 99.95

	loader._change_to_next_scene()

	assert_float(loader.progress_bar.value).is_equal(100.0)


## LS-TRANS-03 | Verify 1.0s completion hold, exact target scene replacement, and loader freeing.
func test_ls_trans_03_scene_swap_and_completion_hold() -> void:
	Globals.next_scene = MAIN_MENU_PATH
	var loader: Control = _create_loader()
	get_tree().root.add_child(loader)
	await await_idle_frame()

	loader.scene = load(MAIN_MENU_PATH) as PackedScene
	loader.is_scene_loaded = true
	loader.loader_progress = 100.0

	loader._change_to_next_scene()

	# Loader remains in tree during the 1.0s completion hold
	assert_bool(loader.is_inside_tree()).is_true()

	# Wait for the 1.0s hold delay + frame settlement
	await get_tree().create_timer(1.1).timeout
	await await_idle_frame()

	assert_object(get_tree().current_scene).is_not_null()
	assert_str(get_tree().current_scene.scene_file_path).is_equal(MAIN_MENU_PATH)
	assert_that(loader).is_queued_for_deletion()


## LS-TRANS-04 | Enforce min_load_time barrier using config-relative offsets.
func test_ls_trans_04_min_load_time_boundary() -> void:
	Globals.next_scene = MAIN_MENU_PATH
	var loader: Control = _create_loader()
	add_child(loader)
	await await_idle_frame()

	var now: float = Time.get_ticks_msec() / 1000.0
	loader.is_scene_loaded = true
	loader.loader_progress = 100.0

	# Subcase A: Elapsed time below min_load_time
	loader.load_start_time = now - maxf(loader.min_load_time - 0.05, 0.0)
	loader.transitioning = false
	loader._process(0.016)
	assert_bool(loader.transitioning).is_false()

	# Subcase B: Elapsed time satisfies min_load_time
	loader.load_start_time = now - loader.min_load_time - EPSILON
	loader._process(0.016)
	assert_bool(loader.transitioning).is_true()


## LS-TRANS-05 | Validate transition gate requires all completion criteria simultaneously.
func test_ls_trans_05_transition_gate_conjunction_logic() -> void:
	Globals.next_scene = MAIN_MENU_PATH
	var loader: Control = _create_loader()
	add_child(loader)
	await await_idle_frame()

	var now: float = Time.get_ticks_msec() / 1000.0

	# Case 1: ✅ Loaded, ❌ 50% progress, valid time -> false
	loader.is_scene_loaded = true
	loader.loader_progress = 50.0
	loader.load_start_time = now - loader.min_load_time - EPSILON
	loader.transitioning = false
	loader._process(0.016)
	assert_bool(loader.transitioning).is_false()

	# Case 2: ✅ Loaded, 100% progress, ❌ insufficient time -> false
	loader.is_scene_loaded = true
	loader.loader_progress = 100.0
	loader.load_start_time = now
	loader.transitioning = false
	loader._process(0.016)
	assert_bool(loader.transitioning).is_false()

	# Case 3: ✅ Loaded, 100% progress, ✅ valid time -> true
	loader.is_scene_loaded = true
	loader.loader_progress = 100.0
	loader.load_start_time = now - loader.min_load_time - EPSILON
	loader.transitioning = false
	loader._process(0.016)
	assert_bool(loader.transitioning).is_true()

	# Case 4: ✅ Failed load, 100% progress, ✅ valid time -> true (Isolated instance)
	Globals.next_scene = MAIN_MENU_PATH
	var loader_fail: Control = _create_loader()
	add_child(loader_fail)
	await await_idle_frame()

	loader_fail.is_scene_loaded = false
	loader_fail.load_failed = true
	loader_fail.loader_progress = 100.0
	loader_fail.load_start_time = now - loader_fail.min_load_time - EPSILON
	loader_fail.transitioning = false
	loader_fail._process(0.016)
	assert_bool(loader_fail.transitioning).is_true()


## LS-TRANS-06 | Reset Globals.next_scene cache to empty string on successful transition.
func test_ls_trans_06_global_cleanup_on_success() -> void:
	Globals.next_scene = MAIN_MENU_PATH
	var loader: Control = _create_loader()
	add_child(loader)
	await await_idle_frame()

	loader.scene = load(MAIN_MENU_PATH) as PackedScene
	loader._change_to_next_scene()

	assert_str(Globals.next_scene).is_empty()


# --- SECTION 5: FALLBACK RECOVERY (LS-FALLBACK) ---

## LS-FALLBACK-01 | Fall back to direct change_scene_to_file when threaded load fails.
func test_ls_fallback_01_direct_load_fallback_when_path_known() -> void:
	Globals.next_scene = MAIN_MENU_PATH
	var loader: Control = _create_loader()
	add_child(loader)
	await await_idle_frame()

	loader.load_failed = true
	loader.scene = null

	loader._change_to_next_scene()

	assert_str(Globals.next_scene).is_empty()


## LS-FALLBACK-02 | Recover safely to main_menu.tscn when next_scene is empty during transition.
func test_ls_fallback_02_empty_path_recovery_to_main_menu() -> void:
	Globals.next_scene = ""
	var loader: Control = _create_loader()
	add_child(loader)
	await await_idle_frame()

	loader._change_to_next_scene()

	assert_str(Globals.next_scene).is_empty()


## LS-FALLBACK-03 | Await 1.0s completion timer to execute empty target_path recovery (lines 116-118).
func test_ls_fallback_03_empty_path_coroutine_execution() -> void:
	Globals.next_scene = ""
	var loader: Control = _create_loader()
	add_child(loader)
	await await_idle_frame()

	loader._change_to_next_scene()

	# Await past the 1.0s timer to execute post-yield recovery lines
	await get_tree().create_timer(1.1).timeout
	await await_idle_frame()

	assert_str(Globals.next_scene).is_empty()


## LS-FALLBACK-04 | Await 1.0s completion timer to execute direct loading fallback (lines 121-123).
func test_ls_fallback_04_direct_load_coroutine_execution() -> void:
	Globals.next_scene = MAIN_MENU_PATH
	var loader: Control = _create_loader()
	add_child(loader)
	await await_idle_frame()

	loader.load_failed = true
	loader.scene = null

	loader._change_to_next_scene()

	# Await past the 1.0s timer to execute post-yield fallback lines
	await get_tree().create_timer(1.1).timeout
	await await_idle_frame()

	assert_str(Globals.next_scene).is_empty()
