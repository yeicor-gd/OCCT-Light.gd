@tool
class_name CurveUtils
extends RefCounted

## Utilities for building and applying Godot Curve3D from rope node positions.


class CurvePointData:
	var position: Vector3
	var in_handle: Vector3
	var out_handle: Vector3
	var tilt: float


## Build CurvePointData array from rope positions using a Catmull-Rom-like
## spline with radial tilt.
static func precompute_curve_data(
		positions: PackedVector3Array,
		sharpness: float,
) -> Array[CurvePointData]:
	var start_time := Time.get_ticks_usec()
	var n := positions.size()
	var data: Array[CurvePointData] = []
	data.resize(n)

	for i in range(n):
		var pos := positions[i]
		var prev := positions[max(i - 1, 0)]
		var next := positions[min(i + 1, n - 1)]
		var tangent := (next - prev).normalized()

		var world_up := Vector3.UP
		if abs(tangent.dot(world_up)) > 0.98:
			world_up = Vector3.RIGHT

		var right := tangent.cross(world_up).normalized()
		var up := right.cross(tangent).normalized()

		# Desired radial up (perpendicular to tangent, pointing away from origin).
		var desired_up := pos - tangent * pos.dot(tangent)
		if desired_up.length_squared() > 1e-10:
			desired_up = desired_up.normalized()
		else:
			desired_up = up

		var tilt := atan2(right.dot(desired_up), up.dot(desired_up))

		var d := CurvePointData.new()
		d.position = pos
		var handle := (next - prev) / sharpness
		d.in_handle = -handle
		d.out_handle = handle
		d.tilt = tilt
		data[i] = d

	var elapsed = (Time.get_ticks_usec() - start_time) / 1000.0
	print("CurveUtils::precompute_curve_data took ", elapsed, " ms for ", n, " points")
	return data


## Apply precomputed curve data to a Curve3D.
static func apply_curve_data(curve: Curve3D, data: Array[CurvePointData]) -> void:
	var start_time := Time.get_ticks_usec()
	curve.clear_points()

	for d in data:
		curve.add_point(d.position)

	for i in range(data.size()):
		curve.set_point_in(i, data[i].in_handle)
		curve.set_point_out(i, data[i].out_handle)
		curve.set_point_tilt(i, data[i].tilt)

	var elapsed = (Time.get_ticks_usec() - start_time) / 1000.0
	print("CurveUtils::apply_curve_data took ", elapsed, " ms for ", data.size(), " points")


## Compute a transform at a given curve index point.
static func transform_at_index(curve: Curve3D, i: int) -> Transform3D:
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


## Compute a transform at a baked length along the curve.
static func transform_at_baked(curve: Curve3D, baked_length: float, cubic_interp: bool = true) -> Transform3D:
	var res := Transform3D.IDENTITY
	if baked_length + 0.001 < curve.get_baked_length():
		var from := curve.sample_baked(baked_length, cubic_interp)
		res = res.translated(from)
		var next_point := curve.sample_baked(baked_length + 0.001, cubic_interp)
		var is_radial = abs(fmod((next_point - from).normalized().angle_to(from.normalized()), PI)) < 0.001
		if not is_radial:
			res = res.looking_at(next_point, from.normalized())
	return res


## Build an auxiliary (offset) curve from a base curve for sweep orientation.
static func build_auxiliary_curve(base_curve: Curve3D, offset_amount: float = 0.15) -> Curve3D:
	var res := Curve3D.new()
	for i in range(base_curve.point_count):
		var p := base_curve.get_point_position(i)
		var forward: Vector3
		if i < base_curve.point_count - 1:
			forward = base_curve.get_point_out(i)
		else:
			forward = -base_curve.get_point_in(i)

		var right := _floor_perpendicular(forward, p)
		res.add_point(p + right * offset_amount)
		if i < base_curve.point_count - 1:
			res.set_point_out(i, base_curve.get_point_out(i))
		if i > 0:
			res.set_point_in(i, base_curve.get_point_in(i))
	return res


## Unit vector perpendicular to |forward| in the "floor" plane (perp. to radial).
static func _floor_perpendicular(forward: Vector3, point: Vector3) -> Vector3:
	var radial := point.normalized()
	if radial.length_squared() < 0.0001:
		radial = Vector3.UP
	var right := forward.cross(radial)
	if right.length_squared() < 0.0001:
		right = radial.cross(Vector3.UP)
		if right.length_squared() < 0.0001:
			right = radial.cross(Vector3.FORWARD)
	return right.normalized()
