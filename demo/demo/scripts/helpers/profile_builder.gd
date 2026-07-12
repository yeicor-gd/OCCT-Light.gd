@tool
class_name ProfileBuilder
extends RefCounted

## Builds sweep profiles (2D wire outlines) for OCCT pipe-shell sweeps.
##
## The profile is a U-shaped cross-section built from line segments and
## embedded arcs (fancy mode) or straight segments only (non-fancy).
## No boolean cuts or fillet_2d are used — the wire is constructed
## directly from its geometric primitives.


class Config:
	var ball_radius: float
	var ball_to_path_min_ratio: Vector2
	var wall_thickness: float
	var wall_height: float

	func _init(
		_ball_radius: float,
		_ball_to_path_min_ratio: Vector2,
		_wall_thickness: float,
		_wall_height: float,
	):
		ball_radius = _ball_radius
		ball_to_path_min_ratio = _ball_to_path_min_ratio
		wall_thickness = _wall_thickness
		wall_height = _wall_height


## Build the sweep profile wire(s).
static func build_profiles(
		graph: OclGraphHandle,
		cfg: Config,
		xf: Transform3D,
		fancy: bool,
) -> Array[OclNodeId]:
	# --- Derived dimensions ---
	var br := cfg.ball_radius
	var bd := 2.0 * br # Ball diameter
	var pwh := br / cfg.ball_to_path_min_ratio.x # pathway half width
	var pw := bd / cfg.ball_to_path_min_ratio.x  # pathway width
	var wt := cfg.wall_thickness # Wall thickness
	var wth := (bd / cfg.ball_to_path_min_ratio.y)  # Maybe-wall total height above pathway floor
	var wh := cfg.wall_height * wth # wall height above pathway floor
	var wr := cfg.wall_height == 1.0 # With extra roof sketch
	# Radius of fancy fillets
	var rt := wt/2 if fancy and not wr else 0.0 # top radius
	var ri := minf(wh, br) - rt if fancy else 0.0 # inner radius
	var ro := ri + wt if fancy else 0.0 # outer radius
	var result: Array[OclNodeId] = []
	var status: OclCore.status
	
	var wb := WireBuilder.new(graph, func(v2: Vector2): return xf.translated_local(Vector3(v2.x, v2.y, 0)).origin)
	
	wb.move_to(-pwh, -br + wh - rt) # Top-left of the inside (for easier core mode)
	if not fancy: # Fast square bottom
		wb.line_to(-pwh, -br)
		wb.line_to(pwh, -br)
		wb.line_to(pwh, -br + wh)
	else: 
		wb.arc(-pwh+ri, -br+ri, ri, 180, 270, true)
		wb.arc(pwh-ri, -br+ri, ri, 270, 360, true)
	if not fancy or wr:
		wb.line_to(pwh + wt, -br + wh)
		wb.line_to(pwh + wt, -br - wt)
	else:
		wb.arc(pwh+rt, -br + wh-rt, rt, 180, 0)
	if not fancy:
		wb.line_to(-pwh - wt, -br - wt)
	else:
		wb.arc(pwh + wt - ro, -br - wt + ro, ro, 360, 270)
		wb.arc(-pwh - wt + ro, -br - wt + ro, ro, 270, 180)
	if not fancy or wr:
		wb.line_to(-pwh - wt, -br + wh)
		wb.line_to(-pwh, -br + wh)
	else:
		wb.arc(-pwh-rt, -br + wh-rt, rt, 180, 0)
	
	result.append(wb.build())
	
	# --- Roof mode (wall_height >= 1.0) ---
	if wr:
		var roof_info := OclPrimRectangleInfo.new()
		roof_info.width = pw + 2 * wt
		roof_info.height = wt
		var roof_xf := xf.translated_local(Vector3.UP * (-br + wth + wt/2))
		roof_info.placement = OcctConversionUtils.transform3d_to_occt_placement(roof_xf)
		var roof_wire := OclNodeId.new()
		status = OclPrimSketch.rectangle(graph, roof_info, roof_wire) as OclCore.status
		assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
		result.append(roof_wire)

	return result
