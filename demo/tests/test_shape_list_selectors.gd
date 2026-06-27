class_name TestShapeListSelectors


static func _approx(a: float, b: float, epsilon := 0.001) -> bool:
	return absf(a - b) <= epsilon


static func _approx_vec(a: Vector3, b: Vector3, epsilon := 0.001) -> bool:
	return _approx(a.x, b.x, epsilon) and _approx(a.y, b.y, epsilon) and _approx(a.z, b.z, epsilon)


func _is_right_of_origin(shape: TopoShape) -> bool:
	return shape.get_center_of_mass().x > 1.0


func _sort_by_center_x(shape: TopoShape) -> float:
	return shape.get_center_of_mass().x


func _group_by_center_x(shape: TopoShape) -> float:
	return shape.get_center_of_mass().x


static func test_shape_list_position_and_distance() -> String:
	var left := SolidBox.new()
	left.build_box(Vector3.ONE, Vector3.ZERO)

	var middle := SolidBox.new()
	middle.build_box(Vector3.ONE, Vector3(2.0, 0.0, 0.0))

	var right := SolidBox.new()
	right.build_box(Vector3.ONE, Vector3(6.0, 0.0, 0.0))

	var shapes := ShapeList.new()
	shapes.append(right)
	shapes.append(left)
	shapes.append(middle)

	var axis := Axis.new()
	axis.set_axis(Vector3.ZERO, Vector3.RIGHT)

	if shapes.size() != 3:
		return "unexpected shape list size: %s" % shapes.size()
	if shapes.is_empty():
		return "shape list unexpectedly empty"

	var filtered := shapes.filter_by_axis(axis, 1.0, 3.0)
	if filtered.size() != 1:
		return "expected one shape in filtered list but got %s" % filtered.size()
	if not _approx(filtered.get_item(0).get_center_of_mass().x, 2.5, 0.02):
		return "unexpected filtered shape center: %s" % filtered.get_item(0).get_center_of_mass().x

	var axis_sorted := shapes.sort_by_axis(axis)
	if axis_sorted.size() != 3:
		return "unexpected axis-sorted list size: %s" % axis_sorted.size()
	if not _approx(axis_sorted.get_item(0).get_center_of_mass().x, 0.5, 0.02):
		return "axis sort did not place the nearest shape first"

	var sorted := shapes.sort_by_distance(middle)
	if sorted.size() != 3:
		return "unexpected sorted list size: %s" % sorted.size()
	if not _approx(sorted.get_item(0).get_center_of_mass().x, 2.5, 0.02):
		return "distance sort did not place middle shape first"
	if not _approx(sorted.get_item(2).get_center_of_mass().x, 6.5, 0.02):
		return "distance sort did not place farthest shape last"

	var sorted_point := shapes.sort_by_distance_to_point(Vector3.ZERO)
	if sorted_point.size() != 3:
		return "unexpected point-sorted list size: %s" % sorted_point.size()
	if not _approx(sorted_point.get_item(0).get_center_of_mass().x, 0.5, 0.02):
		return "point distance sort did not place the nearest shape first"

	if not _approx_vec(shapes.center(), Vector3(3.1666667, 0.5, 0.5), 0.02):
		return "unexpected shape list center: %s" % str(shapes.center())
	if not _approx_vec(shapes.get_bounding_box_min(), Vector3.ZERO, 0.001):
		return "unexpected shape list bounds min: %s" % str(shapes.get_bounding_box_min())
	if not _approx_vec(shapes.get_bounding_box_max(), Vector3(7.0, 1.0, 1.0), 0.001):
		return "unexpected shape list bounds max: %s" % str(shapes.get_bounding_box_max())
	if not _approx_vec(shapes.get_bounding_box_size(), Vector3(7.0, 1.0, 1.0), 0.001):
		return "unexpected shape list bounds size: %s" % str(shapes.get_bounding_box_size())

	var first := shapes.first()
	var last := shapes.last()
	if first == null or last == null:
		return "first/last returned null"
	if not _approx_vec(first.get_bounding_box_min(), Vector3(6.0, 0.0, 0.0), 0.001):
		return "first did not return the first appended shape"
	if not _approx_vec(last.get_bounding_box_min(), Vector3(2.0, 0.0, 0.0), 0.001):
		return "last did not return the last appended shape"

	var plane := CadPlane.new()
	plane.set_plane(Vector3.ZERO, Vector3.UP, Vector3.RIGHT)
	var face := Face.new()
	face.build_polygon(PackedVector3Array([
		Vector3.ZERO,
		Vector3.RIGHT,
		Vector3(1.0, 1.0, 0.0),
		Vector3.UP,
	]), true)
	var plane_edge := Edge.new()
	plane_edge.build_line(Vector3.ZERO, Vector3.RIGHT)
	var vertical_edge := Edge.new()
	vertical_edge.build_line(Vector3.ZERO, Vector3.FORWARD)
	var plane_shapes := ShapeList.new()
	plane_shapes.append(face)
	plane_shapes.append(plane_edge)
	plane_shapes.append(vertical_edge)
	var filtered_plane := plane_shapes.filter_by_plane(plane)
	if filtered_plane.size() != 2:
		return "expected 2 plane-filtered shapes but got %s" % filtered_plane.size()

	var geom_type_filtered := plane_shapes.filter_by_geom_type("LINE")
	if geom_type_filtered.size() != 2:
		return "expected two line geom-type shapes but got %s" % geom_type_filtered.size()
	var plane_geom_filtered := plane_shapes.filter_by_geom_type("PLANE")
	if plane_geom_filtered.size() != 1:
		return "expected one plane geom-type shape but got %s" % plane_geom_filtered.size()
	var geom_type_sorted := plane_shapes.sort_by_geom_type()
	if geom_type_sorted.size() != 3:
		return "unexpected geom-type sorted size: %s" % geom_type_sorted.size()
	if geom_type_sorted.get_item(0).get_geom_type_name() != "LINE":
		return "sort_by_geom_type did not place line shapes first"
	if geom_type_sorted.get_item(2).get_geom_type_name() != "PLANE":
		return "sort_by_geom_type did not place the plane last"
	var geom_type_grouped := plane_shapes.group_by_geom_type()
	if geom_type_grouped.size() != 2:
		return "expected two geom-type groups but got %s" % geom_type_grouped.size()
	if geom_type_grouped[0].get_item(0).get_geom_type_name() != "LINE":
		return "group_by_geom_type did not order groups by geom type name"
	if geom_type_grouped[1].get_item(0).get_geom_type_name() != "PLANE":
		return "group_by_geom_type returned an unexpected last group"

	var short_edge := Edge.new()
	short_edge.build_line(Vector3.ZERO, Vector3.RIGHT)
	var long_edge := Edge.new()
	long_edge.build_line(Vector3.ZERO, Vector3.RIGHT * 2.0)
	var length_shapes := ShapeList.new()
	length_shapes.append(long_edge)
	length_shapes.append(short_edge)
	var sorted_length := length_shapes.sort_by_length()
	if not _approx(sorted_length.get_item(0).get_length(), 1.0, 0.001):
		return "sort_by_length did not place the shorter edge first"

	var small_box := SolidBox.new()
	small_box.build_box(Vector3.ONE)
	var large_box := SolidBox.new()
	large_box.build_box(Vector3(2.0, 2.0, 2.0))
	var volume_shapes := ShapeList.new()
	volume_shapes.append(large_box)
	volume_shapes.append(small_box)
	var sorted_volume := volume_shapes.sort_by_volume()
	if not _approx(sorted_volume.get_item(0).get_volume(), 1.0, 0.001):
		return "sort_by_volume did not place the smaller box first"

	var length_filtered := length_shapes.filter_by_length(1.1, 2.1)
	if length_filtered.size() != 1:
		return "expected one length-filtered edge but got %s" % length_filtered.size()
	if not _approx(length_filtered.get_item(0).get_length(), 2.0, 0.001):
		return "filter_by_length returned the wrong edge"

	var area_filtered := volume_shapes.filter_by_area(20.0, 30.0)
	if area_filtered.size() != 1:
		return "expected one area-filtered shape but got %s" % area_filtered.size()
	if not _approx(area_filtered.get_item(0).get_surface_area(), 24.0, 0.001):
		return "filter_by_area returned the wrong box"

	var volume_filtered := volume_shapes.filter_by_volume(0.5, 1.5)
	if volume_filtered.size() != 1:
		return "expected one volume-filtered shape but got %s" % volume_filtered.size()
	if not _approx(volume_filtered.get_item(0).get_volume(), 1.0, 0.001):
		return "filter_by_volume returned the wrong box"

	var point_filtered := shapes.filter_by_distance_to_point(Vector3.ZERO, 0.0, 1.0)
	if point_filtered.size() != 1:
		return "expected one point-filtered shape but got %s" % point_filtered.size()
	if not _approx(point_filtered.get_item(0).get_center_of_mass().x, 0.5, 0.02):
		return "filter_by_distance_to_point returned the wrong shape"

	var point_filtered_exclusive := shapes.filter_by_distance_to_point(Vector3.ZERO, 0.0, 0.4, false, false)
	if point_filtered_exclusive.size() != 0:
		return "expected no exclusive point-filtered shapes but got %s" % point_filtered_exclusive.size()

	var shape_type_filtered := shapes.filter_by_shape_type("SOLID")
	if shape_type_filtered.size() != 3:
		return "expected three solid shapes but got %s" % shape_type_filtered.size()
	if shape_type_filtered.get_item(0).get_shape_type_name() != "SOLID":
		return "filter_by_shape_type did not preserve solid shape kinds"

	var edge_type_filtered := plane_shapes.filter_by_shape_type("EDGE")
	if edge_type_filtered.size() != 2:
		return "expected two edges but got %s" % edge_type_filtered.size()

	var shape_type_shapes := ShapeList.new()
	shape_type_shapes.append(face)
	shape_type_shapes.append(plane_edge)
	var shape_type_solid := SolidBox.new()
	shape_type_solid.build_box(Vector3.ONE)
	shape_type_shapes.append(shape_type_solid)
	var shape_type_sorted := shape_type_shapes.sort_by_shape_type()
	if shape_type_sorted.size() != 3:
		return "unexpected shape-type sorted size: %s" % shape_type_sorted.size()
	if shape_type_sorted.get_item(0).get_shape_type_name() != "SOLID":
		return "sort_by_shape_type did not place the solid first"
	if shape_type_sorted.get_item(2).get_shape_type_name() != "EDGE":
		return "sort_by_shape_type did not place the edge last"
	var shape_type_sorted_reverse := shape_type_shapes.sort_by_shape_type(true)
	if shape_type_sorted_reverse.get_item(0).get_shape_type_name() != "EDGE":
		return "reverse sort_by_shape_type did not place the edge first"

	var shape_type_grouped := shape_type_shapes.group_by_shape_type()
	if shape_type_grouped.size() != 3:
		return "expected three shape-type groups but got %s" % shape_type_grouped.size()
	if shape_type_grouped[0].get_item(0).get_shape_type_name() != "EDGE":
		return "group_by_shape_type did not order groups by type name"
	if shape_type_grouped[1].get_item(0).get_shape_type_name() != "FACE":
		return "group_by_shape_type returned an unexpected middle group"
	if shape_type_grouped[2].get_item(0).get_shape_type_name() != "SOLID":
		return "group_by_shape_type returned an unexpected last group"

	var axis_group_shapes := ShapeList.new()
	var axis_group_a := SolidBox.new()
	axis_group_a.build_box(Vector3.ONE, Vector3.ZERO)
	var axis_group_b := SolidBox.new()
	axis_group_b.build_box(Vector3.ONE, Vector3(0.0, 2.0, 0.0))
	var axis_group_c := SolidBox.new()
	axis_group_c.build_box(Vector3.ONE, Vector3(2.0, 0.0, 0.0))
	axis_group_shapes.append(axis_group_a)
	axis_group_shapes.append(axis_group_b)
	axis_group_shapes.append(axis_group_c)
	var x_axis := Axis.new()
	x_axis.set_axis(Vector3.ZERO, Vector3.RIGHT)
	var grouped_axis := axis_group_shapes.group_by_axis(x_axis)
	if grouped_axis.size() != 2:
		return "expected two X-axis groups but got %s" % grouped_axis.size()
	if grouped_axis[0].size() != 2 or grouped_axis[1].size() != 1:
		return "unexpected X-axis grouping sizes: %s / %s" % [grouped_axis[0].size(), grouped_axis[1].size()]

	var grouped_length := length_shapes.group_by_length()
	if grouped_length.size() != 2:
		return "expected two length groups but got %s" % grouped_length.size()
	if grouped_length[0].size() != 1 or grouped_length[1].size() != 1:
		return "unexpected length grouping sizes: %s / %s" % [grouped_length[0].size(), grouped_length[1].size()]

	var grouped_area := volume_shapes.group_by_area()
	if grouped_area.size() != 2:
		return "expected two area groups but got %s" % grouped_area.size()
	if grouped_area[0].size() != 1 or grouped_area[1].size() != 1:
		return "unexpected area grouping sizes: %s / %s" % [grouped_area[0].size(), grouped_area[1].size()]

	var grouped_volume := volume_shapes.group_by_volume()
	if grouped_volume.size() != 2:
		return "expected two volume groups but got %s" % grouped_volume.size()
	if grouped_volume[0].size() != 1 or grouped_volume[1].size() != 1:
		return "unexpected volume grouping sizes: %s / %s" % [grouped_volume[0].size(), grouped_volume[1].size()]

	var helper := TestShapeListSelectors.new()
	var callable_filtered := shapes.filter_by(Callable(helper, "_is_right_of_origin"))
	if callable_filtered.size() != 2:
		return "expected two callable-filtered shapes but got %s" % callable_filtered.size()

	var callable_sorted := shapes.sort_by(Callable(helper, "_sort_by_center_x"))
	if callable_sorted.size() != 3:
		return "unexpected callable-sorted size: %s" % callable_sorted.size()
	if not _approx(callable_sorted.get_item(0).get_center_of_mass().x, 0.5, 0.02):
		return "sort_by callable did not place the leftmost shape first"

	var callable_grouped := axis_group_shapes.group_by(Callable(helper, "_group_by_center_x"))
	if callable_grouped.size() != 2:
		return "expected two callable groups but got %s" % callable_grouped.size()
	if callable_grouped[0].size() != 2 or callable_grouped[1].size() != 1:
		return "unexpected callable grouping sizes: %s / %s" % [callable_grouped[0].size(), callable_grouped[1].size()]

	var expanded := shapes.solids()
	if expanded.size() != 3:
		return "expected solids() to preserve all solids but got %s" % expanded.size()

	return ""
