class_name ObstacleTorus
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var major_r := minf(aabb.size.x, aabb.size.z) * 0.35
	var minor_r := major_r * 0.35
	var center := _aabb_center(aabb, xf)

	var circle_info := OclPrimCircleInfo.new()
	var circle_xf := xf
	circle_xf.origin = center + xf.basis * Vector3(major_r, 0, 0)
	circle_xf.basis = xf.basis * Basis(Vector3(1, 0, 0), -PI / 2)
	circle_info.placement = _placement(circle_xf)
	circle_info.radius = minor_r
	var wire := OclNodeId.new()
	if OclPrimSketch.circle(graph, circle_info, wire) != OK:
		return PackedInt64Array()

	var revol_info := OclPrimRevolInfo.new()
	revol_info.profile = wire.get_bits()
	revol_info.axis = _axis1(center, xf.basis * Vector3(0, 1, 0))
	revol_info.angle = TAU
	var out := OclNodeId.new()
	var s := OclPrimSweep.revol(graph, revol_info, out) as int
	return PackedInt64Array([out.get_bits()]) if s == OK else PackedInt64Array()
