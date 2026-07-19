class_name ObstacleWedge
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var info := OclPrimWedgeInfo.new()
	info.placement = _placement(xf)
	info.dx = aabb.size.x * 0.9
	info.dy = aabb.size.y * 0.9
	info.dz = aabb.size.z * 0.9
	info.ltx = aabb.size.x * 0.45
	var out := OclNodeId.new()
	var s := OclPrimSolid.wedge(graph, info, out) as int
	return PackedInt64Array([out.get_bits()]) if s == OK else PackedInt64Array()
