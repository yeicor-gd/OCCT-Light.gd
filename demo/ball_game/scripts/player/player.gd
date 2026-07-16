extends Node3D
class_name Player

func set_radius(radius: float):
	$"Ball/CSGSphere3D".radius = radius
	$"Ball/CollisionShape3D".shape.radius = radius
	$"Ball/GroundCast".shape.radius = radius*1.1
