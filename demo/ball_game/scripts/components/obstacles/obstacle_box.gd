class_name ObstacleBox
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var info := OclPrimBoxInfo.new()
	info.placement = _placement(xf)
	info.dx = aabb.size.x * 0.85
	info.dy = aabb.size.y * 0.85
	info.dz = aabb.size.z * 0.85
	var out := OclNodeId.new()
	var s := OclPrimSolid.box(graph, info, out) as int
	return PackedInt64Array([out.get_bits()]) if s == OK else PackedInt64Array()
