@tool
class_name TopoBuilders
extends RefCounted

## Low-level OCCT topology builders: vertices, edges, wires, curves, sweeps.
## All methods are static and operate on a user-supplied graph handle.


## Create a cubic Bezier curve from 4 control points.
static func make_bezier_curve(
		graph: OclGraphHandle,
		p0: Vector3,
		c0: Vector3,
		c1: Vector3,
		p1: Vector3,
) -> OclRepId:
	var info := OclCurveBezierCreateInfo.new()
	info.poles = OclPoint3Array.from(
		[
			OcctConversionUtils.v3_to_p3(p0),
			OcctConversionUtils.v3_to_p3(c0),
			OcctConversionUtils.v3_to_p3(c1),
			OcctConversionUtils.v3_to_p3(p1),
		],
	)
	info.weights = PackedFloat64Array([1.0, 1.0, 1.0, 1.0])
	var rep := OclRepId.new()
	var status := OclCurves.create_bezier(graph, info, rep) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	return rep


## Create a vertex at |point|.
static func make_vertex(graph: OclGraphHandle, point: Vector3) -> OclNodeId:
	var info := OclTopoMakeVertexInfo.new()
	info.point = OcctConversionUtils.v3_to_p3(point)
	var vertex := OclNodeId.new()
	var status := OclTopoBuild.topo_make_vertex(graph, info, vertex) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	return vertex


## Create an edge from a curve, using the curve's full parameter range.
static func make_edge(
		graph: OclGraphHandle,
		curve: OclRepId,
		start_vertex: OclNodeId,
		end_vertex: OclNodeId,
) -> OclNodeId:
	var info := OclTopoMakeEdgeInfo.new()
	info.curve = curve.bits
	info.start_vertex = start_vertex.bits
	info.end_vertex = end_vertex.bits

	var first := OclDouble.new()
	var last := OclDouble.new()
	var status := OclCurves.parameter_range(graph, curve.bits, first, last) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	info.first = first.value
	info.last = last.value

	var edge := OclNodeId.new()
	status = OclTopoBuild.topo_make_edge(graph, info, edge) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	return edge


## Create a wire from an array of oriented edges.
static func make_wire(graph: OclGraphHandle, oriented_edges: Array[OclOrientedNode]) -> OclNodeId:
	var info := OclTopoMakeWireInfo.new()
	info.edges = OclOrientedNodeArray.from(oriented_edges)
	var wire := OclNodeId.new()
	var status := OclTopoBuild.topo_make_wire(graph, info, wire) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	return wire


## Build a wire along a single Bezier segment of a Curve3D at the given index.
static func build_segment_wire(graph: OclGraphHandle, curve3d: Curve3D, idx: int) -> OclNodeId:
	var p0: Vector3 = curve3d.get_point_position(idx)
	var p1: Vector3 = curve3d.get_point_position(idx + 1)
	var cl0: Vector3 = p0 + curve3d.get_point_out(idx)
	var cl1: Vector3 = p1 + curve3d.get_point_in(idx + 1)

	var bez := make_bezier_curve(graph, p0, cl0, cl1, p1)
	var sv := make_vertex(graph, p0)
	var ev := make_vertex(graph, p1)
	var ed := make_edge(graph, bez, sv, ev)

	var oriented := OclOrientedNode.new()
	oriented.id = ed.bits
	oriented.orientation = OclTopoRelation.ORIENTATION_FORWARD
	return make_wire(graph, [oriented])
