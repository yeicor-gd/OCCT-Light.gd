extends Node3D
class_name Player

signal camera_rotation_changed(_global_basis)

func set_radius(radius: float):
	$"Ball/CSGSphere3D".radius = radius
	$"Ball/CollisionShape3D".shape.radius = radius
	$"Ball/GroundCast".shape.radius = radius*1.1


func set_game_active(active: bool) -> void:
	var ball = get_node_or_null("Ball")
	if ball and ball.has_method("set_game_active"):
		ball.set_game_active(active)


func _on_camera_rig_rotation_changed(_global_basis: Quaternion) -> void:
	camera_rotation_changed.emit(_global_basis)
