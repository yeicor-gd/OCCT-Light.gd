class_name TestCadWorkflows

# ---------------------------------------------------------------------------
# Hand-written integration tests exercising common CAD workflows.
# Each test is a static func returning "" on success or an error message.
# ---------------------------------------------------------------------------

# OCCTL status codes
const OK := 0
const NOT_FOUND := 4

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

# Helper: init runtime (tolerates double-init)
static func _init_runtime() -> int:
	var rt_status = OclCore.runtime_init()
	if rt_status != OK and rt_status != 2:
		return rt_status
	return OK

# Helper: format a status code with its string name for error messages
static func _status_str(s: int) -> String:
	return "%s (%d)" % [OclCore.status_to_string(s), s]

# Helper: format a node kind with its string name for error messages
static func _kind_str(k: int) -> String:
	return "%s (%d)" % [OclCore.node_kind_to_string(k), k]

# Helper: create a simple box on a new graph.
# Returns Dictionary with "graph", "root" keys, or {"error": ...}.
static func _make_box(dx: float = 10.0, dy: float = 10.0, dz: float = 10.0) -> Dictionary:
	var init_err = _init_runtime()
	if init_err != OK:
		return {"error": "runtime_init failed: %s" % _status_str(init_err)}

	var graph := OclGraphHandle.new()
	var create_err := OclTopo.graph_create(graph)
	if create_err != 0 or graph == null:
		return {"error": "graph_create returned null"}

	var info = OclPrimBoxInfo.new()
	info.set_dx(dx)
	info.set_dy(dy)
	info.set_dz(dz)
	var out_solid = OclNodeId.new()
	var status = OclPrimSolid.box(graph, info, out_solid)
	if status != OK:
		return {"error": "make_box failed: %s" % _status_str(status)}
	return {"graph": graph, "root": out_solid}

# Helper: create two overlapping boxes in the same graph for boolean ops
static func _make_two_overlapping_boxes() -> Dictionary:
	var init_err = _init_runtime()
	if init_err != OK:
		return {"error": "runtime_init failed: %s" % _status_str(init_err)}

	var graph := OclGraphHandle.new()
	var create_err := OclTopo.graph_create(graph)
	if create_err != 0 or graph == null:
		return {"error": "graph_create returned null"}
	# Box 1 at origin
	var info1 = OclPrimBoxInfo.new()
	info1.set_dx(20.0)
	info1.set_dy(20.0)
	info1.set_dz(20.0)
	var out1 = OclNodeId.new()
	var status = OclPrimSolid.box(graph, info1, out1)
	if status != OK:
		return {"error": "make_box 1 failed: %s" % _status_str(status)}

	# Box 2 shifted by +10 in X so they overlap by 10
	var info2 = OclPrimBoxInfo.new()
	info2.set_dx(20.0)
	info2.set_dy(20.0)
	info2.set_dz(20.0)
	var axis = OclAxis2Placement.new()
	var loc = OclPoint3.new()
	loc.set_x(10.0)
	loc.set_y(0.0)
	loc.set_z(0.0)
	axis.set_location(loc)
	var x_dir = OclDirection3.new()
	x_dir.set_x(1.0)
	axis.set_x_dir(x_dir)
	var x_dir_ref = OclDirection3.new()
	x_dir_ref.set_y(1.0)
	axis.set_x_dir_ref(x_dir_ref)
	info2.set_placement(axis)
	var out2 = OclNodeId.new()
	status = OclPrimSolid.box(graph, info2, out2)
	if status != OK:
		return {"error": "make_box 2 failed: %s" % _status_str(status)}

	return {"graph": graph, "box1": out1, "box2": out2}

# Helper: collect node ids of a given kind from a graph
static func _collect_ids(graph: OclGraphHandle, kind: int) -> Array:
	var ids = []
	var out_iter := OclNodeIterHandle.new()
	var status: int
	match kind:
		OclCore.KIND_SOLID:
			status = OclTopo.graph_solid_iter_create(graph, out_iter)
		OclCore.KIND_SHELL:
			status = OclTopo.graph_shell_iter_create(graph, out_iter)
		OclCore.KIND_FACE:
			status = OclTopo.graph_face_iter_create(graph, out_iter)
		OclCore.KIND_WIRE:
			status = OclTopo.graph_wire_iter_create(graph, out_iter)
		OclCore.KIND_EDGE:
			status = OclTopo.graph_edge_iter_create(graph, out_iter)
		OclCore.KIND_VERTEX:
			status = OclTopo.graph_vertex_iter_create(graph, out_iter)
		OclCore.KIND_COMPOUND:
			status = OclTopo.graph_compound_iter_create(graph, out_iter)
		OclCore.KIND_COMPSOLID:
			status = OclTopo.graph_compsolid_iter_create(graph, out_iter)
		OclCore.KIND_COEDGE:
			status = OclTopo.graph_coedge_iter_create(graph, out_iter)
		_:
			return []
	if status != 0 or out_iter == null:
		return []
	var out_id = OclNodeId.new()
	while true:
		status = OclTopo.node_iter_next(out_iter, out_id)
		if status != 0:
			break
		ids.append(out_id.get_bits())
	return ids

# Helper: create a graph with a box solid and return {graph, root}
static func _make_box_full(dx: float = 10.0, dy: float = 20.0, dz: float = 30.0) -> Dictionary:
	var init_err = _init_runtime()
	if init_err != OK:
		return {"error": "runtime_init failed: %s" % _status_str(init_err)}

	var graph := OclGraphHandle.new()
	var create_err := OclTopo.graph_create(graph)
	if create_err != 0 or graph == null:
		return {"error": "graph_create returned null"}

	var info = OclPrimBoxInfo.new()
	info.set_dx(dx)
	info.set_dy(dy)
	info.set_dz(dz)

	var out_solid = OclNodeId.new()
	var status = OclPrimSolid.box(graph, info, out_solid)
	if status != OK:
		return {"error": "make_box failed: %s" % _status_str(status)}
	return {"graph": graph, "root": out_solid}

# Helper: make a Count helper
static func _count(graph: OclGraphHandle, count_fn: Callable) -> int:
	var out = OclSize.new()
	var status: int = count_fn.call(graph, out)
	if status != OK:
		return -1
	return out.get_value()

# Helper: make an Int32 helper
static func _int32_val(graph: OclGraphHandle, fn: Callable, arg: int = 0) -> int:
	var out = OclInt32.new()
	var status: int
	if arg != 0:
		status = fn.call(graph, arg, out)
	else:
		status = fn.call(graph, out)
	if status != OK:
		return -1
	return out.get_value()

# ---------------------------------------------------------------------------
# Primitive creation tests
# ---------------------------------------------------------------------------

static func test_make_box_and_count_topology() -> String:
	var result = _make_box(10.0, 20.0, 30.0)
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	# A box has: 1 solid, 1 shell, 6 faces, 12 edges, 8 vertices
	var solids = _collect_ids(graph, OclCore.KIND_SOLID)
	if solids.size() != 1:
		return "Expected 1 solid, got %d" % solids.size()

	var faces = _collect_ids(graph, OclCore.KIND_FACE)
	if faces.size() != 6:
		return "Expected 6 faces, got %d" % faces.size()

	var edges = _collect_ids(graph, OclCore.KIND_EDGE)
	if edges.size() != 12:
		return "Expected 12 edges, got %d" % edges.size()

	var vertices = _collect_ids(graph, OclCore.KIND_VERTEX)
	if vertices.size() != 8:
		return "Expected 8 vertices, got %d" % vertices.size()

	var shells = _collect_ids(graph, OclCore.KIND_SHELL)
	if shells.size() != 1:
		return "Expected 1 shell, got %d" % shells.size()

	return "OK"

static func test_make_sphere() -> String:
	var init_err = _init_runtime()
	if init_err != OK:
		return "runtime_init failed: %s" % _status_str(init_err)

	var graph := OclGraphHandle.new()
	var create_err := OclTopo.graph_create(graph)
	if create_err != 0 or graph == null:
		return "graph_create returned null"

	var info = OclPrimSphereInfo.new()
	info.set_radius(50.0)
	# Default angles give a full sphere (-pi/2 to pi/2 lat, 2pi lon).
	# OCCT uses radians for angular parameters.

	var out_solid = OclNodeId.new()
	var status = OclPrimSolid.sphere(graph, info, out_solid)
	if status != OK:
		return "make_sphere failed: %s" % _status_str(status)

	# A sphere should have 1 solid, 1 shell
	var solids = _collect_ids(graph, OclCore.KIND_SOLID)
	if solids.size() != 1:
		return "Expected 1 solid for sphere, got %d" % solids.size()

	var shells = _collect_ids(graph, OclCore.KIND_SHELL)
	if shells.size() != 1:
		return "Expected 1 shell for sphere, got %d" % shells.size()

	var faces = _collect_ids(graph, OclCore.KIND_FACE)
	if faces.size() < 1:
		return "Expected at least 1 face for sphere, got %d" % faces.size()

	return "OK"

static func test_make_cylinder() -> String:
	var init_err = _init_runtime()
	if init_err != OK:
		return "runtime_init failed: %s" % _status_str(init_err)

	var graph := OclGraphHandle.new()
	var create_err := OclTopo.graph_create(graph)
	if create_err != 0 or graph == null:
		return "graph_create returned null"

	var info = OclPrimCylinderInfo.new()
	info.set_radius(25.0)
	info.set_height(60.0)
	# Default angle = 2*pi (full cylinder)

	var out_solid = OclNodeId.new()
	var status = OclPrimSolid.cylinder(graph, info, out_solid)
	if status != OK:
		return "make_cylinder failed: %s" % _status_str(status)

	var solids = _collect_ids(graph, OclCore.KIND_SOLID)
	if solids.size() != 1:
		return "Expected 1 solid for cylinder, got %d" % solids.size()

	# Should have 3 faces (top, bottom, lateral)
	var faces = _collect_ids(graph, OclCore.KIND_FACE)
	if faces.size() != 3:
		return "Expected 3 faces for cylinder, got %d" % faces.size()

	return "OK"

static func test_make_cone() -> String:
	var init_err = _init_runtime()
	if init_err != OK:
		return "runtime_init failed: %s" % _status_str(init_err)

	var graph := OclGraphHandle.new()
	var create_err := OclTopo.graph_create(graph)
	if create_err != 0 or graph == null:
		return "graph_create returned null"

	var info = OclPrimConeInfo.new()
	info.set_r1(20.0)
	info.set_r2(10.0)
	info.set_height(40.0)
	# Default angle = 2*pi (full cone)

	var out_solid = OclNodeId.new()
	var status = OclPrimSolid.cone(graph, info, out_solid)
	if status != OK:
		return "make_cone failed: %s" % _status_str(status)

	var solids = _collect_ids(graph, OclCore.KIND_SOLID)
	if solids.size() != 1:
		return "Expected 1 solid for cone, got %d" % solids.size()

	return "OK"

static func test_make_torus() -> String:
	var init_err = _init_runtime()
	if init_err != OK:
		return "runtime_init failed: %s" % _status_str(init_err)

	var graph := OclGraphHandle.new()
	var create_err := OclTopo.graph_create(graph)
	if create_err != 0 or graph == null:
		return "graph_create returned null"

	var info = OclPrimTorusInfo.new()
	info.set_r1(50.0)
	info.set_r2(15.0)
	# Default angles give full torus

	var out_solid = OclNodeId.new()
	var status = OclPrimSolid.torus(graph, info, out_solid)
	if status != OK:
		return "make_torus failed: %s" % _status_str(status)

	var solids = _collect_ids(graph, OclCore.KIND_SOLID)
	if solids.size() != 1:
		return "Expected 1 solid for torus, got %d" % solids.size()

	return "OK"

static func test_make_wedge() -> String:
	var init_err = _init_runtime()
	if init_err != OK:
		return "runtime_init failed: %s" % _status_str(init_err)

	var graph := OclGraphHandle.new()
	var create_err := OclTopo.graph_create(graph)
	if create_err != 0 or graph == null:
		return "graph_create returned null"

	var info = OclPrimWedgeInfo.new()
	info.set_dx(30.0)
	info.set_dy(20.0)
	info.set_dz(10.0)
	info.set_ltx(15.0)

	var out_solid = OclNodeId.new()
	var status = OclPrimSolid.wedge(graph, info, out_solid)
	if status != OK:
		return "make_wedge failed: %s" % _status_str(status)

	var solids = _collect_ids(graph, OclCore.KIND_SOLID)
	if solids.size() != 1:
		return "Expected 1 solid for wedge, got %d" % solids.size()

	return "OK"

# ---------------------------------------------------------------------------
# Boolean operation tests
# ---------------------------------------------------------------------------

static func test_boolean_fuse_two_boxes() -> String:
	var result = _make_two_overlapping_boxes()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var box1: OclNodeId = result.box1
	var box2: OclNodeId = result.box2

	var opts = OclBoolOptions.new()

	var objects = PackedInt64Array([box1.get_bits()])
	var tools = PackedInt64Array([box2.get_bits()])
	var out_root = OclNodeId.new()
	var status = OclBool.fuse(graph, objects, tools, opts, out_root)
	if status != OK:
			return "fuse failed: %s" % _status_str(status)

	# After fusing, we should have a result solid
	var solids = _collect_ids(graph, OclCore.KIND_SOLID)
	if solids.size() < 1:
		return "Expected at least 1 solid after fuse, got %d" % solids.size()

	return "OK"

static func test_boolean_cut_two_boxes() -> String:
	var result = _make_two_overlapping_boxes()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var box1: OclNodeId = result.box1
	var box2: OclNodeId = result.box2

	var opts = OclBoolOptions.new()

	var objects = PackedInt64Array([box1.get_bits()])
	var tools = PackedInt64Array([box2.get_bits()])
	var out_root = OclNodeId.new()
	var status = OclBool.cut(graph, objects, tools, opts, out_root)
	if status != OK:
			return "cut failed: %s" % _status_str(status)

	return "OK"

static func test_boolean_common_two_boxes() -> String:
	var result = _make_two_overlapping_boxes()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var box1: OclNodeId = result.box1
	var box2: OclNodeId = result.box2

	var opts = OclBoolOptions.new()

	var objects = PackedInt64Array([box1.get_bits()])
	var tools = PackedInt64Array([box2.get_bits()])
	var out_root = OclNodeId.new()
	var status = OclBool.common(graph, objects, tools, opts, out_root)
	if status != OK:
			return "common failed: %s" % _status_str(status)

	return "OK"

static func test_boolean_section_two_boxes() -> String:
	var result = _make_two_overlapping_boxes()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var box1: OclNodeId = result.box1
	var box2: OclNodeId = result.box2

	var opts = OclBoolOptions.new()

	var objects = PackedInt64Array([box1.get_bits()])
	var tools = PackedInt64Array([box2.get_bits()])
	var out_root = OclNodeId.new()
	var status = OclBool.section(graph, objects, tools, opts, out_root)
	if status != OK:
			return "section failed: %s" % _status_str(status)

	return "OK"

# ---------------------------------------------------------------------------
# Graph count tests (using OclSize out-param)
# ---------------------------------------------------------------------------

static func test_graph_node_count() -> String:
	var result = _make_box(10.0, 10.0, 10.0)
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	var out_solid = OclSize.new()
	var status = OclTopo.graph_solid_count(graph, out_solid)
	if status != OK:
			return "graph_solid_count failed: %s" % _status_str(status)
	if out_solid.get_value() != 1:
		return "Expected 1 solid, got %d" % out_solid.get_value()

	var out_face = OclSize.new()
	status = OclTopo.graph_face_count(graph, out_face)
	if status != OK:
			return "graph_face_count failed: %s" % _status_str(status)
	if out_face.get_value() != 6:
		return "Expected 6 faces, got %d" % out_face.get_value()

	var out_edge = OclSize.new()
	status = OclTopo.graph_edge_count(graph, out_edge)
	if status != OK:
			return "graph_edge_count failed: %s" % _status_str(status)
	if out_edge.get_value() != 12:
		return "Expected 12 edges, got %d" % out_edge.get_value()

	var out_vtx = OclSize.new()
	status = OclTopo.graph_vertex_count(graph, out_vtx)
	if status != OK:
			return "graph_vertex_count failed: %s" % _status_str(status)
	if out_vtx.get_value() != 8:
		return "Expected 8 vertices, got %d" % out_vtx.get_value()

	var out_shell = OclSize.new()
	status = OclTopo.graph_shell_count(graph, out_shell)
	if status != OK:
			return "graph_shell_count failed: %s" % _status_str(status)
	if out_shell.get_value() != 1:
		return "Expected 1 shell, got %d" % out_shell.get_value()

	var out_wire = OclSize.new()
	status = OclTopo.graph_wire_count(graph, out_wire)
	if status != OK:
			return "graph_wire_count failed: %s" % _status_str(status)
	if out_wire.get_value() < 6:
		return "Expected at least 6 wires, got %d" % out_wire.get_value()

	return "OK"

# ---------------------------------------------------------------------------
# Graph node kind query tests
# ---------------------------------------------------------------------------

static func test_graph_node_kind() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var root: OclNodeId = result.root

	var out_kind = OclInt32.new()
	var status = OclTopo.graph_node_kind(graph, root.get_bits(), out_kind)
	if status != OK:
		return "graph_node_kind failed: %s" % _status_str(status)
	if out_kind.get_value() != OclCore.KIND_SOLID:
		return "Expected SOLID kind, got %s" % _kind_str(out_kind.get_value())

	return "OK"

# ---------------------------------------------------------------------------
# Vertex point query tests
# ---------------------------------------------------------------------------

static func test_vertex_point_query() -> String:
	var result = _make_box(10.0, 10.0, 10.0)
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	var vertices = _collect_ids(graph, OclCore.KIND_VERTEX)
	if vertices.size() != 8:
		return "Expected 8 vertices, got %d" % vertices.size()

	var out_pt = OclPoint3.new()
	var status = OclTopo.topo_vertex_point(graph, vertices[0], out_pt)
	if status != OK:
		return "topo_vertex_point failed: %s" % _status_str(status)

	var x = out_pt.get_x()
	var y = out_pt.get_y()
	var z = out_pt.get_z()
	# All vertices should be at (0 or 10, 0 or 10, 0 or 10)
	if (x != 0.0 and x != 10.0) or (y != 0.0 and y != 10.0) or (z != 0.0 and z != 10.0):
		return "Unexpected vertex coordinates: (%f, %f, %f)" % [x, y, z]

	return "OK"

static func test_vertex_tolerance() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var vertices = _collect_ids(graph, OclCore.KIND_VERTEX)
	if vertices.size() < 1:
		return "Expected at least 1 vertex"

	var out_tol = OclDouble.new()
	var status = OclTopo.topo_vertex_tolerance(graph, vertices[0], out_tol)
	if status != OK:
		return "topo_vertex_tolerance failed: %s" % _status_str(status)
	if out_tol.get_value() < 0.0:
		return "Expected non-negative tolerance, got %f" % out_tol.get_value()

	return "OK"

static func test_vertex_edge_count() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var vertices = _collect_ids(graph, OclCore.KIND_VERTEX)
	if vertices.size() < 1:
		return "Expected at least 1 vertex"

	var out_count = OclUint32.new()
	var status = OclTopo.topo_vertex_edge_count(graph, vertices[0], out_count)
	if status != OK:
		return "topo_vertex_edge_count failed: %s" % _status_str(status)
	# Each vertex of a box belongs to 3 edges
	if out_count.get_value() != 3:
		return "Expected vertex to belong to 3 edges, got %d" % out_count.get_value()

	return "OK"

# ---------------------------------------------------------------------------
# Edge topology tests
# ---------------------------------------------------------------------------

static func test_edge_face_count() -> String:
	var result = _make_box(10.0, 10.0, 10.0)
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	var edges = _collect_ids(graph, OclCore.KIND_EDGE)
	if edges.size() != 12:
		return "Expected 12 edges, got %d" % edges.size()

	var edge_id = edges[0]
	var out_count = OclUint32.new()
	var status = OclTopo.topo_edge_face_count(graph, edge_id, out_count)
	if status != OK:
		return "topo_edge_face_count failed: %s" % _status_str(status)
	if out_count.get_value() != 2:
		return "Expected edge adjacent to 2 faces, got %d" % out_count.get_value()

	return "OK"

static func test_edge_range() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	var edges = _collect_ids(graph, OclCore.KIND_EDGE)
	if edges.size() < 1:
		return "Expected at least 1 edge"

	var out_first = OclDouble.new()
	var out_last = OclDouble.new()
	var status = OclTopo.topo_edge_range(graph, edges[0], out_first, out_last)
	if status != OK:
		return "topo_edge_range failed: %s" % _status_str(status)
	if out_last.get_value() <= out_first.get_value():
		return "expected last > first, got %f <= %f" % [out_first.get_value(), out_last.get_value()]

	return "OK"

static func test_edge_tolerance() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	var edges = _collect_ids(graph, OclCore.KIND_EDGE)
	if edges.size() < 1:
		return "Expected at least 1 edge"

	var out_tol = OclDouble.new()
	var status = OclTopo.topo_edge_tolerance(graph, edges[0], out_tol)
	if status != OK:
		return "topo_edge_tolerance failed: %s" % _status_str(status)
	if out_tol.get_value() < 0.0:
		return "Expected non-negative tolerance, got %f" % out_tol.get_value()

	return "OK"

static func test_edge_has_curve() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var edges = _collect_ids(graph, OclCore.KIND_EDGE)
	if edges.size() < 1:
		return "Expected at least 1 edge"

	var out_has = OclInt32.new()
	var status = OclTopo.topo_edge_has_curve(graph, edges[0], out_has)
	if status != OK:
		return "topo_edge_has_curve failed: %s" % _status_str(status)
	if out_has.get_value() != 1:
		return "Expected edge to have curve"

	return "OK"

static func test_edge_curve_kind() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var edges = _collect_ids(graph, OclCore.KIND_EDGE)
	if edges.size() < 1:
		return "Expected at least 1 edge"

	var out_kind = OclInt32.new()
	var status = OclTopo.topo_edge_curve_kind(graph, edges[0], out_kind)
	if status != OK:
		return "topo_edge_curve_kind failed: %s" % _status_str(status)
	# Box edges are lines; CURVE_KIND_LINE is some constant
	if out_kind.get_value() < 0:
		return "Expected positive curve kind, got %d" % out_kind.get_value()

	return "OK"

static func test_edge_curve_kind_get_via_build() -> String:
	# Uses graph_edge_curve_kind_get from OclTopoBuild
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var edges = _collect_ids(graph, OclCore.KIND_EDGE)
	if edges.size() < 1:
		return "Expected at least 1 edge"

	var out_kind = OclInt32.new()
	var status = OclTopoBuild.graph_edge_curve_kind_get(graph, edges[0], out_kind)
	if status != OK:
		return "graph_edge_curve_kind_get failed: %s" % _status_str(status)
	if out_kind.get_value() < 0:
		return "Expected positive curve kind, got %d" % out_kind.get_value()

	return "OK"

static func test_edge_eval() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var edges = _collect_ids(graph, OclCore.KIND_EDGE)
	if edges.size() < 1:
		return "Expected at least 1 edge"

	var out_first = OclDouble.new()
	var out_last = OclDouble.new()
	var st = OclTopo.topo_edge_range(graph, edges[0], out_first, out_last)
	if st != OK:
		return "topo_edge_range failed: %s" % _status_str(st)

	var mid = (out_first.get_value() + out_last.get_value()) / 2.0
	var out_p = OclPoint3.new()
	var status = OclTopo.topo_edge_eval(graph, edges[0], mid, out_p)
	if status != OK:
		return "topo_edge_eval failed: %s" % _status_str(status)

	return "OK"

static func test_edge_start_end_vertex() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var edges = _collect_ids(graph, OclCore.KIND_EDGE)
	if edges.size() < 1:
		return "Expected at least 1 edge"

	var out_sv = OclNodeId.new()
	var out_ev = OclNodeId.new()
	var st1 = OclTopo.topo_edge_start_vertex(graph, edges[0], out_sv)
	var st2 = OclTopo.topo_edge_end_vertex(graph, edges[0], out_ev)
	if st1 != OK or st2 != OK:
		return "topo_edge_start/end_vertex failed: %s / %s" % [_status_str(st1), _status_str(st2)]
	if out_sv.get_bits() == out_ev.get_bits():
		return "Expected start and end vertices to differ"

	return "OK"

static func test_edge_vertex_count() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var edges = _collect_ids(graph, OclCore.KIND_EDGE)
	if edges.size() < 1:
		return "Expected at least 1 edge"

	var out_count = OclUint32.new()
	var status = OclTopo.topo_edge_vertex_count(graph, edges[0], out_count)
	if status != OK:
		return "topo_edge_vertex_count failed: %s" % _status_str(status)
	# A box edge has 2 vertices (start and end)
	if out_count.get_value() != 2:
		return "Expected edge to have 2 vertices, got %d" % out_count.get_value()

	return "OK"

# ---------------------------------------------------------------------------
# Wire topology tests
# ---------------------------------------------------------------------------

static func test_wire_is_closed() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	var wires = _collect_ids(graph, OclCore.KIND_WIRE)
	if wires.size() < 1:
		return "Expected at least 1 wire"

	var out_closed = OclInt32.new()
	var status = OclTopo.topo_wire_is_closed(graph, wires[0], out_closed)
	if status != OK:
		return "topo_wire_is_closed failed: %s" % _status_str(status)
	if out_closed.get_value() != 1:
		return "Expected wire to be closed"

	return "OK"

static func test_wire_edge_count() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var wires = _collect_ids(graph, OclCore.KIND_WIRE)
	if wires.size() < 1:
		return "Expected at least 1 wire"

	var out_count = OclUint32.new()
	var status = OclTopo.topo_wire_edge_count(graph, wires[0], out_count)
	if status != OK:
		return "topo_wire_edge_count failed: %s" % _status_str(status)
	# Each wire of a box face has 4 edges
	if out_count.get_value() != 4:
		return "Expected wire to have 4 edges, got %d" % out_count.get_value()

	return "OK"

static func test_wire_coedge_count() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var wires = _collect_ids(graph, OclCore.KIND_WIRE)
	if wires.size() < 1:
		return "Expected at least 1 wire"

	var out_count = OclUint32.new()
	var status = OclTopo.topo_wire_coedge_count(graph, wires[0], out_count)
	if status != OK:
		return "topo_wire_coedge_count failed: %s" % _status_str(status)
	if out_count.get_value() != 4:
		return "Expected wire to have 4 coedges, got %d" % out_count.get_value()

	return "OK"

static func test_wire_face_of() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var wires = _collect_ids(graph, OclCore.KIND_WIRE)
	if wires.size() < 1:
		return "Expected at least 1 wire"

	var out_face = OclNodeId.new()
	var status = OclTopo.topo_wire_face_of(graph, wires[0], out_face)
	if status != OK:
		return "topo_wire_face_of failed: %s" % _status_str(status)
	if out_face.get_bits() == 0:
		return "Expected wire to have a valid face"

	return "OK"

static func test_wire_is_outer() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var wires = _collect_ids(graph, OclCore.KIND_WIRE)
	if wires.size() < 1:
		return "Expected at least 1 wire"

	var out_outer = OclInt32.new()
	var status = OclTopo.topo_wire_is_outer(graph, wires[0], out_outer)
	if status != OK:
		return "topo_wire_is_outer failed: %s" % _status_str(status)
	# First wire should be outer
	if out_outer.get_value() != 1:
		return "Expected wire to be outer"

	return "OK"

# ---------------------------------------------------------------------------
# Shell topology tests
# ---------------------------------------------------------------------------

static func test_shell_is_closed() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	var shells = _collect_ids(graph, OclCore.KIND_SHELL)
	if shells.size() < 1:
		return "Expected at least 1 shell"

	var out_closed = OclInt32.new()
	var status = OclTopo.topo_shell_is_closed(graph, shells[0], out_closed)
	if status != OK:
		return "topo_shell_is_closed failed: %s" % _status_str(status)
	if out_closed.get_value() != 1:
		return "Expected shell to be closed"

	return "OK"

static func test_shell_face_count() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var shells = _collect_ids(graph, OclCore.KIND_SHELL)
	if shells.size() < 1:
		return "Expected at least 1 shell"

	var out_count = OclUint32.new()
	var status = OclTopo.topo_shell_face_count(graph, shells[0], out_count)
	if status != OK:
		return "topo_shell_face_count failed: %s" % _status_str(status)
	if out_count.get_value() != 6:
		return "Expected shell to have 6 faces, got %d" % out_count.get_value()

	return "OK"

# ---------------------------------------------------------------------------
# Face topology tests
# ---------------------------------------------------------------------------

static func test_face_wire_count() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var faces = _collect_ids(graph, OclCore.KIND_FACE)
	if faces.size() < 1:
		return "Expected at least 1 face"

	var out_count = OclUint32.new()
	var status = OclTopo.topo_face_wire_count(graph, faces[0], out_count)
	if status != OK:
		return "topo_face_wire_count failed: %s" % _status_str(status)
	# Each box face has 1 wire
	if out_count.get_value() != 1:
		return "Expected face to have 1 wire, got %d" % out_count.get_value()

	return "OK"

static func test_face_outer_wire() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var faces = _collect_ids(graph, OclCore.KIND_FACE)
	if faces.size() < 1:
		return "Expected at least 1 face"

	var out_wire = OclNodeId.new()
	var status = OclTopo.topo_face_outer_wire(graph, faces[0], out_wire)
	if status != OK:
		return "topo_face_outer_wire failed: %s" % _status_str(status)
	if out_wire.get_bits() == 0:
		return "Expected face to have a valid outer wire"

	return "OK"

static func test_face_uv_bounds() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var faces = _collect_ids(graph, OclCore.KIND_FACE)
	if faces.size() < 1:
		return "Expected at least 1 face"

	var out_umin = OclDouble.new()
	var out_umax = OclDouble.new()
	var out_vmin = OclDouble.new()
	var out_vmax = OclDouble.new()
	var status = OclTopo.topo_face_uv_bounds(graph, faces[0], out_umin, out_umax, out_vmin, out_vmax)
	if status != OK:
		return "topo_face_uv_bounds failed: %s" % _status_str(status)
	if out_umax.get_value() <= out_umin.get_value():
		return "Expected umax > umin"

	return "OK"

static func test_face_surface_kind() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var faces = _collect_ids(graph, OclCore.KIND_FACE)
	if faces.size() < 1:
		return "Expected at least 1 face"

	var out_kind = OclInt32.new()
	var status = OclTopo.topo_face_surface_kind(graph, faces[0], out_kind)
	if status != OK:
		return "topo_face_surface_kind failed: %s" % _status_str(status)
	if out_kind.get_value() < 0:
		return "Expected positive surface kind, got %d" % out_kind.get_value()

	return "OK"

static func test_face_surface_kind_get_via_build() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var faces = _collect_ids(graph, OclCore.KIND_FACE)
	if faces.size() < 1:
		return "Expected at least 1 face"

	var out_kind = OclInt32.new()
	var status = OclTopoBuild.graph_face_surface_kind_get(graph, faces[0], out_kind)
	if status != OK:
		return "graph_face_surface_kind_get failed: %s" % _status_str(status)
	if out_kind.get_value() < 0:
		return "Expected positive surface kind, got %d" % out_kind.get_value()

	return "OK"

static func test_face_uv_bounds_get_via_build() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var faces = _collect_ids(graph, OclCore.KIND_FACE)
	if faces.size() < 1:
		return "Expected at least 1 face"

	var out_uv = OclGraphUvBounds.new()
	var status = OclTopoBuild.graph_face_uv_bounds_get(graph, faces[0], out_uv)
	if status != OK:
		return "graph_face_uv_bounds_get failed: %s" % _status_str(status)
	if out_uv.get_u_max() <= out_uv.get_u_min():
		return "Expected uv umax > umin"

	return "OK"

# ---------------------------------------------------------------------------
# Solid topology tests
# ---------------------------------------------------------------------------

static func test_solid_shell_count() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var solids = _collect_ids(graph, OclCore.KIND_SOLID)
	if solids.size() < 1:
		return "Expected at least 1 solid"

	var out_count = OclUint32.new()
	var status = OclTopo.topo_solid_shell_count(graph, solids[0], out_count)
	if status != OK:
		return "topo_solid_shell_count failed: %s" % _status_str(status)
	if out_count.get_value() != 1:
		return "Expected solid to have 1 shell, got %d" % out_count.get_value()

	return "OK"

# ---------------------------------------------------------------------------
# Tag operation tests
# ---------------------------------------------------------------------------

static func test_graph_tag_operations() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var root: OclNodeId = result.root

	# Add a tag
	var tag = "my_test_tag"
	var status = OclTopo.graph_tag_add(graph, root.get_bits(), tag)
	if status != OK:
		return "graph_tag_add failed: %s" % _status_str(status)

	# Check tag exists
	var out_has = OclInt32.new()
	status = OclTopo.graph_tag_has(graph, root.get_bits(), tag, out_has)
	if status != OK:
		return "graph_tag_has failed: %s" % _status_str(status)
	if out_has.get_value() != 1:
		return "graph_tag_has returned false (got %d)" % out_has.get_value()

	# List tags
	var tags_buf := OclTagViewArray.new()
	var tags_status = OclTopo.graph_tag_list(graph, root.get_bits(), tags_buf)
	if tags_status != OK:
		return "graph_tag_list failed: %s" % _status_str(tags_status)
	if tags_buf.data.size() != 1 or tags_buf.data[0].get_tag() != tag:
		return "Expected [%s] tags, got %s" % [tag, str(tags_buf.data)]

	# Query nodes by tag
	var tagged_nodes_buf := OclNodeIdArray.new()
	var tn_status = OclTopo.graph_tag_nodes(graph, tag, tagged_nodes_buf)
	if tn_status != OK:
		return "graph_tag_nodes failed: %s" % _status_str(tn_status)
	if tagged_nodes_buf.data.size() != 1:
		return "Expected 1 node with tag, got %d" % tagged_nodes_buf.data.size()

	# Remove tag
	status = OclTopo.graph_tag_remove(graph, root.get_bits(), tag)
	if status != OK:
		return "graph_tag_remove failed: %s" % _status_str(status)

	# Verify tag is gone
	status = OclTopo.graph_tag_has(graph, root.get_bits(), tag, out_has)
	if status != OK:
		return "graph_tag_has after remove failed: %s" % _status_str(status)
	if out_has.get_value() != 0:
		return "graph_tag_has should return 0 after remove, got %d" % out_has.get_value()

	return "OK"

# ---------------------------------------------------------------------------
# Name operation tests
# ---------------------------------------------------------------------------

static func test_graph_name_operations() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var root: OclNodeId = result.root

	# Set a name on the solid node
	var name = "MyBoxSolid"
	var status = OclTopo.graph_name_set(graph, root.get_bits(), name)
	if status != OK:
		return "graph_name_set failed: %s" % _status_str(status)

	# Get the name back (uses out-param, returns status)
	var out_name_buf := OclString.new()
	var ng_status = OclTopo.graph_name_get(graph, root.get_bits(), out_name_buf)
	if ng_status != OK:
		return "graph_name_get failed: %s" % _status_str(ng_status)
	var out_name = out_name_buf.value
	if out_name != name:
		return "Expected name '%s', got '%s'" % [name, out_name]

	# Query name_nodes
	var named_nodes_buf := OclNodeIdArray.new()
	var nn_status = OclTopo.graph_name_nodes(graph, named_nodes_buf)
	if nn_status != OK:
		return "graph_name_nodes failed: %s" % _status_str(nn_status)
	if named_nodes_buf.data.size() < 1:
		return "Expected at least 1 named node, got %d" % named_nodes_buf.data.size()

	return "OK"

# ---------------------------------------------------------------------------
# Color operation tests
# ---------------------------------------------------------------------------

static func test_graph_color_operations() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var root: OclNodeId = result.root

	# Create a color
	var color = OclColorRgba.new()
	color.set_r(1.0)
	color.set_g(0.5)
	color.set_b(0.2)
	color.set_a(1.0)

	# Set color on the root node
	var status = OclTopo.graph_color_set(graph, root.get_bits(), color)
	if status != OK:
		return "graph_color_set failed: %s" % _status_str(status)

	# Get color back
	var out_color = OclColorRgba.new()
	status = OclTopo.graph_color_get(graph, root.get_bits(), out_color)
	if status != OK:
		return "graph_color_get failed: %s" % _status_str(status)
	# Check values approximately
	var tol := 0.01
	if abs(out_color.get_r() - 1.0) > tol or abs(out_color.get_g() - 0.5) > tol or abs(out_color.get_b() - 0.2) > tol:
		return "Color mismatch: (%f,%f,%f)" % [out_color.get_r(), out_color.get_g(), out_color.get_b()]

	# Query color entries
	var entries_buf := OclColorRgbaArray.new()
	var ce_status = OclTopo.graph_color_entries(graph, entries_buf)
	if ce_status != OK:
		return "graph_color_entries failed: %s" % _status_str(ce_status)
	if entries_buf.data.size() < 1:
		return "Expected at least 1 color entry"

	# Unset color
	status = OclTopo.graph_color_unset(graph, root.get_bits())
	if status != OK:
		return "graph_color_unset failed: %s" % _status_str(status)

	return "OK"

# ---------------------------------------------------------------------------
# Metadata operation tests
# ---------------------------------------------------------------------------

static func test_graph_metadata_operations() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var root: OclNodeId = result.root

	# Set node metadata
	var status = OclTopo.graph_node_metadata_set(graph, root.get_bits(), "my_key", "my_value")
	if status != OK:
		return "graph_node_metadata_set failed: %s" % _status_str(status)

	# Get node metadata back
	var val_buf := OclString.new()
	var nmg_status = OclTopo.graph_node_metadata_get(graph, root.get_bits(), "my_key", val_buf)
	if nmg_status != OK:
		return "graph_node_metadata_get failed: %s" % _status_str(nmg_status)
	var val = val_buf.value
	if val != "my_value":
		return "Expected 'my_value', got '%s'" % val

	# List node metadata keys
	var keys_buf := OclMetadataKeyViewArray.new()
	var nk_status = OclTopo.graph_node_metadata_keys(graph, root.get_bits(), keys_buf)
	if nk_status != OK:
		return "graph_node_metadata_keys failed: %s" % _status_str(nk_status)
	if keys_buf.data.size() < 1 or keys_buf.data[0].get_key() != "my_key":
		return "Expected keys containing 'my_key', got %s" % str(keys_buf.data)

	# Query metadata nodes
	var meta_nodes_buf := OclNodeIdArray.new()
	var mn_status = OclTopo.graph_node_metadata_nodes(graph, meta_nodes_buf)
	if mn_status != OK:
		return "graph_node_metadata_nodes failed: %s" % _status_str(mn_status)
	if meta_nodes_buf.data.size() < 1:
		return "Expected at least 1 metadata node"

	# Set graph-level metadata
	status = OclTopo.graph_metadata_set(graph, "graph_key", "graph_value")
	if status != OK:
		return "graph_metadata_set failed: %s" % _status_str(status)

	val_buf = OclString.new()
	var mg_status = OclTopo.graph_metadata_get(graph, "graph_key", val_buf)
	if mg_status != OK:
		return "graph_metadata_get failed: %s" % _status_str(mg_status)
	val = val_buf.value
	if val != "graph_value":
		return "Expected 'graph_value', got '%s'" % val

	# List graph metadata keys
	var gkeys_buf := OclMetadataKeyViewArray.new()
	var gk_status = OclTopo.graph_metadata_keys(graph, gkeys_buf)
	if gk_status != OK:
		return "graph_metadata_keys failed: %s" % _status_str(gk_status)
	if gkeys_buf.data.size() < 1 or gkeys_buf.data[0].get_key() != "graph_key":
		return "Expected graph keys containing 'graph_key', got %s" % str(gkeys_buf.data)

	# Unset graph metadata
	status = OclTopo.graph_metadata_unset(graph, "graph_key")
	if status != OK:
		return "graph_metadata_unset failed: %s" % _status_str(status)

	# Unset node metadata
	status = OclTopo.graph_node_metadata_unset(graph, root.get_bits(), "my_key")
	if status != OK:
		return "graph_node_metadata_unset failed: %s" % _status_str(status)

	return "OK"

# ---------------------------------------------------------------------------
# Material operation tests
# ---------------------------------------------------------------------------

static func test_graph_material_set() -> String:
	var result = _make_box(10.0, 10.0, 10.0)
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var root: OclNodeId = result.root

	# Create material info with name
	var mat_info = OclMaterialInfo.new()
	mat_info.struct_version = OclTopoBuild.MATERIAL_INFO_VERSION_1
	var mat_name = "Aluminium"
	mat_info.set_name(mat_name)
	mat_info.set_name_len(mat_name.length())
	mat_info.set_has_density(1)
	mat_info.set_density(2700.0)

	var status = OclTopo.graph_material_set(graph, root.get_bits(), mat_info)
	if status != OK:
		return "graph_material_set failed: %s" % _status_str(status)

	# Get material back (uses out-param, returns status)
	var out_info = OclMaterialInfo.new()
	var mat_name_buf := OclString.new()
	var mg_status = OclTopo.graph_material_get(graph, root.get_bits(), out_info, mat_name_buf)
	if mg_status != OK:
		return "graph_material_get failed: %s" % _status_str(mg_status)
	mat_name = mat_name_buf.value
	if mat_name != "Aluminium":
		return "Expected material name 'Aluminium', got '%s'" % mat_name

	# Query material nodes
	var mat_nodes_buf := OclNodeIdArray.new()
	var mn_status = OclTopo.graph_material_nodes(graph, mat_nodes_buf)
	if mn_status != OK:
		return "graph_material_nodes failed: %s" % _status_str(mn_status)
	if mat_nodes_buf.data.size() < 1:
		return "Expected at least 1 material node"

	# Unset material
	status = OclTopo.graph_material_unset(graph, root.get_bits())
	if status != OK:
		return "graph_material_unset failed: %s" % _status_str(status)

	return "OK"

# ---------------------------------------------------------------------------
# Units tests
# ---------------------------------------------------------------------------

static func test_graph_units() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	# Set units to millimeters (0.001 meter per unit, name "mm")
	var status = OclTopo.graph_units_set(graph, 0.001, "mm")
	if status != OK:
		return "graph_units_set failed: %s" % _status_str(status)

	# Get units back (uses out-param, returns status)
	var out_scale = OclDouble.new()
	var unit_name_buf := OclString.new()
	var ug_status = OclTopo.graph_units_get(graph, out_scale, unit_name_buf)
	if ug_status != OK:
		return "graph_units_get failed: %s" % _status_str(ug_status)
	var unit_name = unit_name_buf.value
	if unit_name != "mm":
		return "Expected 'mm', got '%s'" % unit_name
	if abs(out_scale.get_value() - 0.001) > 1e-9:
		return "Expected scale 0.001, got %f" % out_scale.get_value()

	return "OK"

# ---------------------------------------------------------------------------
# Bounding box tests
# ---------------------------------------------------------------------------

static func test_bounding_box_box() -> String:
	var result = _make_box(10.0, 20.0, 30.0)
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var root: OclNodeId = result.root

	var bbox = OclSelectBbox.new()
	var status = OclTopoBuild.graph_bbox_get(graph, root.get_bits(), bbox)
	if status != OK:
		return "graph_bbox_get failed: %s" % _status_str(status)

	var bmin = bbox.get_min()
	var bmax = bbox.get_max()

	# Box is at origin, 10x20x30
	var tol = 0.001
	if abs(bmax.get_x() - 10.0) > tol:
		return "Expected x_max=10.0, got %f" % bmax.get_x()
	if abs(bmax.get_y() - 20.0) > tol:
		return "Expected y_max=20.0, got %f" % bmax.get_y()
	if abs(bmax.get_z() - 30.0) > tol:
		return "Expected z_max=30.0, got %f" % bmax.get_z()
	if abs(bmin.get_x() - 0.0) > tol:
		return "Expected x_min=0.0, got %f" % bmin.get_x()
	if abs(bmin.get_y() - 0.0) > tol:
		return "Expected y_min=0.0, got %f" % bmin.get_y()
	if abs(bmin.get_z() - 0.0) > tol:
		return "Expected z_min=0.0, got %f" % bmin.get_z()

	return "OK"

static func test_obb_box() -> String:
	var result = _make_box(10.0, 20.0, 30.0)
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var root: OclNodeId = result.root

	var obb = OclGraphObb.new()
	var status = OclTopoBuild.graph_obb_get(graph, root.get_bits(), obb)
	if status != OK:
		return "graph_obb_get failed: %s" % _status_str(status)

	# Box at origin: center should be at (5, 10, 15)
	var center = obb.get_center()
	var tol = 0.01
	if abs(center.get_x() - 5.0) > tol:
		return "Expected center_x=5.0, got %f" % center.get_x()
	if abs(center.get_y() - 10.0) > tol:
		return "Expected center_y=10.0, got %f" % center.get_y()
	if abs(center.get_z() - 15.0) > tol:
		return "Expected center_z=15.0, got %f" % center.get_z()

	# Half-sizes
	if abs(obb.get_x_half_size() - 5.0) > tol:
		return "Expected x_half_size=5.0, got %f" % obb.get_x_half_size()
	if abs(obb.get_y_half_size() - 10.0) > tol:
		return "Expected y_half_size=10.0, got %f" % obb.get_y_half_size()
	if abs(obb.get_z_half_size() - 15.0) > tol:
		return "Expected z_half_size=15.0, got %f" % obb.get_z_half_size()

	return "OK"

# ---------------------------------------------------------------------------
# Mass properties tests
# ---------------------------------------------------------------------------

static func test_mass_properties_box() -> String:
	var result = _make_box(10.0, 20.0, 30.0)
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var root: OclNodeId = result.root

	var mass_props = OclGraphMassProperties.new()
	var status = OclTopoBuild.graph_mass_properties_get(graph, root.get_bits(), mass_props)
	if status != OK:
		return "graph_mass_properties_get failed: %s" % _status_str(status)

	# Box 10x20x30: volume = 6000, surface_area = 2*(10*20 + 10*30 + 20*30) = 2200
	var expected_volume = 6000.0
	var expected_surface = 2200.0

	var volume = mass_props.get_volume()
	var surface = mass_props.get_surface_area()
	if abs(volume - expected_volume) / expected_volume > 1e-2:
		return "Expected volume ~%f, got %f" % [expected_volume, volume]
	if abs(surface - expected_surface) / expected_surface > 1e-2:
		return "Expected surface area ~%f, got %f" % [expected_surface, surface]

	# Center of mass should be at (5, 10, 15)
	var com = mass_props.get_centre_of_mass()
	var tol = 0.1
	if abs(com.get_x() - 5.0) > tol:
		return "Expected COM_x ~5.0, got %f" % com.get_x()
	if abs(com.get_y() - 10.0) > tol:
		return "Expected COM_y ~10.0, got %f" % com.get_y()
	if abs(com.get_z() - 15.0) > tol:
		return "Expected COM_z ~15.0, got %f" % com.get_z()

	return "OK"

# ---------------------------------------------------------------------------
# Descendant / Adjacent query tests
# ---------------------------------------------------------------------------

static func test_descendant_get() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var root: OclNodeId = result.root

	# Descendant edges from the root solid
	var edge_buf := OclNodeIdArray.new()
	var edge_status = OclTopoBuild.graph_descendant_edges_get(graph, root.get_bits(), edge_buf)
	if edge_status != OK:
		return "graph_descendant_edges_get failed: %s" % _status_str(edge_status)
	if edge_buf.data.size() != 12:
		return "Expected 12 descendant edges, got %d" % edge_buf.data.size()

	# Descendant faces from the root solid
	var face_buf := OclNodeIdArray.new()
	var face_status = OclTopoBuild.graph_descendant_faces_get(graph, root.get_bits(), face_buf)
	if face_status != OK:
		return "graph_descendant_faces_get failed: %s" % _status_str(face_status)
	if face_buf.data.size() != 6:
		return "Expected 6 descendant faces, got %d" % face_buf.data.size()

	# Descendant vertices from the root solid
	var vert_buf := OclNodeIdArray.new()
	var vert_status = OclTopoBuild.graph_descendant_vertices_get(graph, root.get_bits(), vert_buf)
	if vert_status != OK:
		return "graph_descendant_vertices_get failed: %s" % _status_str(vert_status)
	if vert_buf.data.size() != 8:
		return "Expected 8 descendant vertices, got %d" % vert_buf.data.size()

	# Descendants with kind (get each kind separately)
	var desc_faces_buf := OclNodeIdArray.new()
	var df_status = OclTopoBuild.graph_descendants_get(graph, root.get_bits(), OclCore.KIND_FACE, desc_faces_buf)
	if df_status != OK:
		return "graph_descendants_get(faces) failed: %s" % _status_str(df_status)
	var desc_edges_buf := OclNodeIdArray.new()
	var de_status = OclTopoBuild.graph_descendants_get(graph, root.get_bits(), OclCore.KIND_EDGE, desc_edges_buf)
	if de_status != OK:
		return "graph_descendants_get(edges) failed: %s" % _status_str(de_status)
	var desc_verts_buf := OclNodeIdArray.new()
	var dv_status = OclTopoBuild.graph_descendants_get(graph, root.get_bits(), OclCore.KIND_VERTEX, desc_verts_buf)
	if dv_status != OK:
		return "graph_descendants_get(vertices) failed: %s" % _status_str(dv_status)
	if desc_faces_buf.data.size() != 6:
		return "Expected 6 face descendants, got %d" % desc_faces_buf.data.size()
	if desc_edges_buf.data.size() != 12:
		return "Expected 12 edge descendants, got %d" % desc_edges_buf.data.size()
	if desc_verts_buf.data.size() != 8:
		return "Expected 8 vertex descendants, got %d" % desc_verts_buf.data.size()

	return "OK"

static func test_adjacent_queries() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	# Get a face and query adjacent faces
	var faces = _collect_ids(graph, OclCore.KIND_FACE)
	if faces.size() < 1:
		return "Expected at least 1 face"

	var adj_faces_buf := OclNodeIdArray.new()
	var af_status = OclTopoBuild.graph_adjacent_faces_get(graph, faces[0], adj_faces_buf)
	if af_status != OK:
		return "graph_adjacent_faces_get failed: %s" % _status_str(af_status)
	if adj_faces_buf.data.size() < 1:
		return "Expected at least 1 adjacent face"

	# Get an edge and query adjacent edges
	var edges = _collect_ids(graph, OclCore.KIND_EDGE)
	if edges.size() < 1:
		return "Expected at least 1 edge"

	var adj_edges_buf := OclNodeIdArray.new()
	var ae_status = OclTopoBuild.graph_adjacent_edges_get(graph, edges[0], adj_edges_buf)
	if ae_status != OK:
		return "graph_adjacent_edges_get failed: %s" % _status_str(ae_status)
	if adj_edges_buf.data.size() < 1:
		return "Expected at least 1 adjacent edge"

	return "OK"

# ---------------------------------------------------------------------------
# Graph clone and compact tests
# ---------------------------------------------------------------------------

static func test_graph_clone() -> String:
	var result = _make_box(10.0, 10.0, 10.0)
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	# Clone the graph (uses out-param, returns status)
	var cloned = OclGraphHandle.new()
	var status = OclTopoBuild.graph_clone(graph, cloned)
	if status != OK:
		return "graph_clone failed: %s" % _status_str(status)

	# Both graphs should have the same counts
	var out_solid_orig = OclSize.new()
	var out_solid_clone = OclSize.new()
	OclTopo.graph_solid_count(graph, out_solid_orig)
	OclTopo.graph_solid_count(cloned, out_solid_clone)
	if out_solid_orig.get_value() != out_solid_clone.get_value():
		return "Clone has %d solids, expected %d" % [out_solid_clone.get_value(), out_solid_orig.get_value()]

	var orig_faces = _collect_ids(graph, OclCore.KIND_FACE)
	var cloned_faces = _collect_ids(cloned, OclCore.KIND_FACE)
	if orig_faces.size() != cloned_faces.size():
		return "Cloned graph has %d faces, expected %d" % [cloned_faces.size(), orig_faces.size()]

	return "OK"

static func test_graph_compact() -> String:
	var result = _make_box(10.0, 10.0, 10.0)
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	var status = OclTopoBuild.graph_compact(graph)
	if status != OK:
		return "graph_compact failed: %s" % _status_str(status)

	return "OK"

# ---------------------------------------------------------------------------
# Edge split tests
# ---------------------------------------------------------------------------

static func test_edge_split() -> String:
	var result = _make_box(20.0, 20.0, 20.0)
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	# Get the first edge
	var edges = _collect_ids(graph, OclCore.KIND_EDGE)
	if edges.size() < 1:
		return "Expected at least 1 edge"

	# Split the edge at midpoint in parameter space
	var out_first = OclDouble.new()
	var out_last = OclDouble.new()
	OclTopo.topo_edge_range(graph, edges[0], out_first, out_last)

	var mid_param = (out_first.get_value() + out_last.get_value()) / 2.0
	var out_e1 = OclNodeId.new()
	var out_e2 = OclNodeId.new()
	var status = OclTopoBuild.topo_edge_split(graph, edges[0], mid_param, out_e1, out_e2)
	if status != OK:
		return "topo_edge_split failed: %s" % _status_str(status)
	if out_e1.get_bits() == 0 or out_e2.get_bits() == 0:
		return "Expected valid split edge IDs"

	return "OK"

# ---------------------------------------------------------------------------
# Batch operation tests
# ---------------------------------------------------------------------------

static func test_batch_operations() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	# Begin a batch
	var batch_id = OclTopoBuild.graph_begin_batch(graph)
	if batch_id == 0:
		return "graph_begin_batch returned 0"

	# Commit the batch (without making any changes)
	var status = OclTopoBuild.batch_commit(batch_id)
	if status != OK:
		return "batch_commit failed: %s" % _status_str(status)

	return "OK"

# ---------------------------------------------------------------------------
# Remove operation tests
# ---------------------------------------------------------------------------

static func test_topo_remove() -> String:
	var result = _make_two_overlapping_boxes()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	# Remove the second box's solid
	var status = OclTopoBuild.topo_remove(graph, result.box2.get_bits())
	if status != OK:
		return "topo_remove failed: %s" % _status_str(status)

	return "OK"

static func test_topo_remove_subgraph() -> String:
	var result = _make_two_overlapping_boxes()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	# Remove the subgraph of the second box
	var status = OclTopoBuild.topo_remove_subgraph(graph, result.box2.get_bits())
	if status != OK:
		return "topo_remove_subgraph failed: %s" % _status_str(status)

	return "OK"

# ---------------------------------------------------------------------------
# Measurement tests
# ---------------------------------------------------------------------------

static func test_graph_measure() -> String:
	var result = _make_box(10.0, 20.0, 30.0)
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var _root: OclNodeId = result.root

	# Measure the pair distance between two vertices
	var vertices = _collect_ids(graph, OclCore.KIND_VERTEX)
	if vertices.size() < 2:
		return "Expected at least 2 vertices"

	var out_dist = OclDouble.new()
	var status = OclTopoBuild.graph_pair_distance_get(graph, vertices[0], vertices[1], out_dist)
	if status != OK:
		return "graph_pair_distance_get failed: %s" % _status_str(status)
	if out_dist.get_value() <= 0.0:
		return "Expected positive distance, got %f" % out_dist.get_value()

	return "OK"

# ---------------------------------------------------------------------------
# Error handling tests
# ---------------------------------------------------------------------------

static func test_error_handling() -> String:
	# Clear any previous errors
	OclCore.error_clear()

	# Try an invalid operation to trigger an error
	var graph := OclGraphHandle.new()
	var create_err := OclTopo.graph_create(graph)
	if create_err != 0 or graph == null:
		return "graph_create returned null"

	# Query kind on an invalid node ID
	var out_kind = OclInt32.new()
	var status = OclTopo.graph_node_kind(graph, 99999, out_kind)
	# Should fail
	if status == OK:
		return "Expected error for invalid node, got %s" % _status_str(status)

	# Should have an error
	var err = OclCore.error_last()
	if err == null:
		return "Expected error_last to return non-null"
	if err.get_status() == 0:
		return "Expected non-zero error status"

	return "OK"

# ---------------------------------------------------------------------------
# For-each / Callback tests
# ---------------------------------------------------------------------------

static func test_graph_for_each() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	# Iterate over all solids
	var visited = []
	var callable = func(node_id: int) -> int:
		visited.append(node_id)
		return 0  # continue

	# Kind mask must be bit-shifted: 1 << kind
	var status = OclTopo.graph_for_each(graph, 1 << OclCore.KIND_SOLID, callable)
	if status != OK:
		return "graph_for_each failed: %s" % _status_str(status)
	if visited.size() < 1:
		return "Expected at least 1 solid visited"

	return "OK"

# ---------------------------------------------------------------------------
# UID/NodeID round-trip tests
# ---------------------------------------------------------------------------

static func test_uid_roundtrip() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var root: OclNodeId = result.root

	# Get UID from node ID
	var out_uid = OclUid.new()
	var status = OclTopo.graph_uid_from_node_id(graph, root.get_bits(), out_uid)
	if status != OK:
		return "graph_uid_from_node_id failed: %s" % _status_str(status)
	if out_uid.get_bits() == 0:
		return "Expected non-zero UID"

	# Round-trip back to node ID
	var out_node = OclNodeId.new()
	status = OclTopo.graph_node_id_from_uid(graph, out_uid.get_bits(), out_node)
	if status != OK:
		return "graph_node_id_from_uid failed: %s" % _status_str(status)
	if out_node.get_bits() != root.get_bits():
		return "UID round-trip mismatch: %d != %d" % [out_node.get_bits(), root.get_bits()]

	return "OK"

# ---------------------------------------------------------------------------
# History tests
# ---------------------------------------------------------------------------

static func test_graph_history() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var root: OclNodeId = result.root

	# Get UID from node ID
	var out_uid = OclUid.new()
	var status = OclTopo.graph_uid_from_node_id(graph, root.get_bits(), out_uid)
	if status != OK:
		return "graph_uid_from_node_id failed: %s" % _status_str(status)

	# Query history_modified
	var modified_buf := OclUidArray.new()
	var mod_status = OclTopo.graph_history_modified(graph, out_uid.get_bits(), modified_buf)
	if mod_status != OK:
		return "graph_history_modified failed: %s" % _status_str(mod_status)

	# Query history_generated
	var generated_buf := OclUidArray.new()
	var gen_status = OclTopo.graph_history_generated(graph, out_uid.get_bits(), generated_buf)
	if gen_status != OK:
		return "graph_history_generated failed: %s" % _status_str(gen_status)

	return "OK"

# ---------------------------------------------------------------------------
# Coedge tests
# ---------------------------------------------------------------------------

static func test_coedge_queries() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	var coedges = _collect_ids(graph, OclCore.KIND_COEDGE)
	if coedges.size() < 1:
		return "Expected at least 1 coedge"

	# Query is_seam
	var out_seam = OclInt32.new()
	var status = OclTopo.topo_coedge_is_seam(graph, coedges[0], out_seam)
	if status != OK:
		return "topo_coedge_is_seam failed: %s" % _status_str(status)

	# Query edge_of
	var out_edge = OclNodeId.new()
	status = OclTopo.topo_coedge_edge_of(graph, coedges[0], out_edge)
	if status != OK:
		return "topo_coedge_edge_of failed: %s" % _status_str(status)
	if out_edge.get_bits() == 0:
		return "Expected valid edge from coedge"

	# Query face_of
	var out_face = OclNodeId.new()
	status = OclTopo.topo_coedge_face_of(graph, coedges[0], out_face)
	if status != OK:
		return "topo_coedge_face_of failed: %s" % _status_str(status)
	if out_face.get_bits() == 0:
		return "Expected valid face from coedge"

	# Query is_reversed
	var out_rev = OclInt32.new()
	status = OclTopo.topo_coedge_is_reversed(graph, coedges[0], out_rev)
	if status != OK:
		return "topo_coedge_is_reversed failed: %s" % _status_str(status)

	# Query has_pcurve
	var out_has = OclInt32.new()
	status = OclTopo.topo_coedge_has_pcurve(graph, coedges[0], out_has)
	if status != OK:
		return "topo_coedge_has_pcurve failed: %s" % _status_str(status)

	# Query coedge range
	var out_first = OclDouble.new()
	var out_last = OclDouble.new()
	status = OclTopo.topo_coedge_range(graph, coedges[0], out_first, out_last)
	if status != OK:
		return "topo_coedge_range failed: %s" % _status_str(status)

	return "OK"

# ---------------------------------------------------------------------------
# Runtime info tests
# ---------------------------------------------------------------------------

static func test_runtime_version() -> String:
	var out_major = OclUint32.new()
	var out_minor = OclUint32.new()
	var out_patch = OclUint32.new()
	OclCore.runtime_version(out_major, out_minor, out_patch)

	if out_major.get_value() == 0 and out_minor.get_value() == 0 and out_patch.get_value() == 0:
		return "Expected non-zero runtime version"

	var abi = OclCore.runtime_abi_version()
	if abi <= 0:
		return "Expected positive ABI version"

	var occt_ver = OclCore.runtime_occt_version()
	if occt_ver == "":
		return "Expected non-empty OCCT version string"

	return "OK"

# ---------------------------------------------------------------------------
# Mesh generation tests
# ---------------------------------------------------------------------------

static func test_mesh_generate() -> String:
	var result = _make_box(10.0, 10.0, 10.0)
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var root: OclNodeId = result.root

	var opts = OclMeshOptions.new()
	opts.set_deflection(1.0)

	var status = OclMesh.generate(graph, PackedInt64Array([root.get_bits()]), opts)
	if status != OK:
		return "mesh generate failed: %s" % _status_str(status)

	return "OK"

static func test_mesh_to_godot_on_box() -> String:
	var result = _make_box(10.0, 10.0, 10.0)
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	var mesh := ArrayMesh.new()
	var status := OclMeshToGodot.mesh_faces(graph, mesh)
	if status != OclCore.OK:
		return "mesh_faces returned status %s" % _status_str(status)
	if mesh.get_surface_count() == 0:
		return "expected at least 1 surface, got 0"

	var mmesh := MultiMesh.new()
	status = OclMeshToGodot.mesh_edges(graph, mmesh)
	if status != OclCore.OK:
		return "mesh_edges returned status %s" % _status_str(status)
	if mmesh.instance_count == 0:
		return "expected at least 1 edge instance, got 0"

	mmesh = MultiMesh.new()
	status = OclMeshToGodot.mesh_vertices(graph, mmesh)
	if status != OclCore.OK:
		return "mesh_edges returned status %s" % _status_str(status)
	if mmesh.instance_count == 0:
		return "expected at least 1 vertex instance, got 0"

	return "OK"

# ---------------------------------------------------------------------------
# Edge is_degenerated / is_manifold / is_boundary tests
# ---------------------------------------------------------------------------

static func test_edge_boolean_queries() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var edges = _collect_ids(graph, OclCore.KIND_EDGE)
	if edges.size() < 1:
		return "Expected at least 1 edge"

	# is_degenerated
	var out_val = OclInt32.new()
	var st = OclTopo.topo_edge_is_degenerated(graph, edges[0], out_val)
	if st != OK:
		return "topo_edge_is_degenerated failed: %s" % _status_str(st)

	# is_manifold
	st = OclTopo.topo_edge_is_manifold(graph, edges[0], out_val)
	if st != OK:
		return "topo_edge_is_manifold failed: %s" % _status_str(st)

	# is_boundary
	st = OclTopo.topo_edge_is_boundary(graph, edges[0], out_val)
	if st != OK:
		return "topo_edge_is_boundary failed: %s" % _status_str(st)

	return "OK"

# ---------------------------------------------------------------------------
# Vertex parameter tests
# ---------------------------------------------------------------------------

static func test_vertex_parameter_on_edge() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	var edges = _collect_ids(graph, OclCore.KIND_EDGE)
	if edges.size() < 1:
		return "Expected at least 1 edge"

	var out_sv = OclNodeId.new()
	OclTopo.topo_edge_start_vertex(graph, edges[0], out_sv)

	var out_param = OclDouble.new()
	var status = OclTopo.topo_vertex_parameter(graph, out_sv.get_bits(), edges[0], out_param)
	if status != OK:
		return "topo_vertex_parameter failed: %s" % _status_str(status)

	return "OK"

# ---------------------------------------------------------------------------
# Face has_surface / has_triangulation / natural_restriction tests
# ---------------------------------------------------------------------------

static func test_face_boolean_queries() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var faces = _collect_ids(graph, OclCore.KIND_FACE)
	if faces.size() < 1:
		return "Expected at least 1 face"

	# has_surface
	var out_val = OclInt32.new()
	var st = OclTopo.topo_face_has_surface(graph, faces[0], out_val)
	if st != OK:
		return "topo_face_has_surface failed: %s" % _status_str(st)
	if out_val.get_value() != 1:
		return "Expected face to have surface"

	# natural_restriction
	st = OclTopo.topo_face_natural_restriction(graph, faces[0], out_val)
	if st != OK:
		return "topo_face_natural_restriction failed: %s" % _status_str(st)

	# has_triangulation (before meshing, should be 0)
	st = OclTopo.topo_face_has_triangulation(graph, faces[0], out_val)
	if st != OK:
		return "topo_face_has_triangulation failed: %s" % _status_str(st)

	return "OK"

# ---------------------------------------------------------------------------
# Edge same_parameter / same_range tests
# ---------------------------------------------------------------------------

static func test_edge_same_parameter_and_range() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var edges = _collect_ids(graph, OclCore.KIND_EDGE)
	if edges.size() < 1:
		return "Expected at least 1 edge"

	var out_val = OclInt32.new()
	var st = OclTopo.topo_edge_same_parameter(graph, edges[0], out_val)
	if st != OK:
		return "topo_edge_same_parameter failed: %s" % _status_str(st)

	st = OclTopo.topo_edge_same_range(graph, edges[0], out_val)
	if st != OK:
		return "topo_edge_same_range failed: %s" % _status_str(st)

	return "OK"

# ---------------------------------------------------------------------------
# Wire distinct_edge_count test
# ---------------------------------------------------------------------------

static func test_wire_distinct_edge_count() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var wires = _collect_ids(graph, OclCore.KIND_WIRE)
	if wires.size() < 1:
		return "Expected at least 1 wire"

	var out_count = OclUint32.new()
	var status = OclTopo.topo_wire_distinct_edge_count(graph, wires[0], out_count)
	if status != OK:
		return "topo_wire_distinct_edge_count failed: %s" % _status_str(status)
	if out_count.get_value() != 4:
		return "Expected wire to have 4 distinct edges, got %d" % out_count.get_value()

	return "OK"

# ---------------------------------------------------------------------------
# TopoEdgeView / FaceView / etc. initialization tests
# ---------------------------------------------------------------------------

static func test_edge_view() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var edges = _collect_ids(graph, OclCore.KIND_EDGE)
	if edges.size() < 1:
		return "Expected at least 1 edge"

	var view = OclEdgeView.new()
	var status = OclTopo.topo_edge_view(graph, edges[0], view)
	if status != OK:
		return "topo_edge_view failed: %s" % _status_str(status)

	return "OK"

static func test_vertex_view() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var vertices = _collect_ids(graph, OclCore.KIND_VERTEX)
	if vertices.size() < 1:
		return "Expected at least 1 vertex"

	var view = OclVertexView.new()
	var status = OclTopo.topo_vertex_view(graph, vertices[0], view)
	if status != OK:
		return "topo_vertex_view failed: %s" % _status_str(status)

	return "OK"

static func test_face_view() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var faces = _collect_ids(graph, OclCore.KIND_FACE)
	if faces.size() < 1:
		return "Expected at least 1 face"

	var view = OclFaceView.new()
	var status = OclTopo.topo_face_view(graph, faces[0], view)
	if status != OK:
		return "topo_face_view failed: %s" % _status_str(status)

	return "OK"

static func test_wire_view() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var wires = _collect_ids(graph, OclCore.KIND_WIRE)
	if wires.size() < 1:
		return "Expected at least 1 wire"

	var view = OclWireView.new()
	var status = OclTopo.topo_wire_view(graph, wires[0], view)
	if status != OK:
		return "topo_wire_view failed: %s" % _status_str(status)

	return "OK"

static func test_shell_view() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var shells = _collect_ids(graph, OclCore.KIND_SHELL)
	if shells.size() < 1:
		return "Expected at least 1 shell"

	var view = OclShellView.new()
	var status = OclTopo.topo_shell_view(graph, shells[0], view)
	if status != OK:
		return "topo_shell_view failed: %s" % _status_str(status)

	return "OK"

static func test_solid_view() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var solids = _collect_ids(graph, OclCore.KIND_SOLID)
	if solids.size() < 1:
		return "Expected at least 1 solid"

	var view = OclSolidView.new()
	var status = OclTopo.topo_solid_view(graph, solids[0], view)
	if status != OK:
		return "topo_solid_view failed: %s" % _status_str(status)

	return "OK"

static func test_compound_view() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	var view = OclCompoundView.new()
	# A box graph has no compound, so this should return NOT_FOUND
	var status = OclTopo.topo_compound_view(graph, 0, view)
	if status != NOT_FOUND:
		return "Expected NOT_FOUND for invalid compound, got %s" % _status_str(status)

	return "OK"


# ---------------------------------------------------------------------------
# Graph ref_uid / rep_uid round-trip tests
# ---------------------------------------------------------------------------

static func test_ref_uid_roundtrip() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var faces = _collect_ids(graph, OclCore.KIND_FACE)
	if faces.size() < 1:
		return "Expected at least 1 face"

	# Get UID from node ID
	var out_uid = OclUid.new()
	var status = OclTopo.graph_uid_from_node_id(graph, faces[0], out_uid)
	if status != OK:
		return "graph_uid_from_node_id failed: %s" % _status_str(status)

	# Test uid_to_bytes and uid_from_bytes round trip (using OclCore, not ref_uid variant)
	var out_bytes = OclByteArray.new()
	status = OclCore.uid_to_bytes(out_uid.get_bits(), out_bytes)
	if status != OK:
		return "uid_to_bytes failed: %s" % _status_str(status)
	if out_bytes.get_value().size() == 0:
		return "Expected non-empty byte array"

	var out_uid2 = OclUid.new()
	status = OclCore.uid_from_bytes(out_bytes.get_value(), out_uid2)
	if status != OK:
		return "uid_from_bytes failed: %s" % _status_str(status)
	if out_uid2.get_bits() != out_uid.get_bits():
		return "UID byte round-trip mismatch: %d != %d" % [out_uid2.get_bits(), out_uid.get_bits()]

	return "OK"

# ---------------------------------------------------------------------------
# Select / filter tests
# ---------------------------------------------------------------------------

static func test_select_iter_create() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	var sel_opts = OclSelectOptions.new()

	# Set up a select for faces (kind_mask uses bit flags: 1 << kind)
	sel_opts.kind_mask = 1 << OclCore.KIND_FACE

	var iter = OclSelectIterHandle.new()
	var status = OclTopoBuild.select_iter_create(graph, sel_opts, iter)
	if status != OK:
		return "select_iter_create failed: %s" % _status_str(status)

	# Iterate
	var out_node = OclNodeId.new()
	var face_count = 0
	while true:
		status = OclTopoBuild.select_iter_next(iter, out_node)
		if status != 0:
			break
		face_count += 1

	OclTopoBuild.select_iter_free(iter)

	if face_count != 6:
		return "Expected 6 selected faces, got %d" % face_count

	return "OK"

# ---------------------------------------------------------------------------
# Graph UID table tests
# ---------------------------------------------------------------------------

static func test_graph_uid_table() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	var uid_buf := OclNodeIdArray.new()
	var uid_status = OclTopo.graph_uid_table(graph, uid_buf)
	if uid_status != OK:
		return "graph_uid_table failed: %s" % _status_str(uid_status)
	if uid_buf.data.size() < 1:
		return "Expected non-empty UID table"

	var ref_uid_buf := OclRefIdArray.new()
	var ref_status = OclTopo.graph_ref_uid_table(graph, ref_uid_buf)
	if ref_status != OK:
		return "graph_ref_uid_table failed: %s" % _status_str(ref_status)

	return "OK"

# ---------------------------------------------------------------------------
# Graph history deleted_all test
# ---------------------------------------------------------------------------

static func test_graph_history_deleted_all() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph

	var deleted_buf := OclUidArray.new()
	var del_status = OclTopo.graph_history_deleted_all(graph, deleted_buf)
	if del_status != OK:
		return "graph_history_deleted_all failed: %s" % _status_str(del_status)

	return "OK"

# ---------------------------------------------------------------------------
# Compound child count test (empty)
# ---------------------------------------------------------------------------

static func test_compound_child_count_empty() -> String:
	var result = _make_box()
	if result.has("error"):
		return result.error

	var graph: OclGraphHandle = result.graph
	var compounds = _collect_ids(graph, OclCore.KIND_COMPOUND)
	# Box graph has no compounds
	if compounds.size() != 0:
		return "Expected 0 compounds in box graph, got %d" % compounds.size()

	return "OK"

# ---------------------------------------------------------------------------
# Main entry point for external invocation
# ---------------------------------------------------------------------------

static func run_all_tests() -> Dictionary:
	var results = {}
	var methods = []
	var script = load("res://tests/test_cad_workflows.gd")
	for m in script.get_script_method_list():
		if m["name"].begins_with("test_"):
			methods.append(m["name"])
	methods.sort()

	var inst = TestCadWorkflows.new()
	for method in methods:
		var result = inst.call(method)
		results[method] = result
	inst.free()
	return results
