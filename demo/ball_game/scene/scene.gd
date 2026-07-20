@tool
extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Use a timer to defer until the parent generator is fully ready.
	var timer := Timer.new()
	timer.timeout.connect(_sync_from_parent)
	add_child(timer)
	timer.start(0.0)
	if not Engine.is_editor_hint():
		_sync_from_parent()
		visible = true

func _sync_from_parent():
	scale = Vector3.ONE * ($"../Maze".maze_outer_radius / 20)
