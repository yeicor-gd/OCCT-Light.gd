@tool
extends Area3D

@onready var cshape := $CollisionShape3D
@onready var shape := cshape.shape as CylinderShape3D

func _ready():
	# Use a timer to defer until the parent generator is fully ready.
	var timer := Timer.new()
	timer.timeout.connect(_sync_from_parent)
	add_child(timer)
	timer.start(0.0)

func _sync_from_parent():
	var parent = get_parent_node_3d()
	if parent is MazeGenerator:
		transform.origin = (parent.maze_outer_radius - parent.ball_radius) * Vector3.FORWARD
		shape.height = 2.0 * parent.ball_radius
		shape.radius = parent.ball_radius
