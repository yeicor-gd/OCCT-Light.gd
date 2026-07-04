@tool
extends Node3D
class_name MazeGenerator

@export var seed_value := 0

@export_group("Settings")
@export_range(1, 50) var maze_outer_radius := 2.5
@export_range(0.0, 5) var maze_inner_radius := 0.5
@export_range(0.1, 1) var ball_radius := 0.5
@export_range(0.5, 1.0) var ball_to_path_min_ratio := 0.75

@export_group("")
@export_tool_button("Regenerate")
var regenerate_ := regenerate

func regenerate():
	pass
