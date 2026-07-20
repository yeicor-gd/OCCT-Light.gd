class_name ObstacleOffsetShape
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var box := OclNodeId.new()
	if _make_box(graph, xf, aabb, aabb.size.x * 0.6, aabb.size.y * 0.6, aabb.size.z * 0.6, box) != OK:
		return PackedInt64Array()

	var off_info := OclPrimOffsetShapeInfo.new()
	off_info.shape = box.get_bits()
	off_info.offset = minf(aabb.size.x, minf(aabb.size.y, aabb.size.z)) * 0.15
	off_info.tolerance = 0.1
	var out := OclNodeId.new()
	var s := OclPrimSweep.offset_shape(graph, off_info, out) as int
	return PackedInt64Array([out.get_bits()]) if s == OK else PackedInt64Array()
