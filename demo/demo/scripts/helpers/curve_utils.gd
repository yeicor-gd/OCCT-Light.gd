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


## Compute the tangent direction at a curve control point.
##
## Uses the outgoing handle for all points except the last, where the
## incoming handle is used.  This matches what OCCT's Bezier builder
## produces at the wire endpoints and is the **single source of truth**
## for tangent computation — used by both transform placement and
## auxiliary-curve construction.
static func _forward_at_curve_index(curve: Curve3D, i: int) -> Vector3:
	var from := curve.get_point_position(i)
	var to := from
	if i < curve.point_count - 1:
		to += curve.get_point_out(i)
	else:
		to += -curve.get_point_in(i)
	var fwd := to - from
	if fwd.length_squared() < 1e-10:
		# Degenerate handle — fall back to position difference.
		if i > 0 and i < curve.point_count - 1:
			fwd = curve.get_point_position(i + 1) - curve.get_point_position(i - 1)
		elif i < curve.point_count - 1:
			fwd = curve.get_point_position(i + 1) - from
		elif i > 0:
			fwd = from - curve.get_point_position(i - 1)
	if fwd.length_squared() < 1e-10:
		fwd = Vector3.FORWARD
	return fwd.normalized()


## Ensure a forward direction is not radial (parallel to the position vector).
##
## For paths on a sphere the tangent should always be roughly perpendicular
## to the radial direction.  When the Bezier handle produces a nearly-radial
## forward direction this projects it onto the sphere's tangent plane so
## that looking_at() always succeeds and the profile orientation is valid.
static func _safe_forward(forward: Vector3, position: Vector3) -> Vector3:
	if forward.length_squared() < 1e-10:
		return forward
	var radial := position.normalized()
	if radial.length_squared() < 1e-10:
		return forward
	var dot := forward.dot(radial)
	if abs(dot) < 0.999:
		return forward
	# Forward is nearly radial — project onto the tangent plane.
	var projected := forward - radial * dot
	if projected.length_squared() > 1e-10:
		return projected.normalized()
	# Forward is exactly radial — choose an arbitrary tangent direction.
	var ref := Vector3.UP
	if abs(radial.dot(ref)) > 0.9:
		ref = Vector3.RIGHT
	return radial.cross(ref).normalized()


## Compute a transform at a given curve index point.
##
## When [aux_curve] is provided the "up" vector is derived from the
## spine-to-auxiliary offset direction, matching what OCCT's
## PIPE_MODE_AUXILIARY_SPINE sweep uses internally.  This ensures the
## profile placed at a chunk boundary has the same orientation the
## previous chunk's sweep produced there, eliminating seams.
static func transform_at_index(curve: Curve3D, i: int, aux_curve: Curve3D = null) -> Transform3D:
	var res := Transform3D.IDENTITY
	var from := curve.get_point_position(i)
	res = res.translated(from)

	var raw_fwd := _forward_at_curve_index(curve, i)
	var radial := from.normalized()
	if radial.length_squared() > 1e-10 and abs(raw_fwd.dot(radial)) > 0.999:
		push_warning("Forward direction is radial on spine (shouldn't happen) at index %d" % i)
	var forward := _safe_forward(raw_fwd, from)

	# Compute up vector: prefer spine-to-aux right direction when available.
	# This matches OCCT's auxiliary-spine trihedron: right = aux - spine, up = right × forward.
	var up := from.normalized()
	if up.length_squared() < 1e-10:
		up = Vector3.UP
	if aux_curve != null and i < aux_curve.point_count:
		var right := aux_curve.get_point_position(i) - from
		if right.length_squared() > 1e-10:
			up = right.cross(forward).normalized()

	res = res.looking_at(from + forward, up)
	return res


## Compute a transform at a baked length along the curve.
##
## Optionally uses an auxiliary curve for the up vector, matching
## transform_at_index() logic so the camera follow orientation is
## consistent with the sweep orientation.
static func transform_at_baked(
	curve: Curve3D, baked_length: float,
	cubic_interp: bool = true,
	aux_curve: Curve3D = null,
) -> Transform3D:
	var res := Transform3D.IDENTITY
	if baked_length + 0.001 >= curve.get_baked_length():
		return res

	var from := curve.sample_baked(baked_length, cubic_interp)
	res = res.translated(from)

	# Sample forward from the curve at a small step ahead.
	var step := 0.1
	if baked_length + step >= curve.get_baked_length():
		step = maxf(0.001, curve.get_baked_length() - baked_length - 0.001)
	var next_point := curve.sample_baked(baked_length + step, cubic_interp)
	var raw_fwd := (next_point - from).normalized()
	var radial := from.normalized()
	if radial.length_squared() > 1e-10 and abs(raw_fwd.dot(radial)) > 0.999:
		push_warning("Forward direction is radial on spine (shouldn't happen) at baked length %.3f" % baked_length)
	var forward := _safe_forward(raw_fwd, from)

	# Compute up vector: prefer spine-to-aux right direction when available.
	var up := from.normalized()
	if up.length_squared() < 1e-10:
		up = Vector3.UP
	if aux_curve != null:
		var aux_len := baked_length
		if aux_len + 0.001 < aux_curve.get_baked_length():
			var aux_pos := aux_curve.sample_baked(aux_len, cubic_interp)
			var right := aux_pos - from
			if right.length_squared() > 1e-10:
				up = right.cross(forward).normalized()

	res = res.looking_at(from + forward, up)
	return res


## Build an auxiliary (offset) curve from positions and tilts directly.
##
## Each input point produces exactly one output point (1:1 mapping).
## Tangents are computed via central finite differences on the positions,
## bypassing any Curve3D handle state so the count is guaranteed to match.
static func build_auxiliary_curve_from_points(
		positions: PackedVector3Array,
		offset_amount: float, sharpness: float
) -> Curve3D:
	var res := Curve3D.new()
	var n := positions.size()
	if n == 0:
		return res

	var offset_positions := PackedVector3Array()
	offset_positions.resize(n)
	var tilts := PackedFloat32Array()
	tilts.resize(n)

	for i in range(n):
		var pos := positions[i]
		var prev := positions[max(i - 1, 0)]
		var next := positions[min(i + 1, n - 1)]
		var tangent := (next - prev).normalized()

		# Tilt (same logic as precompute_curve_data).
		var wup := Vector3.UP
		if abs(tangent.dot(wup)) > 0.98:
			wup = Vector3.RIGHT
		var r_vec := tangent.cross(wup).normalized()
		var u_vec := r_vec.cross(tangent).normalized()
		var desired := pos - tangent * pos.dot(tangent)
		if desired.length_squared() > 1e-10:
			desired = desired.normalized()
		else:
			desired = u_vec
		tilts[i] = atan2(r_vec.dot(desired), u_vec.dot(desired))

		# Offset position perpendicular to tangent and radial.
		offset_positions[i] = pos + _floor_perpendicular(tangent, pos) * offset_amount

	# Add offset points (one per input position).
	for i in range(n):
		res.add_point(offset_positions[i])

	if n == 1:
		return res

	# Segment vectors of the offset curve.
	var segs: Array[Vector3] = []
	for i in range(n - 1):
		segs.append(offset_positions[i + 1] - offset_positions[i])

	res.set_point_out(0, segs[0] / sharpness)
	res.set_point_in(0, -segs[0] / sharpness)

	res.set_point_out(n - 1, segs[n - 2] / sharpness)
	res.set_point_in(n - 1, -segs[n - 2] / sharpness)

	for i in range(1, n - 1):
		var mean_len := (segs[i - 1].length() + segs[i].length()) * 0.5
		var t := (segs[i - 1].normalized() + segs[i].normalized()).normalized()
		var handle := t * mean_len / sharpness
		res.set_point_out(i, handle)
		res.set_point_in(i, -handle)

	for i in range(n):
		res.set_point_tilt(i, tilts[i])

	return res


# ── Helpers ──────────────────────────────────────────────────────────────

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
