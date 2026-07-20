## Wires game events (death, win, ball movement) to AudioManager.
extends Node
class_name AudioWiring

@onready var audio: AudioManager = $".."
var _spawner: Spawner
var _last_ball_speed := 0.0
var _jump_connected: bool = false

func _ready() -> void:
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
	if _spawner and _spawner.current_player and not _jump_connected:
		var ball := _spawner.current_player.get_node_or_null("Ball") as RigidBody3D
		if ball and ball.has_signal("jumped"):
			ball.jumped.connect(func(): audio.play_sfx("jump"))
			_jump_connected = true
	if _spawner and not _spawner.current_player:
		_jump_connected = false
	if _spawner and _spawner.current_player:
		var ball := _spawner.current_player.get_node_or_null("Ball") as RigidBody3D
		if ball:
			var speed := ball.linear_velocity.length()
			_last_ball_speed = speed
