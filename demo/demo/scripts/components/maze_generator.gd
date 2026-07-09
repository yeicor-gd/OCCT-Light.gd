@tool
extends Node3D
class_name MazeGenerator

## Top-level maze configuration and generator.
## This node holds the global parameters shared by all child systems.

# -----------------------------------------------------------------------------
# Global config
# -----------------------------------------------------------------------------

## Random seed for reproducible maze generation.
@export var seed_value := 0

@export_group("Maze Dimensions")

## Outer radius of the spherical shell.
@export_range(1.0, 50.0) var maze_outer_radius := 5.0
## Inner radius of the spherical shell (central void).
@export_range(0.0, 5.0) var maze_inner_radius := 0.5
## Radius of the ball that will traverse the maze.
@export_range(0.1, 1.0) var ball_radius := 0.5
## Minimum ratio of path width to ball radius.
@export_range(0.5, 1.0) var ball_to_path_min_ratio := 0.75

@export_group("Actions")

@export_tool_button("Regenerate All")
var regenerate_all_ := regenerate_all

# -----------------------------------------------------------------------------
# Lazy lookup helpers
# -----------------------------------------------------------------------------

func get_main_path():
	return $Paths/MainPath if has_node("Paths/MainPath") else null

func get_aux_path():
	return $Paths/MainPathBinormal if has_node("Paths/MainPathBinormal") else null

func get_ocl_manager():
	return $OclManager if has_node("OclManager") else null

# -----------------------------------------------------------------------------
# Actions
# -----------------------------------------------------------------------------

## Regenerate everything: path + auxiliary curve + OCCT mesh.
func regenerate_all():
	var start_time := Time.get_ticks_usec()
	
	# 1. Regenerate the main path (rope simulation).
	var main_path = get_main_path()
	await main_path.regenerate(true)

	# 2. Regenerate auxiliary curve (offset).
	var aux_path = get_aux_path()
	aux_path.regenerate()

	# 3. Regenerate OCCT mesh.
	var ocl = get_ocl_manager()
	await ocl.regenerate()

	print("[Maze] Total generation time: ", (Time.get_ticks_usec() - start_time) / 1000.0, "ms")
