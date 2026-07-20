class_name ObstacleCheckTopology
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var box := OclNodeId.new()
	if _make_box(graph, xf, aabb, aabb.size.x * 0.8, aabb.size.y * 0.8, aabb.size.z * 0.8, box) != OK:
		return PackedInt64Array()

	var r := minf(aabb.size.x, aabb.size.y) * 0.35
	var sph_info := OclPrimSphereInfo.new()
	var sph_xf := xf
	sph_xf.origin = _aabb_center(aabb, xf)
	sph_info.placement = _placement(sph_xf)
	sph_info.radius = r
	var sph := OclNodeId.new()
	if OclPrimSolid.sphere(graph, sph_info, sph) != OK:
		return PackedInt64Array()

	var fuse_out := OclNodeId.new()
	var s := OclBool.fuse(
		graph,
		PackedInt64Array([box.get_bits()]),
		PackedInt64Array([sph.get_bits()]),
		OclBoolOptions.new(),
		fuse_out,
	) as int
	if s != OK:
		return PackedInt64Array()

	var issues := OclTopoCheckIssueArray.new()
	OclTopoAlgo.check(graph, issues)
	return PackedInt64Array([fuse_out.get_bits()])
