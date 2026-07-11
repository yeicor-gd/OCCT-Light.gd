@tool
extends Node3D

func _ready():
	if Engine.is_editor_hint():
		# Use a timer to defer until the parent generator is fully ready.
		var timer := Timer.new()
		timer.timeout.connect(_sync_from_parent)
		add_child(timer)
		timer.start(0.0)
	else:
		_sync_from_parent()
		add_child(preload("res://demo/player.tscn").instantiate())

func _sync_from_parent():
	var parent = get_parent_node_3d()
	if parent is MazeGenerator:
		transform.origin = (parent.maze_outer_radius - parent.ball_radius) * Vector3.BACK
