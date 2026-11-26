## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## Splash Screen Script: splash_screen.gd
##
## Loads the startup scene in the background while showing a smooth progress bar.
## In [method _ready] it resolves the target ([member Globals.next_scene], or
## [constant DEFAULT_STARTUP_SCENE] when that is empty, as it is at boot) and requests it through
## [method ResourceLoader.load_threaded_request]. The bar follows the loader's real progress, and
## the screen changes to the loaded scene once it is ready and the minimum time has passed (#1167).
##
## :vartype resolved_next_scene: String
## :vartype progress_bar: ProgressBar
## :vartype label: Label
## :vartype loader_progress: float

extends Control

const DEFAULT_STARTUP_SCENE := "res://scenes/main_menu.tscn"
const TRANSITION_PROGRESS_THRESHOLD: float = 99.9

@export_range(0.0, 500.0, 0.1, "or_greater") var presentation_speed: float:
	get:
		return _presentation_speed
	set(value):
		_presentation_speed = max(0.0, value)

var resolved_next_scene: String = ""  # Scene requested in _ready(); polled and routed to.
var loader_progress: float = 0.0  # Current smoothed progress value.
var display_target: float = 0.0  # Target display progress value.
var min_load_time: float = 1.0  # Minimum splashing time in seconds for visibility.
var load_start_time: float = 0.0  # Timestamp when splashing starts.
var is_scene_loaded: bool = false  # Flag to track if the scene is fully loaded.
var scene: PackedScene = null  # Holder for the loaded scene.
var load_failed: bool = false  # Flag if splashing request failed.
var transitioning: bool = false  # Flag to prevent multiple scene changes.
var label_text: String = "Loading: "

var _presentation_speed: float = 50.0

@onready var progress_bar: ProgressBar = $ProgressBar  # Progress bar UI element.
@onready var label: Label = $Label  # Label for displaying loading status.


func _ready() -> void:
	load_start_time = Time.get_ticks_msec() / 1000.0
	resolved_next_scene = (
		Globals.next_scene if not Globals.next_scene.is_empty() else DEFAULT_STARTUP_SCENE
	)
	var err: Error = _request_threaded_load(resolved_next_scene)
	if err != OK:
		Globals.log_message(
			(
				"Threaded load request failed for '%s' (error %d). Loading it directly instead."
				% [resolved_next_scene, err]
			),
			Globals.LogLevel.ERROR
		)
		load_failed = true
		# Polling stops once load_failed is set, so push the bar to the end here; otherwise the
		# router would wait forever for TRANSITION_PROGRESS_THRESHOLD.
		display_target = 100.0


func _process(delta: float) -> void:
	_poll_resource_backend()
	_update_presentation_handler(delta)
	_evaluate_transition_router()


## State 1: Resource polling backend.
## Polls status until cache state is reached or failure occurs.
func _poll_resource_backend() -> void:
	# Immediately stop polling if already marked as loaded or failed
	if is_scene_loaded or load_failed:
		return

	var progress_array: Array = []
	var status: int = ResourceLoader.load_threaded_get_status(resolved_next_scene, progress_array)

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if progress_array.size() > 0:
				var backend_progress: float = progress_array[0] * 100.0
				# Preserve strictly monotonic progress scaling
				display_target = max(display_target, backend_progress)
			else:
				Globals.log_message(
					"Progress array empty during IN_PROGRESS.", Globals.LogLevel.WARNING
				)

		ResourceLoader.THREAD_LOAD_LOADED:
			display_target = 100.0
			var loaded_res := ResourceLoader.load_threaded_get(resolved_next_scene)

			# Type check validation on retrieved resource
			if loaded_res is PackedScene:
				scene = loaded_res
				is_scene_loaded = true
				Globals.log_message("Scene loaded successfully.", Globals.LogLevel.DEBUG)
			else:
				Globals.log_message(
					"Loaded resource is null or not a PackedScene.", Globals.LogLevel.ERROR
				)
				load_failed = true

		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			Globals.log_message("Loading failed or invalid.", Globals.LogLevel.ERROR)
			load_failed = true
			display_target = 100.0  # Force target to end on failure fallback


## State 2: Presentation Handler.
## Smoothly steps UI display towards display_target linearly via move_toward.
func _update_presentation_handler(delta: float) -> void:
	loader_progress = move_toward(loader_progress, display_target, presentation_speed * delta)

	# Update visual UI components
	progress_bar.value = loader_progress
	label.text = label_text + str(int(loader_progress)) + "%"


## State 3: Transition Router.
## Evaluates temporal and resource safety flags to switch scene context profiles.
func _evaluate_transition_router() -> void:
	var elapsed_time: float = (Time.get_ticks_msec() / 1000.0) - load_start_time

	# Proceed only when loaded (or failed fallback), display progress >= threshold,
	# and minimum time elapsed.
	if (
		(is_scene_loaded or load_failed)
		and elapsed_time >= min_load_time
		and loader_progress >= TRANSITION_PROGRESS_THRESHOLD
		and not transitioning
	):
		transitioning = true  # Lock to prevent re-entry

		var target_path: String = resolved_next_scene
		Globals.next_scene = ""  # Consumed: clear it so a later loader never sees a stale path.

		if target_path.is_empty():
			# _ready() always resolves a path, so this only happens if it was cleared afterwards.
			Globals.log_message(
				"Empty startup scene - returning to main menu.", Globals.LogLevel.WARNING
			)
			_change_scene_to_file(DEFAULT_STARTUP_SCENE)
		elif load_failed:
			# Fallback to direct load on failure
			Globals.log_message("Fallback: Loading scene directly.", Globals.LogLevel.WARNING)
			_change_scene_to_file(target_path)
		else:
			# Defensive validation before changing scene
			if is_instance_valid(scene) and scene is PackedScene:
				_change_scene_to_packed(scene)
			else:
				Globals.log_message(
					(
						"PackedScene validation failed during scene transition."
						+ " Direct load fallback."
					),
					Globals.LogLevel.ERROR
				)
				_change_scene_to_file(target_path)


## Requests a threaded load of [param path] and returns the loader's result. A separate method
## so tests can force a failed request.
func _request_threaded_load(path: String) -> Error:
	return ResourceLoader.load_threaded_request(path)


## Changes the current scene to the file at [param path]. A separate method so tests can stub
## the scene change.
func _change_scene_to_file(path: String) -> void:
	get_tree().change_scene_to_file(path)


## Changes the current scene to [param packed]. A separate method so tests can stub the scene
## change.
func _change_scene_to_packed(packed: PackedScene) -> void:
	get_tree().change_scene_to_packed(packed)
