class_name ObstacleOffsetShape
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var info := OclPrimBoxInfo.new()
	info.placement = _placement(xf)
	info.dx = aabb.size.x * 0.6
	info.dy = aabb.size.y * 0.6
	info.dz = aabb.size.z * 0.6
	var box := OclNodeId.new()
	if OclPrimSolid.box(graph, info, box) != OK:
		return PackedInt64Array()

	var off_info := OclPrimOffsetShapeInfo.new()
	off_info.shape = box.get_bits()
	off_info.offset = minf(aabb.size.x, minf(aabb.size.y, aabb.size.z)) * 0.15
	off_info.tolerance = 0.1
	var out := OclNodeId.new()
	var s := OclPrimSweep.offset_shape(graph, off_info, out) as int
	return PackedInt64Array([out.get_bits()]) if s == OK else PackedInt64Array()
