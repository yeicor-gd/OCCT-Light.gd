class_name TestProfilePrimitives


static func _approx(a: float, b: float, epsilon := 0.001) -> bool:
	return absf(a - b) <= epsilon


static func _approx_vec(a: Vector3, b: Vector3, epsilon := 0.001) -> bool:
	return _approx(a.x, b.x, epsilon) and _approx(a.y, b.y, epsilon) and _approx(a.z, b.z, epsilon)


static func test_rectangle_wire_default_plane() -> String:
	var rectangle := RectangleWire.new()
	rectangle.build_rectangle(Vector2(2.0, 4.0))

	if not rectangle.is_closed():
		return "rectangle wire was not closed"
	if not _approx(rectangle.get_length(), 12.0, 0.01):
		return "unexpected rectangle perimeter: %s" % rectangle.get_length()
	if not _approx_vec(rectangle.get_bounding_box_size(), Vector3(2.0, 4.0, 0.0), 0.01):
		return "unexpected rectangle bounds size: %s" % str(rectangle.get_bounding_box_size())

	return ""


static func test_rectangle_wire_custom_plane() -> String:
	var plane := CadPlane.new()
	plane.set_plane(Vector3(10.0, 0.0, 0.0), Vector3.UP, Vector3.RIGHT)

	var rectangle := RectangleWire.new()
	rectangle.build_rectangle(Vector2(2.0, 6.0), plane, false)

	if not _approx_vec(rectangle.get_bounding_box_min(), Vector3(10.0, 0.0, -6.0), 0.01):
		return "unexpected custom-plane rectangle bounds min: %s" % str(rectangle.get_bounding_box_min())
	if not _approx_vec(rectangle.get_bounding_box_max(), Vector3(12.0, 0.0, 0.0), 0.01):
		return "unexpected custom-plane rectangle bounds max: %s" % str(rectangle.get_bounding_box_max())

	var polyline := rectangle.get_polyline(0.05)
	if polyline.size() < 4:
		return "rectangle polyline had too few points"

	return ""


static func test_circle_wire_default_plane() -> String:
	var circle := CircleWire.new()
	circle.build_circle(2.0)

	if not circle.is_closed():
		return "circle wire was not closed"
	if not _approx(circle.get_length(), TAU * 2.0, 0.02):
		return "unexpected circle circumference: %s" % circle.get_length()
	if not _approx_vec(circle.get_bounding_box_size(), Vector3(4.0, 4.0, 0.0), 0.02):
		return "unexpected circle bounds size: %s" % str(circle.get_bounding_box_size())

	var polyline := circle.get_polyline(0.05)
	if polyline.size() < 8:
		return "circle polyline had too few points"

	return ""


static func test_circle_wire_custom_plane() -> String:
	var plane := CadPlane.new()
	plane.set_plane(Vector3(10.0, 0.0, 0.0), Vector3.UP, Vector3.RIGHT)

	var circle := CircleWire.new()
	circle.build_circle(3.0, plane)

	if not _approx_vec(circle.get_bounding_box_min(), Vector3(7.0, 0.0, -3.0), 0.02):
		return "unexpected custom-plane circle bounds min: %s" % str(circle.get_bounding_box_min())
	if not _approx_vec(circle.get_bounding_box_max(), Vector3(13.0, 0.0, 3.0), 0.02):
		return "unexpected custom-plane circle bounds max: %s" % str(circle.get_bounding_box_max())

	return ""


static func test_ellipse_wire_default_plane() -> String:
	var ellipse := EllipseWire.new()
	ellipse.build_ellipse(3.0, 2.0)

	if not ellipse.is_closed():
		return "ellipse wire was not closed"
	if not _approx_vec(ellipse.get_bounding_box_size(), Vector3(6.0, 4.0, 0.0), 0.02):
		return "unexpected ellipse bounds size: %s" % str(ellipse.get_bounding_box_size())

	var polyline := ellipse.get_polyline(0.05)
	if polyline.size() < 8:
		return "ellipse polyline had too few points"

	return ""


static func test_ellipse_wire_custom_plane() -> String:
	var plane := CadPlane.new()
	plane.set_plane(Vector3(10.0, 0.0, 0.0), Vector3.UP, Vector3.RIGHT)

	var ellipse := EllipseWire.new()
	ellipse.build_ellipse(4.0, 1.5, plane)

	if not _approx_vec(ellipse.get_bounding_box_min(), Vector3(6.0, 0.0, -1.5), 0.03):
		return "unexpected custom-plane ellipse bounds min: %s" % str(ellipse.get_bounding_box_min())
	if not _approx_vec(ellipse.get_bounding_box_max(), Vector3(14.0, 0.0, 1.5), 0.03):
		return "unexpected custom-plane ellipse bounds max: %s" % str(ellipse.get_bounding_box_max())

	return ""


static func test_regular_polygon_wire_default_plane() -> String:
	var polygon := RegularPolygonWire.new()
	polygon.build_regular_polygon(2.0, 6)

	if not polygon.is_closed():
		return "regular polygon wire was not closed"
	if not _approx(polygon.get_length(), 12.0, 0.02):
		return "unexpected regular polygon perimeter: %s" % polygon.get_length()
	if not _approx_vec(polygon.get_bounding_box_size(), Vector3(4.0, 3.464102, 0.0), 0.03):
		return "unexpected regular polygon bounds size: %s" % str(polygon.get_bounding_box_size())

	return ""


static func test_regular_polygon_wire_custom_plane() -> String:
	var plane := CadPlane.new()
	plane.set_plane(Vector3(10.0, 0.0, 0.0), Vector3.UP, Vector3.RIGHT)

	var polygon := RegularPolygonWire.new()
	polygon.build_regular_polygon(2.0, 4, plane, PI / 4.0)

	if not _approx_vec(polygon.get_bounding_box_min(), Vector3(8.585786, 0.0, -1.414214), 0.03):
		return "unexpected custom-plane polygon bounds min: %s" % str(polygon.get_bounding_box_min())
	if not _approx_vec(polygon.get_bounding_box_max(), Vector3(11.414214, 0.0, 1.414214), 0.03):
		return "unexpected custom-plane polygon bounds max: %s" % str(polygon.get_bounding_box_max())

	return ""


static func test_polygon_wire_default_plane() -> String:
	var polygon := PolygonWire.new()
	polygon.build_polygon_2d(PackedVector2Array([
		Vector2.ZERO,
		Vector2(2.0, 0.0),
		Vector2(2.0, 3.0),
		Vector2(0.0, 3.0),
	]))

	if not polygon.is_closed():
		return "2d polygon wire was not closed"
	if not _approx(polygon.get_length(), 10.0, 0.01):
		return "unexpected 2d polygon perimeter: %s" % polygon.get_length()
	if not _approx_vec(polygon.get_bounding_box_size(), Vector3(2.0, 3.0, 0.0), 0.01):
		return "unexpected 2d polygon bounds size: %s" % str(polygon.get_bounding_box_size())

	return ""


static func test_polygon_wire_custom_plane_open() -> String:
	var plane := CadPlane.new()
	plane.set_plane(Vector3(10.0, 0.0, 0.0), Vector3.UP, Vector3.RIGHT)

	var polygon := PolygonWire.new()
	polygon.build_polygon_2d(PackedVector2Array([
		Vector2.ZERO,
		Vector2(2.0, 0.0),
		Vector2(2.0, 3.0),
	]), plane, false)

	if polygon.is_closed():
		return "custom-plane open polygon wire was unexpectedly closed"
	if not _approx_vec(polygon.get_bounding_box_min(), Vector3(10.0, 0.0, -3.0), 0.01):
		return "unexpected custom-plane open polygon bounds min: %s" % str(polygon.get_bounding_box_min())
	if not _approx_vec(polygon.get_bounding_box_max(), Vector3(12.0, 0.0, 0.0), 0.01):
		return "unexpected custom-plane open polygon bounds max: %s" % str(polygon.get_bounding_box_max())

	return ""


static func test_rectangle_wire_offset_2d() -> String:
	var rectangle := RectangleWire.new()
	rectangle.build_rectangle(Vector2(2.0, 4.0))

	var offset := rectangle.offset_2d(1.0)
	if offset == null or offset.is_null():
		return "rectangle offset returned null"
	if not offset.is_closed():
		return "rectangle offset wire was not closed"
	if not _approx(offset.get_length(), 12.0 + TAU, 0.05):
		return "unexpected rectangle offset perimeter: %s" % offset.get_length()
	if not _approx_vec(offset.get_bounding_box_size(), Vector3(4.0, 6.0, 0.0), 0.03):
		return "unexpected rectangle offset bounds size: %s" % str(offset.get_bounding_box_size())

	return ""


static func test_rectangle_rounded_wire_default_plane() -> String:
	var rounded := RectangleRoundedWire.new()
	rounded.build_rounded_rectangle(Vector2(6.0, 4.0), 1.0)

	if not rounded.is_closed():
		return "rounded rectangle wire was not closed"
	if not _approx(rounded.get_length(), 12.0 + TAU, 0.03):
		return "unexpected rounded rectangle perimeter: %s" % rounded.get_length()
	if not _approx_vec(rounded.get_bounding_box_size(), Vector3(6.0, 4.0, 0.0), 0.02):
		return "unexpected rounded rectangle bounds size: %s" % str(rounded.get_bounding_box_size())

	var face := Face.new()
	face.build_from_wire(rounded, true)
	if not _approx(face.get_surface_area(), 24.0 - 4.0 + PI, 0.03):
		return "unexpected rounded rectangle face area: %s" % face.get_surface_area()

	return ""


static func test_rectangle_rounded_wire_custom_plane() -> String:
	var plane := CadPlane.new()
	plane.set_plane(Vector3(10.0, 0.0, 0.0), Vector3.UP, Vector3.RIGHT)

	var rounded := RectangleRoundedWire.new()
	rounded.build_rounded_rectangle(Vector2(6.0, 4.0), 1.0, plane, false)

	if not _approx_vec(rounded.get_bounding_box_min(), Vector3(10.0, 0.0, -4.0), 0.02):
		return "unexpected custom-plane rounded rectangle bounds min: %s" % str(rounded.get_bounding_box_min())
	if not _approx_vec(rounded.get_bounding_box_max(), Vector3(16.0, 0.0, 0.0), 0.02):
		return "unexpected custom-plane rounded rectangle bounds max: %s" % str(rounded.get_bounding_box_max())

	var polyline := rounded.get_polyline(0.05)
	if polyline.size() < 12:
		return "rounded rectangle polyline had too few points"

	return ""


static func test_circle_wire_offset_2d() -> String:
	var plane := CadPlane.new()
	plane.set_plane(Vector3(10.0, 0.0, 0.0), Vector3.UP, Vector3.RIGHT)

	var circle := CircleWire.new()
	circle.build_circle(2.0, plane)

	var grown := circle.offset_2d(1.5)
	if grown == null or grown.is_null():
		return "circle offset returned null"
	if not grown.is_closed():
		return "circle offset wire was not closed"
	if not _approx(grown.get_length(), TAU * 3.5, 0.05):
		return "unexpected circle offset circumference: %s" % grown.get_length()
	if not _approx_vec(grown.get_bounding_box_min(), Vector3(6.5, 0.0, -3.5), 0.03):
		return "unexpected circle offset bounds min: %s" % str(grown.get_bounding_box_min())
	if not _approx_vec(grown.get_bounding_box_max(), Vector3(13.5, 0.0, 3.5), 0.03):
		return "unexpected circle offset bounds max: %s" % str(grown.get_bounding_box_max())

	var shrunk := circle.offset_2d(-0.5)
	if shrunk == null or shrunk.is_null():
		return "negative circle offset returned null"
	if not _approx(shrunk.get_length(), TAU * 1.5, 0.05):
		return "unexpected shrunk circle circumference: %s" % shrunk.get_length()

	return ""


static func test_slot_overall_wire_default_plane() -> String:
	var slot := SlotOverallWire.new()
	slot.build_slot_overall(8.0, 2.0)

	if not slot.is_closed():
		return "slot wire was not closed"
	if not _approx(slot.get_length(), 12.0 + TAU, 0.03):
		return "unexpected slot perimeter: %s" % slot.get_length()
	if not _approx_vec(slot.get_bounding_box_size(), Vector3(8.0, 2.0, 0.0), 0.02):
		return "unexpected slot bounds size: %s" % str(slot.get_bounding_box_size())

	var face := Face.new()
	face.build_from_wire(slot, true)
	if not _approx(face.get_surface_area(), 12.0 + PI, 0.03):
		return "unexpected slot face area: %s" % face.get_surface_area()

	return ""


static func test_slot_overall_wire_custom_plane_and_circle_case() -> String:
	var plane := CadPlane.new()
	plane.set_plane(Vector3(10.0, 0.0, 0.0), Vector3.UP, Vector3.RIGHT)

	var slot := SlotOverallWire.new()
	slot.build_slot_overall(4.0, 4.0, plane, false)

	if not _approx_vec(slot.get_bounding_box_min(), Vector3(10.0, 0.0, -4.0), 0.03):
		return "unexpected custom-plane slot bounds min: %s" % str(slot.get_bounding_box_min())
	if not _approx_vec(slot.get_bounding_box_max(), Vector3(14.0, 0.0, 0.0), 0.03):
		return "unexpected custom-plane slot bounds max: %s" % str(slot.get_bounding_box_max())
	if not _approx(slot.get_length(), TAU * 2.0, 0.03):
		return "unexpected circular slot perimeter: %s" % slot.get_length()

	return ""
