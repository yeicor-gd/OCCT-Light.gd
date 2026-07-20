@tool
extends Node3D
class_name MazeGenerator

## Top-level maze configuration and generator.
## This node holds the global parameters shared by all child systems.

# -----------------------------------------------------------------------------
# Global config
# -----------------------------------------------------------------------------

## Random seed for reproducible maze generation.
@export var seed_source := "Default"
@onready var seed_value := hash(seed_source)

@export_group("Maze Dimensions")

## Outer radius of the spherical shell.
@export_range(1.0, 50.0) var maze_outer_radius := 20.0
## Inner radius of the spherical shell (central void).
@export_range(0.0, 25.0) var maze_inner_radius := 10.0
## Radius of the ball that will traverse the maze.
@export_range(0.1, 2.0) var ball_radius := 1.0
## Minimum ratio of path width and height to ball radius.
@export var ball_to_path_min_ratio := Vector2(0.75, 0.9)

@export_group("Actions")

@export_tool_button("Regenerate All")
var regenerate_all_ := func(): await regenerate_all(false)

# -----------------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------------

signal paths_generation_started
signal paths_generation_finished(elapsed_ms: float)
signal mesh_generation_finished(total_ms: float, paths_ms: float, mesh_ms: float)

# -----------------------------------------------------------------------------
# Actions
# -----------------------------------------------------------------------------

## Regenerate everything: paths (main + shortcuts) + OCCT mesh.
func regenerate_all(sync: bool):
	# Refresh seed in case seed_source was changed externally.
	seed_value = hash(seed_source)

	var total_start := Time.get_ticks_usec()

	# 1. Regenerate all paths (main, binormal, shortcuts).
	paths_generation_started.emit()
	var paths_start := Time.get_ticks_usec()
	if not sync: await $Paths.regenerate(sync)
	else: $Paths.regenerate(sync)
	var paths_ms := (Time.get_ticks_usec() - paths_start) / 1000.0
	paths_generation_finished.emit(paths_ms)

	# 2. Regenerate OCCT mesh.
	var mesh_start := Time.get_ticks_usec()
	if not sync: await $Meshes.regenerate(sync)
	else: $Meshes.regenerate(sync)
	var mesh_ms := (Time.get_ticks_usec() - mesh_start) / 1000.0

	# 3. Regenerate markers if present.
	var markers := get_node_or_null("Markers")
	if markers and markers.has_method("_build_markers"):
		markers._build_markers()

	var total_ms := (Time.get_ticks_usec() - total_start) / 1000.0
	mesh_generation_finished.emit(total_ms, paths_ms, mesh_ms)
	print("[Maze] Total generation time: ", total_ms, "ms (paths: ", paths_ms, "ms, mesh: ", mesh_ms, "ms)")


## Clear the cached mesh files and regenerate from scratch.
## Safe to call at runtime (e.g. from the settings UI after changing parameters).
func clear_and_regenerate() -> void:
	# Update the seed value in case seed_source changed.
	seed_value = hash(seed_source)

	# Clear persisted mesh cache so they are rebuilt from scratch (editor only).
	if Engine.is_editor_hint():
		var save_path: String = $Meshes.resource_save_path
		if not save_path.is_empty():
			var abs_path := ProjectSettings.globalize_path(save_path)
			if DirAccess.dir_exists_absolute(abs_path):
				var dir := DirAccess.open(save_path)
				if dir:
					dir.list_dir_begin()
					var fname := dir.get_next()
					while fname != "":
						if fname.ends_with(".scn"):
							dir.remove(fname)
						fname = dir.get_next()
					dir.list_dir_end()

	await regenerate_all(false)
