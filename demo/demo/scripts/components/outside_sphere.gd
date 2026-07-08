@tool
extends CSGSphere3D
class_name OutsideSphere

## Automatically syncs the CSG sphere radius with the parent MazeGenerator's
## outer radius.

func _ready():
	# Use a timer to defer until the parent generator is fully ready.
	var timer := Timer.new()
	timer.one_shot = true
	timer.timeout.connect(_sync_from_parent)
	add_child(timer)
	timer.start(0.0)

func _sync_from_parent():
	var parent = get_parent_node_3d()
	if parent is MazeGenerator:
		radius = parent.maze_outer_radius
