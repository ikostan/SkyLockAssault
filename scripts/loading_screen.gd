## Loading Screen Script
##
## Manages background loading of the next scene with a smooth progress bar.
## Uses Godot's ResourceLoader for threaded loading.
##
## Transitions to the loaded scene upon completion.
##
## :vartype progress_bar: ProgressBar
## :vartype label: Label
## :vartype loader_progress: float

extends Control

@onready var progress_bar: ProgressBar = $Panel/Container/ProgressBar  # Progress bar UI element.
@onready var label: Label = $Panel/Container/Label  # Label for displaying loading status.

var loader_progress: float = 0.0  # Current smoothed progress value.
var min_load_time: float = 1.0  # Minimum loading time in seconds for visibility (adjust as needed).
var load_start_time: float = 0.0  # Timestamp when loading starts.
var is_scene_loaded: bool = false  # Flag to track if the scene is fully loaded.
var scene: PackedScene = null  # Holder for the loaded scene.
var load_failed: bool = false  # Flag if loading request failed.



# Starts threaded loading of the next scene from Globals.
func _ready() -> void:
	load_start_time = Time.get_ticks_msec() / 1000.0
	Globals.log_message("Loading screen ready. Next scene: " + Globals.next_scene, Globals.LogLevel.DEBUG)
	
	if Globals.next_scene == "":
		Globals.log_message("Next scene path is empty!", Globals.LogLevel.ERROR)
		load_failed = true
		return
	
	# Start background loading.
	var err: int = ResourceLoader.load_threaded_request(Globals.next_scene)
	if err != OK:
		Globals.log_message("Failed to start loading: " + str(err), Globals.LogLevel.ERROR)
		load_failed = true
	else:
		Globals.log_message("Loading started successfully.", Globals.LogLevel.DEBUG)


# Polls loading status and updates UI. Changes scene when loaded.
func _process(_delta: float) -> void:
	var elapsed_time: float = (Time.get_ticks_msec() / 1000.0) - load_start_time
	var fake_progress: float = clamp((elapsed_time / min_load_time) * 100.0, 0.0, 100.0)
	
	# Get loading status.
	var status: int = ResourceLoader.load_threaded_get_status(Globals.next_scene)
	Globals.log_message("Loading status: " + str(status) + " | Elapsed: " + str(elapsed_time), Globals.LogLevel.DEBUG)  # Debug log
	
	var real_progress: float = 0.0
	
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		var progress_array: Array = []
		ResourceLoader.load_threaded_get_status(Globals.next_scene, progress_array)
		real_progress = progress_array[0] * 100.0  # Convert to percentage.
		Globals.log_message("Real progress: " + str(real_progress), Globals.LogLevel.DEBUG)
		
	elif status == ResourceLoader.THREAD_LOAD_LOADED:
		real_progress = 100.0
		if not is_scene_loaded:
			is_scene_loaded = true
			scene = ResourceLoader.load_threaded_get(Globals.next_scene)
			Globals.log_message("Scene loaded successfully.", Globals.LogLevel.DEBUG)
			
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		if not load_failed:
			Globals.log_message("Loading failed or invalid.", Globals.LogLevel.ERROR)
			load_failed = true
	
	# If load failed, use full fake progress to avoid stuck screen
	var display_progress: float = fake_progress if load_failed else min(fake_progress, real_progress)
	
	# Smooth progress with lerp.
	loader_progress = lerp(loader_progress, display_progress, 0.1)
	
	# Update UI.
	progress_bar.value = loader_progress
	
	# Proceed only when both loaded (or failed fallback) and minimum time elapsed.
	if (is_scene_loaded or load_failed) and elapsed_time >= min_load_time:
		# Optional delay at 100%.
		await get_tree().create_timer(0.5).timeout
		
		if load_failed:
			# Fallback to direct load on failure
			Globals.log_message("Fallback: Loading scene directly.", Globals.LogLevel.WARNING)
			get_tree().change_scene_to_file(Globals.next_scene)
		else:
			# Change scene.
			get_tree().change_scene_to_packed(scene)
