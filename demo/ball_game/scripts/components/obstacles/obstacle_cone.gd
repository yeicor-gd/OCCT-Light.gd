class_name ObstacleCone
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var r := minf(aabb.size.x, aabb.size.z) * 0.45

	var circle_info := OclPrimCircleInfo.new()
	var circle_xf := xf
	circle_xf.origin += xf.basis * (aabb.position + Vector3(aabb.size.x * 0.5, 0, aabb.size.z * 0.5))
	circle_xf.basis = xf.basis * Basis(Vector3(1, 0, 0), -PI / 2)
	circle_info.placement = _placement(circle_xf)
	circle_info.radius = r
	var wire := OclNodeId.new()
	if OclPrimSketch.circle(graph, circle_info, wire) != OK:
		return PackedInt64Array()

	var prism_info := OclPrimPrismInfo.new()
	prism_info.profile = wire.get_bits()
	prism_info.direction = _v3(xf.basis * Vector3(0, aabb.size.y, 0))
	var out := OclNodeId.new()
	var s := OclPrimSweep.prism(graph, prism_info, out) as int
	return PackedInt64Array([out.get_bits()]) if s == OK else PackedInt64Array()
