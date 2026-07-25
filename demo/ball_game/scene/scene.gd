@tool
extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var parent := $"../Maze" if has_node("../Maze") else null
	if parent and parent is MazeGenerator:
		parent.regeneration_finished.connect(_sync_from_parent)
	if not Engine.is_editor_hint():
		_sync_from_parent()
		visible = true

func _sync_from_parent():
	scale = Vector3.ONE * ($"../Maze".maze_outer_radius / 20)
