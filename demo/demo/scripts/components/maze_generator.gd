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
@export_range(1.0, 50.0) var maze_outer_radius := 5.0
## Inner radius of the spherical shell (central void).
@export_range(0.0, 5.0) var maze_inner_radius := 0.5
## Radius of the ball that will traverse the maze.
@export_range(0.1, 1.0) var ball_radius := 0.5
## Minimum ratio of path width and height to ball radius.
@export var ball_to_path_min_ratio := Vector2(0.75, 0.9)

@export_group("Actions")

@export_tool_button("Regenerate All")
var regenerate_all_ := func(): await regenerate_all(false)

# -----------------------------------------------------------------------------
# Actions
# -----------------------------------------------------------------------------

## Regenerate everything: path + auxiliary curve + OCCT mesh.
func regenerate_all(sync: bool):
	var start_time := Time.get_ticks_usec()
	
	# 1. Regenerate the main path (rope simulation).
	if not sync: await $Paths/MainPath.regenerate(sync)
	else: $Paths/MainPath.regenerate(sync)

	# 2. Regenerate auxiliary curve (offset).
	$Paths/MainPathBinormal.regenerate()

	# 3. Regenerate OCCT mesh.
	if not sync: await $Meshes.regenerate(sync)
	else: $Meshes.regenerate(sync)

	print("[Maze] Total generation time: ", (Time.get_ticks_usec() - start_time) / 1000.0, "ms")
