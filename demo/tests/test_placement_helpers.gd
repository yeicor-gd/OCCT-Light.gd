class_name TestPlacementHelpers


static func _approx(a: float, b: float, epsilon := 0.001) -> bool:
	return absf(a - b) <= epsilon


static func _approx_vec(a: Vector3, b: Vector3, epsilon := 0.001) -> bool:
	return _approx(a.x, b.x, epsilon) and _approx(a.y, b.y, epsilon) and _approx(a.z, b.z, epsilon)


static func test_axis_and_location_helpers() -> String:
	var axis := Axis.new()
	axis.set_axis(Vector3(1.0, 2.0, 3.0), Vector3.UP)

	if not _approx_vec(axis.get_origin(), Vector3(1.0, 2.0, 3.0), 0.001):
		return "unexpected axis origin: %s" % str(axis.get_origin())
	if not _approx_vec(axis.get_direction(), Vector3.UP, 0.001):
		return "unexpected axis direction: %s" % str(axis.get_direction())

	var reversed := axis.reversed()
	if not _approx_vec(reversed.get_direction(), Vector3.DOWN, 0.001):
		return "unexpected reversed axis direction: %s" % str(reversed.get_direction())

	var translation := Location.new()
	translation.set_translation(Vector3(5.0, -1.0, 2.0))
	if not _approx_vec(translation.transform_point(Vector3.ONE), Vector3(6.0, 0.0, 3.0), 0.001):
		return "unexpected translated point: %s" % str(translation.transform_point(Vector3.ONE))

	var moved_axis := axis.transformed(translation)
	if not _approx_vec(moved_axis.get_origin(), Vector3(6.0, 1.0, 5.0), 0.001):
		return "unexpected moved axis origin: %s" % str(moved_axis.get_origin())

	var rotation_axis := Axis.new()
	rotation_axis.set_axis(Vector3.ZERO, Vector3.UP)

	var rotation := Location.new()
	rotation.set_rotation(rotation_axis, PI / 2.0)
	if not _approx_vec(rotation.transform_vector(Vector3.RIGHT), Vector3(0.0, 0.0, -1.0), 0.001):
		return "unexpected rotated vector: %s" % str(rotation.transform_vector(Vector3.RIGHT))

	var combined := translation.multiplied(rotation)
	var restored := combined.inverted().transform_point(combined.transform_point(Vector3(2.0, 0.0, 0.0)))
	if not _approx_vec(restored, Vector3(2.0, 0.0, 0.0), 0.001):
		return "combined location inversion did not restore point: %s" % str(restored)

	return ""


static func test_shape_located() -> String:
	var box := SolidBox.new()
	box.build_box(Vector3(1.0, 2.0, 3.0))

	var location := Location.new()
	location.set_translation(Vector3(4.0, 5.0, 6.0))

	var moved := box.located(location)
	if moved == null or moved.is_null():
		return "located returned null"
	if not _approx_vec(moved.get_bounding_box_min(), Vector3(4.0, 5.0, 6.0), 0.01):
		return "unexpected located bounds min: %s" % str(moved.get_bounding_box_min())

	return ""


static func test_plane_helper() -> String:
	var plane := CadPlane.new()
	plane.set_plane(Vector3.ZERO, Vector3.UP, Vector3.RIGHT)

	if not _approx_vec(plane.get_normal(), Vector3.UP, 0.001):
		return "unexpected plane normal: %s" % str(plane.get_normal())
	if not _approx_vec(plane.get_x_direction(), Vector3.RIGHT, 0.001):
		return "unexpected plane x direction: %s" % str(plane.get_x_direction())
	if not _approx_vec(plane.get_y_direction(), Vector3(0.0, 0.0, -1.0), 0.001):
		return "unexpected plane y direction: %s" % str(plane.get_y_direction())
	if not _approx(plane.signed_distance_to_point(Vector3(0.0, 3.0, 0.0)), 3.0, 0.001):
		return "unexpected plane distance: %s" % plane.signed_distance_to_point(Vector3(0.0, 3.0, 0.0))
	if not _approx_vec(plane.project_point(Vector3(2.0, 3.0, 4.0)), Vector3(2.0, 0.0, 4.0), 0.001):
		return "unexpected projected point: %s" % str(plane.project_point(Vector3(2.0, 3.0, 4.0)))

	var offset_plane := plane.offsetted(2.0)
	if not _approx_vec(offset_plane.get_origin(), Vector3(0.0, 2.0, 0.0), 0.001):
		return "unexpected offset plane origin: %s" % str(offset_plane.get_origin())

	var location := Location.new()
	location.set_translation(Vector3(1.0, 2.0, 3.0))
	var moved_plane := plane.transformed(location)
	if not _approx_vec(moved_plane.get_origin(), Vector3(1.0, 2.0, 3.0), 0.001):
		return "unexpected transformed plane origin: %s" % str(moved_plane.get_origin())

	return ""
