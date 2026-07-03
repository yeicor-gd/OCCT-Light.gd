extends Node3D
## 3D Marble Maze Generator — migrated from 3DMarbleMazeGenerator (Python)
## to OCCT-Light.gd (Godot GDExtension)
##
## Uses the OCCT-Light.gd GDExtension:
##   OclCore      — Runtime init/shutdown
##   OclTopo      — Topology: create solids, booleans, queries, meshing
##   OclPrimSolid — Primitives: sphere, cylinder, box, cone, torus, wedge
##   OclBool      — Boolean operations (fuse, cut, common)
##
## Pipeline:
##   1. Generate 3D grid of nodes inside a hollow sphere casing
##   2. A* pathfinding connects waypoints into a continuous path
##   3. Path is split into segments; cylindrical tubes swept along each
##   4. Paths are subtracted from the sphere shell via CSG
##   5. Everything is meshed and rendered as a Godot 3D scene

# ---------------------------------------------------------------------------
# Configuration  (migrated from config.py)
# ---------------------------------------------------------------------------

const NODE_SIZE: float = 10.0
const SPHERE_DIAMETER: float = 250.0
const SHELL_THICKNESS: float = 2.5
const BALL_DIAMETER: float = 6.0
const SEED: int = 0
const NUMBER_OF_WAYPOINTS: int = 14
const MOUNTING_POINTS: int = 4
const WALL_THICKNESS: float = 1.2
const SWEEP_TOLERANCE: float = 0.001
const PATH_HEIGHT: float = 10.0 - SWEEP_TOLERANCE

const PATH_COLORS: Array[Color] = [
	Color(0.94, 0.8, 0.0),
	Color(0.24, 0.25, 0.8),
	Color(0.72, 0.18, 0.18),
]
const BALL_COLOR: Color = Color(0.75, 0.75, 0.75)
const ACCENT_COLOR: Color = Color(0.93, 0.93, 0.93)
const MOUNTING_RING_COLOR: Color = Color(1.0, 0.84, 0.0)

const OCCTL_OK := 0
const OCCTL_KIND_SOLID := OclCore.KIND_SOLID


# ---------------------------------------------------------------------------
# MazeNode  —  internal grid node (from puzzle/node.py)
# ---------------------------------------------------------------------------

class MazeNode:
	var x: float
	var y: float
	var z: float
	var occupied: bool = false
	var overlap_allowed: bool = false
	var in_circular_grid: bool = false
	var in_rectangular_grid: bool = false
	var waypoint: bool = false
	var puzzle_start: bool = false
	var puzzle_end: bool = false
	var mounting: bool = false
	var segment_start: bool = false
	var segment_end: bool = false
	var parent: Variant = null
	var g_score: float = INF
	var h_score: float = 0.0
	var f_score: float = INF
	var is_obstacle_entry: bool = false
	var is_obstacle_exit: bool = false
	var is_obstacle_occupied: bool = false

	func _init(px: float, py: float, pz: float, circ: bool = false, rect: bool = false):
		x = px
		y = py
		z = pz
		in_circular_grid = circ
		in_rectangular_grid = rect

	func to_key() -> String:
		return "%0.6f:%0.6f:%0.6f" % [_snap(x), _snap(y), _snap(z)]

	func _snap(v: float, d: int = 6) -> float:
		var r: float = v * pow(10.0, float(d))
		r = round(r)
		r = r / pow(10.0, float(d))
		return 0.0 if abs(r) < 1e-9 else r

	static func _eq(a: MazeNode, b: MazeNode) -> bool:
		return a != null and b != null and a.x == b.x and a.y == b.y and a.z == b.z

	func _to_string() -> String:
		return "MazeNode(%.1f, %.1f, %.1f)" % [x, y, z]


# ===========================================================================
#  Geometry helpers
# ===========================================================================

static func manhattan(a: MazeNode, b: MazeNode) -> float:
	return abs(a.x - b.x) + abs(a.y - b.y) + abs(a.z - b.z)


static func euclidean(a: MazeNode, b: MazeNode) -> float:
	var dx := a.x - b.x
	var dy := a.y - b.y
	var dz := a.z - b.z
	return sqrt(dx * dx + dy * dy + dz * dz)


static func squared_dist(ax: float, ay: float, az: float, bx: float, by: float, bz: float) -> float:
	var dx := ax - bx
	var dy := ay - by
	var dz := az - bz
	return dx * dx + dy * dy + dz * dz


# ===========================================================================
#  Stage 1 — Grid generation
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


static func _generate_rectangular_grid(inner_radius: float, node_size: float) -> Array:
	"""Return [nodes: Array[MazeNode], node_dict: Dictionary]."""
	var nodes: Array[MazeNode] = []
	var node_dict: Dictionary = {}

	for x in _frange(-inner_radius, inner_radius, node_size):
		for y in _frange(-inner_radius, inner_radius, node_size):
			for z in _frange(-inner_radius, inner_radius, node_size):
				var cube_half_diag := (node_size * sqrt(3.0)) / 2.0
				var eff := inner_radius - cube_half_diag
				if x * x + y * y + z * z <= eff * eff:
					var node := MazeNode.new(x, y, z, false, true)
					nodes.append(node)
					node_dict[node.to_key()] = node

	return [nodes, node_dict]


static func _add_circular_nodes(
	nodes: Array[MazeNode],
	node_dict: Dictionary,
	radius: float,
	z_plane: float,
	count: int
) -> Array[MazeNode]:
	"""Evenly spaced ring nodes on a z-plane."""
	var added: Array[MazeNode] = []

	for i: int in range(count):
		var angle: float = TAU * float(i) / float(count)
		var xr: float = round(radius * cos(angle))
		var yr: float = round(radius * sin(angle))
		var z: float = round(z_plane)
		if abs(z) < 1e-9:
			z = 0.0
		var key := "%0.6f:%0.6f:%0.6f" % [xr, yr, z]
		if node_dict.has(key):
			var old: MazeNode = node_dict[key]
			var idx := nodes.find(old)
			if idx >= 0:
				nodes.erase(old)
		var node := MazeNode.new(xr, yr, z, true, false)
		nodes.append(node)
		node_dict[key] = node
		added.append(node)

	return added

static func _remove_near_rectangular(
	nodes: Array[MazeNode],
	node_dict: Dictionary,
	refs: Array[MazeNode],
	cutoff: float
):
	var cutoff2 := cutoff * cutoff
	var kept: Array[MazeNode] = []

	print("Starting")

	for i in range(nodes.size()):
		if i % 100 == 0:
			print("Node", i)

		var node := nodes[i]

		if node.in_circular_grid:
			kept.append(node)
			continue

		var remove := false

		for j in range(refs.size()):
			var ref := refs[j]

			if squared_dist(
				node.x, node.y, node.z,
				ref.x, ref.y, ref.z
			) < cutoff2:
				node_dict.erase(node.to_key())
				remove = true
				break

		if !remove:
			kept.append(node)

	print("Exited outer loop")

	nodes.clear()
	nodes.append_array(kept)

	print("Done")

# ===========================================================================
#  Stage 1 — Sphere casing via OCCT-Light.gd
# ===========================================================================

static func _make_sphere_shell(
	topo: OclTopo, graph: OclGraphHandle,
	prim: OclPrimSolid, bool_mod: OclBool
) -> Dictionary:
	"""Build hollow sphere (outer - inner) and cut shape via OCCT-Light.gd."""

	var outer_radius := SPHERE_DIAMETER / 2.0
	var inner_radius := outer_radius - SHELL_THICKNESS

	# Outer sphere
	var outer_info := OclPrimSphereInfo.new()
	prim.sphere_info_init(outer_info)
	outer_info.set_radius(outer_radius)
	var outer_solid := OclNodeId.new()
	var st := prim.make_sphere(graph, outer_info, outer_solid)
	assert(st == OCCTL_OK, "make_sphere outer failed: %s" % OclCore.new().status_to_string(st))

	# Inner sphere (to hollow out)
	var inner_info := OclPrimSphereInfo.new()
	prim.sphere_info_init(inner_info)
	inner_info.set_radius(inner_radius)
	var inner_solid := OclNodeId.new()
	st = prim.make_sphere(graph, inner_info, inner_solid)
	assert(st == OCCTL_OK, "make_sphere inner failed: %s" % OclCore.new().status_to_string(st))

	# Shell = outer - inner
	var shell_opts := OclBoolOptions.new()
	bool_mod.options_init(shell_opts)
	var shell := OclNodeId.new()
	st = bool_mod.cut(graph,
		PackedInt64Array([outer_solid.get_bits()]),
		PackedInt64Array([inner_solid.get_bits()]),
		shell_opts, shell)
	assert(st == OCCTL_OK, "shell cut failed: %s" % OclCore.new().status_to_string(st))

	# Cut shape: larger shell to trim excess paths
	var flush_tol := 0.4
	var cut_outer_r := outer_radius * 2.0
	var cut_inner_r := inner_radius - flush_tol

	var cut_outer_info := OclPrimSphereInfo.new()
	prim.sphere_info_init(cut_outer_info)
	cut_outer_info.set_radius(cut_outer_r)
	var cut_outer := OclNodeId.new()
	prim.make_sphere(graph, cut_outer_info, cut_outer)

	var cut_inner_info := OclPrimSphereInfo.new()
	prim.sphere_info_init(cut_inner_info)
	cut_inner_info.set_radius(cut_inner_r)
	var cut_inner := OclNodeId.new()
	prim.make_sphere(graph, cut_inner_info, cut_inner)

	var cut_opts := OclBoolOptions.new()
	bool_mod.options_init(cut_opts)
	var cut_shape := OclNodeId.new()
	bool_mod.cut(graph,
		PackedInt64Array([cut_outer.get_bits()]),
		PackedInt64Array([cut_inner.get_bits()]),
		cut_opts, cut_shape)

	return {"shell": shell, "cut_shape": cut_shape}


# ===========================================================================
#  Stage 2 — A* pathfinding
# ===========================================================================

static func _find_neighbors(puzzle: Dictionary, node: MazeNode) -> Array:
	"""Return [(neighbor, cost), ...] for A* search."""
	var node_dict: Dictionary = puzzle.node_dict
	var tolerance := NODE_SIZE * 0.1
	var neighbors: Array = []

	# Cardinal neighbors
	var offsets: Array = [
		[NODE_SIZE, 0.0, 0.0],
		[-NODE_SIZE, 0.0, 0.0],
		[0.0, NODE_SIZE, 0.0],
		[0.0, -NODE_SIZE, 0.0],
		[0.0, 0.0, NODE_SIZE],
		[0.0, 0.0, -NODE_SIZE],
	]

	for d in offsets:
		var d_arr: Array = d
		var kx: float = round(node.x + d_arr[0])
		var ky: float = round(node.y + d_arr[1])
		var kz: float = round(node.z + d_arr[2])
		if abs(kz) < 1e-9:
			kz = 0.0
		var key: String = "%0.6f:%0.6f:%0.6f" % [kx, ky, kz]
		var cand: MazeNode = node_dict.get(key)
		if cand:
			neighbors.append([cand, NODE_SIZE])

	# Circular ring neighbors (same plane, closest 2)
	if node.in_circular_grid:
		var same_plane: Array[MazeNode] = []
		for n in puzzle.nodes:
			if n.in_circular_grid and abs(n.z - node.z) < tolerance:
				if n != node:
					same_plane.append(n)

		var dists: Array = []
		for c in same_plane:
			var d := euclidean(node, c)
			if d > tolerance:
				dists.append([c, d])
		dists.sort_custom(func(a, b): return a[1] < b[1])
		for item in dists.slice(0, 2):
			neighbors.append(item)

	return neighbors


static func _a_star(start: MazeNode, goal: MazeNode, puzzle: Dictionary) -> Array:
	"""A* search. Returns path array or empty if no path."""
	var open_set: Array = []
	var closed_set: Array = []

	# Reset pathfinding state
	for n in puzzle.nodes:
		n.g_score = INF
		n.h_score = 0.0
		n.f_score = INF
		n.parent = null

	start.g_score = 0.0
	start.h_score = manhattan(start, goal)
	start.f_score = start.h_score
	open_set.append([start.f_score, start])

	while open_set.size() > 0:
		open_set.sort_custom(func(a, b): return a[0] < b[0])
		var cur: Array = open_set.pop_front()
		var current: MazeNode = cur[1]

		if MazeNode._eq(current, goal):
			return _reconstruct(current)

		var in_closed := false
		for item in closed_set:
			if MazeNode._eq(item, current):
				in_closed = true
				break
		if in_closed:
			continue
		closed_set.append(current)

		for item in _find_neighbors(puzzle, current):
			var neighbor: MazeNode = item[0]
			var cost: float = item[1]

			if closed_set.find(neighbor) >= 0:
				continue

			if neighbor.occupied and not MazeNode._eq(neighbor, goal):
				continue

			var tent := current.g_score + cost
			if tent < neighbor.g_score:
				neighbor.parent = current
				neighbor.g_score = tent
				neighbor.h_score = manhattan(neighbor, goal)
				neighbor.f_score = neighbor.g_score + neighbor.h_score

				var already := false
				for o in open_set:
					if MazeNode._eq(o[1], neighbor):
						already = true
						break
				if not already:
					open_set.append([neighbor.f_score, neighbor])

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
#  Stage 2 — Waypoint selection
# ===========================================================================

static func _select_mounting_waypoints(
	nodes: Array[MazeNode], count: int, inner_radius: float
) -> Array[MazeNode]:
	var selected: Array[MazeNode] = []
	var target_r := inner_radius + NODE_SIZE

	for i in range(count):
		var angle := TAU * float(i) / float(count)
		var tx := target_r * cos(angle)
		var ty := target_r * sin(angle)

		var cands: Array[MazeNode] = []
		for n in nodes:
			if not n.occupied and not selected.has(n):
				cands.append(n)

		if cands.is_empty():
			continue

		var nearest := cands[0]
		var nd := squared_dist(cands[0].x, cands[0].y, cands[0].z, tx, ty, 0.0)
		for c in cands.slice(1):
			var d := squared_dist(c.x, c.y, c.z, tx, ty, 0.0)
			if d < nd:
				nearest = c
				nd = d

		nearest.mounting = true
		nearest.waypoint = true
		selected.append(nearest)

	return selected


static func _select_waypoints_random(
	nodes: Array[MazeNode], count: int, random_gen: RandomNumberGenerator
) -> Array[MazeNode]:
	var free: Array[MazeNode] = []
	for n in nodes:
		if not n.occupied:
			free.append(n)

	var selected: Array[MazeNode] = []

	for wp_i in count:
		if free.is_empty():
			break

		var num_c: int = min(10, free.size())
		var cands: Array[MazeNode] = []
		for ci: int in num_c:
			var idx: int = random_gen.randi() % free.size()
			cands.append(free[idx])

		var best: MazeNode = cands[0]
		var best_d := -1.0

		for cand in cands:
			var md := INF
			for wp in selected:
				var d := euclidean(cand, wp)
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

	return selected


# ===========================================================================
#  Stage 3 — Curve detection
# ===========================================================================

static func _detect_curve_type(prev: MazeNode, curr: MazeNode, nxt: MazeNode) -> String:
	var v1 := Vector3(curr.x - prev.x, curr.y - prev.y, curr.z - prev.z).normalized()
	var v2 := Vector3(nxt.x - curr.x, nxt.y - curr.y, nxt.z - curr.z).normalized()
	var dot := v1.dot(v2)

	if abs(dot - 1.0) < 0.01:
		return "straight"

	if abs(dot + 1.0) < 0.1:
		return "s_curve"

	var angle := acos(clamp(dot, -1.0, 1.0))
	if abs(angle - PI / 2.0) < 0.3 or abs(angle - 3.0 * PI / 2.0) < 0.3:
		return "90_degree"

	return "arc"


# ===========================================================================
#  Stage 4 — Build cylindrical tubes along path segments via OCCT-Light.gd
# ===========================================================================

static func _build_cylinder_along_segment(
	topo: OclTopo, graph: OclGraphHandle,
	prim: OclPrimSolid,
	n1: MazeNode, n2: MazeNode,
	tube_radius: float
) -> OclNodeId:
	"""Create a cylinder connecting two nodes."""
	var dx := n2.x - n1.x
	var dy := n2.y - n1.y
	var dz := n2.z - n1.z
	var seg_len := sqrt(dx * dx + dy * dy + dz * dz)

	if seg_len < 0.001:
		return OclNodeId.new()

	var cx := n1.x + dx * 0.5
	var cy := n1.y + dy * 0.5
	var cz := n1.z + dz * 0.5

	var cyl_info := OclPrimCylinderInfo.new()
	prim.cylinder_info_init(cyl_info)
	cyl_info.set_radius(tube_radius)
	cyl_info.set_height(seg_len)

	# Orient along the direction
	var axis := OclAxis2Placement.new()
	var loc := OclPoint3.new()
	loc.set_x(cx)
	loc.set_y(cy)
	loc.set_z(cz)
	axis.set_location(loc)

	var dir := OclDirection3.new()
	dir.set_x(dx / seg_len)
	dir.set_y(dy / seg_len)
	dir.set_z(dz / seg_len)
	axis.set_x_dir(dir)

	var ref := OclDirection3.new()
	ref.set_x(0.0)
	ref.set_y(1.0)
	ref.set_z(0.0)
	axis.set_x_dir_ref(ref)

	cyl_info.set_placement(axis)

	var solid := OclNodeId.new()
	prim.make_cylinder(graph, cyl_info, solid)
	return solid


static func _fuse_multiple(
	topo: OclTopo,
	graph: OclGraphHandle,
	solid_ids: PackedInt64Array
) -> OclNodeId:
	"""Fuse multiple solids into one using binary fuses."""
	var bool_mod := OclBool.new()
	var opts := OclBoolOptions.new()
	bool_mod.options_init(opts)

	if solid_ids.size() == 0:
		return OclNodeId.new()
	if solid_ids.size() == 1:
		var res := OclNodeId.new()
		res.bits = solid_ids[0]
		return res

	var result := OclNodeId.new()
	bool_mod.fuse(graph, solid_ids, PackedInt64Array(), opts, result)
	return result


static func _build_path_tubes(
	topo: OclTopo, graph: OclGraphHandle,
	prim: OclPrimSolid,
	path: Array,
	tube_radius: float = PATH_HEIGHT / 2.0
) -> OclNodeId:
	"""Build fused cylinder tubes along the path."""
	var solid_ids: PackedInt64Array = []

	for i in range(path.size() - 1):
		var n1: MazeNode = path[i]
		var n2: MazeNode = path[i + 1]
		var cyl := _build_cylinder_along_segment(topo, graph, prim, n1, n2, tube_radius)
		if cyl.get_bits() != 0:
			solid_ids.append(cyl.get_bits())

	if solid_ids.is_empty():
		return OclNodeId.new()

	return _fuse_multiple(topo, graph, solid_ids)


# ===========================================================================
#  Stage 4 — Ball & direction indicators
# ===========================================================================

static func _create_ball_solid(
	prim: OclPrimSolid, graph: OclGraphHandle,
	pos: Vector3
) -> OclNodeId:
	var s_info := OclPrimSphereInfo.new()
	prim.sphere_info_init(s_info)
	s_info.set_radius(BALL_DIAMETER / 2.0)

	var axis := OclAxis2Placement.new()
	var loc := OclPoint3.new()
	loc.set_x(pos.x)
	loc.set_y(pos.y)
	loc.set_z(pos.z)
	axis.set_location(loc)
	var dir := OclDirection3.new()
	dir.set_x(1.0)
	axis.set_x_dir(dir)
	var ref := OclDirection3.new()
	ref.set_y(1.0)
	axis.set_x_dir_ref(ref)
	s_info.set_placement(axis)

	var solid := OclNodeId.new()
	prim.make_sphere(graph, s_info, solid)
	return solid


# ===========================================================================
#  Stage 5 — Convert OCCT solid to Godot MeshInstance3D
# ===========================================================================

static func _solid_to_mesh_instance(
	graph: OclGraphHandle,
	solid_id: OclNodeId,
	color: Color,
	transparency: float = 0.0,
	unshaded: bool = false
) -> MeshInstance3D:
	"""Convert an OCCT solid to a Godot MeshInstance3D via mesh_faces()."""
	var options := OclMeshOptions.new()
	options.angle = 1
	options.deflection = 0.1
	var mesher = OclGodotMesher.new()
	var mesh = mesher.mesh_faces(
		graph, null, options,
		PackedInt64Array([solid_id.get_bits()]),
		true,  # normals
		false, # uvs
		false, # tangents
		false  # colors
	)

	if mesh == null:
		return null

	var inst := MeshInstance3D.new()
	inst.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.3
	mat.metallic_specular = 0.1

	if unshaded:
		mat.shading_mode = 0

	if transparency > 0.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	inst.material_override = mat
	return inst


# ===========================================================================
#  Main — Build the maze and add to scene
# ===========================================================================

var rng: RandomNumberGenerator


func _ready() -> void:
	print("=== 3D Marble Maze Generator (OCCT-Light.gd) ===")
	print()

	rng = RandomNumberGenerator.new()
	rng.seed = SEED

	# ------------------------------------------------------------------
	# Step 1 — Grid + Sphere casing
	# ------------------------------------------------------------------
	print("Step 1: Generating grid and sphere casing...")

	var core := OclCore.new()
	var rt := core.runtime_init()
	assert(rt == OCCTL_OK or rt == 2, "runtime_init failed: %s" % core.status_to_string(rt))

	var topo := OclTopo.new()
	var graph: OclGraphHandle = topo.graph_create()
	var prim := OclPrimSolid.new()
	var bool_mod := OclBool.new()

	var inner_radius := (SPHERE_DIAMETER / 2.0) - SHELL_THICKNESS

	# --- Grid ---
	var grid: Array = _generate_rectangular_grid(inner_radius, NODE_SIZE)
	var nodes_arr: Array = grid[0]
	var node_dict: Dictionary = grid[1] as Dictionary
	print("  Rectangular nodes: %d" % nodes_arr.size())

	var circ_r: float = inner_radius - NODE_SIZE
	var added: Array[MazeNode] = _add_circular_nodes(nodes_arr, node_dict, circ_r, 0.0, MOUNTING_POINTS)
	print("  Circular nodes: %d" % added.size())

	_remove_near_rectangular(nodes_arr, node_dict, added, NODE_SIZE)
	print("  Nodes after pruning: %d" % nodes_arr.size())

	# --- Sphere casing ---
	var casing := _make_sphere_shell(topo, graph, prim, bool_mod)

	# Create mesh for the sphere shell
	var casing_mesh := _solid_to_mesh_instance(
		graph, casing.shell,
		Color(0.5, 0.5, 0.5), 0.85, true
	)
	casing_mesh.cast_shadow = GeometryInstance3D.ShadowCastingSetting.SHADOW_CASTING_SETTING_OFF
	add_child(casing_mesh)
	print("  Sphere shell meshed")

	# ------------------------------------------------------------------
	# Step 2 — Waypoints + A* pathfinding
	# ------------------------------------------------------------------
	print("\nStep 2: Selecting waypoints and computing paths...")

	var mounting_wps: Array[MazeNode] = _select_mounting_waypoints(nodes_arr, MOUNTING_POINTS, inner_radius)
	for mw in mounting_wps:
		mw.occupied = true
	print("  Mounting waypoints: %d" % mounting_wps.size())

	var random_wps: Array[MazeNode] = _select_waypoints_random(
		nodes_arr, NUMBER_OF_WAYPOINTS - MOUNTING_POINTS, rng
	)
	print("  Random waypoints: %d" % random_wps.size())

	# Start node (extend along -X)
	var anchor: MazeNode = nodes_arr[0]
	var start_x: float = round(anchor.x - NODE_SIZE * 2.0)
	var start_node := MazeNode.new(start_x, 0.0, 0.0, true, false)
	start_node.puzzle_start = true
	start_node.occupied = true
	nodes_arr.append(start_node)
	node_dict[start_node.to_key()] = start_node

	var total_path: Array[MazeNode] = [start_node]
	var puzzle_dict: Dictionary = {"nodes": nodes_arr, "node_dict": node_dict}

	# Path through mounting waypoints
	for i in range(mounting_wps.size()):
		var from: MazeNode = total_path[total_path.size() - 1]
		var to: MazeNode = mounting_wps[i]
		var seg: Array = _a_star(from, to, puzzle_dict)
		if not seg.is_empty():
			for n in seg:
				if not total_path.has(n):
					total_path.append(n)
					n.occupied = true

	# Path through random waypoints
	for i in range(random_wps.size()):
		var from: MazeNode = total_path[total_path.size() - 1]
		var to: MazeNode = random_wps[i]
		var seg: Array = _a_star(from, to, puzzle_dict)
		if not seg.is_empty():
			for n in seg:
				if not total_path.has(n):
					total_path.append(n)
					n.occupied = true

	print("  Total path length: %d nodes" % total_path.size())

	if random_wps.size() > 0:
		random_wps[-1].puzzle_end = true

	# ------------------------------------------------------------------
	# Step 3 — Detect segments
	# ------------------------------------------------------------------
	print("\nStep 3: Splitting path into segments...")

	var segments: Array = []  # [{nodes, curve_type}]
	var current: Array[MazeNode] = [total_path[0]]

	for i in range(1, total_path.size()):
		var node: MazeNode = total_path[i]
		current.append(node)

		if i < total_path.size() - 1:
			var prev: MazeNode = total_path[i - 1]
			var nxt: MazeNode = total_path[i + 1]
			var curve := _detect_curve_type(prev, node, nxt)

			if curve != "straight":
				segments.append({"nodes": current.duplicate(), "curve_type": curve})
				current = [node]

	if current.size() > 0:
		segments.append({"nodes": current.duplicate(), "curve_type": "straight"})

	print("  Segments: %d" % segments.size())

	# ------------------------------------------------------------------
	# Step 4 — Build 3D path geometry (cylindrical tubes)
	# ------------------------------------------------------------------
	print("\nStep 4: Building 3D path geometry...")

	var tube_radius := PATH_HEIGHT / 2.0

	# Build colored tubes per segment
	for seg_idx in segments.size():
		var seg_data: Dictionary = segments[seg_idx]
		var seg_nodes: Array = seg_data.nodes

		if seg_nodes.size() < 2:
			continue

		var seg_solid: OclNodeId = _build_path_tubes(topo, graph, prim, seg_nodes, tube_radius)
		if seg_solid.get_bits() == 0:
			continue

		var color_idx := seg_idx % PATH_COLORS.size()
		var color: Color = PATH_COLORS[color_idx]
		var seg_mesh := _solid_to_mesh_instance(graph, seg_solid, color, 0.0, false)
		seg_mesh.cast_shadow = GeometryInstance3D.ShadowCastingSetting.SHADOW_CASTING_SETTING_ON
		add_child(seg_mesh)

	print("  Path segments meshed: %d" % segments.size())

	# Full path tube (thin dark line)
	var full_solid: OclNodeId = _build_path_tubes(topo, graph, prim, total_path, 1.0)
	if full_solid.get_bits() != 0:
		var full_mesh := _solid_to_mesh_instance(graph, full_solid, Color(0.1, 0.1, 0.1), 0.0, false)
		full_mesh.cast_shadow = GeometryInstance3D.ShadowCastingSetting.SHADOW_CASTING_SETTING_OFF
		add_child(full_mesh)

	# ------------------------------------------------------------------
	# Step 5 — Ball + indicators
	# ------------------------------------------------------------------
	print("\nStep 5: Adding ball and direction indicators...")

	var ball_solid: OclNodeId = _create_ball_solid(prim, graph,
		Vector3(total_path[0].x, total_path[0].y, total_path[0].z))
	if ball_solid.get_bits() != 0:
		var ball_mesh := _solid_to_mesh_instance(graph, ball_solid, BALL_COLOR, 0.0, false)
		ball_mesh.cast_shadow = GeometryInstance3D.ShadowCastingSetting.SHADOW_CASTING_SETTING_ON
		add_child(ball_mesh)

	# ------------------------------------------------------------------
	# Cleanup
	# ------------------------------------------------------------------
	topo.graph_free(graph)

	print("\n=== Maze generation complete! ===")
	print("Objects in scene: %d" % get_child_count())
