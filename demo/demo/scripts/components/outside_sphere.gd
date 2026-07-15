@tool
extends CSGSphere3D
class_name OutsideSphere

## Automatically syncs the CSG sphere radius with the parent MazeGenerator's
## outer radius.

func _ready():
	if Engine.is_editor_hint():
		# Use a timer to defer until the parent generator is fully ready.
		var timer := Timer.new()
		timer.timeout.connect(_sync_from_parent)
		add_child(timer)
		timer.start(0.0)
	else:
		_sync_from_parent()
		visible = true

func _sync_from_parent():
	radius = $"..".maze_outer_radius
