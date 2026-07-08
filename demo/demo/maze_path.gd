@tool
extends Path3D
class_name MazePath

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

@export_group("Rope")

## Number of nodes along the rope. More nodes = finer detail.
@export_range(2, 5000) var node_count: int = 200

## Rest length of each rope segment. The PBD spring attempts to keep
## consecutive nodes this far apart.
@export_range(0.001, 10.0) var segment_length: float = 0.1

## Curve sharpness. Higher values make the interpolated Catmull-Rom
## spline hug the node positions more tightly (lower = smoother / looser).
@export_range(0.5, 30.0) var sharpness: float = 5.0

@export var regenerate_on_play := false

@export_group("Solver")

## Number of PBD iterations. More iterations = stiffer constraint
## satisfaction but slower generation.
@export_range(1, 10000) var relaxation_iters: int = 2000

## How many adjacent nodes to skip during self-repulsion. 1 means
## neighbours are excluded; higher values let the repulsion range grow.
@export_range(0, 20) var repulsion_skip: int = 1

@export_subgroup("Strengths")

## Stiffness of the segment-length spring.  Higher = segments snap
## faster to rest length.
@export_range(0.0, 10.0) var segment_strength: float = 0.5

## Stiffness of the shell-containment push.  Higher = nodes hug the
## inner/outer boundary more tightly.
@export_range(0.0, 10.0) var shell_strength: float = 1.0

## How radial to be before [radial_penalty_strength] starts to apply
@export_range(0.0, 1.0) var radial_penalty_threshold := 0.5

## Penalty strength for segments aligned with the radial direction.
## Higher = stronger push away from forming columns.
@export_range(0.0, 10.0) var radial_penalty_strength: float = 0.5

## Stiffness of the inter-node repulsion.  Higher = nodes spread apart
## more aggressively.
@export_range(0.0, 10.0) var repulsion_strength: float = 1.0

## Random jitter applied every iteration to help the system escape
## symmetrical local minima. 0 = deterministic, 0.02 = mild, 0.1 = chaotic.
@export_range(0.0, 1.0, 0.001) var jitter_noise: float = 0.001

# -----------------------------------------------------------------------------
# Editor Tools
# -----------------------------------------------------------------------------

@export_group("Actions")

@export_tool_button("Reset") var reset_ = _reset
@export_tool_button("Step") var step_ = func(): _step(1)
@export_tool_button("Step N") var step_n_ = func(): _step(relaxation_iters)
@export_tool_button("Generate") var generate_ = _generate

# -----------------------------------------------------------------------------
# Runtime State
# -----------------------------------------------------------------------------

class RopeNode:
	var pos: Vector3

	func _init(p: Vector3):
		pos = p

var nodes: Array[RopeNode] = []
var _parent_generator = null
var _rng = RandomNumberGenerator.new()

class SpatialHash:
	var cell_size : float
	var cells := {}

	func _init(size: float):
		cell_size = size

	func clear():
		cells.clear()

	func _key(v: Vector3i) -> int:
		return (
			v.x * 73856093 ^
			v.y * 19349663 ^
			v.z * 83492791
		)

	func cell(pos: Vector3) -> Vector3i:
		return Vector3i(
			floori(pos.x / cell_size),
			floori(pos.y / cell_size),
			floori(pos.z / cell_size)
		)

	func insert(index: int, pos: Vector3):
		var c = cell(pos)
		var k = _key(c)

		if !cells.has(k):
			cells[k] = PackedInt32Array()

		var arr : PackedInt32Array = cells[k]
		arr.append(index)
		cells[k] = arr

	func neighbours(pos: Vector3) -> PackedInt32Array:

		var result := PackedInt32Array()

		var c = cell(pos)

		for x in range(-1, 2):
			for y in range(-1, 2):
				for z in range(-1, 2):

					var k = _key(c + Vector3i(x,y,z))

					if cells.has(k):
						result.append_array(cells[k])

		return result

# -----------------------------------------------------------------------------
# Parent access — radii, margin and seed are sourced from MazeGenerator
# -----------------------------------------------------------------------------

func _get_parent_generator():
	if not _parent_generator or not is_instance_valid(_parent_generator):
		_parent_generator = get_parent()
	return _parent_generator

func _get_inner_radius() -> float:
	var p = _get_parent_generator()
	return p.maze_inner_radius if p else 2.0

func _get_outer_radius() -> float:
	var p = _get_parent_generator()
	return p.maze_outer_radius if p else 5.0

func _get_seed() -> int:
	var p = _get_parent_generator()
	return p.seed_value if p else 0

## Clearance margin derived from the parent MazeGenerator's ball size /
## fill ratio.  Controls both shell proximity and self-repulsion.
func _get_tube_margin() -> float:
	var p = _get_parent_generator()
	if p and p.ball_radius > 0 and p.ball_to_path_min_ratio > 0:
		return p.ball_radius / p.ball_to_path_min_ratio
	return 0.0

# -----------------------------------------------------------------------------
# Physical Rope Simulation (Position-Based Dynamics)
#
# The rope starts as a straight line from (-R,0,0) to (+R,0,0) where R is
# the outer radius.  A PBD loop relaxes it: segment springs, shell
# containment, radial-tangent alignment penalty, self-repulsion, and
# a small jitter — producing a space-filling curve inside the shell.
# -----------------------------------------------------------------------------

func _ready():
	if regenerate_on_play and !Engine.is_editor_hint():
		_generate()

func _reset():
	nodes.clear()
	var curve_data := _precompute_curve_data()
	_apply_curve_data(curve_data)
	curve.clear_points()

func _step(n: int):
	var self_task: Array[int] = [-1]
	self_task[0] = WorkerThreadPool.add_task(func():
		if nodes.is_empty():
			_rng.seed = _get_seed()
			_init_rope()
		else:
			var _old_iterations := relaxation_iters
			relaxation_iters = n
			_relax()
			relaxation_iters = _old_iterations
		var curve_data := _precompute_curve_data()
		_apply_curve_data.call_deferred(curve_data)
		WorkerThreadPool.wait_for_task_completion.call_deferred(self_task[0]))

func _generate():
	_reset()
	var self_task: Array[int] = [-1]
	self_task[0] = WorkerThreadPool.add_task(func():
		_rng.seed = _get_seed()
		_init_rope()
		_relax()
		var curve_data := _precompute_curve_data()
		_apply_curve_data.call_deferred(curve_data)
		WorkerThreadPool.wait_for_task_completion.call_deferred(self_task[0]))

var _fixed_start: Vector3
var _fixed_end: Vector3

func _init_rope():
	var start_time := Time.get_ticks_usec()
	var margin = _get_tube_margin()
	var outer = _get_outer_radius() - margin
	_fixed_start = Vector3.FORWARD * -outer
	_fixed_end = Vector3.FORWARD * outer

	nodes.append(RopeNode.new(_fixed_start))
	for i in range(1, node_count - 1):
		var t = float(i) / (node_count - 1)
		nodes.append(RopeNode.new(_fixed_start.lerp(_fixed_end, t) + Vector3(
				_rng.randf_range(-1.0, 1.0),
				_rng.randf_range(-1.0, 1.0),
				_rng.randf_range(-1.0, 1.0)
			) * jitter_noise))
	nodes.append(RopeNode.new(_fixed_end))
	print("MazePath::_init_rope took ", (Time.get_ticks_usec() - start_time) / 1000.0, " ms to build ", nodes.size(), " nodes")

func _relax():
	var start_time := Time.get_ticks_usec()
	var margin = _get_tube_margin()
	var inner = _get_inner_radius() + margin
	var outer = _get_outer_radius() - margin
	var n = nodes.size()
	
	nodes[0].pos = _fixed_start
	nodes[n - 1].pos = _fixed_end

	var spatial_hash = SpatialHash.new(2 * margin)  # radius to diameter -- sep between curves
	for _iter in range(relaxation_iters):
		spatial_hash.clear()
		for i in range(n):
			spatial_hash.insert(i, nodes[i].pos)

		# 1. Segment length.
		for i in range(n - 1):
			var delta = nodes[i + 1].pos - nodes[i].pos
			var dist = delta.length()
			var c = delta / dist * ((dist - segment_length) * 0.5 * min(segment_strength, 1.0))
			nodes[i].pos += c
			nodes[i + 1].pos -= c

		# 2. Shell projection.
		for i in range(n):
			var p = nodes[i].pos
			var d = p.length()

			if d < 0.0001:
				nodes[i].pos += Vector3.RIGHT * inner - p
			elif d < inner:
				nodes[i].pos += (p / d * inner - p) * shell_strength
			elif d > outer:
				nodes[i].pos += (p / d * outer - p) * shell_strength

		# 3. Avoid radial segments.
		for i in range(n - 1):
			var dir = nodes[i + 1].pos - nodes[i].pos
			var dirlen = dir.length()
			if dirlen < 0.0001:
				continue
			dir /= dirlen

			var radial = (nodes[i].pos + nodes[i + 1].pos).normalized()
			var alignment = abs(dir.dot(radial))
			if alignment <= radial_penalty_threshold:
				continue

			var sideways = radial - dir * dir.dot(radial)
			var slen = sideways.length()
			if slen < 0.0001:
				continue

			var t = (alignment - radial_penalty_threshold) / (1.0 - radial_penalty_threshold)
			var push = sideways / slen * (t * t * radial_penalty_strength * 0.5)

			nodes[i].pos += push
			nodes[i + 1].pos += push

		# 4. Self-repulsion.
		# (Repulsion should happen last because it's the least rigid constraint)
		for i in range(n):
			var nearby = spatial_hash.neighbours(nodes[i].pos)
			for j in nearby:
				if j <= i + repulsion_skip:
					continue
				var delta = nodes[j].pos - nodes[i].pos
				var dist2 = delta.length_squared()
				if dist2 < 0.0001:
					continue
				if dist2 > 4 * margin * margin:
					continue
				var dist = sqrt(dist2)
				var t = 1.0 - dist / (2 * margin)
				var push = delta / dist
				push *= t * t * repulsion_strength * 0.5
				nodes[i].pos -= push
				nodes[j].pos += push

		# Restore anchors.
		nodes[0].pos = _fixed_start
		nodes[n - 1].pos = _fixed_end
	var relax_time = (Time.get_ticks_usec() - start_time) / 1000.0
	print("MazePath::_relax took ", relax_time, " ms to do ", relaxation_iters, " iterations (", relax_time / relaxation_iters, "ms/iteration)")

# -----------------------------------------------------------------------------
# Curve — smooth Catmull-Rom-like interpolation with radial tilt
# -----------------------------------------------------------------------------
class CurvePointData:
	var position: Vector3
	var in_handle: Vector3
	var out_handle: Vector3
	var tilt: float


func _precompute_curve_data() -> Array[CurvePointData]:
	var start_time := Time.get_ticks_usec()
	var n := nodes.size()

	var positions := PackedVector3Array()
	positions.resize(n)

	for i in n:
		positions[i] = nodes[i].pos

	var data: Array[CurvePointData] = []
	data.resize(n)

	for i in range(n):
		var pos := positions[i]

		var prev := positions[max(i - 1, 0)]
		var next := positions[min(i + 1, n - 1)]

		var tangent := (next - prev).normalized()

		# Pick a stable reference up.
		var world_up := Vector3.UP
		if abs(tangent.dot(world_up)) > 0.98:
			world_up = Vector3.RIGHT

		var right := tangent.cross(world_up).normalized()
		var up := right.cross(tangent).normalized()

		# Desired radial up.
		var desired_up := pos - tangent * pos.dot(tangent)

		if desired_up.length_squared() > 1e-10:
			desired_up = desired_up.normalized()
		else:
			desired_up = up

		# Closed-form tilt.
		var tilt := atan2(
			right.dot(desired_up),
			up.dot(desired_up)
		)

		var d := CurvePointData.new()
		d.position = pos

		var handle := (next - prev) / sharpness
		d.in_handle = -handle
		d.out_handle = handle
		d.tilt = tilt

		data[i] = d

	var relax_time = (Time.get_ticks_usec() - start_time) / 1000.0
	print("MazePath::_precompute_curve_data took ", relax_time, " ms to compute ", n, " positions")
	return data


func _apply_curve_data(data: Array[CurvePointData]) -> void:
	var start_time := Time.get_ticks_usec()
	curve.clear_points()
	
	for d in data: # Setting point_count first causes false errors: The target vector can't be zero.
		curve.add_point(d.position)

	for i in range(data.size()):
		curve.set_point_in(i, data[i].in_handle)
		curve.set_point_out(i, data[i].out_handle)
		curve.set_point_tilt(i, data[i].tilt)
		
	var relax_time = (Time.get_ticks_usec() - start_time) / 1000.0
	print("MazePath::_apply_curve_data took ", relax_time, " ms to compute ", data.size(), " positions")

func transform_at_point(i: int) -> Transform3D:
	var res := Transform3D.IDENTITY
	var from := curve.get_point_position(i)
	res = res.translated(from)
	var next_point := from
	if i < curve.point_count - 1:
		next_point += curve.get_point_out(i)
	else:
		next_point += -curve.get_point_in(i)
	var is_radial = abs(fmod((next_point - from).normalized().angle_to(from.normalized()), PI)) < 0.001
	if not is_radial:
		res = res.looking_at(next_point, from.normalized())
	return res

func transform_at(baked_length: float, cubic_interp: bool = true) -> Transform3D:
	var res := Transform3D.IDENTITY
	if baked_length+0.001 < curve.get_baked_length():
		var from := curve.sample_baked(baked_length, cubic_interp)
		res = res.translated(from)
		var next_point := curve.sample_baked(baked_length+0.001, cubic_interp)
		var is_radial = abs(fmod((next_point - from).normalized().angle_to(from.normalized()), PI)) < 0.001
		if not is_radial:
			res = res.looking_at(next_point, from.normalized())
	return res
