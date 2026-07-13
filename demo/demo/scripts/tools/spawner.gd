@tool
extends Node3D
class_name Spawner

var PlayerScene := preload("res://demo/player.tscn")
var current_player: Player = null

func _ready():
	if Engine.is_editor_hint():
		# Use a timer to defer until the parent generator is fully ready.
		var timer := Timer.new()
		timer.timeout.connect(_sync_from_parent)
		add_child(timer)
		timer.start(0.0)
	else:
		_sync_from_parent()
		respawn.call_deferred()

func respawn():
	if current_player != null:
		current_player.queue_free()
	current_player = PlayerScene.instantiate()
	current_player.name = "Player"
	current_player.set_radius($"..".ball_radius)
	get_parent_node_3d().get_parent_node_3d().add_child(current_player)
	current_player.global_position = global_position

func _sync_from_parent():
	var parent = get_parent_node_3d()
	if parent is MazeGenerator:
		transform.origin = (parent.maze_outer_radius - parent.ball_radius) * Vector3.BACK
