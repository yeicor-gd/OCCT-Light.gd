// ---------------------------------------------------------------------------
// Hand-written source for OclGodotMesher meshing methods.
//
// Bridges OCCT-Light graph handles (OclGraphHandle / occtl_graph_t) with
// Godot rendering (ArrayMesh, MultiMesh) and physics (PhysicsBody3D +
// CollisionShape3D).
//
// REVERSED face handling
// ----------------------
// BRepMesh_IncrementalMesh (OpenCASCADE) triangulates each face and stores
// triangle indices with CCW winding in UV parameter space.  For a REVERSED
// face the UV→3D mapping flips, so the 3D winding becomes CW and the
// geometric cross product e1×e2 points INWARD (opposite to the face's
// outward direction).
//
// However the per-vertex normals stored in Poly_Triangulation ARE computed
// with the face orientation taken into account — BRepMesh negates the
// surface normal (dS/du × dS/dv) for REVERSED faces so that the stored
// normals point OUTWARD.
//
// Therefore the correction for a REVERSED face is:
//   1. Flip triangle indices (swap 1↔2) → restores CCW/outward winding.
//   2. Keep per-vertex normals as-is — they are already outward-pointing.
//
// Detection: compare the geometric winding normal against the average of
// the per-vertex normals (reliable, always available when mesh data is
// present).  Fall back to surface evaluation (occtl_topo_face_eval_d1)
// when per-vertex normals are absent.
// ---------------------------------------------------------------------------

#include "OclGodotMesher.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>

#include <godot_cpp/classes/physics_body3d.hpp>
#include <godot_cpp/classes/collision_shape3d.hpp>
#include <godot_cpp/classes/concave_polygon_shape3d.hpp>
#include <godot_cpp/classes/capsule_shape3d.hpp>
#include <godot_cpp/classes/sphere_shape3d.hpp>
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

#include <gp_Pnt.hxx>
#include <gp_Vec.hxx>
#include <gp_Dir.hxx>

#include <cmath>
#include <cstring>
#include <unordered_map>
#include <vector>

#include "occtl/occtl_mesh.h"
#include "occtl/occtl_topo_relation.h"

using namespace godot;

// ===========================================================================
// Internal helpers
// ===========================================================================

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

// ===========================================================================
// _bind_methods
// ===========================================================================

void OclGodotMesher::_bind_methods() {
    godot::ClassDB::bind_static_method("OclGodotMesher",
        godot::D_METHOD("mesh_faces", "graph", "existing", "options", "face_ids",
                        "include_normals", "include_uvs", "include_tangents",
                        "include_feature_ids"),
        &OclGodotMesher::mesh_faces,
        DEFVAL(Variant()), DEFVAL(Ref<OclMeshOptions>()), DEFVAL(Variant()),
        DEFVAL(false), DEFVAL(false), DEFVAL(false), DEFVAL(false));

    godot::ClassDB::bind_static_method("OclGodotMesher",
        godot::D_METHOD("mesh_edges", "graph", "existing", "options", "edge_ids",
                        "radius"),
        &OclGodotMesher::mesh_edges,
        DEFVAL(Variant()), DEFVAL(Ref<OclMeshOptions>()), DEFVAL(Variant()),
        DEFVAL(0.01));

    godot::ClassDB::bind_static_method("OclGodotMesher",
        godot::D_METHOD("mesh_vertices", "graph", "existing", "options",
                        "vertex_ids", "radius"),
        &OclGodotMesher::mesh_vertices,
        DEFVAL(Variant()), DEFVAL(Ref<OclMeshOptions>()), DEFVAL(Variant()),
        DEFVAL(0.02));
}

// ===========================================================================
// Mesh generation helpers (pure geometry, no OCCT dependency)
// ===========================================================================

/// Ensure the graph has a triangulation matching the given deflection/angle.
static occtl_status_t _ensure_mesh_generated(
    occtl_graph_t* graph, double deflection, double angle)
{
    occtl_mesh_options_t opts = OCCTL_MESH_OPTIONS_INIT;
    opts.deflection = deflection;
    opts.angle = angle;
    opts.clean_model = 1;
    return occtl_mesh_generate(graph, nullptr, 0, &opts);
}

/// Number of radial slices for a cylinder/sphere from the mesh angle limit.
static inline int _slices_from_angle(double angle) {
    double const safe = std::max(angle, 0.001);
    return std::max(4, static_cast<int>(std::round(Math_PI / safe)) + 2);
}

// ---------------------------------------------------------------------------
// Low-resolution unit cylinder mesh (Y-up, radius 1, height 1)
// ---------------------------------------------------------------------------
static Ref<ArrayMesh> _make_cylinder_mesh(int slices) {
    Ref<ArrayMesh> mesh;
    mesh.instantiate();

    PackedVector3Array verts;
    PackedInt32Array    indices;
    PackedVector3Array normals;

    double const radius      = 1.0;
    double const half_height = 0.5;

    // Bottom cap centre
    int const center_bottom = verts.size();
    verts.push_back(Vector3(0, -half_height, 0));
    normals.push_back(Vector3(0, -1, 0));

    // Top cap centre
    int const center_top = verts.size();
    verts.push_back(Vector3(0, half_height, 0));
    normals.push_back(Vector3(0, 1, 0));

    // Side vertices: bottom ring, then top ring
    int const ring_bottom_start = verts.size();
    for (int i = 0; i < slices; i++) {
        double const a = 2.0 * Math_PI * i / slices;
        double const x = radius * std::cos(a);
        double const z = radius * std::sin(a);
        verts.push_back(Vector3(x, -half_height, z));
        normals.push_back(Vector3(x, 0, z).normalized());
    }
    int const ring_top_start = verts.size();
    for (int i = 0; i < slices; i++) {
        double const a = 2.0 * Math_PI * i / slices;
        double const x = radius * std::cos(a);
        double const z = radius * std::sin(a);
        verts.push_back(Vector3(x, half_height, z));
        normals.push_back(Vector3(x, 0, z).normalized());
    }

    // Bottom cap (fan)
    for (int i = 0; i < slices; i++) {
        int const next = (i + 1) % slices;
        indices.push_back(center_bottom);
        indices.push_back(ring_bottom_start + next);
        indices.push_back(ring_bottom_start + i);
    }
    // Top cap (fan)
    for (int i = 0; i < slices; i++) {
        int const next = (i + 1) % slices;
        indices.push_back(center_top);
        indices.push_back(ring_top_start + i);
        indices.push_back(ring_top_start + next);
    }
    // Side quads → two triangles each
    for (int i = 0; i < slices; i++) {
        int const next = (i + 1) % slices;
        int const b0   = ring_bottom_start + i;
        int const b1   = ring_bottom_start + next;
        int const t0   = ring_top_start + i;
        int const t1   = ring_top_start + next;
        indices.push_back(b0);
        indices.push_back(b1);
        indices.push_back(t0);
        indices.push_back(t1);
        indices.push_back(t0);
        indices.push_back(b1);
    }

    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = verts;
    arrays[Mesh::ARRAY_NORMAL] = normals;
    arrays[Mesh::ARRAY_INDEX]  = indices;

    mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    return mesh;
}

// ---------------------------------------------------------------------------
// Low-resolution unit sphere mesh (centred at origin, radius 1)
// ---------------------------------------------------------------------------
static Ref<ArrayMesh> _make_sphere_mesh(int slices) {
    Ref<ArrayMesh> mesh;
    mesh.instantiate();

    int stacks = std::max(3, slices / 2);
    if (slices < 4) slices = 4;

    PackedVector3Array verts;
    PackedInt32Array    indices;
    PackedVector3Array normals;

    // Top pole
    int const top_idx = verts.size();
    verts.push_back(Vector3(0, 1, 0));
    normals.push_back(Vector3(0, 1, 0));

    // Intermediate rings
    for (int j = 1; j < stacks; j++) {
        double const phi = Math_PI * j / stacks;
        for (int i = 0; i < slices; i++) {
            double const theta = 2.0 * Math_PI * i / slices;
            double const x     = std::sin(phi) * std::cos(theta);
            double const y     = std::cos(phi);
            double const z     = std::sin(phi) * std::sin(theta);
            verts.push_back(Vector3(x, y, z));
            normals.push_back(Vector3(x, y, z));
        }
    }

    // Bottom pole
    int const bottom_idx = verts.size();
    verts.push_back(Vector3(0, -1, 0));
    normals.push_back(Vector3(0, -1, 0));

    // Top cap
    for (int i = 0; i < slices; i++) {
        int const next = (i + 1) % slices;
        indices.push_back(top_idx);
        indices.push_back(1 + next);
        indices.push_back(1 + i);
    }
    // Body
    for (int j = 0; j < stacks - 2; j++) {
        for (int i = 0; i < slices; i++) {
            int const next = (i + 1) % slices;
            int const a    = 1 + j * slices + i;
            int const b    = 1 + j * slices + next;
            int const c    = 1 + (j + 1) * slices + i;
            int const d    = 1 + (j + 1) * slices + next;
            indices.push_back(a);
            indices.push_back(b);
            indices.push_back(c);
            indices.push_back(d);
            indices.push_back(c);
            indices.push_back(b);
        }
    }
    // Bottom cap
    int const last_ring_start = 1 + (stacks - 2) * slices;
    for (int i = 0; i < slices; i++) {
        int const next = (i + 1) % slices;
        indices.push_back(bottom_idx);
        indices.push_back(last_ring_start + i);
        indices.push_back(last_ring_start + next);
    }

    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = verts;
    arrays[Mesh::ARRAY_NORMAL] = normals;
    arrays[Mesh::ARRAY_INDEX]  = indices;

    mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    return mesh;
}

// ===========================================================================
// REVERSED-face detection
// ===========================================================================

/// Returns true when the face's triangulation has CW winding in 3D (i.e. the
/// geometric normal from e1×e2 points inward), which occurs for faces whose
/// TopAbs_Orientation is REVERSED.
///
/// Detection strategy (in order of reliability):
///   1. Compare geometric winding normal against per-vertex normals from
///      Poly_Triangulation (these are adjusted for face orientation and
///      always point outward).
///   2. Fall back to evaluating dS/du × dS/dv at the UV centre of the face
///      via occtl_topo_face_eval_d1.
static bool _is_face_reversed(occtl_graph_t*          graph,
                              occtl_node_id_t          fid,
                              std::vector<Vector3> const& verts,
                              std::vector<int>    const& indices,
                              std::vector<Vector3> const& normals_c)
{
    // --- 1. Compute geometric normal from the raw (possibly-CW) winding ---
    gp_Vec geo_n(0, 0, 0);
    size_t const nt = indices.size() / 3;
    for (size_t i = 0; i < nt; i++) {
        int const i0 = indices[3 * i];
        int const i1 = indices[3 * i + 1];
        int const i2 = indices[3 * i + 2];

        gp_Vec const e1(gp_Pnt(verts[i1].x, verts[i1].y, verts[i1].z),
                        gp_Pnt(verts[i0].x, verts[i0].y, verts[i0].z));
        gp_Vec const e2(gp_Pnt(verts[i2].x, verts[i2].y, verts[i2].z),
                        gp_Pnt(verts[i0].x, verts[i0].y, verts[i0].z));
        gp_Vec const n = e1.Crossed(e2);
        double const len = n.Magnitude();
        if (len > 1e-30) geo_n += n.Normalized();
    }
    {
        double const glen = geo_n.Magnitude();
        if (glen < 1e-30) return false;   // degenerate — assume FORWARD
        geo_n.Normalize();
    }

    // --- 2. Reference from per-vertex normals (most reliable) ---
    if (!normals_c.empty()) {
        gp_Vec ref(0, 0, 0);
        for (auto const& vn : normals_c)
            ref += gp_Vec(vn.x, vn.y, vn.z);
        double const rlen = ref.Magnitude();
        if (rlen > 1e-30) {
            ref.Normalize();
            return ref.Dot(geo_n) < 0;
        }
    }

    // --- 3. Fallback: evaluate dS/du × dS/dv at UV centre ---
    {
        double u_min, u_max, v_min, v_max;
        occtl_status_t s = occtl_topo_face_uv_bounds(graph, fid,
                                                      &u_min, &u_max,
                                                      &v_min, &v_max);
        if (s == OCCTL_OK) {
            double const u = 0.5 * (u_min + u_max);
            double const v = 0.5 * (v_min + v_max);
            occtl_point3_t   pt;
            occtl_vector3_t  du, dv;
            s = occtl_topo_face_eval_d1(graph, fid, u, v, &pt, &du, &dv);
            if (s == OCCTL_OK) {
                gp_Vec const surf_n = gp_Vec(du.x, du.y, du.z)
                                    .Crossed(gp_Vec(dv.x, dv.y, dv.z));
                double const slen = surf_n.Magnitude();
                if (slen > 1e-30)
                    return surf_n.Normalized().Dot(geo_n) < 0;
            }
        }
    }

    return false;   // could not determine — assume FORWARD
}

// ===========================================================================
// mesh_faces
// ===========================================================================

Ref<ArrayMesh> OclGodotMesher::mesh_faces(
    const Ref<OclGraphHandle>& graph,
    const Variant&             existing,
    const Ref<OclMeshOptions>& options,
    const Variant&             face_ids,
    bool                       include_normals,
    bool                       include_uvs,
    bool                       include_tangents,
    bool                       include_feature_ids)
{
    // ----- Handle reuse of PhysicsBody3D or ArrayMesh -------------------
    PhysicsBody3D* existing_body = nullptr;
    if (existing.get_type() == Variant::OBJECT) {
        existing_body = Object::cast_to<PhysicsBody3D>(
            existing.operator godot::Object*());
    }
    Ref<ArrayMesh> out_mesh;
    if (existing_body) {
        _clear_physics_children(existing_body);
    } else if (existing.get_type() == Variant::OBJECT) {
        auto* mesh_obj = Object::cast_to<ArrayMesh>(
            existing.operator godot::Object*());
        if (mesh_obj) {
            out_mesh = Ref<ArrayMesh>(mesh_obj);
            out_mesh->clear_surfaces();
        }
    }
    if (out_mesh.is_null()) out_mesh.instantiate();

    if (graph.is_null() || !graph->_handle) return out_mesh;

    // ----- Options ------------------------------------------------------
    occtl_mesh_options_t opts = OCCTL_MESH_OPTIONS_INIT;
    if (options.is_valid()) opts = options->to_c();
    double const deflection = opts.deflection;
    double const angle      = opts.angle;

    // ----- Resolve face IDs ---------------------------------------------
    std::vector<occtl_node_id_t> ids_vec;
    if (face_ids.get_type() == Variant::PACKED_INT64_ARRAY) {
        PackedInt64Array arr = face_ids;
        ids_vec.reserve(arr.size());
        for (int i = 0; i < arr.size(); i++) {
            occtl_node_id_t nid;
            nid.bits = static_cast<uint64_t>(arr[i] < 0 ? -arr[i] : arr[i]);
            ids_vec.push_back(nid);
        }
    } else if (face_ids.get_type() != Variant::NIL) {
        return out_mesh;
    }

    // ----- Generate mesh ------------------------------------------------
    {
        occtl_status_t st = _ensure_mesh_generated(
            graph->_handle, deflection, angle);
        if (st != OCCTL_OK) return out_mesh;
    }

    // ----- Iterate all faces if no explicit IDs -------------------------
    if (ids_vec.empty()) {
        occtl_node_iter_t* iter = nullptr;
        occtl_status_t st = occtl_graph_face_iter_create(
            graph->_handle, &iter);
        if (st != OCCTL_OK || !iter) return out_mesh;

        occtl_node_id_t fid;
        while (occtl_node_iter_next(iter, &fid) == OCCTL_OK)
            ids_vec.push_back(fid);
        occtl_node_iter_free(iter);
    }
    if (ids_vec.empty()) return out_mesh;

    // ----- Per-face triangulation data ----------------------------------
    struct TriFaceData {
        occtl_node_id_t    face_id;
        std::vector<Vector3> verts;      // local vertices
        std::vector<Vector2> uvs;        // local UVs (may be empty)
        std::vector<Vector3> normals_c;  // per-vertex normals (may be empty)
        std::vector<int>     indices;    // 0-based, 3 per triangle
        Vector3              face_normal; // geometric outward normal
    };

    std::vector<TriFaceData> face_data;
    face_data.reserve(ids_vec.size());
    int total_verts = 0;
    int total_tris  = 0;

    for (auto fid : ids_vec) {
        occtl_triangulation_view_t tv;
        occtl_status_t st = occtl_mesh_face_triangulation(
            graph->_handle, fid, &tv);
        if (st != OCCTL_OK) continue;

        size_t const nv = tv.node_count;
        size_t const nt = tv.triangle_count;
        if (nv == 0 || nt == 0) continue;

        TriFaceData fd;
        fd.face_id = fid;

        // Vertices
        fd.verts.reserve(nv);
        for (size_t i = 0; i < nv; i++)
            fd.verts.emplace_back(tv.nodes[3 * i],
                                  tv.nodes[3 * i + 1],
                                  tv.nodes[3 * i + 2]);

        // Triangles (clamp out-of-range indices)
        fd.indices.reserve(3 * nt);
        for (size_t i = 0; i < 3 * nt; i++) {
            uint32_t idx = tv.triangles[i];
            if (idx >= nv) idx = 0;
            fd.indices.push_back(static_cast<int>(idx));
        }

        // UVs
        if (tv.uvs && include_uvs) {
            fd.uvs.reserve(nv);
            for (size_t i = 0; i < nv; i++)
                fd.uvs.emplace_back(tv.uvs[2 * i], tv.uvs[2 * i + 1]);
        }

        // Per-vertex normals (already outward-pointing from BRepMesh)
        if (tv.normals) {
            fd.normals_c.reserve(nv);
            for (size_t i = 0; i < nv; i++)
                fd.normals_c.emplace_back(tv.normals[3 * i],
                                          tv.normals[3 * i + 1],
                                          tv.normals[3 * i + 2]);
        }

        // ----- REVERSED-face correction --------------------------------
        //
        // BRepMesh stores triangle indices CCW in UV parameter space.
        // For a REVERSED face this produces CW winding in 3D (geometric
        // cross product points inward).  Per-vertex normals ARE already
        // adjusted for face orientation (outward-pointing).
        //
        // Correction: flip indices 1↔2 to restore CCW/outward winding.
        // Per-vertex normals are NOT negated — they are already correct.
        if (_is_face_reversed(graph->_handle, fid,
                              fd.verts, fd.indices, fd.normals_c))
        {
            for (size_t i = 0; i < nt; i++)
                std::swap(fd.indices[3 * i + 1], fd.indices[3 * i + 2]);
        }

        // Compute face-normal from the (now-corrected) winding
        {
            gp_Vec avg(0, 0, 0);
            for (size_t i = 0; i < nt; i++) {
                int const i0 = fd.indices[3 * i];
                int const i1 = fd.indices[3 * i + 1];
                int const i2 = fd.indices[3 * i + 2];
                gp_Vec const e1(
                    gp_Pnt(fd.verts[i1].x, fd.verts[i1].y, fd.verts[i1].z),
                    gp_Pnt(fd.verts[i0].x, fd.verts[i0].y, fd.verts[i0].z));
                gp_Vec const e2(
                    gp_Pnt(fd.verts[i2].x, fd.verts[i2].y, fd.verts[i2].z),
                    gp_Pnt(fd.verts[i0].x, fd.verts[i0].y, fd.verts[i0].z));
                gp_Vec n = e1.Crossed(e2);
                double const len = n.Magnitude();
                if (len > 1e-30) avg += n.Normalized();
            }
            double const alen = avg.Magnitude();
            fd.face_normal = (alen > 1e-30)
                ? Vector3(avg.X() / alen, avg.Y() / alen, avg.Z() / alen)
                : Vector3(0, 0, 1);
        }

        total_verts += static_cast<int>(nv);
        total_tris  += static_cast<int>(nt);
        face_data.push_back(std::move(fd));
    }

    if (face_data.empty()) return out_mesh;

    // ----- PhysicsBody3D path: collision shapes per face ----------------
    if (existing_body) {
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

            existing_body->add_child(cs, true);
            cs->set_owner(
                existing_body->get_owner()
                    ? existing_body->get_owner()
                    : existing_body);
        }
        return Ref<ArrayMesh>();   // caller recognises null as "done"
    }

    // ----- ArrayMesh path -----------------------------------------------

    // Assemble all faces into one surface.  When per-vertex attributes
    // are NOT requested we can deduplicate vertices by position across
    // faces (smaller mesh).  When attributes ARE requested we keep each
    // face's vertices separate because different faces may have different
    // normals/UVs/tangents at the same 3D position.

    PackedVector3Array out_verts;
    PackedInt32Array   out_indices;
    PackedVector3Array out_normals;
    PackedVector2Array out_uvs;
    PackedColorArray   out_colors;
    PackedFloat32Array out_tangents;

    bool const have_attrs = include_normals || include_uvs
                         || include_tangents || include_feature_ids;

    if (!have_attrs) {
        // ----- Simple path: deduplicate by position --------------------
        std::unordered_map<uint64_t, int> pos_map;
        auto pos_hash = [](Vector3 const& v) -> uint64_t {
            uint64_t hx, hy, hz;
            memcpy(&hx, &v.x, sizeof(v.x)); hx >>= 4;
            memcpy(&hy, &v.y, sizeof(v.y)); hy >>= 4;
            memcpy(&hz, &v.z, sizeof(v.z)); hz >>= 4;
            return hx ^ (hy << 20) ^ (hz << 40);
        };

        for (const auto& fd : face_data) {
            for (size_t i = 0; i < fd.indices.size(); i += 3) {
                int tri[3] = { fd.indices[i], fd.indices[i + 1],
                               fd.indices[i + 2] };
                for (int j = 0; j < 3; j++) {
                    int const local_idx = tri[j];
                    Vector3 const& pos = fd.verts[local_idx];
                    uint64_t const key = pos_hash(pos);
                    auto it = pos_map.find(key);
                    if (it != pos_map.end() &&
                        (out_verts[it->second] - pos).length_squared() < 1e-20)
                    {
                        out_indices.push_back(it->second);
                        continue;
                    }
                    int const new_idx = out_verts.size();
                    out_verts.push_back(pos);
                    out_indices.push_back(new_idx);
                    pos_map[key] = new_idx;
                }
            }
        }
    } else {
        // ----- Attribute path: keep per-face vertices separate ---------
        int const estimated_verts = total_verts;
        int const estimated_tris  = total_tris;
        out_verts.resize(estimated_verts);
        out_indices.resize(3 * estimated_tris);

        // Map each face's local vertex index → global output index
        std::vector<std::vector<int>> face_vert_map(face_data.size());

        int voff = 0, ioff = 0;
        for (size_t fi = 0; fi < face_data.size(); fi++) {
            auto const& fd     = face_data[fi];
            face_vert_map[fi].resize(fd.verts.size(), -1);

            for (size_t i = 0; i < fd.verts.size(); i++) {
                out_verts[voff] = fd.verts[i];
                face_vert_map[fi][i] = voff++;
            }
            for (size_t i = 0; i < fd.indices.size(); i += 3) {
                out_indices[ioff++] = face_vert_map[fi][fd.indices[i]];
                out_indices[ioff++] = face_vert_map[fi][fd.indices[i + 1]];
                out_indices[ioff++] = face_vert_map[fi][fd.indices[i + 2]];
            }
        }
        out_verts.resize(voff);
        out_indices.resize(ioff);

        // ----- Normals ------------------------------------------------
        //
        // Use per-vertex normals from Poly_Triangulation (already
        // outward-pointing and smooth) when available.  Fall back to
        // the face geometric normal (flat-shading) otherwise.
        if (include_normals) {
            out_normals.resize(out_verts.size());
            for (size_t fi = 0; fi < face_data.size(); fi++) {
                auto const& fd = face_data[fi];
                for (size_t vi = 0; vi < fd.verts.size(); vi++) {
                    int const gv = face_vert_map[fi][vi];
                    if (vi < fd.normals_c.size()) {
                        out_normals[gv] = fd.normals_c[vi];
                    } else {
                        out_normals[gv] = fd.face_normal;
                    }
                }
            }
        }

        // ----- UVs ----------------------------------------------------
        if (include_uvs) {
            out_uvs.resize(out_verts.size());
            for (size_t fi = 0; fi < face_data.size(); fi++) {
                auto const& fd = face_data[fi];
                if (fd.uvs.empty()) continue;
                for (size_t vi = 0; vi < fd.verts.size(); vi++) {
                    int const gv = face_vert_map[fi][vi];
                    if (vi < fd.uvs.size())
                        out_uvs[gv] = fd.uvs[vi];
                }
            }
        }

        // ----- Tangents -----------------------------------------------
        if (include_tangents && include_normals && include_uvs) {
            out_tangents.resize(out_verts.size() * 4);
            std::fill(out_tangents.begin(), out_tangents.end(), 0.0f);
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

                    double const r = 1.0 / (duv1.x * duv2.y
                                          - duv2.x * duv1.y + 1e-20);
                    Vector3 const tangent =
                        (e1 * duv2.y - e2 * duv1.y) * r;

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
                t = (t - n * n.dot(t)).normalized();

                out_tangents[base]     = static_cast<float>(t.x);
                out_tangents[base + 1] = static_cast<float>(t.y);
                out_tangents[base + 2] = static_cast<float>(t.z);

                Vector3 const bitangent = n.cross(t.normalized());
                Vector3 const accum(out_tangents[base],
                                    out_tangents[base + 1],
                                    out_tangents[base + 2]);
                out_tangents[base + 3] =
                    (bitangent.dot(accum) >= 0) ? 1.0f : -1.0f;
            }
        }

        // ----- Feature-ID colours --------------------------------------
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
        }
    }

    // ----- Build surface arrays -----------------------------------------
    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = out_verts;
    arrays[Mesh::ARRAY_INDEX]  = out_indices;

    if (!out_normals.is_empty())
        arrays[Mesh::ARRAY_NORMAL] = out_normals;
    if (!out_uvs.is_empty())
        arrays[Mesh::ARRAY_TEX_UV] = out_uvs;
    if (!out_tangents.is_empty())
        arrays[Mesh::ARRAY_TANGENT] = out_tangents;
    if (!out_colors.is_empty())
        arrays[Mesh::ARRAY_COLOR] = out_colors;

    out_mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    return out_mesh;
}

// ===========================================================================
// mesh_edges
// ===========================================================================

Ref<MultiMesh> OclGodotMesher::mesh_edges(
    const Ref<OclGraphHandle>& graph,
    const Variant&             existing,
    const Ref<OclMeshOptions>& options,
    const Variant&             edge_ids,
    double                     radius)
{
    // ----- Handle PhysicsBody3D or MultiMesh reuse ---------------------
    PhysicsBody3D* existing_body = nullptr;
    if (existing.get_type() == Variant::OBJECT) {
        existing_body = Object::cast_to<PhysicsBody3D>(
            existing.operator godot::Object*());
    }
    Ref<MultiMesh> out_mm;
    if (existing_body) {
        _clear_physics_children(existing_body);
    } else if (existing.get_type() == Variant::OBJECT) {
        auto* mm_obj = Object::cast_to<MultiMesh>(
            existing.operator godot::Object*());
        if (mm_obj) {
            out_mm = Ref<MultiMesh>(mm_obj);
            out_mm->set_instance_count(0);
            out_mm->set_transform_format(MultiMesh::TRANSFORM_3D);
            out_mm->set_mesh(Ref<ArrayMesh>());
        }
    }
    if (out_mm.is_null()) out_mm.instantiate();

    if (graph.is_null() || !graph->_handle) return out_mm;

    // ----- Options ------------------------------------------------------
    occtl_mesh_options_t opts = OCCTL_MESH_OPTIONS_INIT;
    if (options.is_valid()) opts = options->to_c();
    double const angle      = opts.angle;
    double const deflection = opts.deflection;

    double eff_radius = radius;
    if (eff_radius <= 0.0) eff_radius = deflection * 10.0;

    // ----- Resolve edge IDs --------------------------------------------
    std::vector<occtl_node_id_t> ids_vec;
    if (edge_ids.get_type() == Variant::PACKED_INT64_ARRAY) {
        PackedInt64Array arr = edge_ids;
        ids_vec.reserve(arr.size());
        for (int64_t id : arr) {
            occtl_node_id_t nid;
            nid.bits = static_cast<uint64_t>(id);
            ids_vec.push_back(nid);
        }
    } else if (edge_ids.get_type() != Variant::NIL) {
        return out_mm;
    }

    if (ids_vec.empty()) {
        occtl_node_iter_t* iter = nullptr;
        occtl_status_t st = occtl_graph_edge_iter_create(
            graph->_handle, &iter);
        if (st != OCCTL_OK || !iter) return out_mm;
        occtl_node_id_t eid;
        while (occtl_node_iter_next(iter, &eid) == OCCTL_OK)
            ids_vec.push_back(eid);
        occtl_node_iter_free(iter);
    }
    if (ids_vec.empty()) return out_mm;

    // ----- Generate mesh (caches edge 3D polygons) ---------------------
    {
        occtl_mesh_options_t gen_opts = OCCTL_MESH_OPTIONS_INIT;
        gen_opts.deflection = deflection;
        gen_opts.angle     = angle;
        gen_opts.clean_model = 1;
        occtl_status_t st = occtl_mesh_generate(
            graph->_handle, nullptr, 0, &gen_opts);
        if (st != OCCTL_OK) return out_mm;
    }

    // ----- Build cylinder mesh -----------------------------------------
    int const slices = _slices_from_angle(angle);
    Ref<ArrayMesh> cyl_mesh = _make_cylinder_mesh(slices);

    double const bbox_diag  = _get_graph_bbox_diag(graph->_handle);
    eff_radius *= bbox_diag;

    // ----- Build edge-coedge-face map ----------------------------------
    std::unordered_map<uint64_t,
        std::pair<occtl_node_id_t, occtl_node_id_t>> edge_coedge_map;
    {
        occtl_node_iter_t* coedge_iter = nullptr;
        occtl_status_t st = occtl_graph_coedge_iter_create(
            graph->_handle, &coedge_iter);
        if (st == OCCTL_OK && coedge_iter) {
            occtl_node_id_t cid;
            while (occtl_node_iter_next(coedge_iter, &cid) == OCCTL_OK) {
                occtl_topo_related_iter_t* rel = nullptr;
                if (occtl_topo_related_iter_create(graph->_handle, cid, &rel)
                        != OCCTL_OK || !rel) continue;

                occtl_node_id_t parent_edge{};
                occtl_node_id_t owning_face{};
                occtl_node_id_t rn;
                occtl_relation_kind_t rk;
                while (occtl_topo_related_iter_next(rel, &rn, &rk) == OCCTL_OK)
                {
                    if (rk == OCCTL_RELATION_PARENT_EDGE)
                        parent_edge = rn;
                    else if (rk == OCCTL_RELATION_OWNING_FACE)
                        owning_face = rn;
                }
                occtl_topo_related_iter_free(rel);

                if (parent_edge.bits != 0)
                    edge_coedge_map.emplace(parent_edge.bits,
                        std::make_pair(cid, owning_face));
            }
            occtl_node_iter_free(coedge_iter);
        }
    }

    // ----- Collect segment transforms and collision shapes --------------
    std::vector<Transform3D> xforms;

    auto _add_segment = [&](gp_Pnt const& p0, gp_Pnt const& p1,
                            occtl_node_id_t eid, uint64_t seg_idx)
    {
        gp_Vec dir(p0, p1);
        double const seg_len = dir.Magnitude();
        if (seg_len < 1e-15) return;
        dir.Normalize();

        gp_XYZ const mid = 0.5 * (p0.XYZ() + p1.XYZ());

        gp_Vec const y_axis = dir;
        gp_Vec up(0, 1, 0);
        if (std::abs(y_axis.Y()) > 0.9)
            up = gp_Vec(1, 0, 0);

        gp_Vec const x_axis = up.Crossed(y_axis).Normalized();
        gp_Vec const z_axis = x_axis.Crossed(y_axis).Normalized();

        Basis basis(Vector3(x_axis.X(), x_axis.Y(), x_axis.Z()),
                     Vector3(y_axis.X(), y_axis.Y(), y_axis.Z()),
                     Vector3(z_axis.X(), z_axis.Y(), z_axis.Z()));
        Transform3D xf(basis,
                       Vector3(mid.X(), mid.Y(), mid.Z()));
        xf = xf.scaled_local(Vector3(eff_radius, seg_len, eff_radius));
        xforms.push_back(xf);

        if (existing_body) {
            Ref<CapsuleShape3D> cshape;
            cshape.instantiate();
            cshape->set_radius(eff_radius);
            cshape->set_height(std::max(0.0, seg_len - 2.0 * eff_radius));

            CollisionShape3D* cs = memnew(CollisionShape3D);
            cs->set_shape(cshape);
            cs->set_position(Vector3(mid.X(), mid.Y(), mid.Z()));
            cs->set_basis(basis);
            cs->set_name(String("_occtl_edge_")
                         + String::num_uint64(eid.bits)
                         + "_" + String::num_uint64(seg_idx));

            Dictionary meta;
            meta["feature_id"] = static_cast<int64_t>(eid.bits);
            cs->set_meta("occtl", meta);

            existing_body->add_child(cs, true);
            cs->set_owner(
                existing_body->get_owner()
                    ? existing_body->get_owner()
                    : existing_body);
        }
    };

    for (auto eid : ids_vec) {
        std::vector<gp_Pnt> edge_pts;

        // Strategy 1 — free edge 3D polygon
        {
            occtl_polygon3d_view_t pv;
            occtl_status_t st = occtl_mesh_edge_polygon3d(
                graph->_handle, eid, &pv);
            if (st == OCCTL_OK && pv.node_count >= 2) {
                edge_pts.reserve(pv.node_count);
                for (size_t i = 0; i < pv.node_count; i++)
                    edge_pts.emplace_back(pv.nodes[3 * i],
                                          pv.nodes[3 * i + 1],
                                          pv.nodes[3 * i + 2]);
            }
        }

        // Strategy 2 — face-owned edge via coedge polygon-on-triangulation
        if (edge_pts.size() < 2) {
            auto it = edge_coedge_map.find(eid.bits);
            if (it != edge_coedge_map.end()) {
                auto [coedge_id, face_id] = it->second;
                occtl_polygon_on_tri_view_t potv;
                occtl_status_t ps = occtl_mesh_coedge_polygon_on_tri(
                    graph->_handle, coedge_id, &potv);
                if (ps == OCCTL_OK && potv.node_count >= 2) {
                    occtl_triangulation_view_t tv;
                    occtl_status_t ts = occtl_mesh_face_triangulation(
                        graph->_handle, face_id, &tv);
                    if (ts == OCCTL_OK && tv.node_count > 0) {
                        edge_pts.reserve(potv.node_count);
                        for (size_t j = 0; j < potv.node_count; j++) {
                            uint32_t idx = potv.node_indices[j];
                            if (idx < tv.node_count)
                                edge_pts.emplace_back(
                                    tv.nodes[3 * idx],
                                    tv.nodes[3 * idx + 1],
                                    tv.nodes[3 * idx + 2]);
                        }
                    }
                }
            }
        }

        // Strategy 3 — sample edge's 3D curve directly
        if (edge_pts.size() < 2) {
            int32_t has_curve = 0;
            if (occtl_topo_edge_has_curve(graph->_handle, eid, &has_curve)
                    == OCCTL_OK && has_curve)
            {
                double u_first = 0.0, u_last = 0.0;
                if (occtl_topo_edge_range(graph->_handle, eid,
                                          &u_first, &u_last) == OCCTL_OK
                    && u_last > u_first)
                {
                    occtl_point3_t pt;
                    edge_pts.reserve(4);
                    if (occtl_topo_edge_eval(graph->_handle, eid,
                                             u_first, &pt) == OCCTL_OK)
                        edge_pts.emplace_back(pt.x, pt.y, pt.z);

                    double const u_range = u_last - u_first;
                    occtl_vector3_t d1_mid;
                    int mid_samples = 0;
                    if (occtl_topo_edge_eval_d1(graph->_handle, eid,
                            (u_first + u_last) * 0.5, &pt, &d1_mid) == OCCTL_OK)
                    {
                        double const tan_len = std::sqrt(
                            d1_mid.x * d1_mid.x
                            + d1_mid.y * d1_mid.y
                            + d1_mid.z * d1_mid.z);
                        double const est_arc = tan_len * u_range;
                        if (est_arc > deflection * 2.0)
                            mid_samples = std::min(64,
                                std::max(1, static_cast<int>(
                                    std::ceil(est_arc / deflection))));
                    }
                    for (int k = 1; k < mid_samples; ++k) {
                        double u = u_first + u_range * k / mid_samples;
                        if (occtl_topo_edge_eval(graph->_handle, eid,
                                                 u, &pt) == OCCTL_OK)
                            edge_pts.emplace_back(pt.x, pt.y, pt.z);
                    }
                    if (occtl_topo_edge_eval(graph->_handle, eid,
                                             u_last, &pt) == OCCTL_OK)
                        edge_pts.emplace_back(pt.x, pt.y, pt.z);
                }
            }
        }

        if (edge_pts.size() < 2) continue;

        for (size_t i = 0; i + 1 < edge_pts.size(); i++)
            _add_segment(edge_pts[i], edge_pts[i + 1], eid,
                         static_cast<uint64_t>(i));
    }

    if (existing_body) return Ref<MultiMesh>();

    // ----- Set up MultiMesh --------------------------------------------
    out_mm->set_transform_format(MultiMesh::TRANSFORM_3D);
    out_mm->set_instance_count(static_cast<int>(xforms.size()));
    out_mm->set_mesh(cyl_mesh);
    for (int i = 0; i < static_cast<int>(xforms.size()); i++)
        out_mm->set_instance_transform(i, xforms[i]);

    return out_mm;
}

// ===========================================================================
// mesh_vertices
// ===========================================================================

Ref<MultiMesh> OclGodotMesher::mesh_vertices(
    const Ref<OclGraphHandle>& graph,
    const Variant&             existing,
    const Ref<OclMeshOptions>& options,
    const Variant&             vertex_ids,
    double                     radius)
{
    // ----- Handle PhysicsBody3D or MultiMesh reuse ---------------------
    PhysicsBody3D* existing_body = nullptr;
    if (existing.get_type() == Variant::OBJECT) {
        existing_body = Object::cast_to<PhysicsBody3D>(
            existing.operator godot::Object*());
    }
    Ref<MultiMesh> out_mm;
    if (existing_body) {
        _clear_physics_children(existing_body);
    } else if (existing.get_type() == Variant::OBJECT) {
        auto* mm_obj = Object::cast_to<MultiMesh>(
            existing.operator godot::Object*());
        if (mm_obj) {
            out_mm = Ref<MultiMesh>(mm_obj);
            out_mm->set_instance_count(0);
            out_mm->set_transform_format(MultiMesh::TRANSFORM_3D);
            out_mm->set_mesh(Ref<ArrayMesh>());
        }
    }
    if (out_mm.is_null()) out_mm.instantiate();

    if (graph.is_null() || !graph->_handle) return out_mm;

    // ----- Options ------------------------------------------------------
    occtl_mesh_options_t opts = OCCTL_MESH_OPTIONS_INIT;
    if (options.is_valid()) opts = options->to_c();
    double const angle      = opts.angle;
    double const deflection = opts.deflection;

    double eff_radius = radius;
    if (eff_radius <= 0.0) eff_radius = deflection * 10.0;

    // ----- Resolve vertex IDs ------------------------------------------
    std::vector<occtl_node_id_t> ids_vec;
    if (vertex_ids.get_type() == Variant::PACKED_INT64_ARRAY) {
        PackedInt64Array arr = vertex_ids;
        ids_vec.reserve(arr.size());
        for (int64_t id : arr) {
            occtl_node_id_t nid;
            nid.bits = static_cast<uint64_t>(id);
            ids_vec.push_back(nid);
        }
    } else if (vertex_ids.get_type() != Variant::NIL) {
        return out_mm;
    }

    if (ids_vec.empty()) {
        occtl_node_iter_t* iter = nullptr;
        occtl_status_t st = occtl_graph_vertex_iter_create(
            graph->_handle, &iter);
        if (st != OCCTL_OK || !iter) return out_mm;
        occtl_node_id_t vid;
        while (occtl_node_iter_next(iter, &vid) == OCCTL_OK)
            ids_vec.push_back(vid);
        occtl_node_iter_free(iter);
    }
    if (ids_vec.empty()) return out_mm;

    // ----- Build sphere mesh -------------------------------------------
    int const slices = _slices_from_angle(angle);
    Ref<ArrayMesh> sphere_mesh = _make_sphere_mesh(slices);

    double const bbox_diag = _get_graph_bbox_diag(graph->_handle);
    eff_radius *= bbox_diag;

    // ----- Collect transforms and collision shapes ----------------------
    std::vector<Transform3D> xforms;

    for (auto vid : ids_vec) {
        occtl_point3_t pt;
        occtl_status_t st = occtl_topo_vertex_point(
            graph->_handle, vid, &pt);
        if (st != OCCTL_OK) continue;

        gp_Pnt const pos(pt.x, pt.y, pt.z);

        Transform3D xf;
        xf.origin = Vector3(pos.X(), pos.Y(), pos.Z());
        xf = xf.scaled_local(
            Vector3(eff_radius, eff_radius, eff_radius));
        xforms.push_back(xf);

        if (existing_body) {
            Ref<SphereShape3D> cshape;
            cshape.instantiate();
            cshape->set_radius(eff_radius);

            CollisionShape3D* cs = memnew(CollisionShape3D);
            cs->set_shape(cshape);
            cs->set_position(Vector3(pos.X(), pos.Y(), pos.Z()));
            cs->set_name(String("_occtl_vertex_")
                         + String::num_uint64(vid.bits));

            Dictionary meta;
            meta["feature_id"] = static_cast<int64_t>(vid.bits);
            cs->set_meta("occtl", meta);

            existing_body->add_child(cs, true);
            cs->set_owner(
                existing_body->get_owner()
                    ? existing_body->get_owner()
                    : existing_body);
        }
    }

    if (existing_body) return Ref<MultiMesh>();

    // ----- Set up MultiMesh --------------------------------------------
    out_mm->set_transform_format(MultiMesh::TRANSFORM_3D);
    out_mm->set_instance_count(static_cast<int>(xforms.size()));
    out_mm->set_mesh(sphere_mesh);
    for (int i = 0; i < static_cast<int>(xforms.size()); i++)
        out_mm->set_instance_transform(i, xforms[i]);

    return out_mm;
}
