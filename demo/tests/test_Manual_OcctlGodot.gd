class_name TestOcctlGodot

# ---------------------------------------------------------------------------
# Point3 <-> Vector3
# ---------------------------------------------------------------------------
static func test_point3_to_vector3() -> String:
	var c = OcctlGodot.new()
	var p = OcctlPoint3.new()
	p.set_x(1.5)
	p.set_y(2.5)
	p.set_z(3.5)
	var v = c.point3_to_vector3(p)
	if abs(v.x - 1.5) > 1e-12: return "x mismatch: %s" % v
	if abs(v.y - 2.5) > 1e-12: return "y mismatch: %s" % v
	if abs(v.z - 3.5) > 1e-12: return "z mismatch: %s" % v
	return ""

static func test_vector3_to_point3() -> String:
	var c = OcctlGodot.new()
	var v = Vector3(4.0, 5.0, 6.0)
	var p = c.vector3_to_point3(v)
	if abs(p.get_x() - 4.0) > 1e-12: return "x mismatch: %s" % p.get_x()
	if abs(p.get_y() - 5.0) > 1e-12: return "y mismatch: %s" % p.get_y()
	if abs(p.get_z() - 6.0) > 1e-12: return "z mismatch: %s" % p.get_z()
	return ""

static func test_point3_roundtrip() -> String:
	var c = OcctlGodot.new()
	var orig = Vector3(7.0, 8.0, 9.0)
	var p = c.vector3_to_point3(orig)
	var back = c.point3_to_vector3(p)
	if (back - orig).length() > 1e-12:
		return "roundtrip failed: %s -> %s" % [orig, back]
	return ""

# ---------------------------------------------------------------------------
# OCCT Vector3 <-> Godot Vector3
# ---------------------------------------------------------------------------
static func test_vector3_conversion() -> String:
	var c = OcctlGodot.new()
	var orig = Vector3(10.0, 20.0, 30.0)
	var ov = c.godot_to_occtl_vector3(orig)
	var back = c.occtl_vector3_to_godot(ov)
	if (back - orig).length() > 1e-12:
		return "Vector3 roundtrip failed: %s -> %s" % [orig, back]
	return ""

# ---------------------------------------------------------------------------
# Direction3 <-> Vector3
# ---------------------------------------------------------------------------
static func test_direction3_conversion() -> String:
	var c = OcctlGodot.new()
	var orig = Vector3(0.0, 0.0, 1.0)
	var d = c.vector3_to_direction3(orig)
	var back = c.direction3_to_vector3(d)
	if (back - orig).length() > 1e-12:
		return "direction3 roundtrip failed: %s -> %s" % [orig, back]
	return ""

# ---------------------------------------------------------------------------
# Transform <-> Transform3D
# ---------------------------------------------------------------------------
static func test_transform_conversion() -> String:
	var c = OcctlGodot.new()
	var orig = Transform3D()
	orig = orig.rotated(Vector3(0, 1, 0), 0.5)
	orig = orig.translated(Vector3(10, 20, 30))

	var t = c.transform3d_to_transform(orig)
	var back = c.transform_to_transform3d(t)

	# Compare origin
	if (back.origin - orig.origin).length() > 1e-10:
		return "origin mismatch: %s vs %s" % [back.origin, orig.origin]

	# Compare basis columns (GDScript exposes basis.x/y/z as column vectors)
	var cols_orig = [orig.basis.x, orig.basis.y, orig.basis.z]
	var cols_back = [back.basis.x, back.basis.y, back.basis.z]
	for i in 3:
		var diff = (cols_back[i] - cols_orig[i]).length()
		if diff > 1e-10:
			return "basis column %d mismatch: diff=%s" % [i, diff]
	return ""

static func test_transform_identity_roundtrip() -> String:
	var c = OcctlGodot.new()
	var orig = Transform3D()
	var t = c.transform3d_to_transform(orig)
	var back = c.transform_to_transform3d(t)
	if (back.origin - orig.origin).length() > 1e-12:
		return "origin mismatch"
	var cols_orig = [orig.basis.x, orig.basis.y, orig.basis.z]
	var cols_back = [back.basis.x, back.basis.y, back.basis.z]
	for i in 3:
		if (cols_back[i] - cols_orig[i]).length() > 1e-12:
			return "basis column %d mismatch" % i
	return ""

# ---------------------------------------------------------------------------
# Aabb3 <-> AABB
# ---------------------------------------------------------------------------
static func test_aabb3_conversion() -> String:
	var c = OcctlGodot.new()
	var orig = AABB(Vector3(1, 2, 3), Vector3(4, 5, 6))
	var a = c.aabb_to_aabb3(orig)
	var back = c.aabb3_to_aabb(a)

	if abs(back.position.x - 1.0) > 1e-12: return "min x mismatch"
	if abs(back.position.y - 2.0) > 1e-12: return "min y mismatch"
	if abs(back.position.z - 3.0) > 1e-12: return "min z mismatch"
	if abs(back.size.x - 4.0) > 1e-12: return "size x mismatch"
	if abs(back.size.y - 5.0) > 1e-12: return "size y mismatch"
	if abs(back.size.z - 6.0) > 1e-12: return "size z mismatch"
	return ""

# ---------------------------------------------------------------------------
# ColorRgba <-> Color
# ---------------------------------------------------------------------------
static func test_color_conversion() -> String:
	var c = OcctlGodot.new()
	var orig = Color(0.1, 0.2, 0.3, 0.8)
	var cc = c.color_to_color_rgba(orig)
	var back = c.color_rgba_to_color(cc)

	if abs(back.r - 0.1) > 1e-6: return "r mismatch: %s" % back.r
	if abs(back.g - 0.2) > 1e-6: return "g mismatch: %s" % back.g
	if abs(back.b - 0.3) > 1e-6: return "b mismatch: %s" % back.b
	if abs(back.a - 0.8) > 1e-6: return "a mismatch: %s" % back.a
	return ""

# ---------------------------------------------------------------------------
# Point2 <-> Vector2
# ---------------------------------------------------------------------------
static func test_point2_conversion() -> String:
	var c = OcctlGodot.new()
	var orig = Vector2(100.0, 200.0)
	var p = c.vector2_to_point2(orig)
	var back = c.point2_to_vector2(p)
	if (back - orig).length() > 1e-12:
		return "Point2 roundtrip failed: %s -> %s" % [orig, back]
	return ""

# ---------------------------------------------------------------------------
# AxisPlacement -> Transform3D
# ---------------------------------------------------------------------------
static func test_axis3_placement_to_transform3d() -> String:
	var c = OcctlGodot.new()
	var loc = OcctlPoint3.new()
	loc.set_x(5.0); loc.set_y(0.0); loc.set_z(0.0)
	var xd = OcctlDirection3.new()
	xd.set_x(0.0); xd.set_y(1.0); xd.set_z(0.0)
	var yd = OcctlDirection3.new()
	yd.set_x(0.0); yd.set_y(0.0); yd.set_z(1.0)
	var zd = OcctlDirection3.new()
	zd.set_x(1.0); zd.set_y(0.0); zd.set_z(0.0)

	var a = OcctlAxis3Placement.new()
	a.set_location(loc)
	a.set_x_dir(xd)
	a.set_y_dir(yd)
	a.set_z_dir(zd)

	var t = c.axis3_placement_to_transform3d(a)

	if (t.origin - Vector3(5, 0, 0)).length() > 1e-10:
		return "origin mismatch: %s" % t.origin

	# basis.x = column 0 = (x_dir.x, y_dir.x, z_dir.x) = (0, 0, 1)
	# basis.y = column 1 = (x_dir.y, y_dir.y, z_dir.y) = (1, 0, 0)
	# basis.z = column 2 = (x_dir.z, y_dir.z, z_dir.z) = (0, 1, 0)
	if (t.basis.x - Vector3(0, 0, 1)).length() > 1e-10:
		return "basis.x mismatch: got %s, expected (0,0,1)" % t.basis.x
	if (t.basis.y - Vector3(1, 0, 0)).length() > 1e-10:
		return "basis.y mismatch: got %s, expected (1,0,0)" % t.basis.y
	if (t.basis.z - Vector3(0, 1, 0)).length() > 1e-10:
		return "basis.z mismatch: got %s, expected (0,1,0)" % t.basis.z
	return ""

static func test_axis2_placement_to_transform3d() -> String:
	var c = OcctlGodot.new()
	var loc = OcctlPoint3.new()
	loc.set_x(0.0); loc.set_y(0.0); loc.set_z(0.0)
	var xd = OcctlDirection3.new()
	xd.set_x(1.0); xd.set_y(0.0); xd.set_z(0.0)
	var xdr = OcctlDirection3.new()
	xdr.set_x(0.0); xdr.set_y(1.0); xdr.set_z(0.0)

	var a = OcctlAxis2Placement.new()
	a.set_location(loc)
	a.set_x_dir(xd)
	a.set_x_dir_ref(xdr)

	var t = c.axis2_placement_to_transform3d(a)

	# basis.x = column 0 = (x_dir.x, y_dir.x, z_dir.x) = (1, 0, 0)
	# basis.y = column 1 = (x_dir.y, y_dir.y, z_dir.y) = (0, 1, 0)
	# basis.z = column 2 = (x_dir.z, y_dir.z, z_dir.z) = (0, 0, 1)
	if (t.basis.x - Vector3(1, 0, 0)).length() > 1e-10:
		return "basis.x mismatch: %s" % t.basis.x
	if (t.basis.y - Vector3(0, 1, 0)).length() > 1e-10:
		return "basis.y mismatch: %s" % t.basis.y
	if (t.basis.z - Vector3(0, 0, 1)).length() > 1e-10:
		return "basis.z mismatch: %s" % t.basis.z
	return ""

static func test_axis1_placement_to_transform3d_z() -> String:
	var c = OcctlGodot.new()
	var loc = OcctlPoint3.new()
	loc.set_x(1.0); loc.set_y(2.0); loc.set_z(3.0)
	var dir = OcctlDirection3.new()
	dir.set_x(0.0); dir.set_y(0.0); dir.set_z(1.0)

	var a = OcctlAxis1Placement.new()
	a.set_location(loc)
	a.set_direction(dir)

	var t = c.axis1_placement_to_transform3d(a)

	# Origin should be at (1, 2, 3)
	if (t.origin - Vector3(1, 2, 3)).length() > 1e-10:
		return "origin mismatch: %s" % t.origin

	# basis.z = column 2 = rows[2] = z_dir
	if (t.basis.z - Vector3(0, 0, 1)).length() > 1e-10:
		return "z_dir mismatch: %s" % t.basis.z
	return ""

# ---------------------------------------------------------------------------
# Mesh buffers -> ArrayMesh (empty — must not crash)
# ---------------------------------------------------------------------------
static func test_triangulation_to_array_mesh_empty() -> String:
	var c = OcctlGodot.new()
	var view = OcctlTriangulationView.new()
	view.set_nodes(0)
	view.set_node_count(0)
	view.set_triangles(0)
	view.set_triangle_count(0)
	var mesh = c.triangulation_to_array_mesh(view)
	if mesh == null:
		return "expected non-null ArrayMesh, got null"
	if mesh.get_surface_count() != 0:
		return "expected 0 surfaces for empty view, got %d" % mesh.get_surface_count()
	return ""

static func test_mesh_buffers_to_array_mesh_empty() -> String:
	var c = OcctlGodot.new()
	var view = OcctlMeshTriangleBuffersView.new()
	view.set_nodes(0)
	view.set_node_count(0)
	view.set_triangles(0)
	view.set_triangle_count(0)
	var mesh = c.mesh_buffers_to_array_mesh(view)
	if mesh == null:
		return "expected non-null ArrayMesh, got null"
	if mesh.get_surface_count() != 0:
		return "expected 0 surfaces for empty view, got %d" % mesh.get_surface_count()
	return ""

# ---------------------------------------------------------------------------
# Polygon -> points (empty — must not crash)
# ---------------------------------------------------------------------------
static func test_polygon3d_to_points_empty() -> String:
	var c = OcctlGodot.new()
	var view = OcctlPolygon3dView.new()
	view.set_nodes(0)
	view.set_node_count(0)
	var pts = c.polygon3d_to_points(view)
	if pts.size() != 0:
		return "expected empty array, got size %d" % pts.size()
	return ""

static func test_polygon_on_tri_to_world_points_empty() -> String:
	var c = OcctlGodot.new()
	var tri_view = OcctlTriangulationView.new()
	tri_view.set_nodes(0)
	tri_view.set_node_count(0)
	var poly_view = OcctlPolygonOnTriView.new()
	poly_view.set_node_indices(0)
	poly_view.set_node_count(0)
	var pts = c.polygon_on_tri_to_world_points(tri_view, poly_view)
	if pts.size() != 0:
		return "expected empty array, got size %d" % pts.size()
	return ""
