class_name ObstacleCone
extends ObstacleBase

const R_RATIO := 0.5

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var h := aabb.size.y * 0.9
	var aabb_vol := aabb.size.x * aabb.size.y * aabb.size.z
	var vol_factor := (1.0 + R_RATIO + R_RATIO * R_RATIO) / 3.0
	var r1 := sqrt(aabb_vol * 0.7 / (PI * h * vol_factor))
	var r2 := r1 * R_RATIO

	var center := _aabb_center(aabb, xf)

	var pts := PackedVector3Array()
	pts.append(xf.basis * Vector3(0, -h * 0.5, 0))
	pts.append(xf.basis * Vector3(r1, -h * 0.5, 0))
	pts.append(xf.basis * Vector3(r2, h * 0.5, 0))
	pts.append(xf.basis * Vector3(0, h * 0.5, 0))

	var p3_array := OclPoint3Array.new()
	var godot_pts := []
	for p in pts:
		var v := OclPoint3.new()
		v.set_x(p.x + center.x)
		v.set_y(p.y + center.y)
		v.set_z(p.z + center.z)
		godot_pts.append(v)
	p3_array.set_data(godot_pts)

	var poly_info := OclPrimPolylineInfo.new()
	poly_info.set_points(p3_array)
	poly_info.set_closed(1)

	var wire := OclNodeId.new()
	if OclPrimSketch.polyline(graph, poly_info, wire) != OK:
		return PackedInt64Array()

	var revol_info := OclPrimRevolInfo.new()
	revol_info.profile = wire.get_bits()
	revol_info.axis = _axis1(center, xf.basis * Vector3(0, 1, 0))
	revol_info.angle = TAU
	var out := OclNodeId.new()
	var s := OclPrimSweep.revol(graph, revol_info, out) as int
	return PackedInt64Array([out.get_bits()]) if s == OK else PackedInt64Array()
