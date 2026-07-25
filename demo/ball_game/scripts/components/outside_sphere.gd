@tool
extends CSGSphere3D
class_name OutsideSphere

## Automatically syncs the CSG sphere radius with the parent MazeGenerator's
## outer radius.

func _ready():
	var parent := get_parent_node_3d()
	if parent is MazeGenerator:
		parent.regeneration_finished.connect(_sync_from_parent)
	if not Engine.is_editor_hint():
		_sync_from_parent()
		visible = true

func _sync_from_parent():
	radius = $"..".maze_outer_radius
