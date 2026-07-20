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
		#var tangent := (next - prev).normalized()

		#var up := pos.normalized()
		#var right := tangent.cross(up).normalized()

		#var tilt := atan2(right.dot(up), up.dot(up))

		var d := CurvePointData.new()
		d.position = pos
		var handle := (next - prev) / sharpness
		d.in_handle = -handle
		d.out_handle = handle
		#d.tilt = tilt
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
			var cross := right.cross(forward)
			if cross.length_squared() > 1e-10:
				up = cross.normalized()

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
				var cross := right.cross(forward)
				if cross.length_squared() > 1e-10:
					up = cross.normalized()

	res = res.looking_at(from + forward, up)
	return res


## Build an auxiliary (offset) curve from positions and tilts directly.
##
## Each input point produces exactly one output point (1:1 mapping).
## Tangents are computed via central finite differences on the positions,
## bypassing any Curve3D handle state so the count is guaranteed to match.
static func build_auxiliary_curve_from_points(
		positions: PackedVector3Array,
		offset_amount: float, sharpness: float,
		camber: float = 0.0,
) -> Curve3D:
	var res := Curve3D.new()
	var n := positions.size()
	if n == 0:
		return res

	var offset_positions := PackedVector3Array()
	offset_positions.resize(n)

	# Phase 1 — compute raw camber angles per point.
	var raw_angles: PackedFloat32Array
	raw_angles.resize(n)
	for i in range(n):
		raw_angles[i] = 0.0

	if abs(camber) > 1e-10:
		for i in range(n):
			var pos := positions[i]
			var radial_dir := pos.normalized()
			if radial_dir.length_squared() < 0.0001:
				radial_dir = Vector3.UP
			var half_w := mini(mini(i, n - 1 - i), 2)
			var curvature_vec := Vector3.ZERO
			if half_w == 2:
				curvature_vec = (-positions[i - 2] + 16.0 * positions[i - 1]
					- 30.0 * pos + 16.0 * positions[i + 1] - positions[i + 2]) / 12.0
			elif half_w == 1:
				curvature_vec = positions[i - 1] - 2.0 * pos + positions[i + 1]

			var smooth_tan := Vector3.ZERO
			if half_w >= 2:
				smooth_tan = positions[i + 2] - positions[i - 2]
			elif half_w >= 1:
				smooth_tan = positions[i + 1] - positions[i - 1]
			if smooth_tan.length_squared() > 1e-10:
				smooth_tan = smooth_tan.normalized()
			else:
				smooth_tan = _forward_from_positions(positions, i)

			var lat_curv := curvature_vec - smooth_tan * curvature_vec.dot(smooth_tan) - radial_dir * curvature_vec.dot(radial_dir)
			var curv_mag := lat_curv.length()
			var fade := smoothstep(0.0, 0.35, curv_mag)
			if fade > 1e-6:
				var lateral_ref := smooth_tan.cross(radial_dir)
				var bank_dot := lat_curv.dot(lateral_ref)
				if abs(bank_dot) > 1e-10:
					var angle: float = camber * curv_mag * sign(bank_dot) * fade
					raw_angles[i] = clampf(angle, -PI / 2.0, PI / 2.0)

	# Phase 2 — smooth angles so no single point can spike independently.
	var radius := 3
	var smoothed_angles: PackedFloat32Array
	smoothed_angles.resize(n)
	for i in range(n):
		var sum := 0.0
		var count := 0
		for j in range(maxi(0, i - radius), mini(n, i + radius + 1)):
			sum += raw_angles[j]
			count += 1
		smoothed_angles[i] = sum / float(count)
		# Smoothly disable camber at both ends of the curve.
		var end_frac := float(radius) / float(n - 1)
		var end_fade := smoothstep(0.0, end_frac, float(i) / float(n - 1))
		end_fade *= smoothstep(0.0, end_frac, 1.0 - float(i) / float(n - 1))
		smoothed_angles[i] *= end_fade

	# Phase 3 — apply smoothed angles to offset directions.
	for i in range(n):
		var pos := positions[i]
		var tangent := _forward_from_positions(positions, i)
		var offset_dir := _floor_perpendicular(tangent, pos)
		if abs(smoothed_angles[i]) > 1e-10:
			offset_dir = Quaternion(tangent, smoothed_angles[i]) * offset_dir
		offset_positions[i] = pos + offset_dir * offset_amount

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

	return res


## Smoothly adapt a shortcut's auxiliary curve so that at its endpoints
## the "right" direction (spine→aux) lies in the main path's binormal
## plane — the plane spanned by the main path's tangent and spine→aux
## vectors at the anchor.  The shortcut's own tangent is considered so
## the resulting right is also perpendicular to it, ensuring a valid
## trihedron.  Lateral distance is preserved at [code]offset_amount[/code].
##
## The blend region spans [blend_fraction] of the curve on each end,
## interpolated via smoothstep.
static func blend_auxiliary_endpoints(
		aux_curve: Curve3D,
		spine_positions: PackedVector3Array,
		main_aux_curve: Curve3D,
		main_spine_positions: PackedVector3Array,
		anchor_start: int,
		anchor_end: int,
		sharpness: float,
		offset_amount: float,
		blend_fraction: float = 0.25,
) -> void:
	var n := aux_curve.point_count
	if n < 3:
		return

	var blend_count := maxi(3, int(n * clampf(blend_fraction, 0.0, 0.5)))
	blend_count = mini(blend_count, int(n / 2.0))

	# Main path binormal-plane normals at both anchors.
	var plane_s := _binormal_plane_normal(main_spine_positions, main_aux_curve, anchor_start)
	var plane_e := _binormal_plane_normal(main_spine_positions, main_aux_curve, anchor_end)

	# Blend start region: project right into main plane, blend towards original.
	for i in range(blend_count):
		var t := float(i) / float(blend_count)
		t = t * t * (3.0 - 2.0 * t)  # smoothstep

		var spine_pos := _vec_at(spine_positions, i, aux_curve, i)
		var aux_pos := aux_curve.get_point_position(i)
		var sc_fwd := _forward_from_positions(spine_positions, i)

		var target := _align_right_to_plane(sc_fwd, plane_s, aux_pos - spine_pos, offset_amount, spine_pos)
		aux_curve.set_point_position(i, target.lerp(aux_pos, t))

	# Blend end region: same logic, mirrored.
	for i in range(n - blend_count, n):
		var t := float(n - 1 - i) / float(blend_count)
		t = t * t * (3.0 - 2.0 * t)  # smoothstep

		var spine_pos := _vec_at(spine_positions, i, aux_curve, i)
		var aux_pos := aux_curve.get_point_position(i)
		var sc_fwd := _forward_from_positions(spine_positions, i)

		var target := _align_right_to_plane(sc_fwd, plane_e, aux_pos - spine_pos, offset_amount, spine_pos)
		aux_curve.set_point_position(i, target.lerp(aux_pos, t))

	# Recompute Bezier handles for the modified curve.
	_recompute_curve_handles(aux_curve, sharpness)


## Recompute all Bezier handles for a Curve3D from its current positions.
static func _recompute_curve_handles(curve: Curve3D, sharpness: float) -> void:
	var n := curve.point_count
	if n < 2:
		return

	var segs: Array[Vector3] = []
	for i in range(n - 1):
		segs.append(curve.get_point_position(i + 1) - curve.get_point_position(i))

	curve.set_point_out(0, segs[0] / sharpness)
	curve.set_point_in(0, -segs[0] / sharpness)

	curve.set_point_out(n - 1, segs[n - 2] / sharpness)
	curve.set_point_in(n - 1, -segs[n - 2] / sharpness)

	for i in range(1, n - 1):
		var mean_len := (segs[i - 1].length() + segs[i].length()) * 0.5
		var dir := (segs[i - 1].normalized() + segs[i].normalized()).normalized()
		var handle := dir * mean_len / sharpness
		curve.set_point_out(i, handle)
		curve.set_point_in(i, -handle)


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


## Unit normal to the binormal plane of the main path at the given index.
## The plane is spanned by (tangent, spine→aux), so its normal is tangent × right.
static func _binormal_plane_normal(
		main_spine_positions: PackedVector3Array,
		main_aux_curve: Curve3D,
		idx: int,
) -> Vector3:
	var fwd := _forward_from_positions(main_spine_positions, idx)
	var aux_pos := main_aux_curve.get_point_position(idx)
	var spine_pos := _vec_at(main_spine_positions, idx, main_aux_curve, idx)
	var right := aux_pos - spine_pos
	var plane_normal := right.cross(fwd)
	if plane_normal.length_squared() < 1e-8:
		# Degenerate — fall back to radial (away from origin) as up reference.
		var radial := spine_pos.normalized()
		if radial.length_squared() < 1e-8:
			radial = fwd.cross(Vector3.FORWARD)
		return radial
	return plane_normal.normalized()


## Project the shortcut's right direction into the main path's binormal plane
## and scale it to [offset_amount], returning the absolute aux position.
static func _align_right_to_plane(
		sc_fwd: Vector3,
		plane_normal: Vector3,
		current_right: Vector3,
		offset_amount: float,
		spine_pos: Vector3,
) -> Vector3:
	var proj := sc_fwd.cross(plane_normal).normalized()
	if proj.length_squared() < 1e-8:
		return spine_pos + current_right.normalized() * offset_amount
	return spine_pos + proj * offset_amount


## Forward direction (tangent) estimated from positions with clamped index.
static func _forward_from_positions(positions: PackedVector3Array, idx: int) -> Vector3:
	var n := positions.size()
	if n < 2:
		return Vector3.FORWARD
	if idx <= 0:
		return (positions[1] - positions[0]).normalized()
	if idx >= n - 1:
		return (positions[n - 1] - positions[n - 2]).normalized()
	return (positions[idx + 1] - positions[idx - 1]).normalized()


## Return a position from [positions] if in bounds, otherwise fall back to the
## auxiliary curve point at [curve_idx] or Vector3.ZERO.
static func _vec_at(
		positions: PackedVector3Array,
		pos_idx: int,
		curve: Curve3D,
		curve_idx: int,
) -> Vector3:
	if pos_idx >= 0 and pos_idx < positions.size():
		return positions[pos_idx]
	if curve_idx >= 0 and curve_idx < curve.point_count:
		return curve.get_point_position(curve_idx)
	return Vector3.ZERO
