class_name ObstacleEllipsePrism
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var xf_ell := xf
	xf_ell.origin += xf.basis * (aabb.position + Vector3(aabb.size.x * 0.5, 0, aabb.size.z * 0.5))
	xf_ell.basis = xf.basis * Basis(Vector3(1, 0, 0), -PI / 2)

	var ax := aabb.size.x * 0.45
	var az := aabb.size.z * 0.45
	var major_r := maxf(ax, az)
	var minor_r := minf(ax, az)
	if absf(major_r - minor_r) < 0.01:
		major_r = minor_r * 1.05

	var ell_info := OclPrimEllipseInfo.new()
	ell_info.placement = _placement(xf_ell)
	ell_info.major = major_r
	ell_info.minor = minor_r
	var wire := OclNodeId.new()
	if OclPrimSketch.ellipse(graph, ell_info, wire) != OK:
		return PackedInt64Array()

	var prism_info := OclPrimPrismInfo.new()
	prism_info.profile = wire.get_bits()
	prism_info.direction = _v3(xf.basis * Vector3(0, aabb.size.y, 0))
	var out := OclNodeId.new()
	var s := OclPrimSweep.prism(graph, prism_info, out) as int
	return PackedInt64Array([out.get_bits()]) if s == OK else PackedInt64Array()
