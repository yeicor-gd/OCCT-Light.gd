class_name ObstacleFusedPair
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var half := aabb.size * 0.5
	var cx := _placement(xf)

	var info1 := OclPrimBoxInfo.new()
	info1.placement = cx
	info1.dx = half.x
	info1.dy = aabb.size.y
	info1.dz = aabb.size.z
	var id1 := OclNodeId.new()
	if OclPrimSolid.box(graph, info1, id1) != OK:
		return PackedInt64Array()

	var xf2 := xf
	xf2.origin += xf.basis * Vector3(-half.x * 0.3, half.y * 0.3, 0)
	var info2 := OclPrimBoxInfo.new()
	info2.placement = _placement(xf2)
	info2.dx = half.x
	info2.dy = aabb.size.y * 0.8
	info2.dz = aabb.size.z * 0.8
	var id2 := OclNodeId.new()
	if OclPrimSolid.box(graph, info2, id2) != OK:
		return PackedInt64Array()

	var out := OclNodeId.new()
	var s := OclBool.fuse(
		graph,
		PackedInt64Array([id1.get_bits()]),
		PackedInt64Array([id2.get_bits()]),
		OclBoolOptions.new(),
		out,
	) as int
	return PackedInt64Array([out.get_bits()]) if s == OK else PackedInt64Array()
