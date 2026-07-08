@tool
class_name ProfileBuilder
extends RefCounted

## Builds sweep profiles (2D wire outlines) for OCCT pipe-shell sweeps.
##
## Two strategies are available:
##   - _fast:  boolean-cut rectangle in rectangle → single wire
##   - _cool:  slot primitive → split by plane → trace → wire
##
## Both receive the same config parameters via a ConfigBundle so they stay
## decoupled from specific node references.


class Config:
	var ball_radius: float
	var ball_to_path_min_ratio: float
	var wall_thickness: float
	var wall_height: float

	func _init(
		_ball_radius: float,
		_ball_to_path_min_ratio: float,
		_wall_thickness: float,
		_wall_height: float,
	):
		ball_radius = _ball_radius
		ball_to_path_min_ratio = _ball_to_path_min_ratio
		wall_thickness = _wall_thickness
		wall_height = _wall_height


static func build_profile_fast(
		graph: OclGraphHandle,
		cfg: Config,
		xf: Transform3D,
) -> Array[OclNodeId]:
	## Fast profile: two rectangles boolean-cut together.
	## Returns [outer_wire].

	var path_radius := cfg.ball_radius / cfg.ball_to_path_min_ratio

	# Outer rectangle (wall outer boundary).
	var rect1_info := OclPrimRectangleInfo.new()
	rect1_info.width = path_radius * 2.0 + cfg.wall_thickness * 2.0
	rect1_info.height = cfg.wall_thickness + cfg.wall_height * 2.0 * cfg.ball_radius
	# Shift down in local frame so the profile sits at the right height.
	var rect1_xf := xf.translated_local(Vector3.UP * (
		-cfg.ball_radius - cfg.wall_thickness / 2.0 + (cfg.wall_height * 2.0 * cfg.ball_radius) / 2.0
	))
	rect1_info.placement = OcctConversionUtils.transform3d_to_occt_placement(rect1_xf)
	var rect1 := OclNodeId.new()
	var status := OclPrimSketch.rectangle(graph, rect1_info, rect1) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	var rect1_face_info := OclPrimPlanarFaceInfo.new()
	rect1_face_info.outer_wire = rect1.bits
	var rect1_face := OclNodeId.new()
	status = OclPrimSketch.planar_face(graph, rect1_face_info, rect1_face) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	# Inner rectangle (the cut-out / pathway).
	var rect2_info := OclPrimRectangleInfo.new()
	rect2_info.width = rect1_info.width - 2.0 * cfg.wall_thickness
	rect2_info.height = rect1_info.height - cfg.wall_thickness + cfg.ball_radius
	var rect2_xf := xf.translated_local(Vector3.UP * (
		-cfg.ball_radius + (cfg.wall_height * 2.0 * cfg.ball_radius) / 2.0 + cfg.ball_radius / 2.0
	))
	rect2_info.placement = OcctConversionUtils.transform3d_to_occt_placement(rect2_xf)
	var rect2 := OclNodeId.new()
	status = OclPrimSketch.rectangle(graph, rect2_info, rect2) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	var rect2_face_info := OclPrimPlanarFaceInfo.new()
	rect2_face_info.outer_wire = rect2.bits
	var rect2_face := OclNodeId.new()
	status = OclPrimSketch.planar_face(graph, rect2_face_info, rect2_face) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	# Boolean cut: outer - inner.
	var bool_opts := OclBoolOptions.new()
	var track_profile := OclNodeId.new()
	status = OclBool.cut(
		graph,
		PackedInt64Array([rect1_face.bits]),
		PackedInt64Array([rect2_face.bits]),
		bool_opts,
		track_profile,
	) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	# Clean up temporary faces.
	status = OclTopoBuild.topo_remove_subgraph(graph, rect1_face.bits) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	status = OclTopoBuild.topo_remove_subgraph(graph, rect2_face.bits) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	# Grab the single remaining wire.
	var face_iter := OclNodeIterHandle.new()
	status = OclTopo.graph_face_iter_create(graph, face_iter) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	var mface := OclNodeId.new()
	status = OclTopo.node_iter_next(face_iter, mface) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	OclTopo.node_iter_free(face_iter)

	var res_wire := OclNodeId.new()
	status = OclTopo.topo_face_outer_wire(graph, mface.bits, res_wire) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	return [res_wire]


static func build_profile_cool(
		graph: OclGraphHandle,
		cfg: Config,
		xf: Transform3D,
) -> Array[OclNodeId]:
	# Slot primitive → split by plane → trace → wire.

	var path_radius := cfg.ball_radius / cfg.ball_to_path_min_ratio

	# Outer rectangle (wall outer boundary).
	var slot_info := OclPrimSlotInfo.new()
	slot_info.length = path_radius * 2.0 + 2.0 * cfg.wall_thickness # Centers
	slot_info.width = cfg.ball_radius * 2.0 + cfg.wall_thickness
	slot_info.placement = OcctConversionUtils.transform3d_to_occt_placement(xf)

	var slot_id := OclNodeId.new()
	var status := OclPrimSketch.slot(graph, slot_info, slot_id) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	# Split by plane (keep negative Y).
	var split_info := OclTopoSplitByPlaneOptions.new()
	split_info.root = slot_id.bits
	split_info.keep = OclTopoAlgo.TOPO_SPLIT_KEEP_NEGATIVE
	print("WALL HEIGHT: ", var_to_str(cfg))
	split_info.point = OcctConversionUtils.v3_to_p3(xf.translated_local(Vector3.UP * (-cfg.wall_thickness + (cfg.wall_height - 0.5) * cfg.ball_radius)).origin)
	split_info.normal = OcctConversionUtils.v3_to_d3(xf.basis.y)
	var split_id := OclNodeId.new()
	status = OclTopoAlgo.make_split_by_plane(graph, split_info, graph, split_id) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	# Iterate wires, trace one, clean up.
	var wire_iter := OclNodeIterHandle.new()
	status = OclTopo.graph_wire_iter_create(graph, wire_iter) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	var mwire := OclNodeId.new()
	status = OclTopo.node_iter_next(wire_iter, mwire) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	OclTopo.node_iter_free(wire_iter)

	# Trace to thicken the wire.
	var trace_info := OclPrimTraceInfo.new()
	trace_info.path = mwire.bits
	trace_info.width = cfg.wall_thickness
	var trace_id := OclNodeId.new()
	status = OclPrimSketch.trace(graph, trace_info, trace_id) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	# Remove temporary wire.
	status = OclTopoBuild.topo_remove_subgraph(graph, mwire.bits) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	# Get the resulting wire from trace.
	wire_iter = OclNodeIterHandle.new()
	status = OclTopo.graph_wire_iter_create(graph, wire_iter) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	mwire = OclNodeId.new()
	status = OclTopo.node_iter_next(wire_iter, mwire) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	OclTopo.node_iter_free(wire_iter)

	# Remove the temporary traced face.
	status = OclTopoBuild.topo_remove(graph, trace_id.bits) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	return [mwire]
