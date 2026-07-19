class_name ObstacleRevolveHalf
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var r := minf(aabb.size.x, aabb.size.z) * 0.5
	var half_h := aabb.size.y * 0.5

	var rect_info := OclPrimRectangleInfo.new()
	var rect_xf := xf
	rect_xf.origin += xf.basis * Vector3(0, -half_h, r * 0.3)
	rect_info.placement = _placement(rect_xf)
	rect_info.width = r * 0.6
	rect_info.height = aabb.size.y
	var wire := OclNodeId.new()
	if OclPrimSketch.rectangle(graph, rect_info, wire) != OK:
		return PackedInt64Array()

	var revol_info := OclPrimRevolInfo.new()
	revol_info.profile = wire.get_bits()
	revol_info.axis = _axis1(xf.origin, xf.basis * Vector3(0, 1, 0))
	revol_info.angle = PI
	var out := OclNodeId.new()
	var s := OclPrimSweep.revol(graph, revol_info, out) as int
	return PackedInt64Array([out.get_bits()]) if s == OK else PackedInt64Array()
