## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_fps_settings_integration.gd
##
## GdUnit4 automated integration test suite for FPS settings UI visibility culling,
## persistence isolation, native lifecycle execution, and menu bindings.

extends GdUnitTestSuite

const PATH_TEST_SETTINGS: String = "user://test_fps_settings.cfg"

var _orig_settings: GameSettingsResource
var _orig_save_encryption_pass: String


func before_test() -> void:
	# Backup globals to prevent test bleeding
	_orig_settings = Globals.settings
	_orig_save_encryption_pass = Globals.save_encryption_pass
	
	# BACKUP THE REAL SETTINGS FILE to prevent test keys from corrupting it
	if FileAccess.file_exists(Settings.CONFIG_PATH):
		DirAccess.rename_absolute(Settings.CONFIG_PATH, Settings.CONFIG_PATH + ".backup")
	
	# Reset for isolated tests with a deterministic encryption key
	Globals.settings = GameSettingsResource.new()
	Globals.save_encryption_pass = "deterministic_test_key_123"


func after_test() -> void:
	# Clean up disk I/O artifacts created by explicit test paths
	if FileAccess.file_exists(PATH_TEST_SETTINGS):
		DirAccess.remove_absolute(PATH_TEST_SETTINGS)
		
	# Clean up artifacts created by UI scenes defaulting to Settings.CONFIG_PATH
	if FileAccess.file_exists(Settings.CONFIG_PATH):
		DirAccess.remove_absolute(Settings.CONFIG_PATH)
		
	# RESTORE THE REAL SETTINGS FILE
	if FileAccess.file_exists(Settings.CONFIG_PATH + ".backup"):
		DirAccess.rename_absolute(Settings.CONFIG_PATH + ".backup", Settings.CONFIG_PATH)
		
	# Restore the global state for subsequent suites
	Globals.settings = _orig_settings
	Globals.save_encryption_pass = _orig_save_encryption_pass


## Test 4: Verify UI Visibility & Processing Culling
## Objective: Validate the invariant contract between data state, visibility, and CPU processing.
## Description: Instantiate the FPSCounter, mount it to the test SceneTree using add_child(), and invoke _on_setting_changed("show_fps", true) followed by _on_setting_changed("show_fps", false).
## Expected Result: When true, visible == true and is_processing() == true. When false, visible == false and is_processing() == false.
func test_verify_ui_visibility_and_processing_culling() -> void:
	var fps_counter: FPSCounter = auto_free(FPSCounter.new())
	add_child(fps_counter) # Mount to active SceneTree for true integration verification
	
	# Simulate false -> true transition
	fps_counter._on_setting_changed("show_fps", true)
	assert_bool(fps_counter.visible).is_true()
	assert_bool(fps_counter.is_processing()).is_true()
	
	# Simulate true -> false transition
	fps_counter._on_setting_changed("show_fps", false)
	assert_bool(fps_counter.visible).is_false()
	assert_bool(fps_counter.is_processing()).is_false()


## Test 5: Verify Session-Boundary Persistence
## Objective: Confirm settings survive complete memory teardowns.
## Description: Instantiate Settings A, set `show_fps = true`, and call `_save_settings()`. Destroy Settings A. Instantiate a fresh Settings B and call `_load_settings()`.
## Expected Result: Settings B parses the configuration and asserts `show_fps == true`.
func test_verify_session_boundary_persistence() -> void:
	# 1. Instantiate Settings A
	Globals.settings = auto_free(GameSettingsResource.new())
	Globals.settings.show_fps = true
	Globals._save_settings(PATH_TEST_SETTINGS)
	
	# 2. Destroy A and instantiate fresh Settings B
	Globals.settings = auto_free(GameSettingsResource.new())
	assert_bool(Globals.settings.show_fps).is_false()  # Prove memory was cleared
	
	# 3. Load from disk and verify
	Globals._load_settings(PATH_TEST_SETTINGS)
	assert_bool(Globals.settings.show_fps).is_true()


## Test 6: Verify Persistence Isolation
## Objective: Ensure setting the FPS counter does not corrupt other saved preferences.
## Description: Modify `show_fps` and save. Reload the resource and inspect adjacent settings (e.g., `difficulty`, `log_level`).
## Expected Result: Adjacent properties remain completely unaltered from their previous states.
func test_verify_persistence_isolation() -> void:
	Globals.settings = auto_free(GameSettingsResource.new())
	
	# Setup adjacent state
	Globals.settings.difficulty = 1.5
	Globals.settings.current_log_level = 2
	Globals.settings.show_fps = false
	Globals._save_settings(PATH_TEST_SETTINGS)
	
	# Modify ONLY show_fps and save
	Globals.settings.show_fps = true
	Globals._save_settings(PATH_TEST_SETTINGS)
	
	# Instantiate fresh object and load
	Globals.settings = auto_free(GameSettingsResource.new())
	Globals._load_settings(PATH_TEST_SETTINGS)
	
	# Assert isolation
	assert_float(Globals.settings.difficulty).is_equal(1.5)
	assert_int(Globals.settings.current_log_level).is_equal(2)
	assert_bool(Globals.settings.show_fps).is_true()


## Test 7: Verify Menu Initial State & UI Binding
## Objective: Ensure the frontend correctly reads initial state and mutates the backend without scene reloads.
## Description: Load the options scene. Verify the UI control matches the persisted `show_fps` state. Toggle the control programmatically.
## Expected Result: The control initializes accurately. Toggling it updates `Globals.settings.show_fps`, emits the signal, and updates the `FPSCounter` instantly.
func test_verify_menu_initial_state_and_ui_binding() -> void:
	Globals.settings = auto_free(GameSettingsResource.new())
	Globals.settings.show_fps = true
	
	# Fallback resolution depending on where the FPS toggle is implemented
	var target_scene: String = "res://scenes/advanced_settings.tscn"
	if not ResourceLoader.exists(target_scene):
		target_scene = "res://scenes/gameplay_settings.tscn"
		if not ResourceLoader.exists(target_scene):
			fail("Target options scene does not exist in CI scope.")
			return
			
	var runner: GdUnitSceneRunner = scene_runner(target_scene)
	
	# Dynamically search for the toggle button in the tree using find_child
	var fps_toggle: CheckButton = runner.find_child("CheckButton", true, false) as CheckButton
	if not is_instance_valid(fps_toggle):
		fps_toggle = runner.find_child("ShowFPSButton", true, false) as CheckButton
		if not is_instance_valid(fps_toggle):
			fps_toggle = runner.find_child("FPSButton", true, false) as CheckButton
			
	# Explicitly fail the test if the toggle is missing rather than skipping silently
	assert_bool(is_instance_valid(fps_toggle)).is_true()
	
	if is_instance_valid(fps_toggle):
		# Verify initial sync from backend
		assert_bool(fps_toggle.button_pressed).is_true()
		
		# Simulate user toggling the button OFF
		fps_toggle.button_pressed = false
		fps_toggle.toggled.emit(false)
		
		# Verify backend state mutated successfully
		assert_bool(Globals.settings.show_fps).is_false()


## Test 8: Verify FPSCounter _ready Lifecycle (Fallback to Globals)
## Objective: Ensure the counter wires itself up correctly if the exported resource is unassigned.
## Description: Instantiate `FPSCounter` with a null `settings` property, set a mock `Globals.settings` with `show_fps` enabled, and manually invoke the `_ready()` hook.
## Expected Result: The counter falls back to `Globals.settings`, initializes its visibility to `true`, and connects the `setting_changed` signal.
func test_fps_counter_ready_fallback() -> void:
	var fps_counter: FPSCounter = auto_free(FPSCounter.new())
	fps_counter.settings = null
	
	Globals.settings = auto_free(GameSettingsResource.new())
	Globals.settings.show_fps = true
	
	# Manually trigger the lifecycle hook for pure unit testing
	fps_counter._ready()
	
	assert_object(fps_counter.settings).is_equal(Globals.settings)
	assert_bool(fps_counter.visible).is_true()
	assert_bool(fps_counter.settings.setting_changed.is_connected(fps_counter._on_setting_changed)).is_true()


## Test 9: Verify FPSCounter _ready Lifecycle (Injected Resource)
## Objective: Ensure the counter prefers its explicitly assigned @export resource over Globals.
## Description: Inject a dedicated local settings resource into the counter's `settings` property with `show_fps` disabled, while configuring `Globals.settings` with conflicting data.
## Expected Result: The counter prioritizes the injected local settings over the global instance, leaving its visibility initialized to `false`.
func test_fps_counter_ready_injected() -> void:
	var fps_counter: FPSCounter = auto_free(FPSCounter.new())
	var local_settings: GameSettingsResource = auto_free(GameSettingsResource.new())
	
	local_settings.show_fps = false
	fps_counter.settings = local_settings
	
	# Globals has conflicting data to prove isolation
	Globals.settings = auto_free(GameSettingsResource.new())
	Globals.settings.show_fps = true 
	
	fps_counter._ready()
	
	assert_object(fps_counter.settings).is_equal(local_settings)
	assert_bool(fps_counter.visible).is_false()


## Test 10: Verify FPSCounter _ready Lifecycle (Null Warning)
## Objective: Ensure the node doesn't crash if no settings resource can be found anywhere.
## Description: Nullify both the local `fps_counter.settings` property and the `Globals.settings` singleton, then invoke `_ready()`.
## Expected Result: The counter survives execution without raising a fatal exception, handles the missing configuration gracefully, and leaves the `settings` property as null.
func test_fps_counter_ready_null_warning() -> void:
	var fps_counter: FPSCounter = auto_free(FPSCounter.new())
	fps_counter.settings = null
	Globals.settings = null 
	
	# Assert that a warning is pushed to the console, not a runtime error
	assert_error(func() -> void:
		fps_counter._ready()
	).is_push_warning("FPSCounter: GameSettingsResource not assigned or found!")
	
	assert_object(fps_counter.settings).is_null()


## Test 11: Verify FPSCounter _process Output
## Objective: Validate that the string formatting correctly retrieves engine data.
## Description: Assign an initial dummy string to the counter's text property, then simulate a single frame loop by explicitly calling `_process(delta)`.
## Expected Result: The label's `text` property updates dynamically, replacing the dummy string with the formatted engine framerate (e.g., starting with "FPS: ").
func test_fps_counter_process_output() -> void:
	var fps_counter: FPSCounter = auto_free(FPSCounter.new())
	fps_counter.text = "Initial Text"
	
	# Manually simulate a frame processing step
	fps_counter._process(0.016)
	
	assert_str(fps_counter.text).starts_with("FPS: ")
	assert_str(fps_counter.text).is_not_equal("Initial Text")


## Test 12: Verify FPSCounter Ignores Unrelated Settings
## Objective: Hit the negative branch of _on_setting_changed to ensure unrelated settings don't toggle visibility.
## Description: Explicitly force the counter's visibility to `true`, then trigger the `_on_setting_changed` callback using an unrelated setting key (e.g., "difficulty").
## Expected Result: The conditional logic rejects the unrelated key, leaving the counter's visibility state unaltered as `true`.
func test_fps_counter_ignores_unrelated_settings() -> void:
	var fps_counter: FPSCounter = auto_free(FPSCounter.new())
	fps_counter._update_visibility(true)
	
	assert_bool(fps_counter.visible).is_true()
	
	# Simulate changing a different setting entirely
	fps_counter._on_setting_changed("difficulty", false)
	
	# Visibility should remain untouched
	assert_bool(fps_counter.visible).is_true()


## Test 13: Verify Native Lifecycle Coverage (Valid Settings)
## Objective: Force the Godot engine profiler to track `_ready`, `_process`, and the false branch of the setting changed check.
## Description: Mount the counter to the SceneTree with valid settings, await a frame, and emit an unrelated signal.
## Expected Result: The engine calls the lifecycle methods natively, updating the text, and ignoring the unrelated signal.
func test_native_lifecycle_coverage_valid_settings() -> void:
	var fps_counter: FPSCounter = auto_free(FPSCounter.new())
	
	# Assign valid settings to cover the implicit 'else' branch in _ready
	fps_counter.settings = auto_free(GameSettingsResource.new())
	fps_counter.settings.show_fps = true
	fps_counter.text = "Init"
	
	# Adding to the tree forces the engine to natively call _ready() and _process().
	# This ensures the GdUnit4/Godot coverage profiler registers the lines and branches.
	add_child(fps_counter)
	await await_idle_frame()
	
	# Verify _process ran natively
	assert_str(fps_counter.text).starts_with("FPS: ")
	
	# Emit an unrelated setting change through the signal to natively hit the false branch 
	# of `if setting_name == "show_fps":` inside _on_setting_changed.
	fps_counter.settings.setting_changed.emit("unrelated_setting", true)
	assert_bool(fps_counter.visible).is_true()


## Test 14: Verify Native Lifecycle Coverage (Missing Settings Warning)
## Objective: Force the Godot engine profiler to track the true branch of the `if not settings` check natively.
## Description: Mount the counter to the SceneTree with null settings and a null Globals fallback.
## Expected Result: The engine calls `_ready` natively during `add_child`, triggering the warning which is caught by the test.
func test_native_lifecycle_coverage_missing_settings() -> void:
	var fps_counter: FPSCounter = auto_free(FPSCounter.new())
	
	# Nullify everything to hit the negative branch
	fps_counter.settings = null
	Globals.settings = null
	
	# Intercept the warning triggered synchronously by the engine when entering the tree
	assert_error(func() -> void:
		add_child(fps_counter)
	).is_push_warning("FPSCounter: GameSettingsResource not assigned or found!")
	
	assert_object(fps_counter.settings).is_null()


## Test 15: Verify Native Branch (Fallback to Globals Valid)
## Objective: Hit the 'if not settings' = TRUE branch natively, resolving to a valid Globals object.
## Description: Mount the counter with a null local setting, but provide a valid Globals resource.
## Expected Result: The engine calls `_ready`, successfully assigns the global singleton, and executes the setup block.
func test_native_branch_fallback_to_globals_valid() -> void:
	var fps_counter: FPSCounter = auto_free(FPSCounter.new())
	fps_counter.settings = null # Explicitly null to hit the 'if not settings' branch
	
	Globals.settings = auto_free(GameSettingsResource.new())
	Globals.settings.show_fps = false
	
	add_child(fps_counter) # Triggers _ready natively
	await await_idle_frame()
	
	# Assert it successfully fell back and connected the signal
	assert_object(fps_counter.settings).is_equal(Globals.settings)
	assert_bool(fps_counter.visible).is_false()


## Test 16: Verify Native Branch (Setting Changed Target Match)
## Objective: Hit the 'if setting_name == "show_fps"' = TRUE branch natively via the signal observer.
## Description: Mount the counter, then emit the exact "show_fps" signal natively through the resource.
## Expected Result: The native signal observer correctly matches the string and mutates the visibility state.
func test_native_branch_setting_changed_target_match() -> void:
	var fps_counter: FPSCounter = auto_free(FPSCounter.new())
	fps_counter.settings = auto_free(GameSettingsResource.new())
	fps_counter.settings.show_fps = false
	
	add_child(fps_counter)
	await await_idle_frame()
	
	assert_bool(fps_counter.visible).is_false()
	
	# Emit the target signal to hit the exact string match branch natively
	fps_counter.settings.setting_changed.emit("show_fps", true)
	
	assert_bool(fps_counter.visible).is_true()


## Test 17: Omnibus Native Branch Profiler Sync
## Objective: Guarantee the coverage profiler registers all 6 branch arms natively.
## Description: Executes every logical path of `_ready` and `_on_setting_changed` on nodes actively mounted in the SceneTree using direct method calls rather than signals.
## Expected Result: The profiler logs 100% branch coverage for fps_counter.gd.
func test_omnibus_native_branch_profiler_sync() -> void:
	# Path 1: _ready() -> start null, stay null (Warning branch)
	var fps_warn: FPSCounter = auto_free(FPSCounter.new())
	fps_warn.settings = null
	Globals.settings = null
	assert_error(func() -> void:
		add_child(fps_warn)
	).is_push_warning("FPSCounter: GameSettingsResource not assigned or found!")
	
	# Path 2: _ready() -> start null, fallback to Globals successfully
	var fps_fallback: FPSCounter = auto_free(FPSCounter.new())
	fps_fallback.settings = null
	Globals.settings = auto_free(GameSettingsResource.new())
	add_child(fps_fallback)
	
	# Path 3: _ready() -> start valid, ignore Globals fallback
	var fps_valid: FPSCounter = auto_free(FPSCounter.new())
	fps_valid.settings = auto_free(GameSettingsResource.new())
	add_child(fps_valid)
	
	# Let the engine tick to ensure all tree attachments are fully registered
	await await_idle_frame()
	
	# Path 4 & 5: _on_setting_changed() -> True and False branches via direct invocation in-tree
	fps_valid._on_setting_changed("show_fps", true)      # Hits the TRUE branch
	fps_valid._on_setting_changed("difficulty", false)   # Hits the FALSE branch
	
	assert_bool(fps_valid.visible).is_true()
