class_name TestOcctlGodot

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

static func test_vector3_conversion() -> String:
	var c = OcctlGodot.new()
	var orig = Vector3(10.0, 20.0, 30.0)
	var ov = c.godot_to_occtl_vector3(orig)
	var back = c.occtl_vector3_to_godot(ov)
	if (back - orig).length() > 1e-12:
		return "Vector3 roundtrip failed: %s -> %s" % [orig, back]
	return ""

static func test_direction3_conversion() -> String:
	var c = OcctlGodot.new()
	var orig = Vector3(0.0, 0.0, 1.0)
	var d = c.vector3_to_direction3(orig)
	var back = c.direction3_to_vector3(d)
	if (back - orig).length() > 1e-12:
		return "direction3 roundtrip failed: %s -> %s" % [orig, back]
	return ""

static func test_transform_conversion() -> String:
	var c = OcctlGodot.new()
	var orig = Transform3D()
	orig = orig.rotated(Vector3(0, 1, 0), 0.5)
	orig = orig.translated(Vector3(10, 20, 30))
	var t = c.transform3d_to_transform(orig)
	var back = c.transform_to_transform3d(t)
	if (back.origin - orig.origin).length() > 1e-10:
		return "origin mismatch: %s vs %s" % [back.origin, orig.origin]
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

static func test_point2_conversion() -> String:
	var c = OcctlGodot.new()
	var orig = Vector2(100.0, 200.0)
	var p = c.vector2_to_point2(orig)
	var back = c.point2_to_vector2(p)
	if (back - orig).length() > 1e-12:
		return "Point2 roundtrip failed: %s -> %s" % [orig, back]
	return ""

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
	if (t.origin - Vector3(1, 2, 3)).length() > 1e-10:
		return "origin mismatch: %s" % t.origin
	if (t.basis.z - Vector3(0, 0, 1)).length() > 1e-10:
		return "z_dir mismatch: %s" % t.basis.z
	return ""

# ---------------------------------------------------------------------------
# Mesh batch methods — edge cases (no graph required)
# ---------------------------------------------------------------------------

static func test_edges_to_mesh_empty_array() -> String:
	var c = OcctlGodot.new()
	var mesh = c.edges_to_mesh(null, [])
	if mesh == null:
		return "expected non-null ArrayMesh"
	return ""

static func test_edges_to_mesh_null_graph() -> String:
	var c = OcctlGodot.new()
	var mesh = c.edges_to_mesh(null, [1, 2, 3])
	if mesh == null:
		return "expected non-null ArrayMesh"
	if mesh.get_surface_count() != 0:
		return "expected 0 surfaces for null graph, got %d" % mesh.get_surface_count()
	return ""

static func test_vertices_to_mesh_empty_array() -> String:
	var c = OcctlGodot.new()
	var mesh = c.vertices_to_mesh(null, [])
	if mesh == null:
		return "expected non-null ArrayMesh"
	return ""

static func test_vertices_to_mesh_null_graph() -> String:
	var c = OcctlGodot.new()
	var mesh = c.vertices_to_mesh(null, [1, 2, 3])
	if mesh == null:
		return "expected non-null ArrayMesh"
	if mesh.get_surface_count() != 0:
		return "expected 0 surfaces for null graph, got %d" % mesh.get_surface_count()
	return ""

static func test_faces_to_mesh_empty_array() -> String:
	var c = OcctlGodot.new()
	var mesh = c.faces_to_mesh(null, [])
	if mesh == null:
		return "expected non-null ArrayMesh"
	return ""

static func test_faces_to_mesh_null_graph() -> String:
	var c = OcctlGodot.new()
	var mesh = c.faces_to_mesh(null, [1, 2, 3])
	if mesh == null:
		return "expected non-null ArrayMesh"
	if mesh.get_surface_count() != 0:
		return "expected 0 surfaces for null graph, got %d" % mesh.get_surface_count()
	return ""

# ---------------------------------------------------------------------------
# Mesh batch methods — integration tests
# Creates a box solid, meshes it, then converts faces/edges/vertices
# ---------------------------------------------------------------------------

static func _collect_node_kind_ids(graph, kind: int) -> Array:
	var topo = OcctlTopo.new()
	var ids = []
	# Use per-kind iterator instead of graph_for_each
	var iter: Ref<OcctlNodeIterHandle>
	match kind:
		OcctlCore.OCCTL_KIND_SOLID:
			iter = topo.graph_solid_iter_create(graph)
		OcctlCore.OCCTL_KIND_SHELL:
			iter = topo.graph_shell_iter_create(graph)
		OcctlCore.OCCTL_KIND_FACE:
			iter = topo.graph_face_iter_create(graph)
		OcctlCore.OCCTL_KIND_WIRE:
			iter = topo.graph_wire_iter_create(graph)
		OcctlCore.OCCTL_KIND_EDGE:
			iter = topo.graph_edge_iter_create(graph)
		OcctlCore.OCCTL_KIND_VERTEX:
			iter = topo.graph_vertex_iter_create(graph)
		OcctlCore.OCCTL_KIND_COMPOUND:
			iter = topo.graph_compound_iter_create(graph)
		OcctlCore.OCCTL_KIND_COMPSOLID:
			iter = topo.graph_compsolid_iter_create(graph)
		OcctlCore.OCCTL_KIND_COEDGE:
			iter = topo.graph_coedge_iter_create(graph)
		_:
			return []
	if iter == null:
		return []
	var out_id = OcctlNodeId.new()
	while true:
		var status = topo.node_iter_next(iter, out_id)
		if status != 0:
			break
		ids.append(out_id.get_bits())
	return ids

static func _make_box_graph() -> Dictionary:
	var core = OcctlCore.new()
	var rt_status = core.runtime_init()
	# OCCTL_INVALID_ARGUMENT (2) = runtime already initialized — not a fatal error
	if rt_status != 0 and rt_status != 2:
		return {"error": "runtime_init failed: %d" % rt_status}

	var topo = OcctlTopo.new()
	var graph = topo.graph_create()
	if graph == null:
		return {"error": "graph_create returned null"}

	var prim = OcctlPrimSolid.new()
	var info = OcctlPrimBoxInfo.new()
	prim.box_info_init(info)
	info.set_dx(10.0)
	info.set_dy(20.0)
	info.set_dz(30.0)

	var box_root = OcctlNodeId.new()
	var status = prim.make_box(graph, info, box_root)
	if status != 0:
		return {"error": "make_box failed: %d" % status}

	return {"graph": graph, "root": box_root, "core": core}

static func test_faces_to_mesh_with_box() -> String:
	var result = _make_box_graph()
	if result.has("error"):
		return result.error

	var mw = OcctlMesh.new()
	var mesh_opts = OcctlMeshOptions.new()
	mw.options_init(mesh_opts)
	mesh_opts.set_deflection(1.0)
	var mesh_status = mw.generate(result.graph, result.root.get_bits(), 1, mesh_opts)
	if mesh_status != 0:
		return "mesh generate failed: %d" % mesh_status

	var face_ids = _collect_node_kind_ids(result.graph, OcctlCore.OCCTL_KIND_FACE)
	if face_ids.size() == 0:
		return "no faces found in box graph"

	var c = OcctlGodot.new()
	var mesh = c.faces_to_mesh(result.graph, PackedInt64Array(face_ids),
		true, true, true, true)
	if mesh == null:
		return "faces_to_mesh returned null"
	if mesh.get_surface_count() == 0:
		return "expected at least 1 surface, got 0"

	var surface_arrays = mesh.surface_get_arrays(0)
	if surface_arrays.size() <= Mesh.ARRAY_VERTEX:
		return "surface arrays too small"
	var verts = surface_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	if verts.size() == 0:
		return "expected non-empty vertex array"

	var has_normals = surface_arrays[Mesh.ARRAY_NORMAL] != null
	var has_uvs = surface_arrays[Mesh.ARRAY_TEX_UV] != null
	var has_tangents = surface_arrays[Mesh.ARRAY_TANGENT] != null
	var has_colors = surface_arrays[Mesh.ARRAY_COLOR] != null

	if not has_normals:
		return "expected normals (include_normals=true)"
	if not has_uvs:
		return "expected UVs (include_uvs=true)"
	if not has_tangents:
		return "expected tangents (include_tangents=true)"
	if not has_colors:
		return "expected feature ID colors (include_feature_ids=true)"

	result.core.runtime_shutdown()
	return ""

static func test_edges_to_mesh_with_box() -> String:
	var result = _make_box_graph()
	if result.has("error"):
		return result.error

	var mw = OcctlMesh.new()
	var mesh_opts = OcctlMeshOptions.new()
	mw.options_init(mesh_opts)
	mesh_opts.set_deflection(1.0)
	var mesh_status = mw.generate(result.graph, result.root.get_bits(), 1, mesh_opts)
	if mesh_status != 0:
		return "mesh generate failed: %d" % mesh_status

	var edge_ids = _collect_node_kind_ids(result.graph, OcctlCore.OCCTL_KIND_EDGE)
	if edge_ids.size() == 0:
		return "no edges found in box graph"

	var c = OcctlGodot.new()

	var tube_mesh = c.edges_to_mesh(result.graph, PackedInt64Array(edge_ids),
		0.5, true, true)
	if tube_mesh == null:
		return "edges_to_mesh(tube) returned null"
	if tube_mesh.get_surface_count() == 0:
		return "expected at least 1 surface for tube edges, got 0"

	var line_mesh = c.edges_to_mesh(result.graph, PackedInt64Array(edge_ids),
		0.0, false, true)
	if line_mesh == null:
		return "edges_to_mesh(lines) returned null"
	if line_mesh.get_surface_count() == 0:
		return "expected at least 1 surface for line edges, got 0"

	result.core.runtime_shutdown()
	return ""

static func test_vertices_to_mesh_with_box() -> String:
	var result = _make_box_graph()
	if result.has("error"):
		return result.error

	var mw = OcctlMesh.new()
	var mesh_opts = OcctlMeshOptions.new()
	mw.options_init(mesh_opts)
	mesh_opts.set_deflection(1.0)
	var mesh_status = mw.generate(result.graph, result.root.get_bits(), 1, mesh_opts)
	if mesh_status != 0:
		return "mesh generate failed: %d" % mesh_status

	var vert_ids = _collect_node_kind_ids(result.graph, OcctlCore.OCCTL_KIND_VERTEX)
	if vert_ids.size() == 0:
		return "no vertices found in box graph"

	var c = OcctlGodot.new()
	var mesh = c.vertices_to_mesh(result.graph, PackedInt64Array(vert_ids),
		true, true)
	if mesh == null:
		return "vertices_to_mesh returned null"
	if mesh.get_surface_count() == 0:
		return "expected at least 1 surface for vertices, got 0"

	result.core.runtime_shutdown()
	return ""
