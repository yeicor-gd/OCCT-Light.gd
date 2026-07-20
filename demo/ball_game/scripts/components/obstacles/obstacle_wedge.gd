class_name ObstacleWedge
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var out := OclNodeId.new()
	var s := _make_wedge(graph, xf, aabb, aabb.size.x * 0.9, aabb.size.y * 0.9, aabb.size.z * 0.9, aabb.size.x * 0.45, out)
	return PackedInt64Array([out.get_bits()]) if s == OK else PackedInt64Array()
