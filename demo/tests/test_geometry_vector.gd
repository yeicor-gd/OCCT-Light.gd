class_name TestGeometryVector


static func _approx(a: float, b: float, epsilon := 0.0001) -> bool:
	return absf(a - b) <= epsilon


static func _approx_vec(a: Vector3, b: Vector3, epsilon := 0.0001) -> bool:
	return _approx(a.x, b.x, epsilon) and _approx(a.y, b.y, epsilon) and _approx(a.z, b.z, epsilon)


static func test_vector_arithmetic() -> String:
	var a := GeometryVector.new()
	a.set_xyz(1.0, 2.0, 3.0)

	var b := GeometryVector.new()
	b.set_vector3(Vector3(4.0, -1.0, 2.0))

	var added := a.add(b)
	var subtracted := a.subtract(b)
	var crossed := a.cross(b)
	var scaled := a.scaled(2.5)

	if not _approx(a.length(), sqrt(14.0)):
		return "expected vector length sqrt(14), got %s" % a.length()
	if not _approx(a.dot(b), 8.0):
		return "expected dot product 8, got %s" % a.dot(b)
	if not _approx_vec(added.get_vector3(), Vector3(5.0, 1.0, 5.0)):
		return "unexpected add result: %s" % str(added.get_vector3())
	if not _approx_vec(subtracted.get_vector3(), Vector3(-3.0, 3.0, 1.0)):
		return "unexpected subtract result: %s" % str(subtracted.get_vector3())
	if not _approx_vec(crossed.get_vector3(), Vector3(7.0, 10.0, -9.0)):
		return "unexpected cross result: %s" % str(crossed.get_vector3())
	if not _approx_vec(scaled.get_vector3(), Vector3(2.5, 5.0, 7.5)):
		return "unexpected scaled result: %s" % str(scaled.get_vector3())

	return ""
