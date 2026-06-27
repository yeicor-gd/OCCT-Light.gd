class_name TestSolidBox


static func _approx(a: float, b: float, epsilon := 0.0001) -> bool:
	return absf(a - b) <= epsilon


static func _approx_vec(a: Vector3, b: Vector3, epsilon := 0.0001) -> bool:
	return _approx(a.x, b.x, epsilon) and _approx(a.y, b.y, epsilon) and _approx(a.z, b.z, epsilon)


static func _make_box(size: Vector3, origin := Vector3.ZERO):
	var box = SolidBox.new()
	box.build_box(size, origin)
	return box


static func test_box_measurements() -> String:
	var box = _make_box(Vector3(2.0, 3.0, 4.0), Vector3(1.0, 2.0, 3.0))

	if box.is_null():
		return "box shape is unexpectedly null"
	if not _approx(box.get_volume(), 24.0):
		return "expected volume 24, got %s" % box.get_volume()
	if not _approx(box.get_surface_area(), 52.0):
		return "expected surface area 52, got %s" % box.get_surface_area()
	if not _approx_vec(box.get_bounding_box_min(), Vector3(1.0, 2.0, 3.0)):
		return "unexpected bounding box min: %s" % str(box.get_bounding_box_min())
	if not _approx_vec(box.get_bounding_box_max(), Vector3(3.0, 5.0, 7.0)):
		return "unexpected bounding box max: %s" % str(box.get_bounding_box_max())
	if not _approx_vec(box.get_bounding_box_size(), Vector3(2.0, 3.0, 4.0)):
		return "unexpected bounding box size: %s" % str(box.get_bounding_box_size())
	if not _approx_vec(box.get_center_of_mass(), Vector3(2.0, 3.5, 5.0)):
		return "unexpected center of mass: %s" % str(box.get_center_of_mass())

	var copy = box.copy()
	if copy == null or copy.is_null():
		return "copy returned a null shape"
	if not _approx(copy.get_volume(), 24.0):
		return "expected copied volume 24, got %s" % copy.get_volume()
	return ""


static func test_box_booleans() -> String:
	var a = _make_box(Vector3(2.0, 2.0, 2.0), Vector3.ZERO)
	var b = _make_box(Vector3(2.0, 2.0, 2.0), Vector3.ONE)

	var fused = a.fuse(b)
	var cut = a.cut(b)
	var common = a.common(b)

	if fused == null or fused.is_null():
		return "fuse returned a null shape"
	if cut == null or cut.is_null():
		return "cut returned a null shape"
	if common == null or common.is_null():
		return "common returned a null shape"
	if not _approx(fused.get_volume(), 15.0):
		return "expected fused volume 15, got %s" % fused.get_volume()
	if not _approx(cut.get_volume(), 7.0):
		return "expected cut volume 7, got %s" % cut.get_volume()
	if not _approx(common.get_volume(), 1.0):
		return "expected common volume 1, got %s" % common.get_volume()
	if not _approx_vec(fused.get_bounding_box_min(), Vector3.ZERO):
		return "unexpected fused bounding box min: %s" % str(fused.get_bounding_box_min())
	if not _approx_vec(fused.get_bounding_box_max(), Vector3(3.0, 3.0, 3.0)):
		return "unexpected fused bounding box max: %s" % str(fused.get_bounding_box_max())
	return ""
