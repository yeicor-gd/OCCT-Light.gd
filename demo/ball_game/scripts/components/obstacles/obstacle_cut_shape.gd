class_name ObstacleCutShape
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var box := OclNodeId.new()
	if _make_box(graph, xf, aabb, aabb.size.x, aabb.size.y, aabb.size.z, box) != OK:
		return PackedInt64Array()

	var cut_xf := xf
	cut_xf.origin = _aabb_center(aabb, xf)
	var r := minf(aabb.size.x, aabb.size.y) * 0.5
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
