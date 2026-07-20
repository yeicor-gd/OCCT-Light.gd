@tool
extends EditorExportPlugin

const BALL_GAME_SCENE := "res://ball_game/game.tscn"

func _get_name() -> String:
	return "DemoExport"


func _export_begin(
		_features: PackedStringArray,
		_is_debug: bool,
		_path: String,
		_flags: int
) -> void:
	var packed_scene := load(BALL_GAME_SCENE) as PackedScene
	if packed_scene == null:
		push_error("Failed to load %s" % BALL_GAME_SCENE)
		return

	var root := packed_scene.instantiate()

	var meshes := root.get_node_or_null("Maze/Meshes")
	if meshes == null:
		push_error("Missing node: Maze/Meshes")
		return

	if meshes.get_child_count() == 0:
		print("Maze is empty; generating before export...")

		var maze := root.get_node_or_null("Maze")
		if maze == null:
			push_error("Missing node: Maze")
			return

		maze.regenerate_all(true)

		var packed := PackedScene.new()
		var err := packed.pack(root)
		if err != OK:
			push_error("Failed to pack scene (%s)." % err)
			return

		err = ResourceSaver.save(packed, BALL_GAME_SCENE)
		if err != OK:
			push_error("Failed to save scene (%s)." % err)
			return

		_add_generated_files(meshes.resource_save_path)
	else:
		push_warning("Reusing previously built maze for export.")


func _add_generated_files(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("Cannot open generated mesh directory: %s" % dir_path)
		return

	dir.list_dir_begin()

	while true:
		var file_name := dir.get_next()
		if file_name.is_empty():
			break

		if dir.current_is_dir():
			continue

		if not file_name.ends_with(".scn"):
			continue

		var virtual_path := dir_path.path_join(file_name)

		var bytes := FileAccess.get_file_as_bytes(virtual_path)
		if bytes.is_empty():
			push_error("Failed to read %s" % virtual_path)
			continue

		add_file(virtual_path, bytes, false)
		print("Added generated export file: %s" % virtual_path)

	dir.list_dir_end()
