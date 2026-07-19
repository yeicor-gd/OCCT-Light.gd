@tool
extends Area3D

@onready var cshape := $CollisionShape3D
@onready var shape := cshape.shape as CylinderShape3D
@export var spawner: Spawner
@export var ui_overlay: UIOverlay

func _ready():
	# Use a timer to defer until the parent generator is fully ready.
	var timer := Timer.new()
	timer.timeout.connect(_sync_from_parent)
	add_child(timer)
	timer.start(0.0)

func _sync_from_parent():
	var parent = get_parent_node_3d()
	if parent is MazeGenerator:
		transform.origin = (parent.maze_outer_radius - parent.ball_radius/parent.ball_to_path_min_ratio.y * 2.0) * Vector3.FORWARD
		shape.height = 2.0 * parent.ball_radius/parent.ball_to_path_min_ratio.y
		shape.radius = parent.ball_radius/parent.ball_to_path_min_ratio.x

func _on_body_entered(body: Node3D) -> void:
	if body.get_parent_node_3d() == spawner.current_player:
		ui_overlay.show_game_won((Time.get_ticks_usec() - spawner.start_usec) / 1000000.0)
	elif body.name == "Faces":
		push_warning("Bad maze: faces collide with death area!")
	else:
		print("Ignoring unknown body entered death area: ", body.name)
