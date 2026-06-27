class_name TestFaceProfiles


static func _approx(a: float, b: float, epsilon := 0.001) -> bool:
	return absf(a - b) <= epsilon


static func _approx_vec(a: Vector3, b: Vector3, epsilon := 0.001) -> bool:
	return _approx(a.x, b.x, epsilon) and _approx(a.y, b.y, epsilon) and _approx(a.z, b.z, epsilon)


static func test_face_with_inner_wires() -> String:
	var outer := RectangleWire.new()
	outer.build_rectangle(Vector2(6.0, 6.0))

	var hole := CircleWire.new()
	hole.build_circle(1.0)

	var face := Face.new()
	face.build_from_wires(outer, [hole], true)

	if face.is_null():
		return "face with inner wire construction returned null"
	if not face.is_planar():
		return "face with inner wire was not planar"

	var inner_wires := face.get_inner_wires()
	if inner_wires.size() != 1:
		return "expected 1 inner wire but got %s" % inner_wires.size()

	var outer_wire := face.get_outer_wire()
	if outer_wire == null or outer_wire.is_null():
		return "outer wire extraction returned null"
	if not _approx(outer_wire.get_length(), 24.0, 0.02):
		return "unexpected outer wire length: %s" % outer_wire.get_length()

	var inner_wire: Wire = inner_wires[0]
	if inner_wire == null or inner_wire.is_null():
		return "inner wire extraction returned null"
	if not _approx(inner_wire.get_length(), TAU, 0.03):
		return "unexpected inner wire length: %s" % inner_wire.get_length()

	if not _approx(face.get_surface_area(), 36.0 - PI, 0.05):
		return "unexpected face area with hole: %s" % face.get_surface_area()

	var solid := face.extruded(Vector3(0.0, 0.0, 2.0))
	if solid == null or solid.is_null():
		return "extruding a face with a hole returned null"
	if not solid.is_closed():
		return "extruding a face with a hole did not return a closed solid"
	if not _approx(solid.get_volume(), (36.0 - PI) * 2.0, 0.1):
		return "unexpected extruded holed face volume: %s" % solid.get_volume()
	if not _approx_vec(solid.get_bounding_box_size(), Vector3(6.0, 6.0, 2.0), 0.03):
		return "unexpected extruded holed face bounds size: %s" % str(solid.get_bounding_box_size())

	return ""


static func test_face_offset_2d() -> String:
	var outer := RectangleWire.new()
	outer.build_rectangle(Vector2(6.0, 6.0))

	var hole := CircleWire.new()
	hole.build_circle(1.0)

	var face := Face.new()
	face.build_from_wires(outer, [hole], true)

	var offset := face.offset_2d(1.0)
	if offset == null or offset.is_null():
		return "face offset returned null"
	if not offset.is_planar():
		return "offset face was not planar"
	if offset.get_inner_wires().size() != 0:
		return "expected the small hole to collapse away after outward offset"
	if not _approx(offset.get_surface_area(), 60.0 + PI, 0.08):
		return "unexpected offset face area: %s" % offset.get_surface_area()
	if not _approx_vec(offset.get_bounding_box_size(), Vector3(8.0, 8.0, 0.0), 0.03):
		return "unexpected offset face bounds size: %s" % str(offset.get_bounding_box_size())

	return ""
