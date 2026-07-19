@tool
extends Node3D
class_name MazeMarkers

@export_range(1.0, 50.0, 1.0) var interval_pct: float = 10.0
@export var text_height: float = 0.3
@export var extrude_depth: float = 0.05
@export var font_path: String = "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf"
@export var marker_material: Material  # optional override

@export_tool_button("Regenerate Markers") var regen_ = func(): _build_markers()

func _ready():
    if not Engine.is_editor_hint():
        _build_markers()

func _build_markers():
    # Clear existing
    for c in get_children():
        c.queue_free()

    var gen := _find_generator()
    if gen == null: return
    var paths = gen.get_node_or_null("Paths")
    if paths == null: return
    var main_path = paths.get_node_or_null("MainPath") as Path3D
    var aux_path = paths.get_node_or_null("MainPathBinormal") as Path3D
    if main_path == null or aux_path == null: return
    var curve = main_path.curve
    var aux_curve = aux_path.curve
    if curve == null or curve.point_count < 2: return

    var total_len = curve.get_baked_length()
    var step = total_len * interval_pct / 100.0
    if step <= 0: return

    var pct = interval_pct
    while pct < 100.0:
        var bl = total_len * pct / 100.0
        var xf = CurveUtils.transform_at_baked(curve, bl, true, aux_curve)
        # Place on track floor: offset inward by ball_radius, centered, facing forward
        var br = gen.ball_radius
        var floor_xf = xf.translated_local(Vector3(0, -br * 0.9, 0))
        _build_marker(floor_xf, "%.0f%%" % pct)
        pct += interval_pct

    print("[MazeMarkers] Built markers every %.0f%%" % interval_pct)

func _build_marker(xf: Transform3D, label: String):
    if not FileAccess.file_exists(font_path):
        return

    var graph = GraphUtils.create_graph()

    var info = OclTextInfo.new()
    info.set_utf8_text(label)
    info.set_height(text_height)
    info.set_font_path(font_path)
    info.set_font_aspect(OclText.TEXT_FONT_ASPECT_BOLD)
    info.set_horizontal_align(OclText.TEXT_HALIGN_CENTER)
    info.set_vertical_align(OclText.TEXT_VALIGN_CENTER)
    # The text is built in the XY plane. We want it lying on the track floor
    # facing up (normal = track up = xf.basis.y) and readable in the track
    # forward direction (xf.basis.x). So we need a placement where:
    #   Z = text face normal = xf.basis.y (up from floor)
    #   X = text right = xf.basis.z (track right / lateral)
    #   Y = text up = xf.basis.x (track forward = reading direction)
    # OclAxis2Placement: x_dir = text X axis, axis = text Z (normal)
    var text_xf = Transform3D(
        Basis(xf.basis.z, xf.basis.x, xf.basis.y),  # text X=lateral, text Y=forward, text Z=up
        xf.origin
    )
    info.set_placement(OcctConversionUtils.transform3d_to_occt_placement(text_xf))

    var wire_id = OclNodeId.new()
    var st = OclText.make_wires(graph, info, wire_id)
    if st != OclCore.OK or wire_id.bits == 0:
        OclTopo.graph_free(graph)
        return

    # Extrude the text wires into a solid
    var prism_info = OclPrimPrismInfo.new()
    prism_info.profile = wire_id.bits
    # Extrude along text Z (= xf.basis.y, outward from floor)
    prism_info.direction = OcctConversionUtils.v3_to_ov3(xf.basis.y * extrude_depth)
    var out_id = OclNodeId.new()
    st = OclPrimSweep.prism(graph, prism_info, out_id)
    if st != OclCore.OK or out_id.bits == 0:
        OclTopo.graph_free(graph)
        return

    # Mesh and create MeshInstance3D
    var opts = OclMeshOptions.new()
    opts.set_deflection(0.02)
    opts.set_angle(0.3)
    var am = ArrayMesh.new()
    st = OclMeshToGodot.mesh_faces(graph, am, opts, null, true, false, false)
    OclTopo.graph_free(graph)
    if st != OclCore.OK or am.get_surface_count() == 0:
        return

    if marker_material:
        am.surface_set_material(0, marker_material)

    var mi = MeshInstance3D.new()
    mi.name = "Marker_%s" % label.replace("%", "pct")
    mi.mesh = am
    add_child(mi)
    if Engine.is_editor_hint():
        mi.owner = get_tree().edited_scene_root if is_inside_tree() else null

func _find_generator() -> MazeGenerator:
    var p = get_parent()
    while p:
        if p is MazeGenerator:
            return p
        p = p.get_parent()
    return null
