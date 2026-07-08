@tool
class_name RopePhysics
extends RefCounted

## Position-Based Dynamics rope simulation for space-filling curves inside a
## spherical shell.
##
## Usage:
##   var rope := RopePhysics.new()
##   rope.node_count = 200
##   rope.segment_length = 0.1
##   rope.init_rope(seed_value, outer_radius, tube_margin)
##   rope.relax(inner_radius, outer_radius, tube_margin)
##   var positions: PackedVector3Array = rope.get_positions()


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

var node_count: int = 200
var segment_length: float = 0.1

## Curve sharpness for Catmull-Rom spine. Higher = tighter.
var sharpness: float = 5.0

## Number of PBD iterations.
var relaxation_iters: int = 2000

## Adjacent nodes to skip during self-repulsion.
var repulsion_skip: int = 1

## Segment-length spring stiffness.
var segment_strength: float = 0.5

## Shell-containment push stiffness.
var shell_strength: float = 1.0

## Threshold for radial-penalty alignment.
var radial_penalty_threshold: float = 0.5

## Penalty strength for radial segments.
var radial_penalty_strength: float = 0.5

## Inter-node repulsion stiffness.
var repulsion_strength: float = 1.0

## Random jitter every iteration to escape symmetry.
var jitter_noise: float = 0.001

# -----------------------------------------------------------------------------
# Spatial hash for O(1) neighbour lookups
# -----------------------------------------------------------------------------

class SpatialHash:
	var cell_size: float
	var cells := {}

	func _init(size: float):
		cell_size = size

	func clear():
		cells.clear()

	static func _key(v: Vector3i) -> int:
		return v.x * 73856093 ^ v.y * 19349663 ^ v.z * 83492791

	func cell(pos: Vector3) -> Vector3i:
		return Vector3i(
			floori(pos.x / cell_size),
			floori(pos.y / cell_size),
			floori(pos.z / cell_size),
		)

	func insert(index: int, pos: Vector3):
		var c = cell(pos)
		var k = _key(c)
		if not cells.has(k):
			cells[k] = PackedInt32Array()
		var arr: PackedInt32Array = cells[k]
		arr.append(index)
		cells[k] = arr

	func neighbours(pos: Vector3) -> PackedInt32Array:
		var result := PackedInt32Array()
		var c = cell(pos)
		for x in range(-1, 2):
			for y in range(-1, 2):
				for z in range(-1, 2):
					var k = _key(c + Vector3i(x, y, z))
					if cells.has(k):
						result.append_array(cells[k])
		return result

# -----------------------------------------------------------------------------
# Rope state
# -----------------------------------------------------------------------------

class RopeNode:
	var pos: Vector3
	func _init(p: Vector3):
		pos = p

var nodes: Array[RopeNode] = []
var fixed_start: Vector3
var fixed_end: Vector3
var _rng := RandomNumberGenerator.new()

# -----------------------------------------------------------------------------
# API
# -----------------------------------------------------------------------------

func clear():
	nodes.clear()

func init_rope(seed_value: int, outer_radius: float, margin: float):
	var start_time := Time.get_ticks_usec()
	_rng.seed = seed_value
	var outer := outer_radius - margin
	fixed_start = Vector3.FORWARD * -outer
	fixed_end = Vector3.FORWARD * outer

	nodes.clear()
	nodes.append(RopeNode.new(fixed_start))
	for i in range(1, node_count - 1):
		var t = float(i) / (node_count - 1)
		nodes.append(RopeNode.new(
			fixed_start.lerp(fixed_end, t) + Vector3(
				_rng.randf_range(-1.0, 1.0),
				_rng.randf_range(-1.0, 1.0),
				_rng.randf_range(-1.0, 1.0),
			) * jitter_noise,
		))
	nodes.append(RopeNode.new(fixed_end))

	var elapsed = (Time.get_ticks_usec() - start_time) / 1000.0
	print("RopePhysics::init_rope took ", elapsed, " ms for ", nodes.size(), " nodes")


func relax(inner_radius: float, outer_radius: float, margin: float):
	var start_time := Time.get_ticks_usec()
	var inner := inner_radius + margin
	var outer := outer_radius - margin
	var n := nodes.size()

	nodes[0].pos = fixed_start
	nodes[n - 1].pos = fixed_end

	var spatial_hash := SpatialHash.new(2.0 * margin)

	for _iter in range(relaxation_iters):
		spatial_hash.clear()
		for i in range(n):
			spatial_hash.insert(i, nodes[i].pos)

		# 1. Segment-length spring.
		for i in range(n - 1):
			var delta = nodes[i + 1].pos - nodes[i].pos
			var dist = delta.length()
			if dist < 0.0001:
				continue
			var c = delta / dist * ((dist - segment_length) * 0.5 * minf(segment_strength, 1.0))
			nodes[i].pos += c
			nodes[i + 1].pos -= c

		# 2. Shell containment.
		for i in range(n):
			var p = nodes[i].pos
			var d = p.length()
			if d < 0.0001:
				nodes[i].pos += Vector3.RIGHT * inner - p
			elif d < inner:
				nodes[i].pos += (p / d * inner - p) * shell_strength
			elif d > outer:
				nodes[i].pos += (p / d * outer - p) * shell_strength

		# 3. Radial-penalty (discourage segments aligned with radial).
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
		for i in range(n):
			var nearby = spatial_hash.neighbours(nodes[i].pos)
			for j in nearby:
				if j <= i + repulsion_skip:
					continue
				var delta = nodes[j].pos - nodes[i].pos
				var dist2 = delta.length_squared()
				if dist2 < 0.0001:
					continue
				if dist2 > 4.0 * margin * margin:
					continue
				var dist = sqrt(dist2)
				var t = 1.0 - dist / (2.0 * margin)
				var push = delta / dist
				push *= t * t * repulsion_strength * 0.5
				nodes[i].pos -= push
				nodes[j].pos += push

		# Restore anchors.
		nodes[0].pos = fixed_start
		nodes[n - 1].pos = fixed_end

	var elapsed = (Time.get_ticks_usec() - start_time) / 1000.0
	print("RopePhysics::relax took ", elapsed, " ms for ", relaxation_iters, " iters (", elapsed / relaxation_iters, " ms/iter)")


func get_positions() -> PackedVector3Array:
	var n := nodes.size()
	var positions := PackedVector3Array()
	positions.resize(n)
	for i in range(n):
		positions[i] = nodes[i].pos
	return positions
