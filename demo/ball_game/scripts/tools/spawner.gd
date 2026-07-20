@tool
extends Node3D
class_name Spawner

@export var PlayerScene: PackedScene
var current_player: Player = null
var start_usec: int

@export var ui_overlay: UIOverlay
@export var death_area: DeathArea

@export var scene_node: NodePath
@onready var scene: Node3D = get_node(scene_node)

@export var scene_rotation_speed := 8.0
@onready var target_rotation: Quaternion = scene.global_basis.get_rotation_quaternion()

func _ready():
	# Use a timer to defer until the parent generator is fully ready.
	var timer := Timer.new()
	timer.timeout.connect(_sync_from_parent)
	add_child(timer)
	timer.start(0.0)
	if not Engine.is_editor_hint():
		_sync_from_parent()
		respawn.call_deferred()

func respawn():
	if current_player != null:
		current_player.queue_free()
	ui_overlay.reset_state()
	current_player = PlayerScene.instantiate()
	current_player.name = "Player"
	current_player.set_radius($"..".ball_radius)
	get_parent_node_3d().get_parent_node_3d().add_child(current_player)
	current_player.global_position = global_position
	current_player.camera_rotation_changed.connect(func(b: Basis): target_rotation = b.get_rotation_quaternion())
	current_player.set_game_active(true)
	start_usec = Time.get_ticks_usec()
	# Apply saved control settings (virtual controls, etc.)
	var settings := get_parent_node_3d().get_parent_node_3d().get_node_or_null("UI/MarginContainer")
	if settings is GameSettings:
		settings.apply_to_player(current_player)

func _process(delta):
	var _scale = scene.global_basis.get_scale()
	var current = scene.global_basis.get_rotation_quaternion()
	current = current.slerp(
		target_rotation,
		1.0 - exp(-scene_rotation_speed * delta)
	)
	scene.global_basis = Basis(current).scaled(_scale)
	death_area.global_basis = Basis(current)
	
	if !Engine.is_editor_hint() and Input.is_action_pressed("reset"):
		respawn()

func _sync_from_parent():
	var parent = get_parent_node_3d()
	if parent is MazeGenerator:
		transform.origin = (parent.maze_outer_radius - parent.ball_radius/parent.ball_to_path_min_ratio.y * 2.0) * Vector3.BACK
