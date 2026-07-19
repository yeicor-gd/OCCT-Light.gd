## Wires game events (death, win, ball movement) to AudioManager.
extends Node
class_name AudioWiring

@onready var audio: AudioManager = $"../AudioManager"
var _spawner: Spawner
var _last_ball_speed := 0.0

func _ready() -> void:
	# Find spawner and death/end areas (Maze is a sibling under the same parent)
	var maze = get_node_or_null("../Maze")
	if maze == null:
		return
	_spawner = maze.get_node_or_null("Spawner")
	var death = maze.get_node_or_null("DeathArea")
	var end = maze.get_node_or_null("EndArea")
	death.body_entered.connect(_on_death)
	end.body_entered.connect(_on_win)
	audio.play_background()

func _on_death(_body: Node3D) -> void:
	audio.play_sfx("death")

func _on_win(_body: Node3D) -> void:
	audio.play_sfx("win")

func _process(_delta: float) -> void:
	if _spawner and _spawner.current_player:
		var ball := _spawner.current_player.get_node_or_null("Ball") as RigidBody3D
		if ball:
			var speed := ball.linear_velocity.length()
			_last_ball_speed = speed
