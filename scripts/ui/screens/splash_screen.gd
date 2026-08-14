## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## Splash Screen Script: splash_screen.gd
##
## Manages background splashing of the next scene with smooth progress bar.
## Uses Godot's ResourceLoader for threaded splashing.
## Transitions to the loaded scene upon completion.
##
## :vartype progress_bar: ProgressBar
## :vartype label: Label
## :vartype loader_progress: float

extends Control

const DEFAULT_STARTUP_SCENE := "res://scenes/main_menu.tscn"
const TRANSITION_PROGRESS_THRESHOLD: float = 99.9

var _presentation_speed: float = 50.0

@export_range(0.0, 500.0, 0.1, "or_greater") var presentation_speed: float:
	get:
		return _presentation_speed
	set(value):
		_presentation_speed = max(0.0, value)

var resolved_next_scene: String = ""
var loader_progress: float = 0.0  # Current smoothed progress value.
var display_target: float = 0.0  # Target display progress value.
var min_load_time: float = 1.0  # Minimum splashing time in seconds for visibility.
var load_start_time: float = 0.0  # Timestamp when splashing starts.
var is_scene_loaded: bool = false  # Flag to track if the scene is fully loaded.
var scene: PackedScene = null  # Holder for the loaded scene.
var load_failed: bool = false  # Flag if splashing request failed.
var transitioning: bool = false  # Flag to prevent multiple scene changes.
var label_text: String = "Loading: "

@onready var progress_bar: ProgressBar = $ProgressBar  # Progress bar UI element.
@onready var label: Label = $Label  # Label for displaying loading status.


func _ready() -> void:
	load_start_time = Time.get_ticks_msec() / 1000.0


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
	var status: int = ResourceLoader.load_threaded_get_status(Globals.next_scene, progress_array)

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
			var loaded_res := ResourceLoader.load_threaded_get(Globals.next_scene)

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

		var target_path: String = Globals.next_scene  # Cache the path
		Globals.next_scene = ""  # Reset to avoid stale values

		if target_path == "":
			Globals.log_message(
				"Empty next_scene - returning to main menu.", Globals.LogLevel.ERROR
			)
			get_tree().change_scene_to_file(DEFAULT_STARTUP_SCENE)
		elif load_failed:
			# Fallback to direct load on failure
			Globals.log_message("Fallback: Loading scene directly.", Globals.LogLevel.WARNING)
			get_tree().change_scene_to_file(target_path)
		else:
			# Defensive validation before changing scene
			if is_instance_valid(scene) and scene is PackedScene:
				get_tree().change_scene_to_packed(scene)
			else:
				Globals.log_message(
					(
						"PackedScene validation failed during scene transition."
						+ " Direct load fallback."
					),
					Globals.LogLevel.ERROR
				)
				get_tree().change_scene_to_file(target_path)
