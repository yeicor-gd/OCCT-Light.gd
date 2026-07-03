@tool
extends Node3D
## 3D Spherical Maze Generator — OCCT-Light.gd
##
## Procedurally generates a spherical marble maze using OCCT CSG.
## This is a pure generation/display tool (no gameplay).
##
## Pipeline:
##   1. Generate 3D grid of nodes inside a hollow sphere casing
##   2. A* pathfinding connects waypoints into a continuous path
##   3. Cylindrical tube segments along the path
##   4. Tubes subtract from the sphere shell via CSG (creates tunnels)
##   5. Everything is meshed, given physics collision, and the maze is displayed

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

const NODE_SIZE: float = 10.0
const SPHERE_DIAMETER: float = 250.0
const SHELL_THICKNESS: float = 2.5
const BALL_DIAMETER: float = 6.0
const SEED: int = 0
const NUMBER_OF_WAYPOINTS: int = 14
const MOUNTING_POINTS: int = 4
const PATH_HEIGHT: float = 10.0
const TUBE_RADIUS: float = PATH_HEIGHT / 2.0

const PATH_COLORS: Array[Color] = [
	Color(1.0, 0.84, 0.0),
	Color(0.3, 0.45, 1.0),
	Color(0.95, 0.25, 0.2),
]
const BALL_COLOR: Color = Color(0.85, 0.85, 0.88)
const MOUNTING_RING_COLOR: Color = Color(1.0, 0.84, 0.0)
const END_GLOW_COLOR: Color = Color(0.0, 1.0, 0.3)

const OCCTL_OK := 0

# Camera
const CAMERA_DISTANCE: float = 350.0

# ===========================================================================
# @tool — editor export
# ===========================================================================

@export var generate: bool:
	set(val):
		if val:
			_generate_maze()

@export var clear: bool:
	set(val):
		if val:
			_clear_maze()


# ===========================================================================
# MazeNode  — grid node
# ===========================================================================

class MazeNode:
	var x: float
	var y: float
	var z: float
	var occupied: bool = false
	var in_circular_grid: bool = false
	var in_rectangular_grid: bool = false
	var waypoint: bool = false
	var puzzle_start: bool = false
	var puzzle_end: bool = false
	var mounting: bool = false
	var parent: Variant = null
	var g_score: float = INF
	var h_score: float = 0.0
	var f_score: float = INF

	func _init(px: float, py: float, pz: float, circ: bool = false, rect: bool = false):
		x = px
		y = py
		z = pz
		in_circular_grid = circ
		in_rectangular_grid = rect

	func to_key() -> String:
		return "%0.6f:%0.6f:%0.6f" % [_snap(x), _snap(y), _snap(z)]

	static func _snap(v: float, d: int = 6) -> float:
		var r: float = v * pow(10.0, float(d))
		r = round(r)
		r = r / pow(10.0, float(d))
		return 0.0 if abs(r) < 1e-9 else r

	static func _eq(a: MazeNode, b: MazeNode) -> bool:
		return a != null and b != null and a.x == b.x and a.y == b.y and a.z == b.z

	func _to_string() -> String:
		return "MazeNode(%.1f, %.1f, %.1f)" % [x, y, z]


# ===========================================================================
# OCCT-Light lifecycle
# ===========================================================================

static func _init_occt() -> int:
	var st = OclCore.runtime_init()
	if st != OCCTL_OK and st != 2:
		return st
	return OCCTL_OK


static func _make_graph() -> OclGraphHandle:
	return OclTopo.graph_create()


static func _free_graph(graph: OclGraphHandle) -> void:
	OclTopo.graph_free(graph)


# ===========================================================================
# Geometry helpers
# ===========================================================================

static func _manhattan(a: MazeNode, b: MazeNode) -> float:
	return abs(a.x - b.x) + abs(a.y - b.y) + abs(a.z - b.z)


static func _euclidean(a: MazeNode, b: MazeNode) -> float:
	var dx := a.x - b.x
	var dy := a.y - b.y
	var dz := a.z - b.z
	return sqrt(dx * dx + dy * dy + dz * dz)


static func _squared_dist(ax: float, ay: float, az: float, bx: float, by: float, bz: float) -> float:
	var dx := ax - bx
	var dy := ay - by
	var dz := az - bz
	return dx * dx + dy * dy + dz * dz


# ===========================================================================
# Logging helpers
# ===========================================================================

static func _log_graph_stats(graph: OclGraphHandle, label: String) -> void:
	var out_s := OclSize.new()
	var out_f := OclSize.new()
	var out_e := OclSize.new()
	var out_v := OclSize.new()
	var out_sh := OclSize.new()
	OclTopo.graph_solid_count(graph, out_s)
	OclTopo.graph_face_count(graph, out_f)
	OclTopo.graph_edge_count(graph, out_e)
	OclTopo.graph_vertex_count(graph, out_v)
	OclTopo.graph_shell_count(graph, out_sh)
	print("  [%s] solids=%d shells=%d faces=%d edges=%d vertices=%d" % [
		label, out_s.get_value(), out_sh.get_value(),
		out_f.get_value(), out_e.get_value(), out_v.get_value()])


static func _log_mesh_stats(mesh: ArrayMesh, label: String) -> void:
	if mesh == null:
		print("  [%s] mesh=NULL" % label)
		return
	var sc := mesh.get_surface_count()
	var total_verts := 0
	var total_indices := 0
	for si in sc:
		var arr := mesh.surface_get_arrays(si)
		if arr == null:
			continue
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idxs = arr[Mesh.ARRAY_INDEX]
		if idxs is PackedInt32Array:
			total_indices += idxs.size()
		total_verts += verts.size()
	var total_tris := total_indices / 3 if total_indices > 0 else total_verts / 3
	print("  [%s] surfaces=%d  vertices=%d  indices=%d  ~triangles=%d" % [label, sc, total_verts, total_indices, total_tris])


# ===========================================================================
# Mesh helper — properly collects face IDs for a solid
# ===========================================================================

static func _collect_solid_face_ids(graph: OclGraphHandle, solid_id: OclNodeId) -> PackedInt64Array:
	"""Use child_explorer to find all face IDs belonging to a specific solid.
	Encodes orientation in the sign bit: positive=forward(swap), negative=reversed(keep)."""
	var config := OclTopoChildExplorerConfig.new()
	config.set_target_kind(OclCore.KIND_FACE)

	var iter := OclTopoRelation.child_explorer_create(graph, solid_id.get_bits(), config)
	if iter == null:
		print("    WARNING: child_explorer_create returned null for solid %d" % solid_id.get_bits())
		return PackedInt64Array()

	var out_node := OclNodeId.new()
	var out_transform := OclTransform.new()
	var out_orientation := OclInt32.new()
	var encoded: PackedInt64Array = []
	while true:
		var status := OclTopoRelation.explorer_iter_next(iter, out_node, out_transform, out_orientation)
		if status != OCCTL_OK:
			break
		var id_val: int = out_node.get_bits()
		var orient: int = out_orientation.get_value()
		# Positive = forward (swap winding), Negative = reversed (keep as-is)
		if orient != 0:
			encoded.append(-id_val)
		else:
			encoded.append(id_val)

	OclTopoRelation.explorer_iter_free(iter)
	return encoded


static func _mesh_solid(
	graph: OclGraphHandle,
	solid_id: OclNodeId,
	color: Color,
	transparency: float = 0.0,
	unshaded: bool = false,
	emissive: bool = false,
	metallic: float = 0.3
) -> MeshInstance3D:
	"""Create a MeshInstance3D from a single solid by finding its faces.
	face_ids now encode orientation in the sign bit (positive=forward/swap, negative=reversed/keep),
	which mesh_faces decodes to adjust winding order."""
	# face_ids carries orientation in the sign bit — mesh_faces decodes it natively
	var face_ids := _collect_solid_face_ids(graph, solid_id)
	if face_ids.is_empty():
		print("  WARNING: no faces for solid %d, skipping mesh" % solid_id.get_bits())
		return null

	var options := OclMeshOptions.new()
	options.angle = 0.5
	options.deflection = 0.5

	var mesher := OclGodotMesher.new()
	var mesh := mesher.mesh_faces(
		graph, null, options,
		face_ids,
		true,  # normals
		false, # uvs
		false, # tangents
		false  # feature_ids
	)

	if mesh == null:
		print("  WARNING: mesh_faces returned null for solid %d" % solid_id.get_bits())
		return null

	_log_mesh_stats(mesh, "mesh-%d" % solid_id.get_bits())

	var inst := MeshInstance3D.new()
	inst.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.metallic_specular = 0.4
	mat.roughness = 0.3

	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	if transparency > 0.0:
		# mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		mat.alpha_scissor_threshold = 0.1
		mat.albedo_color.a = 1.0 - transparency
		# Don't write to depth buffer so we can see through to the ball
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED

	if emissive:
		mat.emission_enabled = true
		mat.emission_energy_multiplier = 0.8
		mat.emission = color * 1.5

	inst.material_override = mat
	return inst


# ===========================================================================
# Stage 1 — Grid generation
# ===========================================================================

static func _frange(start: float, stop: float, step: float) -> Array:
	if step <= 0.0:
		return []
	var n_min := ceili(start / step)
	var n_max := floori(stop / step)
	var result: Array = []
	for n in range(n_min, n_max + 1):
		var v := float(n) * step
		v = round(v)
		result.append(0.0 if abs(v) < 1e-9 else v)
	return result


static func _generate_surface_grid(inner_radius: float, node_size: float) -> Array:
	"""Generate grid nodes ON the sphere surface using lat/lon gridding.
	This ensures tubes between adjacent nodes intersect the shell for CSG cut."""
	var nodes: Array[MazeNode] = []
	var node_dict: Dictionary = {}
	var count := 0

	var d_theta := node_size / inner_radius  # Angular step (radians)
	var n_theta := floori(PI / d_theta)

	for i in range(n_theta + 1):
		var theta: float = float(i) * d_theta - PI / 2.0  # -pi/2 to pi/2
		var z: float = inner_radius * sin(theta)
		var r_xy: float = abs(inner_radius * cos(theta))

		if r_xy < 0.001:
			# North/south pole — single node
			var x := 0.0
			var y := 0.0
			z = round(z)
			if abs(z) < 1e-9: z = 0.0
			var key := "%0.6f:%0.6f:%0.6f" % [x, y, z]
			if not node_dict.has(key):
				var node := MazeNode.new(x, y, z, false, true)
				nodes.append(node)
				node_dict[key] = node
				count += 1
			continue

		var circumference: float = TAU * r_xy
		var n_phi := maxi(1, floori(circumference / node_size))

		for j in range(n_phi):
			var phi: float = float(j) * TAU / float(n_phi)
			var x: float = r_xy * cos(phi)
			var y: float = r_xy * sin(phi)
			# Round to integer for clean keys and deduplication
			x = round(x)
			y = round(y)
			z = round(z)
			if abs(x) < 1e-9: x = 0.0
			if abs(y) < 1e-9: y = 0.0
			if abs(z) < 1e-9: z = 0.0

			var key := "%0.6f:%0.6f:%0.6f" % [x, y, z]
			if not node_dict.has(key):
				var node := MazeNode.new(x, y, z, false, true)
				nodes.append(node)
				node_dict[key] = node
				count += 1

	print("  Spherical surface grid: %d nodes at r=%.1f" % [count, inner_radius])
	return [nodes, node_dict]


# (No longer needed — surface grid handles all connectivity)


static func _build_neighbor_cache(nodes: Array[MazeNode], node_dict: Dictionary, node_size: float) -> Dictionary:
	"""Precompute neighbor connections for a surface grid using spatial hashing."""
	var cell_size: float = node_size * 1.5
	var max_dist: float = node_size * 1.5

	# Assign each node to a grid cell
	var spatial: Dictionary = {}
	for node in nodes:
		var cx := int(floor(node.x / cell_size))
		var cy := int(floor(node.y / cell_size))
		var cz := int(floor(node.z / cell_size))
		var ckey := "%d,%d,%d" % [cx, cy, cz]
		if not spatial.has(ckey):
			spatial[ckey] = []
		spatial[ckey].append(node)

	# For each node, find neighbors in adjacent cells
	var cache: Dictionary = {}
	for node in nodes:
		var cx := int(floor(node.x / cell_size))
		var cy := int(floor(node.y / cell_size))
		var cz := int(floor(node.z / cell_size))
		var nkey := node.to_key()
		var neighbors: Array = []

		for dcx in [-1, 0, 1]:
			for dcy in [-1, 0, 1]:
				for dcz in [-1, 0, 1]:
					var ckey := "%d,%d,%d" % [cx+dcx, cy+dcy, cz+dcz]
					var cell_nodes: Array = spatial.get(ckey, [])
					for cand in cell_nodes:
						if cand == node:
							continue
						var d := _euclidean(node, cand)
						if d <= max_dist and d > 0.1:
							neighbors.append([cand, d])

		if neighbors.size() > 0:
			cache[nkey] = neighbors

	print("  Neighbor cache built: %d nodes have connections" % cache.size())
	return cache


# ===========================================================================
# Stage 2 — Waypoint selection
# ===========================================================================

static func _select_mounting_waypoints(
	nodes: Array[MazeNode], count: int, inner_radius: float
) -> Array[MazeNode]:
	var selected: Array[MazeNode] = []

	for i in range(count):
		var angle: float = TAU * float(i) / float(count)
		var tx: float = inner_radius * cos(angle)
		var ty: float = inner_radius * sin(angle)

		var best: MazeNode = null
		var best_d := INF
		for n in nodes:
			if n.occupied or selected.has(n):
				continue
			var d := _squared_dist(n.x, n.y, n.z, tx, ty, 0.0)
			if d < best_d:
				best_d = d
				best = n

		if best != null:
			best.mounting = true
			best.waypoint = true
			selected.append(best)

	print("  Mounting waypoints: %d" % selected.size())
	return selected


static func _select_waypoints_random(
	nodes: Array[MazeNode], count: int, rng: RandomNumberGenerator
) -> Array[MazeNode]:
	var free: Array[MazeNode] = []
	for n in nodes:
		if not n.occupied:
			free.append(n)

	var selected: Array[MazeNode] = []

	for _wp_i in count:
		if free.is_empty():
			break

		var num_c: int = mini(10, free.size())
		var cands: Array[MazeNode] = []
		for _ci in num_c:
			var idx: int = rng.randi() % free.size()
			cands.append(free[idx])

		var best: MazeNode = cands[0]
		var best_d := -1.0

		for cand in cands:
			var md := INF
			for wp in selected:
				var d := _euclidean(cand, wp)
				if d < md:
					md = d
			if selected.is_empty():
				md = INF
			if md > best_d:
				best_d = md
				best = cand

		if best:
			best.waypoint = true
			selected.append(best)
			free.erase(best)

	print("  Random waypoints: %d" % selected.size())
	return selected


# ===========================================================================
# Stage 3 — A* pathfinding
# ===========================================================================

static func _find_neighbors(puzzle: Dictionary, node: MazeNode, ring_cache: Dictionary = {}) -> Array:
	var nkey := node.to_key()
	var neighbor_cache: Dictionary = puzzle.get("neighbor_cache", {})
	var neighbors: Array = neighbor_cache.get(nkey, [])
	return neighbors


static func _a_star(start: MazeNode, goal: MazeNode, puzzle: Dictionary, ring_cache: Dictionary = {}) -> Array:
	var open_set: Dictionary = {}
	var closed_set: Dictionary = {}

	for n in puzzle.nodes:
		n.g_score = INF
		n.h_score = 0.0
		n.f_score = INF
		n.parent = null

	start.g_score = 0.0
	start.h_score = _manhattan(start, goal)
	start.f_score = start.h_score
	var start_key := start.to_key()
	open_set[start_key] = [start.f_score, start]

	while open_set.size() > 0:
		var best_key: String = ""
		var best_f := INF
		for k in open_set:
			var entry: Array = open_set[k]
			if entry[0] < best_f:
				best_f = entry[0]
				best_key = k
		if best_key.is_empty():
			break
		var entry: Array = open_set[best_key]
		open_set.erase(best_key)
		var current: MazeNode = entry[1]

		if MazeNode._eq(current, goal):
			return _reconstruct(current)

		closed_set[current.to_key()] = true

		for item in _find_neighbors(puzzle, current, ring_cache):
			var neighbor: MazeNode = item[0]
			var cost: float = item[1]

			var nkey := neighbor.to_key()
			if closed_set.has(nkey):
				continue

			if neighbor.occupied and not MazeNode._eq(neighbor, goal):
				continue

			var tent := current.g_score + cost
			if tent < neighbor.g_score:
				neighbor.parent = current
				neighbor.g_score = tent
				neighbor.h_score = _manhattan(neighbor, goal)
				neighbor.f_score = neighbor.g_score + neighbor.h_score
				open_set[nkey] = [neighbor.f_score, neighbor]

	return []


static func _reconstruct(current: MazeNode) -> Array:
	var path: Array = []
	var n: MazeNode = current
	while n:
		path.append(n)
		n = n.parent
	path.reverse()
	return path


# ===========================================================================
# Stage 4 — Cylindrical tube construction
# ===========================================================================

static func _make_axis2_placement(
	ox: float, oy: float, oz: float,
	zdir_x: float, zdir_y: float, zdir_z: float
) -> OclAxis2Placement:
	var axis := OclAxis2Placement.new()

	var loc := OclPoint3.new()
	loc.set_x(ox); loc.set_y(oy); loc.set_z(oz)
	axis.set_location(loc)

	# Normalize the Z direction
	var z_len: float = sqrt(zdir_x*zdir_x + zdir_y*zdir_y + zdir_z*zdir_z)
	assert(z_len > 1e-12, "Zero-length Z direction")
	var nz_x := zdir_x / z_len
	var nz_y := zdir_y / z_len
	var nz_z := zdir_z / z_len

	# Compute a vector perpendicular to Z for the X-axis reference
	var ax: float = abs(nz_x); var ay: float = abs(nz_y); var az: float = abs(nz_z)

	var xx: float; var xy: float; var xz: float
	if ax <= ay and ax <= az:
		xx = 0.0; xy = -nz_z; xz = nz_y
	elif ay <= ax and ay <= az:
		xx = nz_z; xy = 0.0; xz = -nz_x
	else:
		xx = -nz_y; xy = nz_x; xz = 0.0

	var x_len: float = sqrt(xx*xx + xy*xy + xz*xz)
	assert(x_len > 1e-12, "Zero-length X ref for Z=(%.4f,%.4f,%.4f)" % [nz_x, nz_y, nz_z])
	xx /= x_len; xy /= x_len; xz /= x_len

	# x_dir = Z-axis (the main/normal direction) — this is the tube direction
	var z_dir := OclDirection3.new()
	z_dir.set_x(nz_x); z_dir.set_y(nz_y); z_dir.set_z(nz_z)
	axis.set_x_dir(z_dir)

	# x_dir_ref = X-axis reference (perpendicular to Z) — OCCT derives Y as Z×X
	var ref := OclDirection3.new()
	ref.set_x(xx); ref.set_y(xy); ref.set_z(xz)
	axis.set_x_dir_ref(ref)

	return axis


static func _build_cylinder_segment(
	graph: OclGraphHandle,
	from: MazeNode, to: MazeNode,
	radius: float
) -> OclNodeId:
	var mx := (from.x + to.x) / 2.0
	var my := (from.y + to.y) / 2.0
	var mz := (from.z + to.z) / 2.0

	var dx := to.x - from.x
	var dy := to.y - from.y
	var dz := to.z - from.z
	var height: float = sqrt(dx*dx + dy*dy + dz*dz)

	if height < 0.001:
		return OclNodeId.new()

	var nx := dx / height; var ny := dy / height; var nz := dz / height

	var placement := _make_axis2_placement(mx, my, mz, nx, ny, nz)

	var info := OclPrimCylinderInfo.new()
	info.set_radius(radius)
	info.set_height(height)
	info.set_placement(placement)

	var solid := OclNodeId.new()
	var st := OclPrimSolid.cylinder(graph, info, solid)
	if st != OCCTL_OK:
		print("    WARNING: cylinder at (%.1f,%.1f,%.1f) h=%.1f failed: %d" % [mx, my, mz, height, st])
	return solid


static func _build_path_tubes(
	graph: OclGraphHandle,
	nodes: Array,
	tube_radius: float
) -> PackedInt64Array:
	var ids: PackedInt64Array = []

	for i in range(nodes.size() - 1):
		var from: MazeNode = nodes[i]
		var to: MazeNode = nodes[i + 1]
		var cyl := _build_cylinder_segment(graph, from, to, tube_radius)
		if cyl.get_bits() == 0:
			print("    WARNING: empty cylinder at segment %d->%d" % [i, i + 1])
			continue
		ids.append(cyl.get_bits())

	print("    Built %d cylinder segments" % ids.size())
	return ids


# ===========================================================================
# Stage 5 — Ball solid (OCCT geometry reference)
# ===========================================================================

static func _create_sphere_at(
	graph: OclGraphHandle,
	x: float, y: float, z: float,
	radius: float
) -> OclNodeId:
	var s_info := OclPrimSphereInfo.new()
	s_info.set_radius(radius)

	var axis := OclAxis2Placement.new()
	var loc := OclPoint3.new()
	loc.set_x(x); loc.set_y(y); loc.set_z(z)
	axis.set_location(loc)
	var dir := OclDirection3.new()
	dir.set_x(1.0)
	axis.set_x_dir(dir)
	var ref := OclDirection3.new()
	ref.set_y(1.0)
	axis.set_x_dir_ref(ref)
	s_info.set_placement(axis)

	var solid := OclNodeId.new()
	var st := OclPrimSolid.sphere(graph, s_info, solid)
	if st != OCCTL_OK:
		print("  WARNING: sphere at (%.1f,%.1f,%.1f) failed: %d" % [x, y, z, st])
	return solid


# ===========================================================================
# Stage 6 — Sphere shell
# ===========================================================================

static func _make_sphere_shell(graph: OclGraphHandle) -> OclNodeId:
	var outer_radius := SPHERE_DIAMETER / 2.0
	var inner_radius := outer_radius - SHELL_THICKNESS

	var outer_info := OclPrimSphereInfo.new()
	outer_info.set_radius(outer_radius)
	var outer_solid := OclNodeId.new()
	var st := OclPrimSolid.sphere(graph, outer_info, outer_solid)
	assert(st == OCCTL_OK, "outer sphere failed: %d" % st)
	print("  Outer sphere: radius=%.1f" % outer_radius)

	var inner_info := OclPrimSphereInfo.new()
	inner_info.set_radius(inner_radius)
	var inner_solid := OclNodeId.new()
	st = OclPrimSolid.sphere(graph, inner_info, inner_solid)
	assert(st == OCCTL_OK, "inner sphere failed: %d" % st)
	print("  Inner sphere: radius=%.1f" % inner_radius)

	var opts := OclBoolOptions.new()
	var shell := OclNodeId.new()
	st = OclBool.cut(graph,
		PackedInt64Array([outer_solid.get_bits()]),
		PackedInt64Array([inner_solid.get_bits()]),
		opts, shell)
	assert(st == OCCTL_OK, "shell cut failed: %d" % st)

	return shell


# ===========================================================================
# Stage 7 — Torus (mounting ring)
# ===========================================================================

static func _create_torus_at(
	graph: OclGraphHandle,
	cx: float, cy: float, cz: float,
	axis_x: float, axis_y: float, axis_z: float,
	major_r: float, minor_r: float
) -> OclNodeId:
	var info := OclPrimTorusInfo.new()
	info.set_r1(major_r)
	info.set_r2(minor_r)

	var placement := _make_axis2_placement(cx, cy, cz, axis_x, axis_y, axis_z)
	info.set_placement(placement)

	var solid := OclNodeId.new()
	var st := OclPrimSolid.torus(graph, info, solid)
	if st != OCCTL_OK:
		print("  WARNING: torus at (%.1f,%.1f,%.1f) failed: %d" % [cx, cy, cz, st])
	return solid


# ===========================================================================
# Node references
# ===========================================================================

var maze_world: Node3D
var rng: RandomNumberGenerator
var total_path: Array[MazeNode] = []
var end_pos: Vector3
var shell_mesh: MeshInstance3D
var maze_camera: Camera3D


# ===========================================================================
# Clear / Generate helpers
# ===========================================================================

func _clear_maze() -> void:
	# Remove all generated children
	for child in get_children():
		if child != null and child.name != "MazeWorld":
			child.queue_free()
	var mw := get_node_or_null("MazeWorld")
	if mw != null:
		mw.queue_free()
		maze_world = null
	shell_mesh = null
	maze_camera = null
	total_path.clear()
	print("Cleared maze.")


# ===========================================================================
# Main generation
# ===========================================================================

func _generate_maze() -> void:
	_clear_maze()
	print("\n=== 3D Marble Maze Game (OCCT-Light.gd) ===")
	print()

	# --- Initialize OCCT ---
	var rt := _init_occt()
	assert(rt == OCCTL_OK, "OCCT runtime_init failed: %d" % rt)
	print("OCCT runtime initialized.")

	# --- Create graph ---
	var graph := _make_graph()
	print("Graph created.")

	# --- RNG ---
	rng = RandomNumberGenerator.new()
	rng.seed = SEED

	# --- Create MazeWorld container ---
	maze_world = Node3D.new()
	maze_world.name = "MazeWorld"
	add_child(maze_world)

	# ==================================================================
	# Phase 1 — Sphere casing
	# ==================================================================
	print("\n=== Phase 1: Sphere casing ===")

	var inner_radius := (SPHERE_DIAMETER / 2.0) - SHELL_THICKNESS
	var shell := _make_sphere_shell(graph)

	shell_mesh = _mesh_solid(graph, shell, Color(0.35, 0.35, 0.4), 0.0, true)
	if shell_mesh != null:
		shell_mesh.cast_shadow = GeometryInstance3D.ShadowCastingSetting.SHADOW_CASTING_SETTING_OFF
		shell_mesh.name = "ShellMesh"
		maze_world.add_child(shell_mesh)
		print("Shell mesh added.")
	else:
		print("ERROR: Shell mesh was null!")

	# ==================================================================
	# Phase 2 — Grid + Waypoints + Pathfinding
	# ==================================================================
	print("\n=== Phase 2: Grid and pathfinding ===")

	var grid: Array = _generate_surface_grid(inner_radius, NODE_SIZE)
	var nodes_arr: Array[MazeNode] = grid[0]
	var node_dict: Dictionary = grid[1] as Dictionary

	# Build neighbor cache for surface grid A* pathfinding
	var neighbor_cache := _build_neighbor_cache(nodes_arr, node_dict, NODE_SIZE)

	var mounting_wps: Array[MazeNode] = _select_mounting_waypoints(nodes_arr, MOUNTING_POINTS, inner_radius)
	for mw in mounting_wps:
		mw.occupied = true

	var random_wps: Array[MazeNode] = _select_waypoints_random(
		nodes_arr, NUMBER_OF_WAYPOINTS - MOUNTING_POINTS, rng
	)
	print("  Random waypoints: %d" % random_wps.size())

	var start_node: MazeNode = null
	var min_x := INF
	for n in nodes_arr:
		if n.x < min_x:
			min_x = n.x
			start_node = n
	if start_node == null:
		start_node = nodes_arr[0]
	start_node.puzzle_start = true
	start_node.occupied = true
	print("  Start node: %s" % start_node)

	total_path = [start_node]
	var puzzle_dict: Dictionary = {"nodes": nodes_arr, "node_dict": node_dict, "neighbor_cache": neighbor_cache}

	var all_wps: Array[MazeNode] = []
	all_wps.append_array(mounting_wps)
	all_wps.append_array(random_wps)

	for wp in all_wps:
		var from: MazeNode = total_path[total_path.size() - 1]
		var to: MazeNode = wp
		print("  Pathfinding: %s -> %s" % [from, to])
		var seg: Array = _a_star(from, to, puzzle_dict, {})
		if not seg.is_empty():
			print("    Path found: %d nodes" % seg.size())
			for n in seg:
				if not total_path.has(n):
					total_path.append(n)
					n.occupied = true
		else:
			print("    No path found!")

	if random_wps.size() > 0 and total_path.size() > 1:
		total_path[total_path.size() - 1].puzzle_end = true

	end_pos = Vector3(total_path[total_path.size() - 1].x, total_path[total_path.size() - 1].y, total_path[total_path.size() - 1].z)
	print("  Total path length: %d nodes" % total_path.size())
	print("  End position: %s" % end_pos)

	# ==================================================================
	# Phase 3 — Cylinder tubes for each segment
	# ==================================================================
	print("\n=== Phase 3: Cylinder tubes ===")

	var segments: Array = []
	var current_seg: Array[MazeNode] = [total_path[0]]

	for i in range(1, total_path.size()):
		current_seg.append(total_path[i])

		if i < total_path.size() - 1:
			var prev: MazeNode = total_path[i - 1]
			var nxt: MazeNode = total_path[i + 1]
			var seg_v1 := Vector3(total_path[i].x - prev.x, total_path[i].y - prev.y, total_path[i].z - prev.z).normalized()
			var seg_v2 := Vector3(nxt.x - total_path[i].x, nxt.y - total_path[i].y, nxt.z - total_path[i].z).normalized()
			var seg_dot: float = seg_v1.dot(seg_v2)

			if abs(seg_dot - 1.0) >= 0.01:
				segments.append({"nodes": current_seg.duplicate()})
				current_seg = [total_path[i]]

	if current_seg.size() > 0:
		segments.append({"nodes": current_seg.duplicate()})

	print("  Segments detected: %d" % segments.size())

	var all_tube_ids: PackedInt64Array = []
	for seg_idx in segments.size():
		var seg_data: Dictionary = segments[seg_idx]
		var seg_nodes: Array = seg_data.nodes

		if seg_nodes.size() < 2:
			continue

		print("  Building segment %d: %d nodes" % [seg_idx, seg_nodes.size()])
		var tube_ids := _build_path_tubes(graph, seg_nodes, TUBE_RADIUS)
		if tube_ids.size() == 0:
			print("    Segment %d: no valid geometry" % seg_idx)
			continue

		for ci in tube_ids.size():
			var cid := OclNodeId.new()
			cid.set_bits(tube_ids[ci])
			var color_idx := seg_idx % PATH_COLORS.size()
			var color: Color = PATH_COLORS[color_idx]
			var seg_mesh := _mesh_solid(graph, cid, color, 0.0, false, true)
			if seg_mesh != null:
				seg_mesh.cast_shadow = GeometryInstance3D.ShadowCastingSetting.SHADOW_CASTING_SETTING_ON
				seg_mesh.name = "TubeMesh_%d_%d" % [seg_idx, ci]
				maze_world.add_child(seg_mesh)

			all_tube_ids.append(tube_ids[ci])

		print("    Segment %d: %d cylinders added" % [seg_idx, tube_ids.size()])

	_log_graph_stats(graph, "after-tubes")
	print("  Total cylinders: %d" % all_tube_ids.size())

	# ==================================================================
	# Phase 4 — Cut tubes from shell
	# ==================================================================
	print("\n=== Phase 4: Cut maze channels into shell ===")

	if all_tube_ids.size() > 0:
		var opts := OclBoolOptions.new()
		var cut_result := OclNodeId.new()
		var st := OclBool.cut(graph,
			PackedInt64Array([shell.get_bits()]),
			all_tube_ids,
			opts, cut_result)
		if st == OCCTL_OK:
			print("  Cut succeeded.")

			var heal_opts := OclHealOptions.new()
			heal_opts.set_mode(OclHeal.HEAL_MODE_STANDARD)
			var heal_st := OclHeal.shape(graph, cut_result.get_bits(), heal_opts)
			if heal_st == OCCTL_OK:
				print("  Healed cut result.")
			else:
				print("  Heal returned: %d (non-fatal)" % heal_st)

			var unify_opts := OclHealUnifySameDomainOptions.new()
			var unified := OclNodeId.new()
			var unify_st := OclHeal.unify_same_domain(graph, cut_result.get_bits(), unify_opts, unified)
			var display_id: OclNodeId = unified if unify_st == OCCTL_OK else cut_result
			if unify_st == OCCTL_OK:
				print("  Unified cut result.")
			else:
				print("  Unify returned: %d (non-fatal, using original)" % unify_st)

			# Remove old shell mesh and add cut version
			if shell_mesh != null:
				maze_world.remove_child(shell_mesh)
				shell_mesh.queue_free()

			shell_mesh = _mesh_solid(graph, display_id, Color(0.35, 0.35, 0.4), 0.0, true)
			if shell_mesh != null:
				shell_mesh.cast_shadow = GeometryInstance3D.ShadowCastingSetting.SHADOW_CASTING_SETTING_OFF
				shell_mesh.name = "ShellMesh"
				maze_world.add_child(shell_mesh)
				print("  Cut shell mesh added.")
			else:
				print("  WARNING: cut shell mesh was null, keeping original shell!")
				if shell_mesh != null:
					maze_world.add_child(shell_mesh)
		else:
			print("  Cut FAILED: %d" % st)
	else:
		print("  No tubes to cut!")

	# ==================================================================
	# Phase 5 — Mounting rings
	# ==================================================================
	print("\n=== Phase 5: Mounting rings ===")

	for mw in mounting_wps:
		var maj_r := NODE_SIZE * 0.5
		var min_r := 1.5
		var ax := -mw.x
		var ay := -mw.y
		var az := -mw.z
		var alen: float = sqrt(ax*ax + ay*ay + az*az)
		if alen > 0.001:
			ax /= alen; ay /= alen; az /= alen
			var ring := _create_torus_at(graph, mw.x, mw.y, mw.z, ax, ay, az, maj_r, min_r)
			if ring.get_bits() != 0:
				var ring_mesh := _mesh_solid(graph, ring, MOUNTING_RING_COLOR, 0.0, false)
				if ring_mesh != null:
					ring_mesh.cast_shadow = GeometryInstance3D.ShadowCastingSetting.SHADOW_CASTING_SETTING_ON
					ring_mesh.name = "RingMesh"
					maze_world.add_child(ring_mesh)
					print("  Mounting ring at %s" % mw)

	# ==================================================================
	# Phase 6 — Add collision body to the maze
	# ==================================================================
	print("\n=== Phase 6: Adding physics collision ===")

	var static_body := StaticBody3D.new()
	static_body.name = "MazeCollision"
	maze_world.add_child(static_body)

	var collision_count := 0
	for child in maze_world.get_children():
		if child is MeshInstance3D and child.mesh != null:
			var trimesh: ConcavePolygonShape3D = child.mesh.create_trimesh_shape()
			if trimesh != null:
				var col_shape := CollisionShape3D.new()
				col_shape.shape = trimesh
				static_body.add_child(col_shape)
				collision_count += 1

	print("  Collision shapes created: %d" % collision_count)

	# ==================================================================
	# Phase 7 — Start/end markers
	# ==================================================================
	print("\n=== Phase 7: Start/End markers ===")

	var start_pos := Vector3(total_path[0].x, total_path[0].y, total_path[0].z)

	# End glow marker (green emissive sphere)
	var end_solid := _create_sphere_at(graph, end_pos.x, end_pos.y, end_pos.z, 4.0)
	if end_solid.get_bits() != 0:
		var end_mesh := _mesh_solid(graph, end_solid, END_GLOW_COLOR, 0.0, false, true, 0.5)
		if end_mesh != null:
			end_mesh.name = "EndMarker"
			end_mesh.cast_shadow = GeometryInstance3D.ShadowCastingSetting.SHADOW_CASTING_SETTING_OFF
			maze_world.add_child(end_mesh)
			print("  End marker at %s" % end_pos)

	_log_graph_stats(graph, "final")

	# ==================================================================
	# Phase 8 — Game ball (MeshInstance3D)
	# ==================================================================
	print("\n=== Phase 8: Ball mesh ===")

	var ball_mat := StandardMaterial3D.new()
	ball_mat.albedo_color = BALL_COLOR
	ball_mat.metallic = 0.9
	ball_mat.metallic_specular = 0.4
	ball_mat.roughness = 0.2
	var ball_mesh_instance := MeshInstance3D.new()
	ball_mesh_instance.name = "BallMesh"
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = BALL_DIAMETER / 2.0
	sphere_mesh.height = BALL_DIAMETER
	sphere_mesh.radial_segments = 16
	sphere_mesh.rings = 12
	ball_mesh_instance.mesh = sphere_mesh
	ball_mesh_instance.material_override = ball_mat
	maze_world.add_child(ball_mesh_instance)
	ball_mesh_instance.position = start_pos

	print("  Ball mesh at %s" % start_pos)

	# ==================================================================
	# Phase 9 — Camera
	# ==================================================================
	print("\n=== Phase 9: Camera ===")

	maze_camera = Camera3D.new()
	maze_camera.name = "MazeCamera"
	maze_camera.current = true
	maze_camera.near = 0.1
	maze_camera.far = 1000.0
	add_child(maze_camera)
	maze_camera.position = Vector3(CAMERA_DISTANCE, CAMERA_DISTANCE * 0.4, CAMERA_DISTANCE * 0.6)
	maze_camera.look_at(Vector3.ZERO)

	print("  Camera at %s" % maze_camera.position)

	# ==================================================================
	# Phase 10 — Cleanup
	# ==================================================================
	print("\n=== Phase 10: Cleanup ===")

	# Free the OCCT graph (we have all meshes now)
	_free_graph(graph)
	print("OCCT graph freed.")

	print("\n=== Maze generation complete! ===")
	var tree_node_count := _count_nodes(self)
	print("Total nodes in scene tree: %d" % tree_node_count)


func _count_nodes(node: Node) -> int:
	var c := 1
	for child in node.get_children():
		c += _count_nodes(child)
	return c


# ===========================================================================
# _ready — auto-generate at runtime, show button in editor
# ===========================================================================

func _ready() -> void:
	if Engine.is_editor_hint():
		print("MazeGenerator: @tool mode — set 'generate' in inspector to create the maze.")
	else:
		# Auto-generate at runtime
		_generate_maze()
