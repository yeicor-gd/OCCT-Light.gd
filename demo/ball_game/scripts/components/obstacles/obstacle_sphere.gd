class_name ObstacleSphere
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var min_dim := minf(aabb.size.x, minf(aabb.size.y, aabb.size.z))
	var max_dim := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var r := min_dim * 0.5

	var long_axis := Vector3.ZERO
	if aabb.size.x >= aabb.size.y and aabb.size.x >= aabb.size.z:
		long_axis.x = 1.0
	elif aabb.size.y >= aabb.size.x and aabb.size.y >= aabb.size.z:
		long_axis.y = 1.0
	else:
		long_axis.z = 1.0

	var span := max_dim - min_dim
	var n := 1
	if span > 0.001:
		n = maxi(2, int(ceil(max_dim / min_dim)))
		if n >= 2:
			var spacing := span / float(n - 1)
			if spacing >= r * 1.9:
				n += 1

	var center := _aabb_center(aabb, xf)

	if n <= 1:
		var sph_info := OclPrimSphereInfo.new()
		sph_info.placement = _placement(Transform3D(xf.basis, center))
		sph_info.radius = r
		var out := OclNodeId.new()
		var s := OclPrimSolid.sphere(graph, sph_info, out) as int
		return PackedInt64Array([out.get_bits()]) if s == OK else PackedInt64Array()

	var roots := PackedInt64Array()
	for i in range(n):
		var t := float(i) / float(n - 1)
		var offset := long_axis * (-span * 0.5 + t * span)
		var sph_info := OclPrimSphereInfo.new()
		sph_info.placement = _placement(Transform3D(xf.basis, center + xf.basis * offset))
		sph_info.radius = r
		var node := OclNodeId.new()
		if OclPrimSolid.sphere(graph, sph_info, node) != OK:
			continue
		roots.append(node.get_bits())

	if roots.is_empty():
		return PackedInt64Array()
	if roots.size() == 1:
		return roots

	var current := roots[0]
	for i in range(1, roots.size()):
		var fused := OclNodeId.new()
		var s := OclBool.fuse(
			graph,
			PackedInt64Array([current]),
			PackedInt64Array([roots[i]]),
			OclBoolOptions.new(),
			fused,
		) as int
		if s != OK:
			return PackedInt64Array()
		current = fused.get_bits()
	return PackedInt64Array([current])
