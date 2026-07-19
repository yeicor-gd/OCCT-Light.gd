extends Node3D
class_name Player

signal camera_rotation_changed(_global_basis)

func set_radius(radius: float):
	$"Ball/CSGSphere3D".radius = radius
	$"Ball/CollisionShape3D".shape.radius = radius
	$"Ball/GroundCast".shape.radius = radius*1.1


func _on_camera_rig_rotation_changed(_global_basis: Quaternion) -> void:
	camera_rotation_changed.emit(_global_basis)
