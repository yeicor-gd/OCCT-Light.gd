class_name ObstacleEllipsePrism
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var wire_xf := Transform3D(Basis(Vector3(1, 0, 0), -PI / 2), Vector3(0, -aabb.size.y * 0.5, 0))

	var ell_info := OclPrimEllipseInfo.new()
	ell_info.placement = _placement(wire_xf)
	ell_info.major = maxf(aabb.size.x, aabb.size.z) * 0.4
	ell_info.minor = minf(aabb.size.x, aabb.size.z) * 0.3
	var wire := OclNodeId.new()
	if OclPrimSketch.ellipse(graph, ell_info, wire) != OK:
		return PackedInt64Array()

	var prism_info := OclPrimPrismInfo.new()
	prism_info.profile = wire.get_bits()
	prism_info.direction = _v3(Vector3(0, aabb.size.y, 0))
	var out := OclNodeId.new()
	var s := OclPrimSweep.prism(graph, prism_info, out) as int
	if s != OK:
		return PackedInt64Array()

	if xf == Transform3D.IDENTITY:
		return PackedInt64Array([out.get_bits()])

	var xf_graph := OclGraphHandle.new()
	var xf_root := OclNodeId.new()
	var t := _transform_to_occl(xf)
	var ts := OclTopoAlgo.transformed(graph, out.get_bits(), t, xf_graph, xf_root) as int
	if ts != OK:
		return PackedInt64Array()
	var h = xf_graph.release()
	graph.free()
	graph.set_handle(h)
	return PackedInt64Array([xf_root.get_bits()])
