class_name ObstacleFusedPair
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var half := aabb.size * 0.5

	var id1 := OclNodeId.new()
	if _make_box(graph, xf, aabb, half.x, aabb.size.y, aabb.size.z, id1) != OK:
		return PackedInt64Array()

	var xf2 := xf
	xf2.origin += xf.basis * Vector3(-half.x * 0.3, half.y * 0.3, 0)
	var id2 := OclNodeId.new()
	if _make_box(graph, xf2, aabb, half.x, aabb.size.y * 0.8, aabb.size.z * 0.8, id2) != OK:
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
