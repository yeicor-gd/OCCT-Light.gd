class_name ObstacleCutShape
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var info := OclPrimBoxInfo.new()
	info.placement = _placement(xf)
	info.dx = aabb.size.x
	info.dy = aabb.size.y
	info.dz = aabb.size.z
	var box := OclNodeId.new()
	if OclPrimSolid.box(graph, info, box) != OK:
		return PackedInt64Array()

	var cut_xf := xf
	cut_xf.origin += xf.basis * Vector3(0, aabb.size.y * 0.3, 0)
	var r := minf(aabb.size.x, aabb.size.y) * 0.65
	var sph_info := OclPrimSphereInfo.new()
	sph_info.placement = _placement(cut_xf)
	sph_info.radius = r
	var sph := OclNodeId.new()
	if OclPrimSolid.sphere(graph, sph_info, sph) != OK:
		return PackedInt64Array()

	var out := OclNodeId.new()
	var s := OclBool.cut(
		graph,
		PackedInt64Array([box.get_bits()]),
		PackedInt64Array([sph.get_bits()]),
		OclBoolOptions.new(),
		out,
	) as int
	return PackedInt64Array([out.get_bits()]) if s == OK else PackedInt64Array()
