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

var resolved_next_scene: String = ""
var loader_progress: float = 0.0  # Current smoothed progress value.
var min_load_time: float = 1.0  # Minimum splashing time in seconds for visibility.
var load_start_time: float = 0.0  # Timestamp when splashing starts.
var is_scene_loaded: bool = false  # Flag to track if the scene is fully loaded.
var scene: PackedScene = null  # Holder for the loaded scene.
var load_failed: bool = false  # Flag if splashing request failed.
var transitioning: bool = false  # Flag to prevent multiple scene changes.
var label_text: String = "Loading: "

@onready var progress_bar: ProgressBar = $ProgressBar  # Progress bar UI element.
@onready var label: Label = $Label  # Label for displaying loading status.


# Polls loading status and updates UI. Changes scene when loaded.
# Eliminated fake_progress; relies on real ResourceLoader progress.
func _process(_delta: float) -> void:
	var elapsed_time: float = (Time.get_ticks_msec() / 1000.0) - load_start_time

	var real_progress: float = 0.0
	if is_scene_loaded:
		real_progress = 100.0  # Force 100% if already loaded (ignores post-load status).
	elif load_failed:
		real_progress = 0.0  # Keep at 0 if failed early.
	else:
		# Only poll if not done.
		var progress_array: Array = []
		var status: int = ResourceLoader.load_threaded_get_status(
			Globals.next_scene, progress_array
		)

		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if progress_array.size() > 0:
				real_progress = progress_array[0] * 100.0  # Convert to percentage.
			else:
				Globals.log_message(
					"Progress array empty during IN_PROGRESS.", Globals.LogLevel.WARNING
				)

		elif status == ResourceLoader.THREAD_LOAD_LOADED:
			real_progress = 100.0
			if not is_scene_loaded:
				is_scene_loaded = true
				scene = ResourceLoader.load_threaded_get(Globals.next_scene)
				Globals.log_message("Scene loaded successfully.", Globals.LogLevel.DEBUG)

		elif (
			status == ResourceLoader.THREAD_LOAD_FAILED
			or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
		):
			Globals.log_message("Loading failed or invalid.", Globals.LogLevel.ERROR)
			load_failed = true

	# Use real progress only (eliminates fake_progress process).
	# Sub-threads + Web min_load_time fix 50% quirk and give breathing room.
	var display_progress: float = real_progress
	if load_failed:
		display_progress = 100.0  # Force end on failure.

	# Smooth progress with lerp.
	loader_progress = lerp(loader_progress, display_progress, 0.01)
	# Update UI.
	progress_bar.value = loader_progress
	label.text = label_text + str(int(loader_progress)) + "%"

	# Proceed only when both loaded (or failed fallback) and minimum time elapsed.
	if (is_scene_loaded or load_failed) and elapsed_time >= min_load_time and not transitioning:
		transitioning = true  # Lock to prevent re-entry.
		loader_progress = 100.0
		progress_bar.value = 100.0
		label.text = label_text + "100%"

		# Optional delay at 100%.
		await get_tree().create_timer(1.5).timeout

		var target_path: String = Globals.next_scene  # Cache the path.
		Globals.next_scene = ""  # Reset to avoid stale values.

		if target_path == "":
			Globals.log_message(
				"Empty next_scene - returning to main menu.", Globals.LogLevel.ERROR
			)
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		elif load_failed:
			# Fallback to direct load on failure
			Globals.log_message("Fallback: Loading scene directly.", Globals.LogLevel.WARNING)
			get_tree().change_scene_to_file(target_path)
		else:
			# Change scene.
			get_tree().change_scene_to_packed(scene)
