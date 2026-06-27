class_name TestPrimitivesAndTransforms


static func _approx(a: float, b: float, epsilon := 0.001) -> bool:
	return absf(a - b) <= epsilon


static func _approx_vec(a: Vector3, b: Vector3, epsilon := 0.001) -> bool:
	return _approx(a.x, b.x, epsilon) and _approx(a.y, b.y, epsilon) and _approx(a.z, b.z, epsilon)


static func test_additional_primitives() -> String:
	var cylinder := SolidCylinder.new()
	cylinder.build_cylinder(2.0, 5.0, Vector3(1.0, 2.0, 3.0))

	if not _approx(cylinder.get_volume(), PI * 20.0, 0.01):
		return "unexpected cylinder volume: %s" % cylinder.get_volume()
	if not _approx_vec(cylinder.get_bounding_box_min(), Vector3(-1.0, 0.0, 3.0), 0.01):
		return "unexpected cylinder bounds min: %s" % str(cylinder.get_bounding_box_min())
	if not _approx_vec(cylinder.get_bounding_box_max(), Vector3(3.0, 4.0, 8.0), 0.01):
		return "unexpected cylinder bounds max: %s" % str(cylinder.get_bounding_box_max())

	var sphere := SolidSphere.new()
	sphere.build_sphere(2.0, Vector3(5.0, 0.0, -1.0))

	if not _approx(sphere.get_volume(), 4.0 / 3.0 * PI * 8.0, 0.02):
		return "unexpected sphere volume: %s" % sphere.get_volume()
	if not _approx_vec(sphere.get_bounding_box_size(), Vector3(4.0, 4.0, 4.0), 0.01):
		return "unexpected sphere bounds size: %s" % str(sphere.get_bounding_box_size())

	var cone := SolidCone.new()
	cone.build_cone(2.0, 1.0, 6.0, Vector3.ZERO)

	if not _approx(cone.get_volume(), PI * 14.0, 0.02):
		return "unexpected cone volume: %s" % cone.get_volume()
	if not _approx_vec(cone.get_bounding_box_size(), Vector3(4.0, 4.0, 6.0), 0.02):
		return "unexpected cone bounds size: %s" % str(cone.get_bounding_box_size())

	var torus := SolidTorus.new()
	torus.build_torus(3.0, 1.0, Vector3(2.0, -1.0, 4.0))

	if not _approx(torus.get_volume(), 2.0 * PI * PI * 3.0, 0.05):
		return "unexpected torus volume: %s" % torus.get_volume()
	var torus_center := (torus.get_bounding_box_min() + torus.get_bounding_box_max()) * 0.5
	if not _approx_vec(torus_center, Vector3(2.0, -1.0, 4.0), 0.02):
		return "unexpected torus bounds center: %s" % str(torus_center)

	var torus_bounds_size := torus.get_bounding_box_size()
	if not _approx(torus_bounds_size.z, 2.0, 0.02):
		return "unexpected torus z bounds size: %s" % torus_bounds_size.z
	if not _approx(torus_bounds_size.x, torus_bounds_size.y, 0.02):
		return "torus x/y bounds were not symmetric: %s" % str(torus_bounds_size)
	if torus_bounds_size.x < 8.0 or torus_bounds_size.x > 8.8:
		return "unexpected torus radial bounds size: %s" % torus_bounds_size.x

	var wedge := SolidWedge.new()
	wedge.build_wedge(4.0, 5.0, 6.0, 1.5, Vector3(1.0, 2.0, 3.0))

	if not _approx(wedge.get_volume(), 82.5, 0.05):
		return "unexpected wedge volume: %s" % wedge.get_volume()
	if not _approx_vec(wedge.get_bounding_box_min(), Vector3(1.0, 2.0, 3.0), 0.02):
		return "unexpected wedge bounds min: %s" % str(wedge.get_bounding_box_min())
	if not _approx_vec(wedge.get_bounding_box_max(), Vector3(5.0, 7.0, 9.0), 0.02):
		return "unexpected wedge bounds max: %s" % str(wedge.get_bounding_box_max())

	return ""


static func test_shape_transforms() -> String:
	var box := SolidBox.new()
	box.build_box(Vector3(1.0, 2.0, 3.0))

	var translated := box.translated(Vector3(10.0, -5.0, 2.0))
	if translated == null or translated.is_null():
		return "translated returned null"
	if not _approx_vec(translated.get_bounding_box_min(), Vector3(10.0, -5.0, 2.0), 0.01):
		return "unexpected translated bounds min: %s" % str(translated.get_bounding_box_min())

	var rotated := box.rotated(Vector3.ZERO, Vector3.UP, PI / 2.0)
	if rotated == null or rotated.is_null():
		return "rotated returned null"
	if not _approx(rotated.get_volume(), 6.0, 0.01):
		return "rotation changed volume: %s" % rotated.get_volume()
	if not _approx_vec(rotated.get_bounding_box_size(), Vector3(3.0, 2.0, 1.0), 0.02):
		return "unexpected rotated bounds size: %s" % str(rotated.get_bounding_box_size())

	var scaled := box.scaled(Vector3.ZERO, 2.0)
	if scaled == null or scaled.is_null():
		return "scaled returned null"
	if not _approx(scaled.get_volume(), 48.0, 0.05):
		return "unexpected scaled volume: %s" % scaled.get_volume()
	if not _approx_vec(scaled.get_bounding_box_size(), Vector3(2.0, 4.0, 6.0), 0.02):
		return "unexpected scaled bounds size: %s" % str(scaled.get_bounding_box_size())

	var point_mirrored := box.mirrored_about_point(Vector3.ZERO)
	if point_mirrored == null or point_mirrored.is_null():
		return "point mirror returned null"
	if not _approx_vec(point_mirrored.get_bounding_box_min(), Vector3(-1.0, -2.0, -3.0), 0.01):
		return "unexpected point-mirrored bounds min: %s" % str(point_mirrored.get_bounding_box_min())

	var axis := Axis.new()
	axis.set_axis(Vector3.ZERO, Vector3.UP)
	var axis_mirrored := box.mirrored_about_axis(axis)
	if axis_mirrored == null or axis_mirrored.is_null():
		return "axis mirror returned null"
	if not _approx_vec(axis_mirrored.get_bounding_box_min(), Vector3(-1.0, 0.0, -3.0), 0.01):
		return "unexpected axis-mirrored bounds min: %s" % str(axis_mirrored.get_bounding_box_min())

	var plane := CadPlane.new()
	plane.set_plane(Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD)
	var plane_mirrored := box.mirrored_about_plane(plane)
	if plane_mirrored == null or plane_mirrored.is_null():
		return "plane mirror returned null"
	if not _approx_vec(plane_mirrored.get_bounding_box_min(), Vector3(-1.0, 0.0, 0.0), 0.01):
		return "unexpected plane-mirrored bounds min: %s" % str(plane_mirrored.get_bounding_box_min())

	return ""
