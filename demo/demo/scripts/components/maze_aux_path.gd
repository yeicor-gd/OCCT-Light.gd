@tool
extends Path3D
class_name MazeAuxPath

## Holds the auxiliary (offset) curve used for sweep profile orientation.
## Auto-updates from the main path when regenerated.

@export_node_path("Path3D") var source_path: NodePath
@export var offset_amount: float = 0.15

@export_group("Actions")

## Rebuild this offset curve from the source path's curve data.
@export_tool_button("Regenerate from Main Path") var regenerate_ = regenerate

func regenerate():
	var src = get_node_or_null(source_path) if source_path else get_parent().get_node("MainPath")
	if not src:
		push_error("MazeAuxPath: source path not found")
		return
	var src_curve: Curve3D = src.curve
	if not src_curve or src_curve.point_count < 2:
		push_error("MazeAuxPath: source path curve has too few points")
		return
	curve = CurveUtils.build_auxiliary_curve(src_curve, offset_amount)
