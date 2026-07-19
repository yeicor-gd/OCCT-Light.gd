// ---------------------------------------------------------------------------
// Hand-written source for OclMeshToGodot meshing methods.
//
// Bridges OCCT-Light graph handles (OclGraphHandle / occtl_graph_t) with
// Godot rendering (ArrayMesh, MultiMesh) and physics (PhysicsBody3D +
// CollisionShape3D).
// ---------------------------------------------------------------------------

#include "OclMeshToGodot.h"

#include <BRepGraph_NodeId.hxx>
#include <TopAbs_Orientation.hxx>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>

#include <godot_cpp/classes/physics_body3d.hpp>
#include <godot_cpp/classes/collision_shape3d.hpp>
#include <godot_cpp/classes/concave_polygon_shape3d.hpp>
#include <godot_cpp/classes/capsule_shape3d.hpp>
#include <godot_cpp/classes/cylinder_mesh.hpp>
#include <godot_cpp/classes/sphere_shape3d.hpp>
#include <godot_cpp/classes/sphere_mesh.hpp>
#include <godot_cpp/classes/node3d.hpp>

#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <BRep_Tool.hxx>
#include <BRepTools.hxx>
#include <Geom_Surface.hxx>
#include <Poly_Triangulation.hxx>
#include <Poly_Triangle.hxx>
#include <TopExp_Explorer.hxx>
#include <TopLoc_Location.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Face.hxx>
#include <TopoDS_Solid.hxx>
#include <gp_Pnt.hxx>
#include <gp_Pnt2d.hxx>
#include <gp_Trsf.hxx>
#include <gp_Vec.hxx>
#include <gp_Dir.hxx>

#include <cmath>

#include <unordered_map>
#include <vector>
#include <utility>

#include "OclGraphHandle.h"
#include "occtl/occtl_mesh.h"

// XXX: Internal OCCTL APIs / OpenCASCADE APIs
#include "opencascade/BRepGraph_ShapesView.hxx"
#include "../OCCT-Light/src/topo/GraphHandle.hxx"
#include "../OCCT-Light/src/topo/TopoMath.hxx"

using namespace godot;

// ===========================================================================
// Internal helpers (all file-static, never published)
// ===========================================================================

// ---------------------------------------------------------------------------
// Graph helpers
// ---------------------------------------------------------------------------

/// Helper macro: try to get a representative node from an iterator.
/// Sets @p ref_node to the first element if the iterator yields at least one.
#define OCCTL_TRY_ITER(call_expr) \
    do { \
        if (ref_node.bits != 0) break; \
        occtl_node_iter_t* _it = nullptr; \
        if ((call_expr) == OCCTL_OK && _it) { \
            occtl_node_id_t _tmp; \
            if (occtl_node_iter_next(_it, &_tmp) == OCCTL_OK) { \
                ref_node = _tmp; \
            } \
            occtl_node_iter_free(_it); \
        } \
    } while (0)

/// Graph-wide bounding-box diagonal.  Used to scale edge/vertex radii
/// proportionally to the model.  Returns 1.0 when the graph is empty.
static double _get_graph_bbox_diag(occtl_graph_t* graph) {
    occtl_node_id_t ref_node{};
    occtl_node_id_t const dummy{};
    ref_node = dummy;

    OCCTL_TRY_ITER(occtl_graph_compound_iter_create(graph, &_it));
    OCCTL_TRY_ITER(occtl_graph_compsolid_iter_create(graph, &_it));
    OCCTL_TRY_ITER(occtl_graph_solid_iter_create(graph, &_it));
    OCCTL_TRY_ITER(occtl_graph_shell_iter_create(graph, &_it));
    OCCTL_TRY_ITER(occtl_graph_face_iter_create(graph, &_it));
    OCCTL_TRY_ITER(occtl_graph_wire_iter_create(graph, &_it));
    OCCTL_TRY_ITER(occtl_graph_edge_iter_create(graph, &_it));
    OCCTL_TRY_ITER(occtl_graph_vertex_iter_create(graph, &_it));
    OCCTL_TRY_ITER(occtl_graph_coedge_iter_create(graph, &_it));

    if (ref_node.bits == 0) return 1.0;

    occtl_select_bbox_t c_bbox;
    if (occtl_graph_bbox_get(graph, ref_node, &c_bbox) != OCCTL_OK) return 1.0;

    gp_Pnt const bmin(c_bbox.min.x, c_bbox.min.y, c_bbox.min.z);
    gp_Pnt const bmax(c_bbox.max.x, c_bbox.max.y, c_bbox.max.z);
    double const diag = bmin.Distance(bmax);
    return (diag < 1e-15) ? 1.0 : diag;
}

/// Remove every child CollisionShape3D previously created by a meshing call
/// on @p body (identified by a name starting with "_occtl_").
static void _clear_physics_children(PhysicsBody3D* body) {
    if (!body) return;
    std::vector<CollisionShape3D*> to_remove;
    to_remove.reserve(static_cast<size_t>(body->get_child_count()));
    for (int i = 0; i < body->get_child_count(); i++) {
        auto* cs = Object::cast_to<CollisionShape3D>(body->get_child(i));
        if (cs && String(cs->get_name()).begins_with("_occtl_")) {
            to_remove.push_back(cs);
        }
    }
    for (auto* cs : to_remove) {
        body->remove_child(cs);
        cs->queue_free();
    }
}

// ---------------------------------------------------------------------------
// Node ID resolution
// ---------------------------------------------------------------------------

using iter_create_fn = occtl_status_t (*)(const occtl_graph_t*, occtl_node_iter_t**);

/// Collect all nodes of a given kind (face, edge, vertex, …) into a vector.
static std::vector<occtl_node_id_t> _collect_all_nodes(
    occtl_graph_t* graph, iter_create_fn create_iter)
{
    std::vector<occtl_node_id_t> ids;
    occtl_node_iter_t* iter = nullptr;
    occtl_status_t st = create_iter(graph, &iter);
    if (st != OCCTL_OK || !iter) return ids;
    occtl_node_id_t nid;
    while (occtl_node_iter_next(iter, &nid) == OCCTL_OK)
        ids.push_back(nid);
    occtl_node_iter_free(iter);
    return ids;
}

/// Parse a Variant (nil or PackedInt64Array) into a vector of node IDs.
/// For faces, negative values are treated as absolute (backward-compatible).
static std::vector<occtl_node_id_t> _parse_face_ids(const Variant& ids) {
    std::vector<occtl_node_id_t> ids_vec;
    if (ids.get_type() == Variant::PACKED_INT64_ARRAY) {
        PackedInt64Array arr = ids;
        ids_vec.reserve(static_cast<size_t>(arr.size()));
        for (int i = 0; i < arr.size(); i++) {
            occtl_node_id_t nid;
            nid.bits = static_cast<uint64_t>(arr[i] < 0 ? -arr[i] : arr[i]);
            ids_vec.push_back(nid);
        }
    }
    return ids_vec;
}

/// Parse Variant into edge/vertex IDs (direct bits, no absolute-value).
static std::vector<occtl_node_id_t> _parse_simple_ids(const Variant& ids) {
    std::vector<occtl_node_id_t> ids_vec;
    if (ids.get_type() == Variant::PACKED_INT64_ARRAY) {
        PackedInt64Array arr = ids;
        ids_vec.reserve(static_cast<size_t>(arr.size()));
        for (int64_t id : arr) {
            occtl_node_id_t nid;
            nid.bits = static_cast<uint64_t>(id);
            ids_vec.push_back(nid);
        }
    }
    return ids_vec;
}

/// Resolve face IDs: parse explicit list or iterate all faces.
static std::vector<occtl_node_id_t> _resolve_face_ids(
    occtl_graph_t* graph, const Variant& face_ids)
{
    std::vector<occtl_node_id_t> ids = _parse_face_ids(face_ids);
    if (!ids.empty()) return ids;
    if (face_ids.get_type() == Variant::NIL)
        return _collect_all_nodes(graph, occtl_graph_face_iter_create);
    return ids;  // invalid type — return empty
}

/// Resolve edge IDs: parse explicit list or iterate all edges.
static std::vector<occtl_node_id_t> _resolve_edge_ids(
    occtl_graph_t* graph, const Variant& edge_ids)
{
    std::vector<occtl_node_id_t> ids = _parse_simple_ids(edge_ids);
    if (!ids.empty()) return ids;
    if (edge_ids.get_type() == Variant::NIL)
        return _collect_all_nodes(graph, occtl_graph_edge_iter_create);
    return ids;
}

/// Resolve vertex IDs: parse explicit list or iterate all vertices.
static std::vector<occtl_node_id_t> _resolve_vertex_ids(
    occtl_graph_t* graph, const Variant& vertex_ids)
{
    std::vector<occtl_node_id_t> ids = _parse_simple_ids(vertex_ids);
    if (!ids.empty()) return ids;
    if (vertex_ids.get_type() == Variant::NIL)
        return _collect_all_nodes(graph, occtl_graph_vertex_iter_create);
    return ids;
}

// ---------------------------------------------------------------------------
// Mesh generation helpers (pure geometry, no OCCT dependency)
// ---------------------------------------------------------------------------

/// Ensure the graph has a triangulation matching the given deflection/angle.
/// Check if at least one face in @p ids_vec has cached triangulation data.
static bool _graph_has_mesh(occtl_graph_t* graph,
    const std::vector<occtl_node_id_t>& ids_vec)
{
    // Directly check via BRep_Tool::Triangulation on the internal BRepGraph faces.
    // Matching the existing pattern, use non-const cast since BRepGraph_ShapesView
    // may not expose a const Shape() overload (see lines 335-336 of old code).
    if (!graph) return false;
    auto* internal_graph = static_cast<struct occtl_graph*>(graph);

    for (auto fid : ids_vec) {
        const BRepGraph_NodeId node_id =
            BRepGraph_NodeId::Typed<BRepGraph_NodeId::Kind::Face>(fid.bits);
        const TopoDS_Shape shape = internal_graph->graph.Shapes().Shape(node_id);
        if (shape.IsNull()) continue;
        const TopoDS_Face face = TopoDS::Face(shape);
        if (face.IsNull()) continue;
        TopLoc_Location loc;
        const Handle(Poly_Triangulation) tri = BRep_Tool::Triangulation(face, loc);
        if (!tri.IsNull() && tri->NbTriangles() > 0) return true;
    }
    return false;
}

/// Ensure mesh is generated for the graph.
///
/// Only calls occtl_mesh_generate when the graph does not yet have
/// cached mesh data for the requested faces.  This avoids unnecessary
/// cache invalidation inside occtl_mesh_generate which can cause
/// BRepMesh to skip normal computation on repeat calls.
static occtl_status_t _ensure_mesh_generated(
    occtl_graph_t* graph,
    const std::vector<occtl_node_id_t>& ids_vec,
    double deflection, double angle)
{
    if (_graph_has_mesh(graph, ids_vec)) {
        return OCCTL_OK;
    }

    occtl_mesh_options_t opts = OCCTL_MESH_OPTIONS_INIT;
    opts.deflection = deflection;
    opts.angle = angle;
    opts.clean_model = 1;

    // Collect root product nodes so BRepMesh works on the correct
    // top-level shapes.
    std::vector<occtl_node_id_t> root_ids;
    occtl_node_iter_t* iter = nullptr;
    if (occtl_graph_root_product_iter_create(graph, &iter) == OCCTL_OK && iter) {
        occtl_node_id_t nid;
        while (occtl_node_iter_next(iter, &nid) == OCCTL_OK)
            root_ids.push_back(nid);
        occtl_node_iter_free(iter);
    }

    occtl_status_t st = OCCTL_OK;
    if (!root_ids.empty()) {
        st = occtl_mesh_generate(
            graph, root_ids.data(), root_ids.size(), &opts);
    } else {
        st = occtl_mesh_generate(graph, nullptr, 0, &opts);
    }

    if (st != OCCTL_OK) return st;

    // Fallback: if the standard paths did not produce mesh for the
    // requested faces, try meshing the individual face nodes directly.
    // This handles solids built via the BRepGraph Editor API (e.g.,
    // topo_make_solid + topo_make_shell) where Shapes().Shape(solidId)
    // returns null because the solid was not stored via Shapes().Add().
    // Individual faces created by primitives (ruled_surface, planar_face)
    // DO have shapes stored, so passing them directly to mesh_generate
    // allows BRepMesh to triangulate them.
    if (!_graph_has_mesh(graph, ids_vec) && !ids_vec.empty()) {
        st = occtl_mesh_generate(graph, ids_vec.data(), ids_vec.size(), &opts);
    }

    return st;
}

/// Number of radial slices for a cylinder/sphere from the mesh angle limit.
static inline int _slices_from_angle(double angle) {
    double const safe = std::max(angle, 0.001);
    return std::max(4, static_cast<int>(std::round(Math_PI / safe)) + 2);
}
/// Build a map from face UID to whether the face is REVERSED within its
/// root solid context, mirroring how the STL exporter (DESTL_Provider)
/// determines orientation.
///
/// The STL exporter iterates faces via TopExp_Explorer on each root
/// product shape.  Each face returned carries the accumulated orientation
/// from the solid/shell hierarchy.  This function does the same and
/// records the face's orientation (FORWARD/REVERSED) keyed by its
/// persistent UID.
///
/// Uses #occtl_topo_child_explorer_create with target_kind=OCCTL_KIND_FACE
/// to directly yield face node IDs with accumulated orientation, avoiding
/// the fragile IsSame matching required by the earlier TopExp_Explorer
/// approach.
///
/// If root products are not found (e.g. for graphs read with
/// CreateAutoProduct=false, such as STL-imported graphs), falls back to
/// iterating all solids, then all shells.  If nothing is found, returns
/// an empty map (callers fall back to the face's own Orientation()).
static std::unordered_map<uint64_t, bool> _build_accumulated_orientation_map(
    occtl_graph_t* graph)
{
    std::unordered_map<uint64_t, bool> rev_map;
    if (!graph) return rev_map;

    // ---- Collect root product nodes (same as _ensure_mesh_generated) ----
    std::vector<occtl_node_id_t> root_ids;
    {
        occtl_node_iter_t* iter = nullptr;
        if (occtl_graph_root_product_iter_create(graph, &iter) == OCCTL_OK && iter) {
            occtl_node_id_t nid;
            while (occtl_node_iter_next(iter, &nid) == OCCTL_OK)
                root_ids.push_back(nid);
            occtl_node_iter_free(iter);
        }
    }

    // Fallback: if no root products (e.g. STL-read graphs with
    // CreateAutoProduct=false), try all solids.
    if (root_ids.empty()) {
        occtl_node_iter_t* iter = nullptr;
        if (occtl_graph_solid_iter_create(graph, &iter) == OCCTL_OK && iter) {
            occtl_node_id_t nid;
            while (occtl_node_iter_next(iter, &nid) == OCCTL_OK)
                root_ids.push_back(nid);
            occtl_node_iter_free(iter);
        }
    }

    // Fallback: if no solids either, try all shells.
    if (root_ids.empty()) {
        occtl_node_iter_t* iter = nullptr;
        if (occtl_graph_shell_iter_create(graph, &iter) == OCCTL_OK && iter) {
            occtl_node_id_t nid;
            while (occtl_node_iter_next(iter, &nid) == OCCTL_OK)
                root_ids.push_back(nid);
            occtl_node_iter_free(iter);
        }
    }

    if (root_ids.empty()) return rev_map;

    // Use child explorer with target_kind=FACE to directly yield graph
    // face node IDs with accumulated orientation — mirrors what
    // TopExp_Explorer provides on the root TopoDS_Shape in the STL
    // exporter code path, but without needing IsSame matching.
    occtl_topo_child_explorer_config_t cfg = OCCTL_TOPO_CHILD_EXPLORER_CONFIG_INIT;
    cfg.target_kind = OCCTL_KIND_FACE;
    // accumulate_orientation defaults to 1 (enabled) via the INIT macro.

    for (auto root_id : root_ids) {
        occtl_topo_explorer_iter_t* iter = nullptr;
        if (occtl_topo_child_explorer_create(
                graph, root_id, &cfg, &iter) != OCCTL_OK || !iter)
            continue;

        occtl_node_id_t     face_id;
        occtl_transform_t   xform;
        occtl_orientation_t orient;
        while (occtl_topo_explorer_iter_next(iter, &face_id, &xform, &orient) == OCCTL_OK) {
            occtl_uid_t uid;
            if (occtl_graph_uid_from_node_id(graph, face_id, &uid) == OCCTL_OK) {
                rev_map[uid.bits] = (orient == OCCTL_ORIENTATION_REVERSED);
            }
        }
        occtl_topo_explorer_iter_free(iter);
    }

    return rev_map;
}


/// Per-face triangulation data used by both ArrayMesh and collision paths.
struct TriFaceData {
    occtl_node_id_t    face_id;
    bool                 reversed;   // true if face is REVERSED in its solid context
    std::vector<int>     indices;    // 0-based, 3 per triangle, Godot-compatible winding
    std::vector<Vector3> verts;      // local vertices (with location applied)
    std::vector<Vector2> uvs;        // world-scaled UVs (1 UV unit ≈ 1 world unit)
};

/// Compute world-space scale factors (du_scale, dv_scale) for a face so that
/// UV deltas map to approximate world-space arc lengths.
///
/// Uses BRep_Tool::Surface to obtain the underlying Geom_Surface and evaluates
/// its first derivatives at the parametric midpoint (from BRepTools::UVBounds),
/// which is always inside the valid domain.  This avoids BRepAdaptor_Surface
/// which can segfault when called with UV coordinates outside the surface's
/// restricted domain (e.g. for instance-transformed faces where the triangulation
/// UV nodes are in a different coordinate frame than the adaptor expects).
///
/// Returns {1,1} on any failure so the caller can divide safely.
static std::pair<double,double> _face_uv_world_scale(const TopoDS_Face& face)
{
    // Get the underlying geometric surface (with location baked in via Transform).
    TopLoc_Location loc;
    Handle(Geom_Surface) surf = BRep_Tool::Surface(face, loc);
    if (surf.IsNull()) return {1.0, 1.0};

    // Find the parametric bounds of this face on its surface.
    double umin, umax, vmin, vmax;
    BRepTools::UVBounds(face, umin, umax, vmin, vmax);
    if (umax <= umin || vmax <= vmin) return {1.0, 1.0};

    // Evaluate the first derivatives at the parametric midpoint, which is
    // guaranteed to be inside the valid domain for any surface type.
    double um = 0.5 * (umin + umax);
    double vm = 0.5 * (vmin + vmax);
    gp_Pnt P;
    gp_Vec dU, dV;
    try {
        surf->D1(um, vm, P, dU, dV);
    } catch (...) {
        return {1.0, 1.0};
    }

    // If the face has a non-identity location, the surface was already obtained
    // with BRep_Tool::Surface which gives the underlying (un-transformed) surface.
    // Apply the transformation to dU/dV to get world-space magnitudes.
    if (!loc.IsIdentity()) {
        const gp_Trsf& trsf = loc.Transformation();
        dU.Transform(trsf);
        dV.Transform(trsf);
    }

    double su = dU.Magnitude();
    double sv = dV.Magnitude();
    if (su < 1e-20) su = 1.0;
    if (sv < 1e-20) sv = 1.0;
    return {su, sv};
}

/// Collect triangulation data for every face in @p ids_vec.
///
/// Uses classical OpenCASCADE BRep_Tool::Triangulation to extract the cached
/// triangulation directly from the internal BRepGraph, bypassing the occtl
/// mesh view layer.  This ensures correct face orientation handling and avoids
/// the occtl library's winding quirks.
static std::vector<TriFaceData> _collect_face_data(
    occtl_graph_t* graph,
    const std::vector<occtl_node_id_t>& ids_vec,
    bool include_uvs,
    int& out_total_verts,
    int& out_total_tris)
{
    std::vector<TriFaceData> face_data;
    face_data.reserve(ids_vec.size());
    out_total_verts = 0;
    out_total_tris  = 0;

    // Access the internal BRepGraph structure (same trick used by the
    // STL exporter which works correctly).
    if (!graph) return face_data;
    auto* internal_graph = static_cast<struct occtl_graph*>(graph);

    // ---- Build accumulated orientation map (mirrors STL exporter strategy) ----
    // Uses occtl_topo_child_explorer_create with target_kind=FACE to directly
    // yield face node IDs with accumulated orientation from root products (or
    // solids/shells as fallback).  Each face's accumulated orientation takes
    // precedence over its own stored orientation, matching the STL exporter's
    // TopExp_Explorer-based behaviour without the fragile IsSame matching.
    auto const acc_orient = _build_accumulated_orientation_map(graph);

    for (auto fid : ids_vec) {
        const BRepGraph_NodeId node_id =
            BRepGraph_NodeId::Typed<BRepGraph_NodeId::Kind::Face>(fid.bits);
        const TopoDS_Shape shape = internal_graph->graph.Shapes().Shape(node_id);
        if (shape.IsNull()) continue;

        const TopoDS_Face face = TopoDS::Face(shape);
        if (face.IsNull()) continue;

        // Get triangulation via the classic OpenCASCADE API.
        // BRepMesh_IncrementalMesh (invoked earlier by _ensure_mesh_generated)
        // stores the triangulation on each face's TShape, so it is accessible
        // here regardless of the occtl mesh cache.
        TopLoc_Location loc;
        const Handle(Poly_Triangulation) tri = BRep_Tool::Triangulation(face, loc);
        if (tri.IsNull()) continue;

        const size_t nv = static_cast<size_t>(tri->NbNodes());
        const size_t nt = static_cast<size_t>(tri->NbTriangles());
        if (nv == 0 || nt == 0) continue;

        // Determine face orientation — prefer accumulated (solid-context)
        // orientation matching the STL exporter's approach, fall back to the
        // face's own stored orientation.
        bool reversed = (face.Orientation() == TopAbs_REVERSED);
        if (!acc_orient.empty()) {
            occtl_uid_t uid;
            if (occtl_graph_uid_from_node_id(graph, fid, &uid) == OCCTL_OK) {
                auto const it = acc_orient.find(uid.bits);
                if (it != acc_orient.end()) {
                    reversed = it->second;
                }
            }
        }

        TriFaceData fd;
        fd.face_id  = fid;
        fd.reversed = reversed;

        // ---- Vertices (apply face location to get global coords) ----
        const bool has_loc = !loc.IsIdentity();
        const gp_Trsf trsf = has_loc ? loc.Transformation() : gp_Trsf();
        fd.verts.reserve(nv);
        for (size_t i = 1; i <= nv; i++) {
            gp_Pnt p = tri->Node(static_cast<int>(i));
            if (has_loc) p.Transform(trsf);
            fd.verts.emplace_back(p.X(), p.Y(), p.Z());
        }

        // ---- Triangles ----
        //
        // OCCT's Poly_Triangulation stores triangles with natural surface
        // winding (right-handed FORWARD orientation).  Faces with REVERSED
        // orientation carry the same triangulation but the winding must be
        // flipped to produce outward-pointing normals.
        //
        // Additionally, Godot's winding convention is opposite to OCCT's for
        // FORWARD faces (comment: "OpenCASCADE winds the opposite as Godot
        // for all faces"), so we flip FORWARD faces.  REVERSED faces already
        // have their winding inverted by the face orientation, so they end up
        // correct for Godot without the extra flip.  The net effect matches
        // the original occtl-based code.
        fd.indices.reserve(3 * nt);
        for (size_t i = 1; i <= nt; i++) {
            const Poly_Triangle& t = tri->Triangle(static_cast<int>(i));
            int aA = 0, aB = 0, aC = 0;
            t.Get(aA, aB, aC);
            // Convert from 1-based to 0-based
            aA--; aB--; aC--;

            if (reversed) {
                // REVERSED face: keep natural winding — the reversal has
                // already inverted the triangle order, making it correct for
                // Godot's opposite convention.
                fd.indices.push_back(aA);
                fd.indices.push_back(aB);
                fd.indices.push_back(aC);
            } else {
                // FORWARD face: swap for Godot's opposite winding convention.
                fd.indices.push_back(aA);
                fd.indices.push_back(aC);
                fd.indices.push_back(aB);
            }
        }

        // ---- UVs (world-scaled) ----
        // Raw OCCT surface parameters (U,V) have units that depend on the
        // surface type (e.g. radians for cylinders, millimetres for planes).
        // Dividing by the Jacobian magnitude at the face centroid converts
        // each UV delta to approximately 1 world unit = 1 UV unit, making
        // textures appear at a consistent scale across different surface types
        // without requiring triplanar mapping.
        if (include_uvs && tri->HasUVNodes()) {
            auto [su, sv] = _face_uv_world_scale(face);
            fd.uvs.reserve(nv);
            for (size_t i = 1; i <= nv; i++) {
                const gp_Pnt2d uv = tri->UVNode(static_cast<int>(i));
                fd.uvs.emplace_back(uv.X() * su, uv.Y() * sv);
            }
        }

        out_total_verts += static_cast<int>(nv);
        out_total_tris  += static_cast<int>(nt);
        face_data.push_back(std::move(fd));
    }

    return face_data;
}

/// Assemble a Godot Mesh::Array from the per-face triangulation data.
///
/// Within each face, smooth per-vertex normals are computed by averaging
/// the face normals of all incident triangles.  Faces never share vertices
/// with each other, producing hard edges at face boundaries automatically
/// without any angle-threshold tuning.
static Array _assemble_mesh_arrays(
    const std::vector<TriFaceData>& face_data,
    bool include_uvs,
    bool include_tangents,
    bool include_feature_ids)
{
    PackedVector3Array out_verts;
    PackedInt32Array   out_indices;
    PackedVector3Array out_normals;
    PackedVector2Array out_uvs;
    PackedColorArray   out_colors;
    PackedFloat32Array out_tangents;
    bool have_uvs      = false;
    bool have_tangents = false;
    bool have_colors   = false;

    // Map each face's local vertex index → global output index
    std::vector<std::vector<int>> face_vert_map(face_data.size());

    // ---- First pass: emit vertices & compute smooth per-face normals ----
    for (size_t fi = 0; fi < face_data.size(); fi++) {
        auto const& fd = face_data[fi];
        size_t const nv = fd.verts.size();
        size_t const nt = fd.indices.size() / 3;
        if (nv == 0 || nt == 0) continue;

        // Compute face normal for each triangle
        // The normals from (B-A)×(C-A) use OCCT's orientation convention;
        // Godot expects the opposite, so we negate all triangle normals.
        std::vector<Vector3> tri_normals(nt);
        for (size_t i = 0; i < nt; i++) {
            int const i0 = fd.indices[3 * i];
            int const i1 = fd.indices[3 * i + 1];
            int const i2 = fd.indices[3 * i + 2];
            Vector3 const e1 = fd.verts[i1] - fd.verts[i0];
            Vector3 const e2 = fd.verts[i2] - fd.verts[i0];
            Vector3 n = -(e1.cross(e2));
            double len = n.length();
            if (len > 1e-30) n /= len;
            tri_normals[i] = n;
        }

        // Accumulate incident triangle normals per vertex
        std::vector<Vector3> vert_normals(nv, Vector3(0, 0, 0));
        for (size_t i = 0; i < nt; i++) {
            Vector3 const& n = tri_normals[i];
            vert_normals[fd.indices[3 * i]]     += n;
            vert_normals[fd.indices[3 * i + 1]] += n;
            vert_normals[fd.indices[3 * i + 2]] += n;
        }
        // Normalise
        for (auto& vn : vert_normals) {
            double len = vn.length();
            if (len > 1e-30) vn /= len;
        }

        // Emit to global arrays (no cross-face sharing → sharp seams)
        face_vert_map[fi].resize(nv);
        for (size_t vi = 0; vi < nv; vi++) {
            int const gv = static_cast<int>(out_verts.size());
            out_verts.push_back(fd.verts[vi]);
            out_normals.push_back(vert_normals[vi]);
            if (include_uvs && vi < fd.uvs.size()) {
                out_uvs.push_back(fd.uvs[vi]);
                have_uvs = true;
            }
            face_vert_map[fi][vi] = gv;
        }
    }

    // ---- Build index buffer ----
    for (size_t fi = 0; fi < face_data.size(); fi++) {
        auto const& fd = face_data[fi];
        for (size_t i = 0; i < fd.indices.size(); i += 3) {
            out_indices.push_back(face_vert_map[fi][fd.indices[i]]);
            out_indices.push_back(face_vert_map[fi][fd.indices[i + 1]]);
            out_indices.push_back(face_vert_map[fi][fd.indices[i + 2]]);
        }
    }

    // ---- Tangents ----
    if (include_tangents && have_uvs) {
        out_tangents.resize(out_verts.size() * 4);
        out_tangents.fill(0.0f);
        std::vector<int> tangent_count(out_verts.size(), 0);

        for (size_t ti = 0; ti < face_data.size(); ti++) {
            auto const& fd = face_data[ti];
            if (fd.uvs.empty()) continue;
            for (size_t j = 0; j < fd.indices.size() / 3; j++) {
                int const i0 = face_vert_map[ti][fd.indices[3 * j]];
                int const i1 = face_vert_map[ti][fd.indices[3 * j + 1]];
                int const i2 = face_vert_map[ti][fd.indices[3 * j + 2]];

                Vector3 const e1 = out_verts[i1] - out_verts[i0];
                Vector3 const e2 = out_verts[i2] - out_verts[i0];
                Vector2 const duv1 = out_uvs[i1] - out_uvs[i0];
                Vector2 const duv2 = out_uvs[i2] - out_uvs[i0];

                double const det = duv1.x * duv2.y - duv2.x * duv1.y;
                double const r = 1.0 / (det + (det >= 0.0 ? 1e-20 : -1e-20));
                // Standard Gram-Schmidt tangent (no negation): T = (e1*dv2 - e2*dv1) / det
                Vector3 const tangent = (e1 * duv2.y - e2 * duv1.y) * r;

                for (int vi : {i0, i1, i2}) {
                    int const base = vi * 4;
                    out_tangents[base]     += static_cast<float>(tangent.x);
                    out_tangents[base + 1] += static_cast<float>(tangent.y);
                    out_tangents[base + 2] += static_cast<float>(tangent.z);
                    tangent_count[vi]++;
                }
            }
        }

        // Orthogonalize and normalize
        for (int i = 0; i < out_verts.size(); i++) {
            if (tangent_count[i] == 0) continue;
            int const base = i * 4;
            Vector3 t(out_tangents[base],
                      out_tangents[base + 1],
                      out_tangents[base + 2]);
            t /= static_cast<double>(tangent_count[i]);

            Vector3 const& n = out_normals[i];
            // Gram-Schmidt: remove normal component from accumulated tangent.
            t = (t - n * n.dot(t)).normalized();

            out_tangents[base]     = static_cast<float>(t.x);
            out_tangents[base + 1] = static_cast<float>(t.y);
            out_tangents[base + 2] = static_cast<float>(t.z);

            // Bitangent handedness: w = sign(dot(n × T, B_uv)).
            // B_uv is the UV-derived bitangent accumulated from per-triangle
            // data.  We recompute it from the bitangent accumulator stored in
            // a temporary pass — but since we only stored tangents above, we
            // use the standard sign-based approach: if the UV winding matches
            // the geometric winding, w=+1, else w=-1.
            // Here we check whether (n × T) would need to be flipped to align
            // with the coordinate frame implied by the right-hand rule.
            // For Godot's convention (right-hand): B = w * (n × T), w ∈ {±1}.
            // A positive determinant in the UV → position mapping means the
            // UV frame is right-handed, so w = +1; negative means w = -1.
            // We encoded `r` with the sign of `det`, so the tangent already
            // points in the correct direction; w = +1 always (no flip needed).
            // However, reversed faces have their winding swapped, so we need
            // to propagate the reversal into w.  Since faces don't share
            // vertices we track it per-face.  For the simple per-vertex path
            // here, w = +1 is correct for forward faces; the winding swap
            // already handled by the index reordering ensures the normal is
            // outward, and tangent follows consistently.
            out_tangents[base + 3] = 1.0f;
        }
        have_tangents = true;
    }

    // ---- Feature-ID colours ----
    if (include_feature_ids) {
        out_colors.resize(out_verts.size());
        for (size_t fi = 0; fi < face_data.size(); fi++) {
            auto const& fd   = face_data[fi];
            uint64_t const b = fd.face_id.bits;
            Color const color(
                ((b * 1234567u) & 0xFF) / 255.0f,
                ((b * 7654321u) & 0xFF) / 255.0f,
                ((b * 3456789u) & 0xFF) / 255.0f,
                1.0f);
            for (size_t vi = 0; vi < fd.verts.size(); vi++) {
                int const gv = face_vert_map[fi][vi];
                out_colors[gv] = color;
            }
        }
        have_colors = true;
    }

    // ---- Build surface arrays ----
    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = out_verts;
    arrays[Mesh::ARRAY_INDEX]  = out_indices;
    arrays[Mesh::ARRAY_NORMAL] = out_normals;
    if (have_uvs)
        arrays[Mesh::ARRAY_TEX_UV] = out_uvs;
    if (have_tangents)
        arrays[Mesh::ARRAY_TANGENT] = out_tangents;
    if (have_colors)
        arrays[Mesh::ARRAY_COLOR] = out_colors;

    return arrays;
}

/// Create one ConcavePolygonShape3D child per face on @p body.
static void _add_face_collisions(PhysicsBody3D* body,
    const std::vector<TriFaceData>& face_data)
{
    for (const auto& fd : face_data) {
        PackedVector3Array tri_verts;
        tri_verts.resize(fd.indices.size());
        for (size_t i = 0; i < fd.indices.size(); i++)
            tri_verts[i] = fd.verts[fd.indices[i]];

        Ref<ConcavePolygonShape3D> shape;
        shape.instantiate();
        shape->set_faces(tri_verts);

        CollisionShape3D* cs = memnew(CollisionShape3D);
        cs->set_shape(shape);
        cs->set_name(String("_occtl_face_")
                     + String::num_uint64(fd.face_id.bits));

        Dictionary meta;
        meta["feature_id"] = static_cast<int64_t>(fd.face_id.bits);
        cs->set_meta("occtl", meta);

        body->add_child(cs, true);
        cs->set_owner(
            body->get_owner() ? body->get_owner() : body);
    }
}

// ===========================================================================
// Edge segment data
// ===========================================================================

/// A single edge segment (pair of consecutive polygon-on-tri nodes).
struct EdgeSegment {
    gp_Pnt p0, p1;
    occtl_node_id_t eid;
    uint64_t seg_idx;   // per-edge segment index
};

// ===========================================================================
// Edge curve sampling fallback (for edges without faces)
// ===========================================================================

/// Sample point on an edge curve, used by the adaptive curve sampler.
struct CurvePt {
    double t;     ///< Curve parameter.
    gp_Pnt p;     ///< 3D position.
    gp_Vec d1;    ///< First derivative (may be zero if unavailable).
};

/// Evaluate a point (and tangent) on an edge at parameter @p t.
/// Falls back to vertex positions when curve evaluation is unavailable.
static CurvePt _curve_eval(
    occtl_graph_t* graph, occtl_node_id_t eid,
    int32_t has_curve, double t,
    double t_min, double t_max)
{
    CurvePt pt;
    pt.t = t;
    pt.d1 = gp_Vec(0, 0, 0);

    if (has_curve) {
        occtl_point3_t cp;
        if (occtl_topo_edge_eval(graph, eid, t, &cp) == OCCTL_OK) {
            pt.p = gp_Pnt(cp.x, cp.y, cp.z);
            occtl_vector3_t d1;
            if (occtl_topo_edge_eval_d1(graph, eid, t, &cp, &d1) == OCCTL_OK) {
                pt.d1 = gp_Vec(d1.x, d1.y, d1.z);
            }
            return pt;
        }
    }

    // Fallback: try vertex positions
    if (t == t_min) {
        occtl_node_id_t sv;
        if (occtl_topo_edge_start_vertex(graph, eid, &sv) == OCCTL_OK) {
            occtl_point3_t vp;
            if (occtl_topo_vertex_point(graph, sv, &vp) == OCCTL_OK)
                pt.p = gp_Pnt(vp.x, vp.y, vp.z);
        }
    } else if (t == t_max) {
        occtl_node_id_t ev;
        if (occtl_topo_edge_end_vertex(graph, eid, &ev) == OCCTL_OK) {
            occtl_point3_t vp;
            if (occtl_topo_vertex_point(graph, ev, &vp) == OCCTL_OK)
                pt.p = gp_Pnt(vp.x, vp.y, vp.z);
        }
    }
    return pt;
}

/// Recursively subdivide an edge curve segment, inserting sample points
/// into @p samples in parameter order.  Stops when the chord deviation is
/// within @p deflection AND the angular change is within @p angle.
static void _curve_subdivide(
    occtl_graph_t* graph, occtl_node_id_t eid, int32_t has_curve,
    double t0, double t1,
    const CurvePt& s0, const CurvePt& s1,
    double deflection, double angle, int depth,
    double t_min, double t_max,
    std::vector<CurvePt>& samples)
{
    if (depth > 24) return; // safety limit

    double const tm = 0.5 * (t0 + t1);
    CurvePt sm = _curve_eval(graph, eid, has_curve, tm, t_min, t_max);

    // --- chord deviation (distance from midpoint to chord) ---
    gp_Vec const chord(s0.p, s1.p);
    double const chord_len = chord.Magnitude();
    double dev = 0.0;
    if (chord_len > 1e-15) {
        gp_Vec const v(s0.p, sm.p);
        double t = v.Dot(chord) / (chord_len * chord_len);
        t = std::max(0.0, std::min(1.0, t));
        gp_Pnt const proj = s0.p.XYZ() + t * chord.XYZ();
        dev = sm.p.Distance(proj);
    }

    // --- angular deviation (change in tangent direction) ---
    double ang_dev = 0.0;
    double const mag0 = s0.d1.Magnitude();
    double const magm = sm.d1.Magnitude();
    if (mag0 > 1e-15 && magm > 1e-15) {
        double cos_a = s0.d1.Dot(sm.d1) / (mag0 * magm);
        cos_a = std::max(-1.0, std::min(1.0, cos_a));
        ang_dev = std::acos(cos_a);
    }

    double const seg_len = s0.p.Distance(s1.p);
    bool const tiny = seg_len < 1e-12;

    if ((dev <= deflection || tiny) && (ang_dev <= angle || tiny)) {
        return; // segment meets quality criteria
    }

    // Subdivide: left, midpoint, right (maintains parameter order)
    _curve_subdivide(graph, eid, has_curve,
                     t0, tm, s0, sm,
                     deflection, angle, depth + 1,
                     t_min, t_max, samples);
    samples.push_back(sm);
    _curve_subdivide(graph, eid, has_curve,
                     tm, t1, sm, s1,
                     deflection, angle, depth + 1,
                     t_min, t_max, samples);
}

/// Custom curve sampling for edges that have no face adjacency and no
/// cached 3D polygon data.  Uses the OCCT curve evaluation API with
/// adaptive subdivision controlled by @p deflection and @p angle.
/// Segments are appended to @p out_segments.
static void _sample_edge_curve_segments(
    occtl_graph_t* graph,
    occtl_node_id_t eid,
    double deflection,
    double angle,
    std::vector<EdgeSegment>& out_segments)
{
    // Get parametric range
    double t_min = 0.0, t_max = 1.0;
    if (occtl_topo_edge_range(graph, eid, &t_min, &t_max) != OCCTL_OK)
        return;

    // Check if edge has a 3D curve
    int32_t has_curve = 0;
    occtl_topo_edge_has_curve(graph, eid, &has_curve);
    // UtilityFunctions::print(
    //     "  range=[", t_min, ", ", t_max, "] has_curve=", has_curve);

    // if (!has_curve) {
    //     UtilityFunctions::push_warning(
    //         String("EDGE ")
    //         + String::num_uint64(eid.bits)
    //         + " HAS NO 3D CURVE");
    // }

    CurvePt s0 = _curve_eval(graph, eid, has_curve, t_min, t_min, t_max);
    CurvePt s1 = _curve_eval(graph, eid, has_curve, t_max, t_min, t_max);

    // UtilityFunctions::print(
    //     "  p0=", s0.p.X(), ",", s0.p.Y(), ",", s0.p.Z(),
    //     "  p1=", s1.p.X(), ",", s1.p.Y(), ",", s1.p.Z());

    // double edge_len = s0.p.Distance(s1.p);

    // if (edge_len < 1e-15) {
    //     UtilityFunctions::push_warning(
    //         String("EDGE ")
    //         + String::num_uint64(eid.bits)
    //         + " ZERO ENDPOINT DISTANCE");
    // }

    // Collect sample points via adaptive subdivision
    std::vector<CurvePt> samples;
    samples.reserve(64);
    samples.push_back(s0);
    _curve_subdivide(graph, eid, has_curve,
                     t_min, t_max, s0, s1,
                     deflection, angle, 0,
                     t_min, t_max, samples);
    samples.push_back(s1);

    // Build EdgeSegments from consecutive sample points
    for (size_t i = 0; i + 1 < samples.size(); i++) {
        double const seg_len = samples[i].p.Distance(samples[i + 1].p);
        if (seg_len < 1e-15) continue;

        EdgeSegment seg;
        seg.p0 = samples[i].p;
        seg.p1 = samples[i + 1].p;
        seg.eid = eid;
        seg.seg_idx = static_cast<uint64_t>(i);
        out_segments.push_back(std::move(seg));
    }
}

/// Collect edge segments from polygon-on-triangulation data.
/// @note The graph must be meshed before calling this function.
/// For edges without face adjacency and no cached 3D polygon, falls back
/// to adaptive curve sampling controlled by @p deflection and @p angle.
static std::vector<EdgeSegment> _collect_edge_segments(
    occtl_graph_t* graph,
    const std::vector<occtl_node_id_t>& edge_ids,
    double deflection,
    double angle)
{
    std::vector<EdgeSegment> segments;
    segments.reserve(edge_ids.size());

    // Build edge -> ALL (coedge, face) pairs instead of just the first one.
    std::unordered_map<uint64_t,
        std::vector<std::pair<occtl_node_id_t, occtl_node_id_t>>> edge_coedge_map;

    {
        occtl_node_iter_t* coedge_iter = nullptr;
        occtl_status_t st = occtl_graph_coedge_iter_create(graph, &coedge_iter);
        if (st == OCCTL_OK && coedge_iter) {
            occtl_node_id_t cid;
            while (occtl_node_iter_next(coedge_iter, &cid) == OCCTL_OK) {
                occtl_node_id_t edge_of{};
                occtl_node_id_t face_of{};
                occtl_topo_coedge_edge_of(graph, cid, &edge_of);
                occtl_topo_coedge_face_of(graph, cid, &face_of);

                if (edge_of.bits != 0 && face_of.bits != 0)
                    edge_coedge_map[edge_of.bits].push_back({cid, face_of});
            }
            occtl_node_iter_free(coedge_iter);
        }
    }

    for (auto eid : edge_ids) {
        // const size_t before = segments.size();

        // UtilityFunctions::print("\n=== EDGE ", uint64_t(eid.bits), " ===");

        // Try EVERY adjacent coedge until one produces a polygon.
        auto it = edge_coedge_map.find(eid.bits);
        if (it != edge_coedge_map.end()) {
            // UtilityFunctions::print("  coedges: ", int(it->second.size()));

            bool handled = false;

            for (auto [coedge_id, face_id] : it->second) {
                occtl_polygon_on_tri_view_t potv{};
                auto st = occtl_mesh_coedge_polygon_on_tri(graph, coedge_id, &potv);

                // UtilityFunctions::print(
                //     "    coedge ", uint64_t(coedge_id.bits),
                //     " status=", int(st),
                //     " nodes=", int(potv.node_count));

                if (st != OCCTL_OK || potv.node_count < 2)
                    continue;

                occtl_triangulation_view_t tv{};
                st = occtl_mesh_face_triangulation(graph, face_id, &tv);

                // UtilityFunctions::print(
                //     "      face ", uint64_t(face_id.bits),
                //     " status=", int(st),
                //     " tri_nodes=", int(tv.node_count));

                if (st != OCCTL_OK || tv.node_count == 0)
                    continue;

                for (size_t i = 0; i + 1 < potv.node_count; ++i) {
                    uint32_t idx0 = potv.node_indices[i];
                    uint32_t idx1 = potv.node_indices[i + 1];

                    if (idx0 >= tv.node_count || idx1 >= tv.node_count)
                        continue;

                    EdgeSegment seg;
                    seg.p0 = gp_Pnt(
                        tv.nodes[3 * idx0],
                        tv.nodes[3 * idx0 + 1],
                        tv.nodes[3 * idx0 + 2]);

                    seg.p1 = gp_Pnt(
                        tv.nodes[3 * idx1],
                        tv.nodes[3 * idx1 + 1],
                        tv.nodes[3 * idx1 + 2]);

                    seg.eid = eid;
                    seg.seg_idx = static_cast<uint64_t>(i);
                    segments.push_back(std::move(seg));
                }

                handled = true;
                break;
            }

            if (handled) {
                // UtilityFunctions::print(
                //     "  emitted ",
                //     int(segments.size() - before),
                //     " segments via coedge");
                continue;
            }
        } else {
            // UtilityFunctions::print("  no coedges");
        }

        // Try cached Polygon3D.
        occtl_polygon3d_view_t pv{};
        auto st = occtl_mesh_edge_polygon3d(graph, eid, &pv);

        // UtilityFunctions::print(
        //     "  polygon3d status=",
        //     int(st),
        //     " nodes=",
        //     int(pv.node_count));

        if (st == OCCTL_OK && pv.node_count >= 2) {
            for (size_t i = 0; i + 1 < pv.node_count; ++i) {
                EdgeSegment seg;
                seg.p0 = gp_Pnt(
                    pv.nodes[3 * i],
                    pv.nodes[3 * i + 1],
                    pv.nodes[3 * i + 2]);

                seg.p1 = gp_Pnt(
                    pv.nodes[3 * (i + 1)],
                    pv.nodes[3 * (i + 1) + 1],
                    pv.nodes[3 * (i + 1) + 2]);

                seg.eid = eid;
                seg.seg_idx = static_cast<uint64_t>(i);
                segments.push_back(std::move(seg));
            }

            // UtilityFunctions::print(
            //     "  emitted ",
            //     int(segments.size() - before),
            //     " segments via polygon3d");
            continue;
        }

        // Last resort: sample the curve.
        // UtilityFunctions::print("  sampling curve...");

        _sample_edge_curve_segments(
            graph,
            eid,
            deflection,
            angle,
            segments);

        // UtilityFunctions::print(
        //     "  emitted ",
        //     int(segments.size() - before),
        //     " segments via sampler");

        // if (segments.size() == before) {
        //     UtilityFunctions::push_warning(
        //         String("EDGE ")
        //         + String::num_uint64(eid.bits)
        //         + " PRODUCED ZERO SEGMENTS");
        // }
    }

    return segments;
}

// ===========================================================================
// Vertex position data
// ===========================================================================

struct VertexPos {
    occtl_node_id_t vid;
    gp_Pnt pos;
};

/// Collect 3D positions for each vertex ID.
static std::vector<VertexPos> _collect_vertex_positions(
    occtl_graph_t* graph,
    const std::vector<occtl_node_id_t>& vertex_ids)
{
    std::vector<VertexPos> vertices;
    vertices.reserve(vertex_ids.size());

    for (auto vid : vertex_ids) {
        occtl_point3_t pt;
        occtl_status_t st = occtl_topo_vertex_point(graph, vid, &pt);
        if (st != OCCTL_OK) continue;

        VertexPos vp;
        vp.vid = vid;
        vp.pos = gp_Pnt(pt.x, pt.y, pt.z);
        vertices.push_back(vp);
    }

    return vertices;
}

// ===========================================================================
// Shared helper: build orientation Basis + mid-point for an edge segment
// ===========================================================================

/// Build an orientation Basis + translation for a segment from p0→p1.
/// The Y axis follows the segment direction. Handles the pole-zero case
/// where the segment aligns with the global Y axis.
static inline Basis _segment_basis(gp_Vec const& dir) {
    gp_Vec up(0, 1, 0);
    if (std::abs(dir.Y()) > 0.9)
        up = gp_Vec(1, 0, 0);
    gp_Vec const x_axis = up.Crossed(dir).Normalized();
    gp_Vec const z_axis = x_axis.Crossed(dir).Normalized();
    return Basis(Vector3(x_axis.X(), x_axis.Y(), x_axis.Z()),
                 Vector3(dir.X(), dir.Y(), dir.Z()),
                 Vector3(z_axis.X(), z_axis.Y(), z_axis.Z()));
}

// ===========================================================================
// _bind_methods
// ===========================================================================

void OclMeshToGodot::_bind_methods() {
    // --- ArrayMesh/MultiMesh methods ---
    godot::ClassDB::bind_static_method("OclMeshToGodot",
        godot::D_METHOD("mesh_faces", "graph", "existing", "options", "face_ids",
                        "include_uvs", "include_tangents",
                        "include_feature_ids"),
        &OclMeshToGodot::mesh_faces,
        DEFVAL(Ref<ArrayMesh>()), DEFVAL(Ref<OclMeshOptions>()), DEFVAL(Variant()),
        DEFVAL(false), DEFVAL(false), DEFVAL(false));

    godot::ClassDB::bind_static_method("OclMeshToGodot",
        godot::D_METHOD("mesh_edges", "graph", "existing", "options", "edge_ids",
                        "radius"),
        &OclMeshToGodot::mesh_edges,
        DEFVAL(Ref<MultiMesh>()), DEFVAL(Ref<OclMeshOptions>()), DEFVAL(Variant()),
        DEFVAL(0.001));

    godot::ClassDB::bind_static_method("OclMeshToGodot",
        godot::D_METHOD("mesh_vertices", "graph", "existing", "options",
                        "vertex_ids", "radius"),
        &OclMeshToGodot::mesh_vertices,
        DEFVAL(Ref<MultiMesh>()), DEFVAL(Ref<OclMeshOptions>()), DEFVAL(Variant()),
        DEFVAL(0.002));

    // --- Collision methods ---
    godot::ClassDB::bind_static_method("OclMeshToGodot",
        godot::D_METHOD("mesh_faces_collision", "graph", "body", "options",
                        "face_ids"),
        &OclMeshToGodot::mesh_faces_collision,
        DEFVAL(Ref<OclMeshOptions>()), DEFVAL(Variant()));

    godot::ClassDB::bind_static_method("OclMeshToGodot",
        godot::D_METHOD("mesh_edges_collision", "graph", "body", "options",
                        "edge_ids", "radius"),
        &OclMeshToGodot::mesh_edges_collision,
        DEFVAL(Ref<OclMeshOptions>()), DEFVAL(Variant()), DEFVAL(0.001));

    godot::ClassDB::bind_static_method("OclMeshToGodot",
        godot::D_METHOD("mesh_vertices_collision", "graph", "body", "options",
                        "vertex_ids", "radius"),
        &OclMeshToGodot::mesh_vertices_collision,
        DEFVAL(Ref<OclMeshOptions>()), DEFVAL(Variant()), DEFVAL(0.002));

    // --- New merge/extract methods ---
    godot::ClassDB::bind_static_method("OclMeshToGodot",
        godot::D_METHOD("merge_surface_arrays", "surfaces"),
        &OclMeshToGodot::merge_surface_arrays);

    godot::ClassDB::bind_static_method("OclMeshToGodot",
        godot::D_METHOD("extract_face_triangles", "graph", "options",
                        "face_ids"),
        &OclMeshToGodot::extract_face_triangles);
}

// ===========================================================================
// mesh_faces  —  ArrayMesh rendering path
// ===========================================================================

int OclMeshToGodot::mesh_faces(
    const Ref<OclGraphHandle>& graph,
    const Ref<ArrayMesh>&      existing,
    const Ref<OclMeshOptions>& options,
    const Variant&             face_ids,
    bool                       include_uvs,
    bool                       include_tangents,
    bool                       include_feature_ids)
{
    if (graph.is_null() || !graph->_handle) return OCCTL_INVALID_ARGUMENT;
    if (existing.is_null()) return OCCTL_INVALID_ARGUMENT;

    // ----- Prepare output mesh ---------------------------------------------
    existing->clear_surfaces();

    // ----- Options --------------------------------------------------------
    occtl_mesh_options_t opts = OCCTL_MESH_OPTIONS_INIT;
    if (options.is_valid()) opts = options->to_c();
    double const deflection = opts.deflection;
    double const angle      = opts.angle;

    // ----- Resolve face IDs -----------------------------------------------
    std::vector<occtl_node_id_t> ids_vec =
        _resolve_face_ids(graph->_handle, face_ids);
    if (ids_vec.empty()) return OCCTL_OK;

    // ----- Generate mesh --------------------------------------------------
    {
        occtl_status_t st = _ensure_mesh_generated(
            graph->_handle, ids_vec, deflection, angle);
        if (st != OCCTL_OK) return OCCTL_OK;
    }

    // ----- Collect triangulation data -------------------------------------
    int total_verts = 0, total_tris = 0;
    std::vector<TriFaceData> face_data = _collect_face_data(
        graph->_handle, ids_vec, include_uvs, total_verts, total_tris);
    if (face_data.empty()) return OCCTL_OK;

    // ----- Assemble ArrayMesh surface -------------------------------------
    Array arrays = _assemble_mesh_arrays(face_data,
        include_uvs, include_tangents, include_feature_ids);
    existing->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    return OCCTL_OK;
}

// ===========================================================================
// mesh_faces_collision  —  physics collision path
// ===========================================================================

int OclMeshToGodot::mesh_faces_collision(
    const Ref<OclGraphHandle>& graph,
    PhysicsBody3D*             body,
    const Ref<OclMeshOptions>& options,
    const Variant&             face_ids)
{
    if (!body) return OCCTL_INVALID_ARGUMENT;
    if (graph.is_null() || !graph->_handle) return OCCTL_INVALID_ARGUMENT;

    _clear_physics_children(body);

    // ----- Options --------------------------------------------------------
    occtl_mesh_options_t opts = OCCTL_MESH_OPTIONS_INIT;
    if (options.is_valid()) opts = options->to_c();
    double const deflection = opts.deflection;
    double const angle      = opts.angle;

    // ----- Resolve face IDs -----------------------------------------------
    std::vector<occtl_node_id_t> ids_vec =
        _resolve_face_ids(graph->_handle, face_ids);
    if (ids_vec.empty()) return OCCTL_OK;

    // ----- Generate mesh --------------------------------------------------
    {
        occtl_status_t st = _ensure_mesh_generated(
            graph->_handle, ids_vec, deflection, angle);
        if (st != OCCTL_OK) return OCCTL_OK;
    }

    // ----- Collect triangulation data (no UVs needed for physics) ---------
    int total_verts = 0, total_tris = 0;
    std::vector<TriFaceData> face_data = _collect_face_data(
        graph->_handle, ids_vec, false, total_verts, total_tris);
    if (face_data.empty()) return OCCTL_OK;

    // ----- Add collision shapes -------------------------------------------
    _add_face_collisions(body, face_data);
    return OCCTL_OK;
}

// ===========================================================================
// mesh_edges  —  MultiMesh rendering path
// ===========================================================================

int OclMeshToGodot::mesh_edges(
    const Ref<OclGraphHandle>& graph,
    const Ref<MultiMesh>&      existing,
    const Ref<OclMeshOptions>& options,
    const Variant&             edge_ids,
    double                     radius)
{
    if (graph.is_null() || !graph->_handle) return OCCTL_INVALID_ARGUMENT;
    if (existing.is_null()) return OCCTL_INVALID_ARGUMENT;

    // ----- Prepare output MultiMesh ---------------------------------------
    existing->set_instance_count(0);
    existing->set_transform_format(MultiMesh::TRANSFORM_3D);
    existing->set_mesh(Ref<ArrayMesh>());

    // ----- Options --------------------------------------------------------
    occtl_mesh_options_t opts = OCCTL_MESH_OPTIONS_INIT;
    if (options.is_valid()) opts = options->to_c();
    double const angle      = opts.angle;
    double const deflection = opts.deflection;

    double eff_radius = std::abs(radius);
    if (eff_radius <= 0.0) eff_radius = deflection * 10.0;

    // ----- Resolve edge IDs -----------------------------------------------
    std::vector<occtl_node_id_t> ids_vec =
        _resolve_edge_ids(graph->_handle, edge_ids);
    if (ids_vec.empty()) return OCCTL_OK;

    // ----- Generate mesh (caches edge 3D polygons) ------------------------
    {
        occtl_mesh_options_t gen_opts = OCCTL_MESH_OPTIONS_INIT;
        gen_opts.deflection = deflection;
        gen_opts.angle      = angle;
        gen_opts.clean_model = 1;
        occtl_status_t st = occtl_mesh_generate(
            graph->_handle, nullptr, 0, &gen_opts);
        if (st != OCCTL_OK) return OCCTL_OK;
    }

    // ----- Collect edge segments ------------------------------------------
    std::vector<EdgeSegment> segments =
        _collect_edge_segments(graph->_handle, ids_vec, deflection, angle);

    // ----- Build MultiMesh transforms -------------------------------------
    std::vector<Transform3D> xforms;
    xforms.reserve(segments.size());

    if (radius >= 0.0) {
        double const bbox_diag = _get_graph_bbox_diag(graph->_handle);
        eff_radius *= bbox_diag;
    }

    for (const auto& seg : segments) {
        gp_Vec dir(seg.p0, seg.p1);
        double const seg_len = dir.Magnitude();
        if (seg_len < 1e-15) continue;
        dir.Normalize();

        gp_XYZ const mid = 0.5 * (seg.p0.XYZ() + seg.p1.XYZ());
        Basis const basis = _segment_basis(dir);

        Transform3D xf(basis, Vector3(mid.X(), mid.Y(), mid.Z()));
        xf = xf.scaled_local(Vector3(eff_radius, seg_len, eff_radius));
        xforms.push_back(xf);
    }

    // ----- Set up MultiMesh -----------------------------------------------
    existing->set_transform_format(MultiMesh::TRANSFORM_3D);
    existing->set_instance_count(static_cast<int>(xforms.size()));
    if (!existing->get_mesh().is_valid()) {
        int const slices = _slices_from_angle(angle);
        Ref<CylinderMesh> cyl_mesh;
        cyl_mesh.instantiate();
        cyl_mesh->set_height(1.0);
        cyl_mesh->set_radial_segments(slices);
        cyl_mesh->set_rings(1);
        cyl_mesh->set_cap_top(false);
        cyl_mesh->set_cap_bottom(false);
        existing->set_mesh(cyl_mesh);
    }
    for (int i = 0; i < static_cast<int>(xforms.size()); i++)
        existing->set_instance_transform(i, xforms[i]);

    return OCCTL_OK;
}

// ===========================================================================
// mesh_edges_collision  —  physics collision path
// ===========================================================================

int OclMeshToGodot::mesh_edges_collision(
    const Ref<OclGraphHandle>& graph,
    PhysicsBody3D*             body,
    const Ref<OclMeshOptions>& options,
    const Variant&             edge_ids,
    double                     radius)
{
    if (!body) return OCCTL_INVALID_ARGUMENT;
    if (graph.is_null() || !graph->_handle) return OCCTL_INVALID_ARGUMENT;

    _clear_physics_children(body);

    // ----- Options --------------------------------------------------------
    occtl_mesh_options_t opts = OCCTL_MESH_OPTIONS_INIT;
    if (options.is_valid()) opts = options->to_c();
    double const angle      = opts.angle;
    double const deflection = opts.deflection;

    double eff_radius = std::abs(radius);
    if (eff_radius <= 0.0) eff_radius = deflection * 10.0;

    // ----- Resolve edge IDs -----------------------------------------------
    std::vector<occtl_node_id_t> ids_vec =
        _resolve_edge_ids(graph->_handle, edge_ids);
    if (ids_vec.empty()) return OCCTL_OK;

    // ----- Generate mesh (caches edge 3D polygons) ------------------------
    {
        occtl_mesh_options_t gen_opts = OCCTL_MESH_OPTIONS_INIT;
        gen_opts.deflection = deflection;
        gen_opts.angle      = angle;
        gen_opts.clean_model = 1;
        occtl_status_t st = occtl_mesh_generate(
            graph->_handle, nullptr, 0, &gen_opts);
        if (st != OCCTL_OK) return OCCTL_OK;
    }

    if (radius >= 0.0) {
        double const bbox_diag = _get_graph_bbox_diag(graph->_handle);
        eff_radius *= bbox_diag;
    }

    // ----- Collect edge segments ------------------------------------------
    std::vector<EdgeSegment> segments =
        _collect_edge_segments(graph->_handle, ids_vec, deflection, angle);

    // ----- Create collision shapes ----------------------------------------
    for (const auto& seg : segments) {
        gp_Vec dir(seg.p0, seg.p1);
        double const seg_len = dir.Magnitude();
        if (seg_len < 1e-15) continue;
        dir.Normalize();

        gp_XYZ const mid = 0.5 * (seg.p0.XYZ() + seg.p1.XYZ());
        Basis const basis = _segment_basis(dir);

        Ref<CapsuleShape3D> cshape;
        cshape.instantiate();
        cshape->set_radius(eff_radius);
        cshape->set_height(std::max(0.0, seg_len - 2.0 * eff_radius));

        CollisionShape3D* cs = memnew(CollisionShape3D);
        cs->set_shape(cshape);
        cs->set_position(Vector3(mid.X(), mid.Y(), mid.Z()));
        cs->set_basis(basis);
        cs->set_name(String("_occtl_edge_")
                     + String::num_uint64(seg.eid.bits)
                     + "_" + String::num_uint64(seg.seg_idx));

        Dictionary meta;
        meta["feature_id"] = static_cast<int64_t>(seg.eid.bits);
        cs->set_meta("occtl", meta);

        body->add_child(cs, true);
        cs->set_owner(
            body->get_owner() ? body->get_owner() : body);
    }
    return OCCTL_OK;
}

// ===========================================================================
// mesh_vertices  —  MultiMesh rendering path
// ===========================================================================

int OclMeshToGodot::mesh_vertices(
    const Ref<OclGraphHandle>& graph,
    const Ref<MultiMesh>&      existing,
    const Ref<OclMeshOptions>& options,
    const Variant&             vertex_ids,
    double                     radius)
{
    if (graph.is_null() || !graph->_handle) return OCCTL_INVALID_ARGUMENT;
    if (existing.is_null()) return OCCTL_INVALID_ARGUMENT;

    // ----- Prepare output MultiMesh ---------------------------------------
    existing->set_instance_count(0);
    existing->set_transform_format(MultiMesh::TRANSFORM_3D);
    existing->set_mesh(Ref<ArrayMesh>());

    // ----- Options --------------------------------------------------------
    occtl_mesh_options_t opts = OCCTL_MESH_OPTIONS_INIT;
    if (options.is_valid()) opts = options->to_c();
    double const angle      = opts.angle;
    double const deflection = opts.deflection;

    double eff_radius = std::abs(radius);
    if (eff_radius <= 0.0) eff_radius = deflection * 10.0;

    // ----- Resolve vertex IDs ---------------------------------------------
    std::vector<occtl_node_id_t> ids_vec =
        _resolve_vertex_ids(graph->_handle, vertex_ids);
    if (ids_vec.empty()) return OCCTL_OK;

    // ----- Collect vertex positions and build transforms ------------------
    std::vector<Transform3D> xforms;
    std::vector<VertexPos> verts =
        _collect_vertex_positions(graph->_handle, ids_vec);
    xforms.reserve(verts.size());

    if (radius >= 0.0) {
        double const bbox_diag = _get_graph_bbox_diag(graph->_handle);
        eff_radius *= bbox_diag;
    }

    for (const auto& vp : verts) {
        Transform3D xf;
        xf.origin = Vector3(vp.pos.X(), vp.pos.Y(), vp.pos.Z());
        xf = xf.scaled_local(
            Vector3(eff_radius, eff_radius, eff_radius));
        xforms.push_back(xf);
    }

    // ----- Set up MultiMesh -----------------------------------------------
    existing->set_transform_format(MultiMesh::TRANSFORM_3D);
    existing->set_instance_count(static_cast<int>(xforms.size()));
    if (!existing->get_mesh().is_valid()) {
        int const slices = _slices_from_angle(angle);
        Ref<SphereMesh> sph_mesh;
        sph_mesh.instantiate();
        sph_mesh->set_radius(1.0);
        sph_mesh->set_radial_segments(slices);
        sph_mesh->set_rings(slices / 2);
        existing->set_mesh(sph_mesh);
    }
    for (int i = 0; i < static_cast<int>(xforms.size()); i++)
        existing->set_instance_transform(i, xforms[i]);

    return OCCTL_OK;
}

// ===========================================================================
// mesh_vertices_collision  —  physics collision path
// ===========================================================================

int OclMeshToGodot::mesh_vertices_collision(
    const Ref<OclGraphHandle>& graph,
    PhysicsBody3D*             body,
    const Ref<OclMeshOptions>& options,
    const Variant&             vertex_ids,
    double                     radius)
{
    if (!body) return OCCTL_INVALID_ARGUMENT;
    if (graph.is_null() || !graph->_handle) return OCCTL_INVALID_ARGUMENT;

    _clear_physics_children(body);

    // ----- Options --------------------------------------------------------
    occtl_mesh_options_t opts = OCCTL_MESH_OPTIONS_INIT;
    if (options.is_valid()) opts = options->to_c();
    double const deflection = opts.deflection;
    // angle is not needed &mdash; vertex collision shapes don't build a sphere mesh

    double eff_radius = std::abs(radius);
    if (eff_radius <= 0.0) eff_radius = deflection * 10.0;

    // ----- Resolve vertex IDs ---------------------------------------------
    std::vector<occtl_node_id_t> ids_vec =
        _resolve_vertex_ids(graph->_handle, vertex_ids);
    if (ids_vec.empty()) return OCCTL_OK;

    if (radius >= 0.0) {
        double const bbox_diag = _get_graph_bbox_diag(graph->_handle);
        eff_radius *= bbox_diag;
    }

    // ----- Collect vertex positions and create collision shapes -----------
    std::vector<VertexPos> verts =
        _collect_vertex_positions(graph->_handle, ids_vec);

    for (const auto& vp : verts) {
        Ref<SphereShape3D> cshape;
        cshape.instantiate();
        cshape->set_radius(eff_radius);

        CollisionShape3D* cs = memnew(CollisionShape3D);
        cs->set_shape(cshape);
        cs->set_position(Vector3(vp.pos.X(), vp.pos.Y(), vp.pos.Z()));
        cs->set_name(String("_occtl_vertex_")
                     + String::num_uint64(vp.vid.bits));

        Dictionary meta;
        meta["feature_id"] = static_cast<int64_t>(vp.vid.bits);
        cs->set_meta("occtl", meta);

        body->add_child(cs, true);
        cs->set_owner(
            body->get_owner() ? body->get_owner() : body);
    }
    return OCCTL_OK;
}

// ===========================================================================
// merge_surface_arrays  —  merge multiple sets of arrays into one
// ===========================================================================

Array OclMeshToGodot::merge_surface_arrays(const Array& surfaces) {
    // Accumulators
    PackedVector3Array all_verts;
    PackedInt32Array   all_indices;
    PackedVector3Array all_normals;
    PackedVector2Array all_uvs;
    PackedColorArray   all_colors;
    PackedFloat32Array all_tangents;
    bool have_uvs      = false;
    bool have_tangents = false;
    bool have_colors   = false;

    for (int si = 0; si < surfaces.size(); si++) {
        Array arr = surfaces[si];
        if (arr.size() < Mesh::ARRAY_VERTEX) continue;

        PackedVector3Array verts = arr[Mesh::ARRAY_VERTEX];
        if (verts.size() == 0) continue;

        // Vertices
        int base = all_verts.size();
        all_verts.append_array(verts);

        // Normals
        if (arr.size() > Mesh::ARRAY_NORMAL) {
            PackedVector3Array norms = arr[Mesh::ARRAY_NORMAL];
            if (norms.size() > 0) {
                all_normals.append_array(norms);
            }
        }

        // UVs
        if (arr.size() > Mesh::ARRAY_TEX_UV) {
            PackedVector2Array uvs = arr[Mesh::ARRAY_TEX_UV];
            if (uvs.size() > 0) {
                all_uvs.append_array(uvs);
                have_uvs = true;
            }
        }

        // Colors
        if (arr.size() > Mesh::ARRAY_COLOR) {
            PackedColorArray cols = arr[Mesh::ARRAY_COLOR];
            if (cols.size() > 0) {
                all_colors.append_array(cols);
                have_colors = true;
            }
        }

        // Tangents
        if (arr.size() > Mesh::ARRAY_TANGENT) {
            PackedFloat32Array tans = arr[Mesh::ARRAY_TANGENT];
            if (tans.size() > 0) {
                all_tangents.append_array(tans);
                have_tangents = true;
            }
        }

        // Indices (remapped)
        if (arr.size() > Mesh::ARRAY_INDEX) {
            PackedInt32Array idx = arr[Mesh::ARRAY_INDEX];
            for (int i = 0; i < idx.size(); i++) {
                all_indices.push_back(idx[i] + base);
            }
        } else {
            // No index array — assume non-indexed geometry
            for (int i = 0; i < verts.size(); i++) {
                all_indices.push_back(base + i);
            }
        }
    }

    // Build the merged surface array
    Array result;
    result.resize(Mesh::ARRAY_MAX);
    result[Mesh::ARRAY_VERTEX] = all_verts;
    result[Mesh::ARRAY_INDEX]  = all_indices;
    result[Mesh::ARRAY_NORMAL] = all_normals;
    if (have_uvs)
        result[Mesh::ARRAY_TEX_UV] = all_uvs;
    if (have_tangents)
        result[Mesh::ARRAY_TANGENT] = all_tangents;
    if (have_colors)
        result[Mesh::ARRAY_COLOR] = all_colors;

    return result;
}

// ===========================================================================
// extract_face_triangles  —  collision data for ConcavePolygonShape3D
// ===========================================================================

PackedVector3Array OclMeshToGodot::extract_face_triangles(
    const Ref<OclGraphHandle>& graph,
    const Ref<OclMeshOptions>& options,
    const Variant&             face_ids)
{
    PackedVector3Array tri_verts;
    if (graph.is_null() || !graph->_handle) return tri_verts;

    // ----- Options --------------------------------------------------------
    occtl_mesh_options_t opts = OCCTL_MESH_OPTIONS_INIT;
    if (options.is_valid()) opts = options->to_c();
    double const deflection = opts.deflection;
    double const angle      = opts.angle;

    // ----- Resolve face IDs -----------------------------------------------
    std::vector<occtl_node_id_t> ids_vec =
        _resolve_face_ids(graph->_handle, face_ids);
    if (ids_vec.empty()) return tri_verts;

    // ----- Generate mesh --------------------------------------------------
    {
        occtl_status_t st = _ensure_mesh_generated(
            graph->_handle, ids_vec, deflection, angle);
        if (st != OCCTL_OK) return tri_verts;
    }

    // ----- Collect triangulation data -------------------------------------
    int total_verts = 0, total_tris = 0;
    std::vector<TriFaceData> face_data = _collect_face_data(
        graph->_handle, ids_vec, false, total_verts, total_tris);
    if (face_data.empty()) return tri_verts;

    // ----- Concatenate all face triangles into one flat array -------------
    // Count total triangles first.
    size_t total_tri_count = 0;
    for (const auto& fd : face_data)
        total_tri_count += fd.indices.size() / 3;

    tri_verts.resize(static_cast<int>(total_tri_count * 3));
    int out_idx = 0;
    for (const auto& fd : face_data) {
        for (size_t i = 0; i + 2 < fd.indices.size(); i += 3) {
            tri_verts[out_idx++] = fd.verts[fd.indices[i]];
            tri_verts[out_idx++] = fd.verts[fd.indices[i + 1]];
            tri_verts[out_idx++] = fd.verts[fd.indices[i + 2]];
        }
    }

    return tri_verts;
}
