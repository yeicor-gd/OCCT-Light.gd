class_name ObstacleCommonIntersection
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var box1 := OclNodeId.new()
	if _make_box(graph, xf, aabb, aabb.size.x, aabb.size.y, aabb.size.z, box1) != OK:
		return PackedInt64Array()

	var xf2 := xf
	xf2.origin += xf.basis * Vector3(0, aabb.size.y * 0.1, 0)
	var box2 := OclNodeId.new()
	if _make_box(graph, xf2, aabb, aabb.size.x * 0.8, aabb.size.y * 0.8, aabb.size.z, box2) != OK:
		return PackedInt64Array()

	var out := OclNodeId.new()
	var s := OclBool.common(
		graph,
		PackedInt64Array([box1.get_bits()]),
		PackedInt64Array([box2.get_bits()]),
		OclBoolOptions.new(),
		out,
	) as int
	return PackedInt64Array([out.get_bits()]) if s == OK else PackedInt64Array()
