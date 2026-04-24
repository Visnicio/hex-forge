extends Node


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass
	#copy_base_files("res://resources/tilesets/example_tileset.tres", "user://tilesets/example_tileset.tres")


func copy_base_files(base_file: String, target_file: String) -> void:
	# 1. Check if the source file actually exists
	if not FileAccess.file_exists(base_file):
		printerr("Error: Source file not found: ", base_file)
		return

	# 2. Check if the target directory exists; create it if not.
	var target_dir = base_file.get_base_dir()
	if not DirAccess.dir_exists_absolute(target_dir):
		var err_dir = DirAccess.make_dir_recursive_absolute(target_dir)
		if err_dir != OK:
			printerr("Error creating directory: ", error_string(err_dir))
			return

	# 3. Perform the copy
	var err = DirAccess.copy_absolute(base_file, target_file)

	if err == OK:
		print("Success! File copied to: ", target_file)
	else:
		printerr("Failed to copy file. Error code: ", err)
