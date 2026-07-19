class_name ObstacleCommonIntersection
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var info1 := OclPrimBoxInfo.new()
	info1.placement = _placement(xf)
	info1.dx = aabb.size.x
	info1.dy = aabb.size.y
	info1.dz = aabb.size.z
	var box1 := OclNodeId.new()
	if OclPrimSolid.box(graph, info1, box1) != OK:
		return PackedInt64Array()

	var xf2 := xf
	xf2.origin += xf.basis * Vector3(0, aabb.size.y * 0.15, 0)
	var info2 := OclPrimBoxInfo.new()
	info2.placement = _placement(xf2)
	info2.dx = aabb.size.x * 0.85
	info2.dy = aabb.size.y * 0.85
	info2.dz = aabb.size.z
	var box2 := OclNodeId.new()
	if OclPrimSolid.box(graph, info2, box2) != OK:
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
