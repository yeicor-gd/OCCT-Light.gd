@tool
class_name WireBuilder
extends RefCounted

## Canvas-like wire builder for constructing OCCT wires from
## line segments and arc segments.
##
## Converts a sequence of 2D drawing commands into an OCCT wire
## via a to_world projection callable.
##
## Usage:
##   var b := WireBuilder.new(graph, to_world)
##   b.move_to(0, 0)
##   b.line_to(1, 0)
##   b.arc(1, 0, 0.5, 0, 90, true)
##   b.line_to(0, 1)
##   var wire := b.build()

var _graph: OclGraphHandle
var _to_world: Callable
var _edges: Array[OclOrientedNode] = []
var _current_2d := Vector2(INF, INF)
var _start_2d := Vector2(INF, INF)
var _prev_vertex := OclNodeId.new()
var _has_start := false


func _init(graph: OclGraphHandle, to_world: Callable):
	_graph = graph
	_to_world = to_world


## Move the pen to (x, y) without drawing. Must be called first.
func move_to(x: float, y: float) -> WireBuilder:
	_start_2d = Vector2(x, y)
	_current_2d = Vector2(x, y)
	_prev_vertex = TopoBuilders.make_vertex(_graph, _to_world.call(Vector2(x, y)))
	_has_start = true
	return self


## Draw a line from the current position to (x, y).
func line_to(x: float, y: float) -> WireBuilder:
	var to_2d := Vector2(x, y)
	if _current_2d.distance_squared_to(to_2d) < 1e-12:
		return self

	var to_world_pt: Vector3 = _to_world.call(to_2d)

	var sv := _prev_vertex
	var ev := TopoBuilders.make_vertex(_graph, to_world_pt)

	var curve := TopoBuilders.make_line_curve(_graph, _to_world.call(_current_2d), to_world_pt)
	var edge := TopoBuilders.make_edge(_graph, curve, sv, ev)

	var oriented := OclOrientedNode.new()
	oriented.id = edge.bits
	oriented.orientation = OclTopoRelation.ORIENTATION_FORWARD
	_edges.append(oriented)

	_prev_vertex = ev
	_current_2d = to_2d
	return self


## Draw an arc from the current position to the arc end point.
##
## @param cx, cy    Arc center in 2D.
## @param r         Arc radius.
## @param start_deg Start angle in degrees (0=right, 90=up, 180=left, 270=down).
## @param end_deg   End angle in degrees.
## @param ccw       If true, arc sweeps counterclockwise (increasing angles).
##                  If false, arc sweeps clockwise (decreasing angles).
func arc(cx: float, cy: float, r: float, start_deg: float, end_deg: float, ccw: bool = false) -> WireBuilder:
	var start_rad := deg_to_rad(start_deg)
	var end_rad := deg_to_rad(end_deg)

	var p_start := Vector2(cx + r * cos(start_rad), cy + r * sin(start_rad))
	var p_end := Vector2(cx + r * cos(end_rad), cy + r * sin(end_rad))

	# Line to arc start if not already there.
	if _current_2d.distance_squared_to(p_start) > 1e-12:
		line_to(p_start.x, p_start.y)

	# Compute mid-point for the 3-point arc.
	var sweep: float
	if ccw:
		sweep = fmod(end_rad - start_rad + TAU, TAU)
	else:
		sweep = fmod(start_rad - end_rad + TAU, TAU)
	if sweep < 1e-6:
		sweep = TAU
	var mid_rad: float
	if ccw:
		mid_rad = start_rad + sweep * 0.5
	else:
		mid_rad = start_rad - sweep * 0.5
	var p_mid := Vector2(cx + r * cos(mid_rad), cy + r * sin(mid_rad))

	# Create arc edge.
	var sv := _prev_vertex
	var ev := TopoBuilders.make_vertex(_graph, _to_world.call(p_end))

	var curve := TopoBuilders.make_arc_3pt(
		_graph, _to_world.call(p_start), _to_world.call(p_mid), _to_world.call(p_end),
	)
	var edge := TopoBuilders.make_edge(_graph, curve, sv, ev)

	var oriented := OclOrientedNode.new()
	oriented.id = edge.bits
	oriented.orientation = OclTopoRelation.ORIENTATION_FORWARD
	_edges.append(oriented)

	_prev_vertex = ev
	_current_2d = p_end
	return self


## Close the wire and return the OCCT wire node.
func build(auto_close: bool = false) -> OclNodeId:
	if auto_close:
		assert(_has_start, "WireBuilder: move_to() must be called before build() for auto_close mode")
		if _current_2d.distance_squared_to(_start_2d) > 1e-12:
			line_to(_start_2d.x, _start_2d.y)
	return TopoBuilders.make_wire(_graph, _edges)
