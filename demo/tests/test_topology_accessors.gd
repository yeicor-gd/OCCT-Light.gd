class_name TestTopologyAccessors


static func _approx(a: float, b: float, epsilon := 0.001) -> bool:
	return absf(a - b) <= epsilon


static func _approx_vec(a: Vector3, b: Vector3, epsilon := 0.001) -> bool:
	return _approx(a.x, b.x, epsilon) and _approx(a.y, b.y, epsilon) and _approx(a.z, b.z, epsilon)


static func test_vertex_positions() -> String:
	var box := SolidBox.new()
	box.build_box(Vector3(1.0, 2.0, 3.0))

	var vertices := box.get_vertex_positions()
	if vertices.size() != 8:
		return "expected 8 vertices but got %s" % vertices.size()

	var found_origin := false
	var found_max := false
	for vertex: Vector3 in vertices:
		if _approx_vec(vertex, Vector3.ZERO, 0.001):
			found_origin = true
		if _approx_vec(vertex, Vector3(1.0, 2.0, 3.0), 0.001):
			found_max = true

	if not found_origin:
		return "box vertices did not include the origin corner"
	if not found_max:
		return "box vertices did not include the max corner"

	return ""


static func test_edge_polylines() -> String:
	var box := SolidBox.new()
	box.build_box(Vector3(1.0, 2.0, 3.0))

	var polylines := box.get_edge_polylines(0.05)
	if polylines.size() != 12:
		return "expected 12 edge polylines but got %s" % polylines.size()

	for polyline_variant in polylines:
		var polyline: PackedVector3Array = polyline_variant
		if polyline.size() < 2:
			return "edge polyline had fewer than 2 points"
		var start_point := polyline[0]
		var end_point := polyline[polyline.size() - 1]
		if _approx_vec(start_point, end_point, 0.001):
			return "edge polyline start and end collapsed to the same point"

	return ""
