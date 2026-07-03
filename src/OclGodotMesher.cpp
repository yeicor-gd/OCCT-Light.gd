// ---------------------------------------------------------------------------
// Hand-written source for OclGodotMesher meshing methods.
// Provides Godot-friendly batch meshing (ArrayMesh, MultiMesh,
// PhysicsBody3D collision shapes) on top of auto-generated OclGraphHandle.
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
#include <godot_cpp/classes/rendering_server.hpp>
#include <cmath>
#include <cstring>
#include <unordered_map>
#include <vector>

#include "OclMeshOptions.h"
#include "occtl/occtl_topo_relation.h"

using namespace godot;

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Get the bounding box diagonal of the entire graph for consistent sizing.
/// Returns 1.0 when the graph has no suitable geometry.
// Helper macro to try getting a representative node from an iterator.
// Declares a local iter variable.  Sets ref_node to the first element
// if the iterator can be created and yields at least one element.
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

static double _get_graph_bbox_diag(occtl_graph_t* graph) {
    occtl_node_id_t ref_node;
    occtl_node_id_t dummy;
    dummy.bits = 0;
    ref_node = dummy;

    // Try to find a representative node, preferring larger scopes.
    OCCTL_TRY_ITER(occtl_graph_compound_iter_create(graph, &_it));
    OCCTL_TRY_ITER(occtl_graph_compsolid_iter_create(graph, &_it));
    OCCTL_TRY_ITER(occtl_graph_solid_iter_create(graph, &_it));
    OCCTL_TRY_ITER(occtl_graph_shell_iter_create(graph, &_it));
    OCCTL_TRY_ITER(occtl_graph_face_iter_create(graph, &_it));
    OCCTL_TRY_ITER(occtl_graph_wire_iter_create(graph, &_it));
    OCCTL_TRY_ITER(occtl_graph_edge_iter_create(graph, &_it));
    OCCTL_TRY_ITER(occtl_graph_vertex_iter_create(graph, &_it));
    OCCTL_TRY_ITER(occtl_graph_coedge_iter_create(graph, &_it));

    if (ref_node.bits == 0) {
        return 1.0;
    }

    occtl_select_bbox_t c_bbox;
    occtl_status_t status = occtl_graph_bbox_get(graph, ref_node, &c_bbox);
    if (status != OCCTL_OK) {
        return 1.0;
    }

    Vector3 bmin(c_bbox.min.x, c_bbox.min.y, c_bbox.min.z);
    Vector3 bmax(c_bbox.max.x, c_bbox.max.y, c_bbox.max.z);
    double diag = (bmax - bmin).length();
    return (diag < 1e-15) ? 1.0 : diag;
}

/// Remove all child CollisionShape3D nodes previously created by a meshing
/// call on this PhysicsBody3D (identified by name starting with "_occtl_").
static void _clear_physics_children(PhysicsBody3D* body) {
    if (!body) return;
    std::vector<CollisionShape3D*> to_remove;
    for (int i = 0; i < body->get_child_count(); i++) {
        CollisionShape3D* cs = Object::cast_to<CollisionShape3D>(body->get_child(i));
        if (cs && String(cs->get_name()).begins_with("_occtl_")) {
            to_remove.push_back(cs);
        }
    }
    for (auto* cs : to_remove) {
        body->remove_child(cs);
        cs->queue_free();
    }
}

/// Hash combiner for std::pair<occtl_node_id_t, int> used in normal merging.
struct PairHash {
    inline std::size_t operator()(const std::pair<int64_t, int>& p) const {
        return std::hash<int64_t>{}(p.first) ^ (std::hash<int>{}(p.second) << 1);
    }
};

// ---------------------------------------------------------------------------
// _bind_methods
// ---------------------------------------------------------------------------

void OclGodotMesher::_bind_methods() {
    godot::ClassDB::bind_method(godot::D_METHOD("mesh_faces", "graph", "existing", "options", "face_ids", "include_normals", "include_uvs", "include_tangents", "include_feature_ids"), &OclGodotMesher::mesh_faces, DEFVAL(Variant()), DEFVAL(Ref<OclMeshOptions>()), DEFVAL(Variant()), DEFVAL(false), DEFVAL(false), DEFVAL(false), DEFVAL(false));
    godot::ClassDB::bind_method(godot::D_METHOD("mesh_edges", "graph", "existing", "options", "edge_ids", "radius"), &OclGodotMesher::mesh_edges, DEFVAL(Variant()), DEFVAL(Ref<OclMeshOptions>()), DEFVAL(Variant()), DEFVAL(0.01));
    godot::ClassDB::bind_method(godot::D_METHOD("mesh_vertices", "graph", "existing", "options", "vertex_ids", "radius"), &OclGodotMesher::mesh_vertices, DEFVAL(Variant()), DEFVAL(Ref<OclMeshOptions>()), DEFVAL(Variant()), DEFVAL(0.02));
}

// ---------------------------------------------------------------------------
// Mesh generation helpers
// ---------------------------------------------------------------------------

/// Ensure the graph has a triangulation matching the given deflection and angle.
static occtl_status_t _ensure_mesh_generated(
    occtl_graph_t* graph,
    double deflection,
    double angle)
{
    occtl_mesh_options_t opts = OCCTL_MESH_OPTIONS_INIT;
    opts.deflection = deflection;
    opts.angle = angle;
    opts.clean_model = 1;
    return occtl_mesh_generate(graph, nullptr, 0, &opts);
}

/// Compute the number of radial slices from an angle limit.
static inline int _slices_from_angle(double angle) {
    double safe_angle = std::max(angle, 0.001);
    return std::max(4, static_cast<int>(std::round(Math_PI / safe_angle)) + 2);
}

/// Build a low-resolution unit cylinder mesh (Y-up) with the given number of slices.
static Ref<ArrayMesh> _make_cylinder_mesh(int slices) {
    Ref<ArrayMesh> mesh;
    mesh.instantiate();

    PackedVector3Array verts;
    PackedInt32Array indices;
    PackedVector3Array normals;

    // Cylinder around Y axis with radius 1, height 1
    const double radius = 1.0;
    const double half_height = 0.5;

    // Bottom cap center
    int center_bottom = verts.size();
    verts.push_back(Vector3(0, -half_height, 0));
    normals.push_back(Vector3(0, -1, 0));

    // Top cap center
    int center_top = verts.size();
    verts.push_back(Vector3(0, half_height, 0));
    normals.push_back(Vector3(0, 1, 0));

    // Side vertices: bottom ring, then top ring
    int ring_bottom_start = verts.size();
    for (int i = 0; i < slices; i++) {
        double a = 2.0 * Math_PI * i / slices;
        double x = radius * std::cos(a);
        double z = radius * std::sin(a);
        verts.push_back(Vector3(x, -half_height, z));
        normals.push_back(Vector3(x, 0, z).normalized());
    }
    int ring_top_start = verts.size();
    for (int i = 0; i < slices; i++) {
        double a = 2.0 * Math_PI * i / slices;
        double x = radius * std::cos(a);
        double z = radius * std::sin(a);
        verts.push_back(Vector3(x, half_height, z));
        normals.push_back(Vector3(x, 0, z).normalized());
    }

    // Bottom cap triangles (fan)
    for (int i = 0; i < slices; i++) {
        int next = (i + 1) % slices;
        indices.push_back(center_bottom);
        indices.push_back(ring_bottom_start + next);
        indices.push_back(ring_bottom_start + i);
    }

    // Top cap triangles (fan)
    for (int i = 0; i < slices; i++) {
        int next = (i + 1) % slices;
        indices.push_back(center_top);
        indices.push_back(ring_top_start + i);
        indices.push_back(ring_top_start + next);
    }

    // Side quads as two triangles each
    for (int i = 0; i < slices; i++) {
        int next = (i + 1) % slices;
        int b0 = ring_bottom_start + i;
        int b1 = ring_bottom_start + next;
        int t0 = ring_top_start + i;
        int t1 = ring_top_start + next;
        // Triangle 1
        indices.push_back(b0);
        indices.push_back(b1);
        indices.push_back(t0);
        // Triangle 2
        indices.push_back(t1);
        indices.push_back(t0);
        indices.push_back(b1);
    }

    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = verts;
    arrays[Mesh::ARRAY_NORMAL] = normals;
    arrays[Mesh::ARRAY_INDEX] = indices;

    mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    return mesh;
}

/// Build a low-resolution unit sphere mesh (centered at origin) with the given number of slices.
static Ref<ArrayMesh> _make_sphere_mesh(int slices) {
    Ref<ArrayMesh> mesh;
    mesh.instantiate();

    int stacks = std::max(3, slices / 2);
    if (slices < 4) slices = 4;

    PackedVector3Array verts;
    PackedInt32Array indices;
    PackedVector3Array normals;

    // Top pole
    int top_idx = verts.size();
    verts.push_back(Vector3(0, 1, 0));
    normals.push_back(Vector3(0, 1, 0));

    // Intermediate rings
    for (int j = 1; j < stacks; j++) {
        double phi = Math_PI * j / stacks;
        for (int i = 0; i < slices; i++) {
            double theta = 2.0 * Math_PI * i / slices;
            double x = std::sin(phi) * std::cos(theta);
            double y = std::cos(phi);
            double z = std::sin(phi) * std::sin(theta);
            verts.push_back(Vector3(x, y, z));
            normals.push_back(Vector3(x, y, z));
        }
    }

    // Bottom pole
    int bottom_idx = verts.size();
    verts.push_back(Vector3(0, -1, 0));
    normals.push_back(Vector3(0, -1, 0));

    // Top cap triangles
    for (int i = 0; i < slices; i++) {
        int next = (i + 1) % slices;
        indices.push_back(top_idx);
        indices.push_back(1 + next);  // first ring, next vertex
        indices.push_back(1 + i);      // first ring, current vertex
    }

    // Body triangles
    for (int j = 0; j < stacks - 2; j++) {
        for (int i = 0; i < slices; i++) {
            int next = (i + 1) % slices;
            int a = 1 + j * slices + i;
            int b = 1 + j * slices + next;
            int c = 1 + (j + 1) * slices + i;
            int d = 1 + (j + 1) * slices + next;
            indices.push_back(a);
            indices.push_back(b);
            indices.push_back(c);
            indices.push_back(d);
            indices.push_back(c);
            indices.push_back(b);
        }
    }

    // Bottom cap triangles
    int last_ring_start = 1 + (stacks - 2) * slices;
    for (int i = 0; i < slices; i++) {
        int next = (i + 1) % slices;
        indices.push_back(bottom_idx);
        indices.push_back(last_ring_start + i);
        indices.push_back(last_ring_start + next);
    }

    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = verts;
    arrays[Mesh::ARRAY_NORMAL] = normals;
    arrays[Mesh::ARRAY_INDEX] = indices;

    mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    return mesh;
}

// ---------------------------------------------------------------------------
// mesh_faces
// ---------------------------------------------------------------------------

Ref<ArrayMesh> OclGodotMesher::mesh_faces(
    const Ref<OclGraphHandle>& graph,
    const Variant& existing,
    const Ref<OclMeshOptions>& options,
    const Variant& face_ids,
    bool include_normals,
    bool include_uvs,
    bool include_tangents,
    bool include_feature_ids)
{
    // Check if existing is a PhysicsBody3D (→ collision shapes) or ArrayMesh
    PhysicsBody3D* existing_body = nullptr;
    if (existing.get_type() == Variant::OBJECT) {
        existing_body = Object::cast_to<PhysicsBody3D>(existing.operator godot::Object*());
    }
    Ref<ArrayMesh> out_mesh;
    if (existing_body) {
        _clear_physics_children(existing_body);
    } else if (existing.get_type() == Variant::OBJECT) {
        ArrayMesh* mesh_obj = Object::cast_to<ArrayMesh>(existing.operator godot::Object*());
        if (mesh_obj) {
            out_mesh = Ref<ArrayMesh>(mesh_obj);
            // Clear all existing surfaces while preserving user customizations
            out_mesh->clear_surfaces();
        }
    }
    if (out_mesh.is_null()) {
        out_mesh.instantiate();
    }

    if (graph.is_null() || !graph->_handle) {
        return out_mesh;
    }

    // Build mesh options struct
    occtl_mesh_options_t opts = OCCTL_MESH_OPTIONS_INIT;
    if (options.is_valid()) {
        opts = options->to_c();
    }
    double deflection = opts.deflection;
    double angle = opts.angle;

    // Resolve face IDs
    std::vector<occtl_node_id_t> ids_vec;
    if (face_ids.get_type() == Variant::PACKED_INT64_ARRAY) {
        PackedInt64Array ids_arr = face_ids;
        ids_vec.reserve(ids_arr.size());
        for (int i = 0; i < ids_arr.size(); i++) {
            int64_t val = ids_arr[i];
            uint64_t face_id = static_cast<uint64_t>(val < 0 ? -val : val);
            occtl_node_id_t nid;
            nid.bits = face_id;
            ids_vec.push_back(nid);
        }
    } else if (face_ids.get_type() != Variant::NIL) {
        // Invalid type — return empty mesh
        return out_mesh;
    }

    // Ensure mesh generated
    {
        occtl_status_t status = _ensure_mesh_generated(graph->_handle, deflection, angle);
        if (status != OCCTL_OK) {
            return out_mesh;
        }
    }

    // If no explicit face IDs, iterate all faces
    if (ids_vec.empty()) {
        occtl_node_iter_t* iter = nullptr;
        occtl_status_t status = occtl_graph_face_iter_create(graph->_handle, &iter);
        if (status != OCCTL_OK || !iter) {
            return out_mesh;
        }
        occtl_node_id_t fid;
        while (occtl_node_iter_next(iter, &fid) == OCCTL_OK) {
            ids_vec.push_back(fid);
        }
        occtl_node_iter_free(iter);
    }

    if (ids_vec.empty()) {
        return out_mesh;
    }

    // Collect triangulations from all requested faces
    struct TriFaceData {
        occtl_node_id_t face_id;
        std::vector<Vector3> verts;      // local vertex positions
        std::vector<Vector2> uvs;        // local UVs (may be empty)
        std::vector<Vector3> normals_c;  // local normals from C (may be empty)
        std::vector<int> indices;        // indices into local verts
        Vector3 face_normal;             // geometric face normal
    };

    std::vector<TriFaceData> face_data;
    face_data.reserve(ids_vec.size());
    int total_verts = 0;
    int total_tris = 0;
    for (auto fid : ids_vec) {
        occtl_triangulation_view_t tv;
        occtl_status_t status = occtl_mesh_face_triangulation(graph->_handle, fid, &tv);
        if (status != OCCTL_OK) {
            continue;
        }

        TriFaceData fd;
        fd.face_id = fid;

        size_t nv = tv.node_count;
        size_t nt = tv.triangle_count;

        // Skip degenerate faces with no vertices (they would cause buffer overruns
        // on fd.verts even with clamped indices). Skip faces with no triangles too.
        if (nv == 0 || nt == 0) {
            continue;
        }

        fd.verts.reserve(nv);
        for (size_t i = 0; i < nv; i++) {
            fd.verts.push_back(Vector3(
                tv.nodes[3 * i],
                tv.nodes[3 * i + 1],
                tv.nodes[3 * i + 2]
            ));
        }

        fd.indices.reserve(3 * nt);
        for (size_t i = 0; i < 3 * nt; i++) {
            uint32_t idx = tv.triangles[i];
            if (idx >= nv) {
                idx = 0; // Clamp out-of-range triangle indices to 0 to prevent buffer overruns
            }
            fd.indices.push_back(static_cast<int>(idx));
        }

        if (tv.uvs && include_uvs) {
            fd.uvs.reserve(nv);
            for (size_t i = 0; i < nv; i++) {
                fd.uvs.push_back(Vector2(tv.uvs[2 * i], tv.uvs[2 * i + 1]));
            }
        }

        if (tv.normals) {
            fd.normals_c.reserve(nv);
            for (size_t i = 0; i < nv; i++) {
                fd.normals_c.push_back(Vector3(
                    tv.normals[3 * i],
                    tv.normals[3 * i + 1],
                    tv.normals[3 * i + 2]
                ));
            }
        }
        Vector3 avg_normal(0, 0, 0);
        for (size_t i = 0; i < nt; i++) {
            int i0 = fd.indices[3 * i];
            int i1 = fd.indices[3 * i + 1];
            int i2 = fd.indices[3 * i + 2];
            Vector3 e1 = fd.verts[i1] - fd.verts[i0];
            Vector3 e2 = fd.verts[i2] - fd.verts[i0];
            Vector3 n = e1.cross(e2);
            double len = n.length();
            if (len > 1e-30) {
                n /= len;
            }
            avg_normal += n;
        }
        double alen = avg_normal.length();
        if (alen > 1e-30) {
            avg_normal /= alen;
        } else {
            avg_normal = Vector3(0, 0, 1);
        }
        fd.face_normal = avg_normal;

        total_verts += static_cast<int>(nv);
        total_tris += static_cast<int>(nt);
        face_data.push_back(std::move(fd));
    }

    if (face_data.empty()) {
        return out_mesh;
    }

    // If a PhysicsBody3D was passed, create collision shapes instead of ArrayMesh
    if (existing_body) {
        for (const auto& fd : face_data) {
            // Build face triangles as a PackedVector3Array (consecutive triples)
            PackedVector3Array tri_verts;
            tri_verts.resize(fd.indices.size());
            for (size_t i = 0; i < fd.indices.size(); i++) {
                tri_verts[i] = fd.verts[fd.indices[i]];
            }

            Ref<ConcavePolygonShape3D> shape;
            shape.instantiate();
            shape->set_faces(tri_verts);

            CollisionShape3D* cs = memnew(CollisionShape3D);
            cs->set_shape(shape);

            // Name prefix allows _clear_physics_children to find it later
            cs->set_name(String("_occtl_face_") + String::num_uint64(fd.face_id.bits));

            // Metadata maps back to the feature (face node ID)
            Dictionary meta;
            meta["feature_id"] = static_cast<int64_t>(fd.face_id.bits);
            cs->set_meta("occtl", meta);

            existing_body->add_child(cs, true);
            cs->set_owner(
                existing_body->get_owner()
                    ? existing_body->get_owner()
                    : existing_body);
        }
        return Ref<ArrayMesh>();
    }

    // Build merged vertex/triangle arrays
    PackedVector3Array out_verts;
    PackedVector3Array out_normals;
    PackedVector2Array out_uvs;
    PackedColorArray out_colors;
    PackedFloat32Array out_tangents;
    PackedInt32Array out_indices;

    if (!include_normals && !include_feature_ids && !include_tangents) {
        // Simple path: deduplicate by position, no per-vertex attributes needed per-face
        // Map from serialized position to vertex index
        std::unordered_map<uint64_t, int> pos_map;
        auto pos_hash = [](const Vector3& v) -> uint64_t {
            // Quantize to ~1e-9 precision.
            uint64_t hx = 0, hy = 0, hz = 0;
            memcpy(&hx, &v.x, sizeof(v.x)); hx >>= 4;
            memcpy(&hy, &v.y, sizeof(v.y)); hy >>= 4;
            memcpy(&hz, &v.z, sizeof(v.z)); hz >>= 4;
            return hx ^ (hy << 20) ^ (hz << 40);
        };

        for (const auto& fd : face_data) {
            // Process as triplets
            for (int i = 0; i < static_cast<int>(fd.indices.size()); i += 3) {
                int tri[3];
                tri[0] = fd.indices[i];
                tri[1] = fd.indices[i + 2];
                tri[2] = fd.indices[i + 1];
                for (int j = 0; j < 3; j++) {
                    int local_idx = tri[j];
                    const Vector3& pos = fd.verts[local_idx];
                    uint64_t key = pos_hash(pos);
                    auto it = pos_map.find(key);
                    if (it != pos_map.end()) {
                        if ((out_verts[it->second] - pos).length_squared() < 1e-20) {
                            out_indices.push_back(it->second);
                            continue;
                        }
                    }
                    int new_idx = out_verts.size();
                    out_verts.push_back(pos);
                    out_indices.push_back(new_idx);
                    pos_map[key] = new_idx;
                }
            }
        }
    } else {
        // Complex path: need per-face vertex attributes
        int estimated_verts = total_verts;
        int estimated_tris = total_tris;
        out_verts.resize(estimated_verts);
        out_indices.resize(3 * estimated_tris);

        // For normal computation: track which face+vertex maps to which output vertex
        std::vector<std::vector<int>> face_vert_map(face_data.size());

        int voff = 0;
        int ioff = 0;
        for (size_t fi = 0; fi < face_data.size(); fi++) {
            const auto& fd = face_data[fi];
            face_vert_map[fi].resize(fd.verts.size(), -1);

            for (size_t i = 0; i < fd.verts.size(); i++) {
                out_verts[voff] = fd.verts[i];
                face_vert_map[fi][i] = voff;
                voff++;
            }
            // Process as triplets
            for (size_t i = 0; i < fd.indices.size(); i += 3) {
                out_indices[ioff++] = face_vert_map[fi][fd.indices[i]];
                out_indices[ioff++] = face_vert_map[fi][fd.indices[i + 2]];
                out_indices[ioff++] = face_vert_map[fi][fd.indices[i + 1]];
            }
        }
        out_verts.resize(voff);
        out_indices.resize(ioff);

        // Compute smooth normals if requested
        if (include_normals) {
            out_normals.resize(out_verts.size());
            for (int i = 0; i < out_normals.size(); i++) {
                out_normals[i] = Vector3(0, 0, 0);
            }

            struct VertNormalContrib {
                Vector3 normal;
                Vector3 ref_normal;
                int count;
            };
            std::vector<VertNormalContrib> vnc(out_verts.size());
            for (int i = 0; i < out_normals.size(); i++) {
                vnc[i] = {Vector3(0, 0, 0), Vector3(0, 0, 0), 0};
            }

            // First pass: compute all triangle normals and accumulate at vertices
            for (size_t ti = 0; ti < face_data.size(); ti++) {
                const auto& fd = face_data[ti];
                for (size_t j = 0; j < fd.indices.size() / 3; j++) {
                    int i0 = face_vert_map[ti][fd.indices[3 * j]];
                    int i1, i2;
                    i1 = face_vert_map[ti][fd.indices[3 * j + 2]];
                    i2 = face_vert_map[ti][fd.indices[3 * j + 1]];

                    Vector3 e1 = out_verts[i1] - out_verts[i0];
                    Vector3 e2 = out_verts[i2] - out_verts[i0];
                    Vector3 n = e1.cross(e2);
                    double len = n.length();
                    if (len > 1e-30) {
                        n /= len;
                    } else {
                        n = fd.face_normal;
                    }

                    for (int vi : {i0, i1, i2}) {
                        vnc[vi].normal += n;
                        vnc[vi].count++;
                        if (vnc[vi].count == 1) {
                            vnc[vi].ref_normal = fd.face_normal;
                        }
                    }
                }
            }

            // Second pass: apply angle threshold smoothing
            double angle_threshold = 2.0 * angle;
            double cos_threshold = std::cos(angle_threshold);

            for (int i = 0; i < out_normals.size(); i++) {
                vnc[i] = {Vector3(0, 0, 0), Vector3(0, 0, 0), 0};
            }

            for (size_t ti = 0; ti < face_data.size(); ti++) {
                const auto& fd = face_data[ti];
                for (size_t j = 0; j < fd.indices.size() / 3; j++) {
                    int i0 = face_vert_map[ti][fd.indices[3 * j]];
                    int i1, i2;
                    i1 = face_vert_map[ti][fd.indices[3 * j + 2]];
                    i2 = face_vert_map[ti][fd.indices[3 * j + 1]];

                    Vector3 e1 = out_verts[i1] - out_verts[i0];
                    Vector3 e2 = out_verts[i2] - out_verts[i0];
                    Vector3 n = e1.cross(e2);
                    double len = n.length();
                    if (len > 1e-30) {
                        n /= len;
                    } else {
                        n = fd.face_normal;
                    }

                    for (int vi : {i0, i1, i2}) {
                        if (vnc[vi].count == 0) {
                            vnc[vi].ref_normal = fd.face_normal;
                            vnc[vi].normal = n;
                            vnc[vi].count = 1;
                        } else if (vnc[vi].ref_normal.dot(n) >= cos_threshold) {
                            vnc[vi].normal += n;
                            vnc[vi].count++;
                        }
                    }
                }
            }

            // Normalize
            for (int i = 0; i < out_normals.size(); i++) {
                if (vnc[i].count > 0) {
                    double nlen = vnc[i].normal.length();
                    if (nlen > 1e-30) {
                        out_normals[i] = vnc[i].normal / nlen;
                    } else {
                        out_normals[i] = vnc[i].ref_normal;
                    }
                } else {
                    out_normals[i] = Vector3(0, 0, 1);
                }
            }
        }

        // Copy UVs if requested
        if (include_uvs) {
            out_uvs.resize(out_verts.size());
            for (size_t fi = 0; fi < face_data.size(); fi++) {
                const auto& fd = face_data[fi];
                if (fd.uvs.empty()) continue;
                for (size_t vi = 0; vi < fd.verts.size(); vi++) {
                    int gv = face_vert_map[fi][vi];
                    out_uvs[gv] = fd.uvs[vi];
                }
            }
        }

        // Compute tangents if requested
        if (include_tangents && include_normals && include_uvs) {
            out_tangents.resize(out_verts.size() * 4);
            for (int i = 0; i < out_tangents.size(); i++) {
                out_tangents[i] = 0.0f;
            }
            std::vector<int> tangent_count(out_verts.size(), 0);

            for (size_t ti = 0; ti < face_data.size(); ti++) {
                const auto& fd = face_data[ti];
                if (fd.uvs.empty()) continue;
                for (size_t j = 0; j < fd.indices.size() / 3; j++) {
                    int i0 = face_vert_map[ti][fd.indices[3 * j]];
                    int i1, i2;
                    i1 = face_vert_map[ti][fd.indices[3 * j + 2]];
                    i2 = face_vert_map[ti][fd.indices[3 * j + 1]];

                    Vector3 e1 = out_verts[i1] - out_verts[i0];
                    Vector3 e2 = out_verts[i2] - out_verts[i0];
                    Vector2 duv1 = out_uvs[i1] - out_uvs[i0];
                    Vector2 duv2 = out_uvs[i2] - out_uvs[i0];

                    double r = 1.0 / (duv1.x * duv2.y - duv2.x * duv1.y + 1e-20);
                    Vector3 tangent = (e1 * duv2.y - e2 * duv1.y) * r;

                    for (int vi : {i0, i1, i2}) {
                        int base = vi * 4;
                        out_tangents[base] += static_cast<float>(tangent.x);
                        out_tangents[base + 1] += static_cast<float>(tangent.y);
                        out_tangents[base + 2] += static_cast<float>(tangent.z);
                        tangent_count[vi]++;
                    }
                }
            }

            // Orthogonalize and normalize tangents
            for (int i = 0; i < out_verts.size(); i++) {
                if (tangent_count[i] > 0) {
                    int base = i * 4;
                    Vector3 t(
                        out_tangents[base],
                        out_tangents[base + 1],
                        out_tangents[base + 2]
                    );
                    t /= static_cast<double>(tangent_count[i]);

                    const Vector3& n = out_normals[i];
                    t = (t - n * n.dot(t)).normalized();

                    out_tangents[base] = static_cast<float>(t.x);
                    out_tangents[base + 1] = static_cast<float>(t.y);
                    out_tangents[base + 2] = static_cast<float>(t.z);
                    Vector3 t_norm = t.normalized();
                    Vector3 bitangent = n.cross(t_norm);
                    float w = (bitangent.dot(
                        Vector3(out_tangents[base], out_tangents[base + 1], out_tangents[base + 2])
                    ) >= 0) ? 1.0f : -1.0f;
                    out_tangents[base + 3] = w;
                }
            }
        }

        // Feature ID colors
        if (include_feature_ids) {
            out_colors.resize(out_verts.size());
            for (size_t fi = 0; fi < face_data.size(); fi++) {
                const auto& fd = face_data[fi];
                uint64_t face_bits = fd.face_id.bits;
                float r = ((face_bits * 1234567u) & 0xFF) / 255.0f;
                float g = ((face_bits * 7654321u) & 0xFF) / 255.0f;
                float b = ((face_bits * 3456789u) & 0xFF) / 255.0f;
                Color color(r, g, b, 1.0f);
                for (size_t vi = 0; vi < fd.verts.size(); vi++) {
                    int gv = face_vert_map[fi][vi];
                    out_colors[gv] = color;
                }
            }
        }
    }

    // Build the surface arrays
    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = out_verts;
    arrays[Mesh::ARRAY_INDEX] = out_indices;

    if (!out_normals.is_empty()) {
        arrays[Mesh::ARRAY_NORMAL] = out_normals;
    }
    if (!out_uvs.is_empty()) {
        arrays[Mesh::ARRAY_TEX_UV] = out_uvs;
    }
    if (!out_tangents.is_empty()) {
        arrays[Mesh::ARRAY_TANGENT] = out_tangents;
    }
    if (!out_colors.is_empty()) {
        arrays[Mesh::ARRAY_COLOR] = out_colors;
    }

    out_mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);

    return out_mesh;
}

// ---------------------------------------------------------------------------
// mesh_edges
// ---------------------------------------------------------------------------

Ref<MultiMesh> OclGodotMesher::mesh_edges(
    const Ref<OclGraphHandle>& graph,
    const Variant& existing,
    const Ref<OclMeshOptions>& options,
    const Variant& edge_ids,
    double radius)
{
    // Check if existing is a PhysicsBody3D (→ collision shapes) or MultiMesh
    PhysicsBody3D* existing_body = nullptr;
    if (existing.get_type() == Variant::OBJECT) {
        existing_body = Object::cast_to<PhysicsBody3D>(existing.operator godot::Object*());
    }
    Ref<MultiMesh> out_mm;
    if (existing_body) {
        _clear_physics_children(existing_body);
    } else if (existing.get_type() == Variant::OBJECT) {
        MultiMesh* mm_obj = Object::cast_to<MultiMesh>(existing.operator godot::Object*());
        if (mm_obj) {
            out_mm = Ref<MultiMesh>(mm_obj);
            out_mm->set_instance_count(0);
            out_mm->set_transform_format(MultiMesh::TRANSFORM_3D);
            out_mm->set_mesh(Ref<ArrayMesh>());
        }
    }
    if (out_mm.is_null()) {
        out_mm.instantiate();
    }

    if (graph.is_null() || !graph->_handle) {
        return out_mm;
    }

    // Mesh options
    occtl_mesh_options_t opts = OCCTL_MESH_OPTIONS_INIT;
    if (options.is_valid()) {
        opts = options->to_c();
    }
    double angle = opts.angle;
    double deflection = opts.deflection;

    // Effective radius
    double eff_radius = radius;
    if (eff_radius <= 0.0) {
        eff_radius = deflection * 10.0;
    }

    // Resolve edge IDs
    std::vector<occtl_node_id_t> ids_vec;

    if (edge_ids.get_type() == Variant::PACKED_INT64_ARRAY) {
        PackedInt64Array ids_arr = edge_ids;
        ids_vec.reserve(ids_arr.size());
        for (int64_t id : ids_arr) {
            occtl_node_id_t nid;
            nid.bits = static_cast<uint64_t>(id);
            ids_vec.push_back(nid);
        }
    } else if (edge_ids.get_type() != Variant::NIL) {
        return out_mm;
    }

    // If no explicit edge IDs, iterate all edges
    if (ids_vec.empty()) {
        occtl_node_iter_t* iter = nullptr;
        occtl_status_t status = occtl_graph_edge_iter_create(graph->_handle, &iter);
        if (status != OCCTL_OK || !iter) {
            return out_mm;
        }
        occtl_node_id_t eid;
        while (occtl_node_iter_next(iter, &eid) == OCCTL_OK) {
            ids_vec.push_back(eid);
        }
        occtl_node_iter_free(iter);
    }

    if (ids_vec.empty()) {
        return out_mm;
    }

    // Generate mesh with whole-graph dispatch so edge 3D polygons are cached.
    {
        occtl_mesh_options_t gen_opts = OCCTL_MESH_OPTIONS_INIT;
        gen_opts.deflection = deflection;
        gen_opts.angle = angle;
        gen_opts.clean_model = 1;
        occtl_status_t status = occtl_mesh_generate(graph->_handle, nullptr, 0, &gen_opts);
        if (status != OCCTL_OK) {
            return out_mm;
        }
    }

    // Build cylinder mesh resolution from angle
    int slices = _slices_from_angle(angle);
    Ref<ArrayMesh> cyl_mesh = _make_cylinder_mesh(slices);

    // Scale radius by bounding box diagonal for model-size adaptation
    double bbox_diag = _get_graph_bbox_diag(graph->_handle);
    eff_radius *= bbox_diag;

    // Compute transforms for each edge segment
    std::vector<Transform3D> xforms;

    // Helper: build a tube segment transform from two points
    auto _add_segment = [&](const Vector3& p0, const Vector3& p1, occtl_node_id_t eid, uint64_t seg_idx) {
        Vector3 dir = p1 - p0;
        double seg_len = dir.length();
        if (seg_len < 1e-15) return;
        dir /= seg_len;

        Vector3 mid = (p0 + p1) * 0.5;

        Basis basis;
        Vector3 y_axis = dir;
        Vector3 up = (std::abs(y_axis.y) < 0.9) ? Vector3(0, 1, 0) : Vector3(1, 0, 0);
        Vector3 x_axis = up.cross(y_axis).normalized();
        Vector3 z_axis = x_axis.cross(y_axis).normalized();
        basis = Basis(x_axis, y_axis, z_axis);

        Transform3D xf(basis, mid);
        xf = xf.scaled_local(Vector3(eff_radius, seg_len, eff_radius));

        xforms.push_back(xf);

        if (existing_body) {
            Ref<CapsuleShape3D> cshape;
            cshape.instantiate();
            cshape->set_radius(eff_radius);
            cshape->set_height(std::max(0.0, seg_len - 2.0 * eff_radius));

            CollisionShape3D* cs = memnew(CollisionShape3D);
            cs->set_shape(cshape);
            cs->set_position(mid);
            cs->set_basis(basis);

            cs->set_name(String("_occtl_edge_") + String::num_uint64(eid.bits) + "_" + String::num_uint64(seg_idx));

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

    // Pre-build a mapping from edge → coedge + owning face for face-owned edges.
    std::unordered_map<uint64_t, std::pair<occtl_node_id_t, occtl_node_id_t>> edge_coedge_map;
    {
        occtl_node_iter_t* coedge_iter = nullptr;
        occtl_status_t coedge_iter_status = occtl_graph_coedge_iter_create(graph->_handle, &coedge_iter);
        if (coedge_iter_status == OCCTL_OK && coedge_iter) {
            occtl_node_id_t cid;
            while (occtl_node_iter_next(coedge_iter, &cid) == OCCTL_OK) {
                occtl_topo_related_iter_t* rel = nullptr;
                if (occtl_topo_related_iter_create(graph->_handle, cid, &rel) == OCCTL_OK && rel) {
                    occtl_node_id_t rn;
                    occtl_relation_kind_t rk;
                    occtl_node_id_t parent_edge = {0};
                    occtl_node_id_t owning_face = {0};
                    while (occtl_topo_related_iter_next(rel, &rn, &rk) == OCCTL_OK) {
                        if (rk == OCCTL_RELATION_PARENT_EDGE) {
                            parent_edge = rn;
                        } else if (rk == OCCTL_RELATION_OWNING_FACE) {
                            owning_face = rn;
                        }
                    }
                    occtl_topo_related_iter_free(rel);

                    if (parent_edge.bits != 0) {
                        edge_coedge_map.emplace(parent_edge.bits,
                            std::make_pair(cid, owning_face));
                    }
                }
            }

            occtl_node_iter_free(coedge_iter);
        }
    }

    for (auto eid : ids_vec) {
        // Collect 3D polyline points for this edge
        std::vector<Vector3> edge_pts;

        // Strategy 1: free edge — direct 3D polygon
        {
            occtl_polygon3d_view_t pv;
            occtl_status_t status = occtl_mesh_edge_polygon3d(graph->_handle, eid, &pv);
            if (status == OCCTL_OK && pv.node_count >= 2) {
                edge_pts.reserve(pv.node_count);
                for (size_t i = 0; i < pv.node_count; i++) {
                    edge_pts.emplace_back(pv.nodes[3 * i], pv.nodes[3 * i + 1], pv.nodes[3 * i + 2]);
                }
            }
        }

        // Strategy 2: face-owned edge — use pre-built coedge map
        if (edge_pts.empty()) {
            auto map_it = edge_coedge_map.find(eid.bits);
            if (map_it != edge_coedge_map.end()) {
                occtl_node_id_t coedge_id = map_it->second.first;
                occtl_node_id_t face_id = map_it->second.second;

                occtl_polygon_on_tri_view_t potv;
                occtl_status_t potv_status = occtl_mesh_coedge_polygon_on_tri(graph->_handle, coedge_id, &potv);
                if (potv_status == OCCTL_OK && potv.node_count >= 2) {
                    occtl_triangulation_view_t tv;
                    occtl_status_t tv_status = occtl_mesh_face_triangulation(graph->_handle, face_id, &tv);
                    if (tv_status == OCCTL_OK && tv.node_count > 0) {
                        edge_pts.reserve(potv.node_count);
                        for (size_t j = 0; j < potv.node_count; j++) {
                            uint32_t idx = potv.node_indices[j];
                            if (idx < tv.node_count) {
                                edge_pts.emplace_back(
                                    tv.nodes[3 * idx], tv.nodes[3 * idx + 1], tv.nodes[3 * idx + 2]);
                            }
                        }
                    }
                }
            }
        }

        // Strategy 3: fallback — sample the edge's 3D curve directly via topology.
        if (edge_pts.size() < 2) {
            int32_t has_curve = 0;
            occtl_status_t hs = occtl_topo_edge_has_curve(graph->_handle, eid, &has_curve);
            if (hs == OCCTL_OK && has_curve) {
                double u_first = 0.0, u_last = 0.0;
                occtl_status_t rs = occtl_topo_edge_range(graph->_handle, eid, &u_first, &u_last);
                if (rs == OCCTL_OK && u_last > u_first) {
                    occtl_point3_t pt;
                    edge_pts.reserve(4);
                    if (occtl_topo_edge_eval(graph->_handle, eid, u_first, &pt) == OCCTL_OK) {
                        edge_pts.emplace_back(pt.x, pt.y, pt.z);
                    }
                    double u_range = u_last - u_first;
                    occtl_vector3_t d1_mid;
                    int mid_samples = 0;
                    if (occtl_topo_edge_eval_d1(graph->_handle, eid, (u_first + u_last) * 0.5, &pt, &d1_mid) == OCCTL_OK) {
                        double tan_len = std::sqrt(d1_mid.x * d1_mid.x + d1_mid.y * d1_mid.y + d1_mid.z * d1_mid.z);
                        double est_arc = tan_len * u_range;
                        if (est_arc > deflection * 2.0) {
                            mid_samples = std::min(64, std::max(1, static_cast<int>(std::ceil(est_arc / deflection))));
                        }
                    }
                    for (int k = 1; k < mid_samples; ++k) {
                        double u = u_first + u_range * static_cast<double>(k) / static_cast<double>(mid_samples);
                        if (occtl_topo_edge_eval(graph->_handle, eid, u, &pt) == OCCTL_OK) {
                            edge_pts.emplace_back(pt.x, pt.y, pt.z);
                        }
                    }
                    if (occtl_topo_edge_eval(graph->_handle, eid, u_last, &pt) == OCCTL_OK) {
                        edge_pts.emplace_back(pt.x, pt.y, pt.z);
                    }
                }
            }
        }

        if (edge_pts.size() < 2) {
            continue;
        }

        // Build tube segments along the polyline
        for (size_t i = 0; i + 1 < edge_pts.size(); i++) {
            _add_segment(edge_pts[i], edge_pts[i + 1], eid, static_cast<uint64_t>(i));
        }
    }
    if (existing_body) {
        return Ref<MultiMesh>();
    }

    // Set up MultiMesh.
    out_mm->set_transform_format(MultiMesh::TRANSFORM_3D);
    out_mm->set_instance_count(static_cast<int>(xforms.size()));
    out_mm->set_mesh(cyl_mesh);

    for (int i = 0; i < static_cast<int>(xforms.size()); i++) {
        out_mm->set_instance_transform(i, xforms[i]);
    }

    return out_mm;
}

// ---------------------------------------------------------------------------
// mesh_vertices
// ---------------------------------------------------------------------------

Ref<MultiMesh> OclGodotMesher::mesh_vertices(
    const Ref<OclGraphHandle>& graph,
    const Variant& existing,
    const Ref<OclMeshOptions>& options,
    const Variant& vertex_ids,
    double radius)
{
    // Check if existing is a PhysicsBody3D (→ collision shapes) or MultiMesh
    PhysicsBody3D* existing_body = nullptr;
    if (existing.get_type() == Variant::OBJECT) {
        existing_body = Object::cast_to<PhysicsBody3D>(existing.operator godot::Object*());
    }
    Ref<MultiMesh> out_mm;
    if (existing_body) {
        _clear_physics_children(existing_body);
    } else if (existing.get_type() == Variant::OBJECT) {
        MultiMesh* mm_obj = Object::cast_to<MultiMesh>(existing.operator godot::Object*());
        if (mm_obj) {
            out_mm = Ref<MultiMesh>(mm_obj);
            out_mm->set_instance_count(0);
            out_mm->set_transform_format(MultiMesh::TRANSFORM_3D);
            out_mm->set_mesh(Ref<ArrayMesh>());
        }
    }
    if (out_mm.is_null()) {
        out_mm.instantiate();
    }

    if (graph.is_null() || !graph->_handle) {
        return out_mm;
    }

    // Mesh options
    occtl_mesh_options_t opts = OCCTL_MESH_OPTIONS_INIT;
    if (options.is_valid()) {
        opts = options->to_c();
    }
    double angle = opts.angle;
    double deflection = opts.deflection;

    // Resolve vertex IDs
    std::vector<occtl_node_id_t> ids_vec;

    if (vertex_ids.get_type() == Variant::PACKED_INT64_ARRAY) {
        PackedInt64Array ids_arr = vertex_ids;
        ids_vec.reserve(ids_arr.size());
        for (int64_t id : ids_arr) {
            occtl_node_id_t nid;
            nid.bits = static_cast<uint64_t>(id);
            ids_vec.push_back(nid);
        }
    } else if (vertex_ids.get_type() != Variant::NIL) {
        return out_mm;
    }

    // If no explicit vertex IDs, iterate all vertices
    if (ids_vec.empty()) {
        occtl_node_iter_t* iter = nullptr;
        occtl_status_t status = occtl_graph_vertex_iter_create(graph->_handle, &iter);
        if (status != OCCTL_OK || !iter) {
            return out_mm;
        }
        occtl_node_id_t vid;
        while (occtl_node_iter_next(iter, &vid) == OCCTL_OK) {
            ids_vec.push_back(vid);
        }
        occtl_node_iter_free(iter);
    }

    if (ids_vec.empty()) {
        return out_mm;
    }

    // Build sphere mesh resolution from angle
    int slices = _slices_from_angle(angle);
    Ref<ArrayMesh> sphere_mesh = _make_sphere_mesh(slices);

    // Compute transforms for each vertex
    std::vector<Transform3D> xforms;

    // Scale sphere by radius * bbox diagonal for model-size adaptation
    double bbox_diag = _get_graph_bbox_diag(graph->_handle);
    double sphere_scale = radius;
    if (sphere_scale <= 0.0) {
        sphere_scale = deflection * 10.0;
    }
    sphere_scale *= bbox_diag;

    for (auto vid : ids_vec) {
        occtl_point3_t pt;
        occtl_status_t status = occtl_topo_vertex_point(graph->_handle, vid, &pt);
        if (status != OCCTL_OK) {
            continue;
        }

        Vector3 pos(pt.x, pt.y, pt.z);

        Transform3D xf;
        xf.origin = pos;
        xf = xf.scaled_local(Vector3(sphere_scale, sphere_scale, sphere_scale));
        xforms.push_back(xf);

        // If a PhysicsBody3D was passed, create a SphereShape3D collision child
        if (existing_body) {
            Ref<SphereShape3D> cshape;
            cshape.instantiate();
            cshape->set_radius(sphere_scale);

            CollisionShape3D* cs = memnew(CollisionShape3D);
            cs->set_shape(cshape);
            cs->set_position(pos);

            cs->set_name(String("_occtl_vertex_") + String::num_uint64(vid.bits));

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

    if (existing_body) {
        return Ref<MultiMesh>();
    }

    // Set up MultiMesh.
    out_mm->set_transform_format(MultiMesh::TRANSFORM_3D);
    out_mm->set_instance_count(static_cast<int>(xforms.size()));
    out_mm->set_mesh(sphere_mesh);

    for (int i = 0; i < static_cast<int>(xforms.size()); i++) {
        out_mm->set_instance_transform(i, xforms[i]);
    }

    return out_mm;
}
