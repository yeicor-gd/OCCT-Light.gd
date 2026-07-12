@tool
class_name RopePhysics
extends Resource

@export var node_count := 200
@export var segment_length := 1.0

@export var iterations := 2000
@export var init_attempts := 10

var inner_radius := 1.0
var outer_radius := 2.0

@export var bend_passes := 2
@export var bend_stiffness := 0.8
@export var bend_levels := 4

@export var collision_passes := 2
@export var collision_stiffness := 0.8
var collision_radius := 0.35

@export var endpoint_flatness := 0.5
@export var endpoint_flatness_passes := 2

@export var radial_bias := 0.1

class RopeNode:

	var pos: Vector3
	var inv_mass: float

	func _init(position: Vector3, pinned := false):
		pos = position
		inv_mass = 0.0 if pinned else 1.0
		
var nodes: Array[RopeNode] = []

var spatial_hash := SpatialHash.new(collision_radius)

var bend_rest_length := 0.0

var fixed_start := Vector3.ZERO
var fixed_end := Vector3.ZERO

var rng := RandomNumberGenerator.new()

class SpatialHash:

	var cell_size: float
	var cells := {}

	func _init(size: float):
		cell_size = size

	func clear():
		cells.clear()
	
	static func _key(cell: Vector3i) -> int:
		return (
			cell.x * 73856093
			^ cell.y * 19349663
			^ cell.z * 83492791
		)
	
	func _cell(position: Vector3) -> Vector3i:
		return Vector3i(
			floori(position.x / cell_size),
			floori(position.y / cell_size),
			floori(position.z / cell_size)
		)

	func insert(index: int, position: Vector3):
		var key := _key(_cell(position))

		if !cells.has(key):
			cells[key] = PackedInt32Array()

		cells[key].append(index)

	func neighbours(position: Vector3) -> PackedInt32Array:
		var result := PackedInt32Array()

		var c := _cell(position)

		for x in range(-1, 2):
			for y in range(-1, 2):
				for z in range(-1, 2):

					var key := _key(c + Vector3i(x, y, z))

					if cells.has(key):
						result.append_array(cells[key])

		return result

func clear():
	nodes.clear()

func init_rope(
	_seed: int,
	start: Vector3 = Vector3.LEFT,
	end: Vector3 = Vector3.RIGHT
):

	rng.seed = _seed

	fixed_start = start
	fixed_end = end

	nodes.clear()

	nodes.append(RopeNode.new(fixed_start, true))

	var front := fixed_start
	var back := fixed_end

	var left := []
	var right := []

	while left.size() + right.size() < node_count - 2:

		if left.size() <= right.size():

			front = _find_next_position(front)

			left.append(front)

		else:

			back = _find_next_position(back)

			right.push_front(back)

	for p in left:
		nodes.append(RopeNode.new(p))

	for p in right:
		nodes.append(RopeNode.new(p))

	nodes.append(RopeNode.new(fixed_end, true))
	
	bend_rest_length = segment_length * 2.0

func _find_next_position(from: Vector3) -> Vector3:

	for _attempt in range(init_attempts):

		var candidate := _next_random_position(from)

		if nodes.size() > 1:

			var previous: Vector3 = nodes.back().pos

			var old_dir := (from - previous).normalized()

			var new_dir := (candidate - from).normalized()

			if old_dir.dot(new_dir) < -0.5:
				continue

		if _is_valid_initial_position(candidate):
			return candidate

	return _next_random_position(from)

func _is_valid_initial_position(position: Vector3) -> bool:

	var min_sq := collision_radius * collision_radius

	for node in nodes:

		if node.pos.distance_squared_to(position) < min_sq:
			return false

	return true

func _build_spatial_hash():
	spatial_hash.cell_size = collision_radius
	spatial_hash.clear()
	for i in range(nodes.size()):
		spatial_hash.insert(i, nodes[i].pos)

func _solve_distance(a_index: int, b_index: int):

	var a := nodes[a_index]
	var b := nodes[b_index]

	var delta := b.pos - a.pos

	var length_sq := delta.length_squared()

	if length_sq < 0.0000001:
		return

	var length := sqrt(length_sq)

	var error := length - segment_length

	if absf(error) < 0.000001:
		return

	var weight := a.inv_mass + b.inv_mass

	if weight == 0.0:
		return

	var correction := delta * (error / length)

	a.pos += correction * (a.inv_mass / weight)
	b.pos -= correction * (b.inv_mass / weight)

func _solve_length_constraints():

	var count := nodes.size()

	# Even edges
	for i in range(0, count - 1, 2):
		_solve_distance(i, i + 1)

	# Odd edges
	for i in range(1, count - 1, 2):
		_solve_distance(i, i + 1)

func _solve_shell_constraints():

	_for_each_free_node(func(i):

		nodes[i].pos = _project_to_shell(nodes[i].pos)

	)

func _solve_bending_constraints():

	for level in range(1, bend_levels + 1):

		var spacing := level + 1
		var rest := segment_length * spacing

		for _pass in range(bend_passes):

			for i in range(nodes.size() - spacing):

				_solve_bend_distance(
					i,
					i + spacing,
					rest
				)

func _solve_bend_distance(a_index, b_index, rest_length: float):

	var a := nodes[a_index]
	var b := nodes[b_index]

	var delta := b.pos - a.pos

	var dist := delta.length()

	if dist < 0.000001:
		return

	var error := dist - rest_length

	var weight := a.inv_mass + b.inv_mass

	if weight == 0.0:
		return

	var correction := delta.normalized()

	correction *= error * bend_stiffness

	a.pos += correction * (a.inv_mass / weight)
	b.pos -= correction * (b.inv_mass / weight)

func _solve_self_collisions():

	for _pass in collision_passes:

		_build_spatial_hash()

		for i in range(nodes.size()):

			_solve_node_collision(i)

			if (i & 15) == 15:
				_build_spatial_hash()

func _solve_node_collision(index: int):

	if _is_pinned(index):
		return

	var nearby := spatial_hash.neighbours(nodes[index].pos)

	for other in nearby:

		if other <= index:
			continue

		if abs(other - index) <= ceili(collision_radius / segment_length):
			continue

		_solve_pair_collision(index, other)

func _solve_pair_collision(a_index: int, b_index: int):

	var a := nodes[a_index]
	var b := nodes[b_index]

	var delta := b.pos - a.pos

	var dist_sq := delta.length_squared()

	if dist_sq < 0.000001:
		return

	var dist := sqrt(dist_sq)

	if dist >= collision_radius:
		return

	var overlap := collision_radius - dist

	var weight := a.inv_mass + b.inv_mass

	if weight == 0.0:
		return

	var correction := delta.normalized()
	correction *= minf(
		overlap * collision_stiffness,
		collision_radius * 0.5
	)

	a.pos -= correction * (a.inv_mass / weight)
	b.pos += correction * (b.inv_mass / weight)

func _solve_endpoint_tangents():

	for _pass in range(endpoint_flatness_passes):

		_solve_endpoint_tangent(0, 1)

		var last := nodes.size() - 1

		_solve_endpoint_tangent(last, last - 1)

func _solve_endpoint_tangent(anchor_index: int, node_index: int):

	var anchor := nodes[anchor_index]
	var node := nodes[node_index]

	var radius := anchor.pos.normalized()

	var tangent := node.pos - anchor.pos

	var radial := radius * tangent.dot(radius)

	tangent -= radial

	if tangent.length_squared() < 0.000001:
		return

	var target := anchor.pos + tangent.normalized() * segment_length

	node.pos = node.pos.lerp(target, endpoint_flatness)

func _pin_anchors():

	nodes[0].pos = fixed_start
	nodes[nodes.size() - 1].pos = fixed_end

func relax():

	if nodes.size() < 2:
		return

	for _iter in range(iterations):

		_solve_length_constraints()
		_project_all_nodes()

		_solve_bending_constraints()
		_project_all_nodes()

		_solve_endpoint_tangents()
		_project_all_nodes()

		_solve_shell_constraints()
		_project_all_nodes()

		_solve_self_collisions()
		_project_all_nodes()

		_pin_anchors()

func _is_pinned(index: int) -> bool:
	return nodes[index].inv_mass == 0.0

func _for_each_free_node(callback: Callable):

	for i in range(1, nodes.size() - 1):
		callback.call(i)

func _next_random_position(from: Vector3) -> Vector3:

	var radial := from.normalized()

	var dir := Vector3(
		rng.randf_range(-1.0, 1.0),
		rng.randf_range(-1.0, 1.0),
		rng.randf_range(-1.0, 1.0)
	).normalized()

	dir -= radial * dir.dot(radial)

	if dir.length_squared() < 0.000001:
		dir = radial.cross(Vector3.UP)

		if dir.length_squared() < 0.000001:
			dir = radial.cross(Vector3.RIGHT)

	dir = dir.normalized()

	dir += radial * rng.randf_range(
		-radial_bias,
		radial_bias
	)

	dir = dir.normalized()

	var p := from + dir * segment_length

	return _project_to_shell(p)

func _project_to_shell(
	p: Vector3,
	target_radius: float = -1.0
) -> Vector3:

	var d := p.length()

	if d < 0.000001:
		return Vector3.RIGHT * inner_radius

	if target_radius < 0.0:
		target_radius = clampf(
			d,
			inner_radius,
			outer_radius
		)

	return p * (target_radius / d)

func _project_all_nodes():

	for i in range(1, nodes.size() - 1):
		nodes[i].pos = _project_to_shell(nodes[i].pos)

func get_positions() -> PackedVector3Array:

	var result := PackedVector3Array()

	result.resize(nodes.size())

	for i in nodes.size():
		result[i] = nodes[i].pos

	return result
