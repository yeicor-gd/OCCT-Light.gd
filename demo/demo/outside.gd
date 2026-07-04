@tool
extends CSGSphere3D

func _ready():
	var timer := Timer.new()
	timer.timeout.connect(func():
		radius = (get_parent_node_3d() as MazeGenerator).maze_outer_radius)
	add_child(timer)
	timer.start()
