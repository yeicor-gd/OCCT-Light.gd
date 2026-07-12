@tool
extends Area3D

@export var spawner: Spawner

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
		visible = true

func _sync_from_parent():
	$Mesh.radius = $"..".maze_inner_radius
	$Shape.shape.radius = $"..".maze_inner_radius


func _on_body_entered(body: Node3D) -> void:
	if body.get_parent_node_3d() == spawner.current_player:
		spawner.respawn()
	elif body.name == "Faces":
		push_warning("Bad maze: faces collide with death area!")
	else:
		print("Ignoring unknown body entered death area: ", body.name)
