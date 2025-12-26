@tool  # Runs in editor
extends ResourcePreloader

@export var force_reload: bool = false : set = _force_reload

## Forces reload in editor.
## @param value: bool - Toggle value.
## @return: void
func _force_reload(value: bool) -> void:
	if value and Engine.is_editor_hint():
		print("Forcing reload of resources!")
		_ready()
		force_reload = false  # Reset toggle

## Editor-only ready function.
## @return: void
func _ready() -> void:
	print("@tool script starting in editor!")  # Debug to confirm run
	if Engine.is_editor_hint():  # Only run in editor
		print("@tool is in editor hint!")  # Confirm hint check
		# Clear existing preloaded resources to avoid duplicates on reload
		var ids: Array[String] = get_resource_list()
		for id in ids:
			remove_resource(id)
		
		# Load and add bushes
		var bush_dir_path: String = "res://files/trees/"  # Updated to match your structure
		print("Attempting to load bushes from: ", bush_dir_path)
		var bush_textures: Array[Texture2D] = load_textures_from_dir(bush_dir_path)
		for i in bush_textures.size():
			var texture: Texture2D = bush_textures[i]
			if texture:
				add_resource("bush_" + str(i), texture)  # Unique ID for each texture
		print("Editor: Loaded ", bush_textures.size(), " bush textures")
		
		# Load and add decor
		var decor_dir_path: String = "res://files/random_decor/"  # Updated to match your structure
		print("Attempting to load decor from: ", decor_dir_path)
		var decor_textures: Array[Texture2D] = load_textures_from_dir(decor_dir_path)
		for i in decor_textures.size():
			var texture: Texture2D = decor_textures[i]
			if texture:
				add_resource("decor_" + str(i), texture)  # Unique ID for each texture
		print("Editor: Loaded ", decor_textures.size(), " decor textures")

## Helper to scan and load textures from a directory (editor only)
## @param dir_path: String - Directory path.
## @return: Array[Texture2D] - Loaded textures.
func load_textures_from_dir(dir_path: String) -> Array[Texture2D]:
	print("Trying to open directory: ", dir_path)  # Debug path
	var textures: Array[Texture2D] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir:
		print("Directory opened successfully!")  # Confirm open
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		var file_count: int = 0  # Track total files found
		var file_list: String = ""  # To list all files
		while file_name != "":
			file_count += 1
			file_list += file_name + ", "  # Collect all files
			if not dir.current_is_dir() and file_name.ends_with(".png"):
				var texture_path: String = dir_path + file_name
				var texture: Texture2D = load(texture_path)
				if texture:
					textures.append(texture)
					print("Loaded texture: ", texture_path)  # Confirm load
				else:
					print("Warning: Failed to load ", texture_path, " in editor")
			file_name = dir.get_next()
		dir.list_dir_end()
		print("Total files found in directory: ", file_count)
		print("Files list: ", file_list.strip_edges())  # Print all files found
	else:
		print("Error: Could not open directory at ", dir_path)
	return textures
