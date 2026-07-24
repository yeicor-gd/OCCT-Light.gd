## Wires game events (death, win, ball movement) to AudioManager.
extends Node
class_name AudioWiring

@onready var audio: AudioManager = $".."
var _spawner: Spawner
var _jump_connected: bool = false
var _was_grounded := false

func _ready() -> void:
	var maze = get_node_or_null("../../Maze")
	if maze == null:
		return
	_spawner = maze.get_node_or_null("Spawner")
	var death = maze.get_node_or_null("DeathArea")
	var end = maze.get_node_or_null("EndArea")
	if death:
		death.body_entered.connect(_on_death)
	if end:
		end.body_entered.connect(_on_win)

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
		_was_grounded = false
	if _spawner and _spawner.current_player:
		var ball := _spawner.current_player.get_node_or_null("Ball") as RigidBody3D
		if ball:
			var is_grounded: bool = ball.get("grounded") if ball else false
			if is_grounded and not _was_grounded:
				audio.play_sfx("land")
			_was_grounded = is_grounded
