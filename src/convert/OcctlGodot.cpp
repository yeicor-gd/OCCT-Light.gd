#include "OcctlGodot.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <occtl/occtl_core.h>
#include <occtl/occtl_mesh.h>
#include <occtl/occtl_topo.h>

#include <cstring>
#include <cmath>
#include <algorithm>
#include <cfloat>

// ========================================================================
// Internal helpers
// ========================================================================

/// Encode a 64-bit node/feature ID into a 32-bit RGBA Color.
/// Each channel stores 8 bits of the ID: R=bits 0-7, G=bits 8-15,
/// B=bits 16-23, A=bits 24-31.  Only the lower 32 bits are preserved.
static Color _feature_id_color(int64_t id) {
    return Color(
        ((id >> 0) & 0xFF) / 255.0f,
        ((id >> 8) & 0xFF) / 255.0f,
        ((id >> 16) & 0xFF) / 255.0f,
        ((id >> 24) & 0xFF) / 255.0f);
}

/// Extract a raw occtl_graph_t* from a Ref<OcctlGraphHandle>.
/// Returns nullptr when the handle is null or invalid.
static const occtl_graph_t* _graph_ptr(const Ref<OcctlGraphHandle>& g) {
    if (g.is_null()) return nullptr;
    uint64_t handle = static_cast<uint64_t>(g->get_handle());
    if (handle == 0) return nullptr;
    return reinterpret_cast<const occtl_graph_t*>(static_cast<uintptr_t>(handle));
}

/// Extract a mutable occtl_graph_t* from a Ref<OcctlGraphHandle>.
/// Returns nullptr when the handle is null or invalid.
static occtl_graph_t* _graph_ptr_mut(const Ref<OcctlGraphHandle>& g) {
    if (g.is_null()) return nullptr;
    uint64_t handle = static_cast<uint64_t>(g->get_handle());
    if (handle == 0) return nullptr;
    return reinterpret_cast<occtl_graph_t*>(static_cast<uintptr_t>(handle));
}

/// Convert a `Variant` ids argument to a vector of node IDs.
/// When `ids` is null (Variant::NIL), iterate the graph and collect all
/// nodes matching `kind`, effectively exporting every feature of that kind.
/// When `ids` is a PackedInt64Array, use those IDs directly (empty → nothing).
/// Returns true if any valid IDs were found.
static bool _resolve_ids(
    const Variant& ids,
    const occtl_graph_t* graph,
    int32_t kind,
    std::vector<int64_t>& out_ids)
{
    out_ids.clear();

    if (ids.get_type() == Variant::NIL) {
        if (!graph) return false;
        size_t node_count = 0;
        occtl_status_t st = ::occtl_graph_node_count(graph, &node_count);
        if (st != OCCTL_OK) return false;

        for (size_t i = 0; i < node_count; ++i) {
            occtl_node_kind_t node_kind = static_cast<occtl_node_kind_t>(-1);
            occtl_node_id_t nid{static_cast<uint64_t>(i)};
            st = ::occtl_graph_node_kind(graph, nid, &node_kind);
            if (st == OCCTL_OK && static_cast<int32_t>(node_kind) == kind) {
                out_ids.push_back(static_cast<int64_t>(i));
            }
        }
        return !out_ids.empty();
    }

    if (ids.get_type() == Variant::PACKED_INT64_ARRAY) {
        PackedInt64Array arr = ids.operator PackedInt64Array();
        out_ids.reserve(static_cast<size_t>(arr.size()));
        for (int64_t i = 0; i < arr.size(); ++i) {
            out_ids.push_back(arr[i]);
        }
        return !out_ids.empty();
    }

    return false;
}

/// Ensure the graph has mesh data for the given face IDs.
/// Generates a mesh with the given deflection if no cached triangulation exists.
/// Returns OCCTL_OK if mesh data is available for at least one face.
static occtl_status_t _ensure_mesh_generated(
    occtl_graph_t* graph,
    const std::vector<int64_t>& face_ids,
    double deflection,
    double angle = 0.5)
{
    if (!graph || face_ids.empty()) return OCCTL_INVALID_ARGUMENT;

    // Check if any face already has a cached triangulation
    for (int64_t fid : face_ids) {
        occtl_triangulation_view_t tv;
        occtl_status_t st = ::occtl_mesh_face_triangulation(
            graph, occtl_node_id_t{static_cast<uint64_t>(fid)}, &tv);
        if (st == OCCTL_OK && tv.node_count > 0) {
            return OCCTL_OK; // Data already cached
        }
    }

    // No cached data — generate mesh on-the-fly
    occtl_mesh_options_t opts = OCCTL_MESH_OPTIONS_INIT;
    opts.deflection = deflection;
    opts.angle = angle;

    // Build node ID array from face IDs
    std::vector<occtl_node_id_t> node_ids;
    node_ids.reserve(face_ids.size());
    for (int64_t fid : face_ids) {
        node_ids.push_back(occtl_node_id_t{static_cast<uint64_t>(fid)});
    }

    return ::occtl_mesh_generate(graph, node_ids.data(), node_ids.size(), &opts);
}

/// Sample the 3D curve of an edge into a vector of 3D points.
///
/// Uses `occtl_topo_edge_eval_d1` to evaluate the curve at regular
/// parameter intervals chosen so that the chordal deviation is below
/// `deflection`.  For linear/straight edges only the endpoints are sampled.
///
/// Returns true on success and populates `out_points`.
static bool _sample_edge_curve(
    const occtl_graph_t* graph,
    occtl_node_id_t edge_id,
    double deflection,
    std::vector<Vector3>& out_points)
{
    out_points.clear();

    // Check if edge has a 3D curve
    int32_t has_curve = 0;
    occtl_status_t st = ::occtl_topo_edge_has_curve(graph, edge_id, &has_curve);
    if (st != OCCTL_OK || !has_curve) {
        return false;
    }

    // Get parameter range
    double u_first = 0.0, u_last = 0.0;
    st = ::occtl_topo_edge_range(graph, edge_id, &u_first, &u_last);
    if (st != OCCTL_OK) return false;
    if (u_last <= u_first) return false;

    // Always include start and end points
    occtl_point3_t pt;
    st = ::occtl_topo_edge_eval(graph, edge_id, u_first, &pt);
    if (st != OCCTL_OK) return false;
    out_points.push_back(Vector3(pt.x, pt.y, pt.z));

    occtl_vector3_t d1;
    st = ::occtl_topo_edge_eval_d1(graph, edge_id, u_first, &pt, &d1);
    if (st != OCCTL_OK) return false;
    double start_tan_len = std::sqrt(d1.x * d1.x + d1.y * d1.y + d1.z * d1.z);

    st = ::occtl_topo_edge_eval(graph, edge_id, u_last, &pt);
    if (st != OCCTL_OK) return false;
    out_points.push_back(Vector3(pt.x, pt.y, pt.z));

    st = ::occtl_topo_edge_eval_d1(graph, edge_id, u_last, &pt, &d1);
    if (st != OCCTL_OK) return false;
    double end_tan_len = std::sqrt(d1.x * d1.x + d1.y * d1.y + d1.z * d1.z);

    // Estimate arc length from tangent magnitudes
    double avg_tan_len = (start_tan_len + end_tan_len) * 0.5;
    double arc_len = avg_tan_len * (u_last - u_first);

    // For very short or straight edges, endpoints are enough
    if (arc_len <= deflection * 2.0) {
        return true;
    }

    // Sample intermediate points (cap at 64 segments max for performance)
    size_t n_segments = static_cast<size_t>(std::ceil(arc_len / deflection));
    n_segments = std::max<size_t>(n_segments, static_cast<size_t>(1));
    n_segments = std::min<size_t>(n_segments, static_cast<size_t>(64));

    // Remove the endpoint we already added (we'll re-add at the end)
    out_points.pop_back();

    for (size_t i = 1; i < n_segments; ++i) {
        double u = u_first + (u_last - u_first) * static_cast<double>(i) / static_cast<double>(n_segments);
        st = ::occtl_topo_edge_eval(graph, edge_id, u, &pt);
        if (st != OCCTL_OK) continue;
        out_points.push_back(Vector3(pt.x, pt.y, pt.z));
    }

    // Re-add endpoint
    st = ::occtl_topo_edge_eval(graph, edge_id, u_last, &pt);
    if (st != OCCTL_OK) return false;
    out_points.push_back(Vector3(pt.x, pt.y, pt.z));

    return out_points.size() >= 2;
}

/// Compute per-vertex normals from a triangulation, averaging face normals.
///
/// Called when the cached triangulation has `normals == nullptr`.
/// `nodes` are xyz-interleaved doubles, `triangles` are uint32_t triplets.
static std::vector<Vector3> _compute_triangulation_normals(
    const double* nodes, size_t node_count,
    const uint32_t* triangles, size_t triangle_count)
{
    std::vector<Vector3> normals(node_count, Vector3(0, 0, 0));
    std::vector<int> counts(node_count, 0);

    // Accumulate face normals
    for (size_t t = 0; t < triangle_count; ++t) {
        uint32_t i0 = triangles[t * 3];
        uint32_t i1 = triangles[t * 3 + 1];
        uint32_t i2 = triangles[t * 3 + 2];

        Vector3 p0(nodes[i0 * 3], nodes[i0 * 3 + 1], nodes[i0 * 3 + 2]);
        Vector3 p1(nodes[i1 * 3], nodes[i1 * 3 + 1], nodes[i1 * 3 + 2]);
        Vector3 p2(nodes[i2 * 3], nodes[i2 * 3 + 1], nodes[i2 * 3 + 2]);

        Vector3 e1 = p1 - p0;
        Vector3 e2 = p2 - p0;
        Vector3 n = e1.cross(e2);
        double len = n.length();
        if (len > 1e-30) n /= len;

        normals[i0] = normals[i0] + n;
        normals[i1] = normals[i1] + n;
        normals[i2] = normals[i2] + n;
        counts[i0]++;
        counts[i1]++;
        counts[i2]++;
    }

    // Normalize
    for (size_t i = 0; i < node_count; ++i) {
        if (counts[i] > 0) {
            double len = normals[i].length();
            if (len > 1e-30) normals[i] /= len;
        } else {
            normals[i] = Vector3(0, 0, 1);
        }
    }

    return normals;
}

/// Accumulator for mesh building — collects per-vertex data and triangle
/// indices, then flattens into Godot surface arrays at the end.
struct MeshAccum {
    std::vector<Vector3> verts;
    std::vector<Vector3> normals;
    std::vector<Vector2> uvs;
    std::vector<Color> colors;
    std::vector<int32_t> indices;
};

/// Compute the flat-shading normal of a triangle (a, b, c).
static void _compute_face_normal(const Vector3& a, const Vector3& b, const Vector3& c, Vector3* out) {
    Vector3 e1 = b - a;
    Vector3 e2 = c - a;
    Vector3 n = e1.cross(e2);
    double len = n.length();
    if (len > 1e-30) n /= len;
    *out = n;
}

/// Build a tube surface around a 3D polyline.
///
/// At each polyline point a local frame (tangent, right, up) is computed
/// and a circle of `segments` vertices is placed in the plane perpendicular
/// to the tangent.  Adjacent circles are connected by triangle quads.
///
/// @param acc          Output accumulator.
/// @param poly_nodes   Interleaved xyz doubles, length 3 * poly_count.
/// @param poly_count   Number of polyline points.
/// @param radius       Tube radius (>0).
/// @param segments     Circle subdivision (8 is typical).
/// @param include_normals  When true, per-vertex normals are emitted.
/// @param feature_id   ID encoded into vertex colors when include_feature_ids.
/// @param include_feature_ids  When true, vertex colors encode the feature ID.
static void _build_tube(MeshAccum& acc,
    const double* poly_nodes, size_t poly_count,
    double radius, int segments,
    bool include_normals,
    int64_t feature_id, bool include_feature_ids)
{
    if (poly_count < 2 || radius <= 0.0) return;

    Color fcolor = include_feature_ids ? _feature_id_color(feature_id) : Color(1, 1, 1, 1);

    // Build rings around each polyline point (segments+1 to close the circle)
    size_t ring_stride = static_cast<size_t>(segments + 1);
    std::vector<Vector3> ring_verts(poly_count * ring_stride);
    std::vector<Vector3> ring_normals(poly_count * ring_stride);

    for (size_t i = 0; i < poly_count; ++i) {
        Vector3 pt(poly_nodes[i * 3], poly_nodes[i * 3 + 1], poly_nodes[i * 3 + 2]);

        // Tangent direction at this point (central difference where possible)
        Vector3 tangent;
        if (i == 0) {
            tangent = Vector3(
                poly_nodes[3] - poly_nodes[0],
                poly_nodes[4] - poly_nodes[1],
                poly_nodes[5] - poly_nodes[2]);
        } else if (i == poly_count - 1) {
            tangent = Vector3(
                poly_nodes[i * 3] - poly_nodes[(i - 1) * 3],
                poly_nodes[i * 3 + 1] - poly_nodes[(i - 1) * 3 + 1],
                poly_nodes[i * 3 + 2] - poly_nodes[(i - 1) * 3 + 2]);
        } else {
            tangent = Vector3(
                poly_nodes[(i + 1) * 3] - poly_nodes[(i - 1) * 3],
                poly_nodes[(i + 1) * 3 + 1] - poly_nodes[(i - 1) * 3 + 1],
                poly_nodes[(i + 1) * 3 + 2] - poly_nodes[(i - 1) * 3 + 2]);
        }
        double tlen = tangent.length();
        if (tlen < 1e-30) {
            tangent = Vector3(0, 0, 1);
        } else {
            tangent /= tlen;
        }

        // Perpendicular frame using an arbitrary up vector
        Vector3 up;
        if (std::abs(tangent.y) < 0.9) {
            up = tangent.cross(Vector3(0, 1, 0));
        } else {
            up = tangent.cross(Vector3(1, 0, 0));
        }
        double ulen = up.length();
        if (ulen < 1e-30) {
            up = Vector3(1, 0, 0);
        } else {
            up /= ulen;
        }
        Vector3 right = tangent.cross(up);

        for (int j = 0; j <= segments; ++j) {
            double angle = 2.0 * Math_PI * j / segments;
            double c = std::cos(angle);
            double s = std::sin(angle);
            Vector3 offset = right * (c * radius) + up * (s * radius);
            size_t idx = i * ring_stride + static_cast<size_t>(j);
            ring_verts[idx] = pt + offset;
            ring_normals[idx] = offset / radius;
        }
    }

    // Connect adjacent rings with triangle pairs
    for (size_t i = 0; i < poly_count - 1; ++i) {
        for (int j = 0; j < segments; ++j) {
            size_t off = i * ring_stride;
            size_t a0 = off + static_cast<size_t>(j);
            size_t a1 = off + static_cast<size_t>(j + 1);
            size_t b0 = off + ring_stride + static_cast<size_t>(j);
            size_t b1 = off + ring_stride + static_cast<size_t>(j + 1);

            // Two triangles per quad: (a0,b0,b1) and (a0,b1,a1)
            acc.verts.push_back(ring_verts[a0]);
            acc.verts.push_back(ring_verts[b0]);
            acc.verts.push_back(ring_verts[b1]);
            acc.verts.push_back(ring_verts[a0]);
            acc.verts.push_back(ring_verts[b1]);
            acc.verts.push_back(ring_verts[a1]);

            if (include_normals) {
                acc.normals.push_back(ring_normals[a0]);
                acc.normals.push_back(ring_normals[b0]);
                acc.normals.push_back(ring_normals[b1]);
                acc.normals.push_back(ring_normals[a0]);
                acc.normals.push_back(ring_normals[b1]);
                acc.normals.push_back(ring_normals[a1]);
            }

            if (include_feature_ids) {
                acc.colors.push_back(fcolor);
                acc.colors.push_back(fcolor);
                acc.colors.push_back(fcolor);
                acc.colors.push_back(fcolor);
                acc.colors.push_back(fcolor);
                acc.colors.push_back(fcolor);
            }

            int32_t base = static_cast<int32_t>(acc.verts.size()) - 6;
            acc.indices.push_back(base);
            acc.indices.push_back(base + 1);
            acc.indices.push_back(base + 2);
            acc.indices.push_back(base + 3);
            acc.indices.push_back(base + 4);
            acc.indices.push_back(base + 5);
        }
    }
}

/// Build a tetrahedron marker at a vertex position.
/// The marker is a small 4-triangle shape centred on `pos`.
static void _build_vertex_marker(MeshAccum& acc,
    const Vector3& pos,
    bool include_normals,
    int64_t feature_id, bool include_feature_ids,
    double size = 0.001)
{
    Color fcolor = include_feature_ids ? _feature_id_color(feature_id) : Color(1, 1, 1, 1);
    double s = size;

    Vector3 verts_arr[4] = {
        pos + Vector3(-s, -s, -s),
        pos + Vector3( s, -s, -s),
        pos + Vector3( s,  s, -s),
        pos + Vector3(-s,  s,  s)
    };

    int tri_indices[4][3] = {
        {0, 1, 2},
        {0, 2, 3},
        {0, 3, 1},
        {1, 3, 2}
    };

    for (int t = 0; t < 4; ++t) {
        const Vector3& a = verts_arr[tri_indices[t][0]];
        const Vector3& b = verts_arr[tri_indices[t][1]];
        const Vector3& c = verts_arr[tri_indices[t][2]];

        acc.verts.push_back(a);
        acc.verts.push_back(b);
        acc.verts.push_back(c);

        if (include_normals) {
            Vector3 n;
            _compute_face_normal(a, b, c, &n);
            acc.normals.push_back(n);
            acc.normals.push_back(n);
            acc.normals.push_back(n);
        }

        if (include_feature_ids) {
            acc.colors.push_back(fcolor);
            acc.colors.push_back(fcolor);
            acc.colors.push_back(fcolor);
        }

        int32_t base = static_cast<int32_t>(acc.verts.size()) - 3;
        acc.indices.push_back(base);
        acc.indices.push_back(base + 1);
        acc.indices.push_back(base + 2);
    }
}

/// Compute per-vertex tangents from positions, normals, UVs, and indices.
///
/// Uses the standard triangle-based accumulation with Gram-Schmidt
/// orthogonalization against the vertex normal.  Returns a PackedFloat64Array
/// with 4 components per vertex (xyz + sign).
static PackedFloat64Array _compute_tangents(
    const std::vector<Vector3>& verts,
    const std::vector<Vector3>& normals,
    const std::vector<Vector2>& uvs,
    const std::vector<int32_t>& indices)
{
    size_t n_verts = verts.size();
    if (n_verts == 0) return PackedFloat64Array();

    size_t n_tris = indices.size() / 3;
    std::vector<Vector3> tangents(n_verts, Vector3());
    std::vector<float> tangent_ws(n_verts, 0.0f);

    for (size_t t = 0; t < n_tris; ++t) {
        int i0 = indices[t * 3];
        int i1 = indices[t * 3 + 1];
        int i2 = indices[t * 3 + 2];

        const Vector3& v0 = verts[static_cast<size_t>(i0)];
        const Vector3& v1 = verts[static_cast<size_t>(i1)];
        const Vector3& v2 = verts[static_cast<size_t>(i2)];

        const Vector2& uv0 = uvs[static_cast<size_t>(i0)];
        const Vector2& uv1 = uvs[static_cast<size_t>(i1)];
        const Vector2& uv2 = uvs[static_cast<size_t>(i2)];

        Vector3 e1 = v1 - v0;
        Vector3 e2 = v2 - v0;
        Vector2 duv1 = uv1 - uv0;
        Vector2 duv2 = uv2 - uv0;
        double r = 1.0 / (duv1.x * duv2.y - duv1.y * duv2.x + 1e-12);
        Vector3 tdir = (e1 * duv2.y - e2 * duv1.y) * r;

        tangents[static_cast<size_t>(i0)] = tangents[static_cast<size_t>(i0)] + tdir;
        tangents[static_cast<size_t>(i1)] = tangents[static_cast<size_t>(i1)] + tdir;
        tangents[static_cast<size_t>(i2)] = tangents[static_cast<size_t>(i2)] + tdir;
    }

    PackedFloat64Array result;
    result.resize(static_cast<int64_t>(n_verts) * 4);
    for (size_t i = 0; i < n_verts; ++i) {
        const Vector3& n = normals[i];
        const Vector3& t = tangents[i];
        // Gram-Schmidt orthogonalization
        Vector3 tg = t - n * n.dot(t);
        double tlen = tg.length();
        if (tlen > 1e-15) tg /= tlen;

        // Compute handedness (w)
        Vector3 cross_n_t = n.cross(t);
        double w = (cross_n_t.dot(tg) < 0.0) ? -1.0 : 1.0;
        // Clamp sign to [-1, 1]
        if (w > 1.0f) w = 1.0f;
        if (w < -1.0f) w = -1.0f;

        result.set(static_cast<int64_t>(i) * 4, tg.x);
        result.set(static_cast<int64_t>(i) * 4 + 1, tg.y);
        result.set(static_cast<int64_t>(i) * 4 + 2, tg.z);
        result.set(static_cast<int64_t>(i) * 4 + 3, static_cast<double>(w));
    }

    return result;
}

/// Flatten accumulated mesh data into a Godot ArrayMesh surface.
static Ref<ArrayMesh> _finalize_mesh(
    const std::vector<Vector3>& verts,
    const std::vector<Vector3>& normals,
    const std::vector<Vector2>& uvs,
    const std::vector<Color>& colors,
    const PackedFloat64Array& tangents,
    const std::vector<int32_t>& indices,
    Mesh::PrimitiveType prim_type)
{
    Ref<ArrayMesh> mesh;
    mesh.instantiate();
    if (verts.empty() || indices.empty()) return mesh;

    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);

    PackedVector3Array vert_arr;
    vert_arr.resize(static_cast<int64_t>(verts.size()));
    for (size_t i = 0; i < verts.size(); ++i)
        vert_arr[static_cast<int64_t>(i)] = verts[i];
    arrays[Mesh::ARRAY_VERTEX] = vert_arr;

    PackedInt32Array idx_arr;
    idx_arr.resize(static_cast<int64_t>(indices.size()));
    for (size_t i = 0; i < indices.size(); ++i)
        idx_arr[static_cast<int64_t>(i)] = indices[i];
    arrays[Mesh::ARRAY_INDEX] = idx_arr;

    if (!normals.empty()) {
        PackedVector3Array n_arr;
        n_arr.resize(static_cast<int64_t>(normals.size()));
        for (size_t i = 0; i < normals.size(); ++i)
            n_arr[static_cast<int64_t>(i)] = normals[i];
        arrays[Mesh::ARRAY_NORMAL] = n_arr;
    }

    if (!uvs.empty()) {
        PackedVector2Array uv_arr;
        uv_arr.resize(static_cast<int64_t>(uvs.size()));
        for (size_t i = 0; i < uvs.size(); ++i)
            uv_arr[static_cast<int64_t>(i)] = uvs[i];
        arrays[Mesh::ARRAY_TEX_UV] = uv_arr;
    }

    if (!colors.empty()) {
        PackedColorArray col_arr;
        col_arr.resize(static_cast<int64_t>(colors.size()));
        for (size_t i = 0; i < colors.size(); ++i)
            col_arr[static_cast<int64_t>(i)] = colors[i];
        arrays[Mesh::ARRAY_COLOR] = col_arr;
    }

    if (tangents.size() > 0) {
        arrays[Mesh::ARRAY_TANGENT] = tangents;
    }

    mesh->add_surface_from_arrays(prim_type, arrays);
    return mesh;
}

// ========================================================================
// OcctlGodot implementation
// ========================================================================

void OcctlGodot::_bind_methods() {
    // --- Value conversions ---
    ClassDB::bind_static_method("OcctlGodot", D_METHOD("point3_to_vector3", "p"), &OcctlGodot::point3_to_vector3);
    ClassDB::bind_static_method("OcctlGodot", D_METHOD("vector3_to_point3", "v"), &OcctlGodot::vector3_to_point3);

    ClassDB::bind_static_method("OcctlGodot", D_METHOD("occtl_vector3_to_godot", "v"), &OcctlGodot::occtl_vector3_to_godot);
    ClassDB::bind_static_method("OcctlGodot", D_METHOD("godot_to_occtl_vector3", "v"), &OcctlGodot::godot_to_occtl_vector3);

    ClassDB::bind_static_method("OcctlGodot", D_METHOD("direction3_to_vector3", "d"), &OcctlGodot::direction3_to_vector3);
    ClassDB::bind_static_method("OcctlGodot", D_METHOD("vector3_to_direction3", "v"), &OcctlGodot::vector3_to_direction3);

    ClassDB::bind_static_method("OcctlGodot", D_METHOD("transform_to_transform3d", "t"), &OcctlGodot::transform_to_transform3d);
    ClassDB::bind_static_method("OcctlGodot", D_METHOD("transform3d_to_transform", "t"), &OcctlGodot::transform3d_to_transform);

    ClassDB::bind_static_method("OcctlGodot", D_METHOD("aabb3_to_aabb", "a"), &OcctlGodot::aabb3_to_aabb);
    ClassDB::bind_static_method("OcctlGodot", D_METHOD("aabb_to_aabb3", "a"), &OcctlGodot::aabb_to_aabb3);

    ClassDB::bind_static_method("OcctlGodot", D_METHOD("color_rgba_to_color", "c"), &OcctlGodot::color_rgba_to_color);
    ClassDB::bind_static_method("OcctlGodot", D_METHOD("color_to_color_rgba", "c"), &OcctlGodot::color_to_color_rgba);

    ClassDB::bind_static_method("OcctlGodot", D_METHOD("point2_to_vector2", "p"), &OcctlGodot::point2_to_vector2);
    ClassDB::bind_static_method("OcctlGodot", D_METHOD("vector2_to_point2", "v"), &OcctlGodot::vector2_to_point2);

    // --- Axis placement to Transform3D ---
    ClassDB::bind_static_method("OcctlGodot", D_METHOD("axis1_placement_to_transform3d", "a"), &OcctlGodot::axis1_placement_to_transform3d);
    ClassDB::bind_static_method("OcctlGodot", D_METHOD("axis2_placement_to_transform3d", "a"), &OcctlGodot::axis2_placement_to_transform3d);
    ClassDB::bind_static_method("OcctlGodot", D_METHOD("axis3_placement_to_transform3d", "a"), &OcctlGodot::axis3_placement_to_transform3d);

    // --- Edge batch to mesh ---
    ClassDB::bind_static_method("OcctlGodot", D_METHOD("edges_to_mesh", "graph", "edge_ids", "radius", "include_normals", "include_feature_ids", "deflection", "angle"),
        &OcctlGodot::edges_to_mesh, DEFVAL(Variant()), DEFVAL(0.0), DEFVAL(true), DEFVAL(false), DEFVAL(0.001), DEFVAL(0.5));

    // --- Vertex batch to mesh ---
    ClassDB::bind_static_method("OcctlGodot", D_METHOD("vertices_to_mesh", "graph", "vertex_ids", "include_normals", "include_feature_ids", "deflection", "angle"),
        &OcctlGodot::vertices_to_mesh, DEFVAL(Variant()), DEFVAL(true), DEFVAL(false), DEFVAL(0.001), DEFVAL(0.5));

    // --- Face triangulation batch to mesh ---
    ClassDB::bind_static_method("OcctlGodot", D_METHOD("faces_to_mesh", "graph", "face_ids", "include_normals", "include_uvs", "include_tangents", "include_feature_ids", "deflection", "angle"),
        &OcctlGodot::faces_to_mesh, DEFVAL(Variant()), DEFVAL(true), DEFVAL(true), DEFVAL(false), DEFVAL(false), DEFVAL(0.001), DEFVAL(0.5));
}

// ========================================================================
// Point3 <-> Vector3
// ========================================================================

Vector3 OcctlGodot::point3_to_vector3(const Ref<OcctlPoint3>& p) {
    const occtl_point3_t c = p->to_c();
    return Vector3(c.x, c.y, c.z);
}

Ref<OcctlPoint3> OcctlGodot::vector3_to_point3(const Vector3& v) {
    occtl_point3_t c;
    c.x = v.x;
    c.y = v.y;
    c.z = v.z;
    return OcctlPoint3::from_c(c);
}

// ========================================================================
// OCCT Vector3 <-> Godot Vector3
// ========================================================================

Vector3 OcctlGodot::occtl_vector3_to_godot(const Ref<OcctlVector3>& v) {
    const occtl_vector3_t c = v->to_c();
    return Vector3(c.x, c.y, c.z);
}

Ref<OcctlVector3> OcctlGodot::godot_to_occtl_vector3(const Vector3& v) {
    occtl_vector3_t c;
    c.x = v.x;
    c.y = v.y;
    c.z = v.z;
    return OcctlVector3::from_c(c);
}

// ========================================================================
// Direction3 <-> Vector3
// ========================================================================

Vector3 OcctlGodot::direction3_to_vector3(const Ref<OcctlDirection3>& d) {
    const occtl_direction3_t c = d->to_c();
    return Vector3(c.x, c.y, c.z);
}

Ref<OcctlDirection3> OcctlGodot::vector3_to_direction3(const Vector3& v) {
    occtl_direction3_t c;
    c.x = v.x;
    c.y = v.y;
    c.z = v.z;
    return OcctlDirection3::from_c(c);
}

// ========================================================================
// Transform <-> Transform3D
// ========================================================================

Transform3D OcctlGodot::transform_to_transform3d(const Ref<OcctlTransform>& t) {
    const occtl_transform_t c = t->to_c();
    Basis basis;
    basis.rows[0] = Vector3(c.m[0], c.m[1], c.m[2]);
    basis.rows[1] = Vector3(c.m[4], c.m[5], c.m[6]);
    basis.rows[2] = Vector3(c.m[8], c.m[9], c.m[10]);
    Transform3D result;
    result.set_basis(basis);
    result.set_origin(Vector3(c.m[3], c.m[7], c.m[11]));
    return result;
}

Ref<OcctlTransform> OcctlGodot::transform3d_to_transform(const Transform3D& t) {
    occtl_transform_t c;
    const Vector3& o = t.get_origin();
    const Basis& b = t.get_basis();
    c.m[0] = b.rows[0].x;  c.m[1]  = b.rows[0].y;  c.m[2]  = b.rows[0].z;  c.m[3]  = o.x;
    c.m[4] = b.rows[1].x;  c.m[5]  = b.rows[1].y;  c.m[6]  = b.rows[1].z;  c.m[7]  = o.y;
    c.m[8] = b.rows[2].x;  c.m[9]  = b.rows[2].y;  c.m[10] = b.rows[2].z;  c.m[11] = o.z;
    return OcctlTransform::from_c(c);
}

// ========================================================================
// Aabb3 <-> AABB
// ========================================================================

AABB OcctlGodot::aabb3_to_aabb(const Ref<OcctlAabb3>& a) {
    const occtl_aabb3_t c = a->to_c();
    return AABB(
        Vector3(c.min.x, c.min.y, c.min.z),
        Vector3(c.max.x - c.min.x, c.max.y - c.min.y, c.max.z - c.min.z));
}

Ref<OcctlAabb3> OcctlGodot::aabb_to_aabb3(const AABB& a) {
    occtl_aabb3_t c;
    const Vector3& pos = a.get_position();
    const Vector3& sz = a.get_size();
    c.min.x = pos.x;           c.min.y = pos.y;           c.min.z = pos.z;
    c.max.x = pos.x + sz.x;    c.max.y = pos.y + sz.y;    c.max.z = pos.z + sz.z;
    return OcctlAabb3::from_c(c);
}

// ========================================================================
// ColorRgba <-> Color
// ========================================================================

Color OcctlGodot::color_rgba_to_color(const Ref<OcctlColorRgba>& c) {
    const occtl_color_rgba_t cc = c->to_c();
    return Color(cc.r, cc.g, cc.b, cc.a);
}

Ref<OcctlColorRgba> OcctlGodot::color_to_color_rgba(const Color& c) {
    occtl_color_rgba_t cc;
    cc.r = c.r;
    cc.g = c.g;
    cc.b = c.b;
    cc.a = c.a;
    return OcctlColorRgba::from_c(cc);
}

// ========================================================================
// Point2 <-> Vector2
// ========================================================================

Vector2 OcctlGodot::point2_to_vector2(const Ref<OcctlPoint2>& p) {
    const occtl_point2_t c = p->to_c();
    return Vector2(c.x, c.y);
}

Ref<OcctlPoint2> OcctlGodot::vector2_to_point2(const Vector2& v) {
    occtl_point2_t c;
    c.x = v.x;
    c.y = v.y;
    return OcctlPoint2::from_c(c);
}

// ========================================================================
// Axis placement -> Transform3D
// ========================================================================

Transform3D OcctlGodot::axis1_placement_to_transform3d(const Ref<OcctlAxis1Placement>& a) {
    const occtl_axis1_placement_t c = a->to_c();
    const double zx = c.direction.x, zy = c.direction.y, zz = c.direction.z;
    double xd_x, xd_y, xd_z;
    const double azx = fabs(zx), azy = fabs(zy), azz = fabs(zz);
    if (azx <= azy && azx <= azz) {
        xd_x = 0.0; xd_y = zz; xd_z = -zy;
    } else if (azy <= azx && azy <= azz) {
        xd_x = -zz; xd_y = 0.0; xd_z = zx;
    } else {
        xd_x = zy; xd_y = -zx; xd_z = 0.0;
    }
    const double x_len = sqrt(xd_x * xd_x + xd_y * xd_y + xd_z * xd_z);
    if (x_len < 1e-15) return Transform3D();
    const double inv_x = 1.0 / x_len;
    xd_x *= inv_x; xd_y *= inv_x; xd_z *= inv_x;
    const double yd_x = zy * xd_z - zz * xd_y;
    const double yd_y = zz * xd_x - zx * xd_z;
    const double yd_z = zx * xd_y - zy * xd_x;
    Basis basis;
    basis.rows[0] = Vector3(xd_x, xd_y, xd_z);
    basis.rows[1] = Vector3(yd_x, yd_y, yd_z);
    basis.rows[2] = Vector3(zx, zy, zz);
    Transform3D result;
    result.set_basis(basis);
    result.set_origin(Vector3(c.location.x, c.location.y, c.location.z));
    return result;
}

Transform3D OcctlGodot::axis2_placement_to_transform3d(const Ref<OcctlAxis2Placement>& a) {
    const occtl_axis2_placement_t c = a->to_c();
    const double x_x = c.x_dir.x, x_y = c.x_dir.y, x_z = c.x_dir.z;
    const double dot = x_x * c.x_dir_ref.x + x_y * c.x_dir_ref.y + x_z * c.x_dir_ref.z;
    double y_x = c.x_dir_ref.x - dot * x_x;
    double y_y = c.x_dir_ref.y - dot * x_y;
    double y_z = c.x_dir_ref.z - dot * x_z;
    const double y_len = sqrt(y_x * y_x + y_y * y_y + y_z * y_z);
    if (y_len < 1e-15) return Transform3D();
    const double inv_y = 1.0 / y_len;
    y_x *= inv_y; y_y *= inv_y; y_z *= inv_y;
    const double z_x = x_y * y_z - x_z * y_y;
    const double z_y = x_z * y_x - x_x * y_z;
    const double z_z = x_x * y_y - x_y * y_x;
    Basis basis;
    basis.rows[0] = Vector3(x_x, x_y, x_z);
    basis.rows[1] = Vector3(y_x, y_y, y_z);
    basis.rows[2] = Vector3(z_x, z_y, z_z);
    Transform3D result;
    result.set_basis(basis);
    result.set_origin(Vector3(c.location.x, c.location.y, c.location.z));
    return result;
}

Transform3D OcctlGodot::axis3_placement_to_transform3d(const Ref<OcctlAxis3Placement>& a) {
    const occtl_axis3_placement_t c = a->to_c();
    Basis basis;
    basis.rows[0] = Vector3(c.x_dir.x, c.x_dir.y, c.x_dir.z);
    basis.rows[1] = Vector3(c.y_dir.x, c.y_dir.y, c.y_dir.z);
    basis.rows[2] = Vector3(c.z_dir.x, c.z_dir.y, c.z_dir.z);
    Transform3D result;
    result.set_basis(basis);
    result.set_origin(Vector3(c.location.x, c.location.y, c.location.z));
    return result;
}

// ========================================================================
// Edge batch → mesh
// ========================================================================

Ref<ArrayMesh> OcctlGodot::edges_to_mesh(
    const Ref<OcctlGraphHandle>& graph,
    const Variant& edge_ids,
    double radius,
    bool include_normals,
    bool include_feature_ids,
    double deflection,
    double angle)
{
    occtl_graph_t* g = _graph_ptr_mut(graph);
    if (!g) {
        Ref<ArrayMesh> empty;
        empty.instantiate();
        return empty;
    }

    std::vector<int64_t> ids;
    if (!_resolve_ids(edge_ids, g, OCCTL_KIND_EDGE, ids)) {
        Ref<ArrayMesh> empty;
        empty.instantiate();
        return empty;
    }

    static const int TUBE_SEGMENTS = 8;
    MeshAccum acc;

    for (int64_t ei : ids) {
        occtl_polygon3d_view_t poly_view;
        occtl_status_t status = ::occtl_mesh_edge_polygon3d(
            g, occtl_node_id_t{static_cast<uint64_t>(ei)}, &poly_view);

        if (status != OCCTL_OK || poly_view.node_count < 2) {
            // No cached polygon — try generating mesh data with the given deflection
            occtl_node_id_t nid{static_cast<uint64_t>(ei)};
            occtl_mesh_options_t opts = OCCTL_MESH_OPTIONS_INIT;
            opts.deflection = deflection;
            opts.angle = angle;
            occtl_status_t gen_st = ::occtl_mesh_generate(g, &nid, 1, &opts);

            // Try reading the cached polygonization again
            if (gen_st == OCCTL_OK) {
                status = ::occtl_mesh_edge_polygon3d(
                    g, occtl_node_id_t{static_cast<uint64_t>(ei)}, &poly_view);
            }
        }

        if (status != OCCTL_OK || poly_view.node_count < 2) {
            // Still no data — fall back to sampling the edge's 3D curve directly
            std::vector<Vector3> sampled;
            if (!_sample_edge_curve(g, occtl_node_id_t{static_cast<uint64_t>(ei)},
                    deflection, sampled) || sampled.size() < 2) {
                continue;
            }

            // Build a flat double array for _build_tube
            std::vector<double> flat_nodes;
            flat_nodes.reserve(sampled.size() * 3);
            for (const auto& v : sampled) {
                flat_nodes.push_back(v.x);
                flat_nodes.push_back(v.y);
                flat_nodes.push_back(v.z);
            }

            if (radius > 0.0) {
                _build_tube(acc, flat_nodes.data(), sampled.size(),
                    radius, TUBE_SEGMENTS,
                    include_normals, ei, include_feature_ids);
            } else {
                int base = static_cast<int>(acc.verts.size());
                for (const auto& v : sampled) {
                    acc.verts.push_back(v);
                }
                for (size_t j = 0; j + 1 < sampled.size(); ++j) {
                    acc.indices.push_back(base + static_cast<int>(j));
                    acc.indices.push_back(base + static_cast<int>(j + 1));
                }
            }
            continue;
        }

        if (radius > 0.0) {
            _build_tube(acc, poly_view.nodes, poly_view.node_count,
                radius, TUBE_SEGMENTS,
                include_normals, ei, include_feature_ids);
        } else {
            int base = static_cast<int>(acc.verts.size());
            for (size_t j = 0; j < poly_view.node_count; ++j) {
                acc.verts.push_back(Vector3(
                    poly_view.nodes[j * 3],
                    poly_view.nodes[j * 3 + 1],
                    poly_view.nodes[j * 3 + 2]));
            }
            for (size_t j = 0; j + 1 < poly_view.node_count; ++j) {
                acc.indices.push_back(base + static_cast<int>(j));
                acc.indices.push_back(base + static_cast<int>(j + 1));
            }
        }
    }

    return _finalize_mesh(acc.verts, acc.normals, acc.uvs, acc.colors,
        PackedFloat64Array(), acc.indices,
        radius > 0.0 ? Mesh::PRIMITIVE_TRIANGLES : Mesh::PRIMITIVE_LINES);
}

// ========================================================================
// Vertices batch → mesh
// ========================================================================

Ref<ArrayMesh> OcctlGodot::vertices_to_mesh(
    const Ref<OcctlGraphHandle>& graph,
    const Variant& vertex_ids,
    bool include_normals,
    bool include_feature_ids,
    double deflection,
    double angle)
{
    const occtl_graph_t* g = _graph_ptr(graph);
    if (!g) {
        Ref<ArrayMesh> empty;
        empty.instantiate();
        return empty;
    }

    std::vector<int64_t> ids;
    if (!_resolve_ids(vertex_ids, g, OCCTL_KIND_VERTEX, ids)) {
        Ref<ArrayMesh> empty;
        empty.instantiate();
        return empty;
    }

    MeshAccum acc;

    for (int64_t vi : ids) {
        occtl_point3_t pt;
        occtl_status_t status = ::occtl_topo_vertex_point(
            g, occtl_node_id_t{static_cast<uint64_t>(vi)}, &pt);
        if (status != OCCTL_OK) continue;

        _build_vertex_marker(acc, Vector3(pt.x, pt.y, pt.z),
            include_normals, vi, include_feature_ids, deflection);
    }
    (void)angle;

    return _finalize_mesh(acc.verts, acc.normals, acc.uvs, acc.colors,
        PackedFloat64Array(), acc.indices,
        Mesh::PRIMITIVE_TRIANGLES);
}

// ========================================================================
// Face triangulation batch → mesh
// ========================================================================

Ref<ArrayMesh> OcctlGodot::faces_to_mesh(
    const Ref<OcctlGraphHandle>& graph,
    const Variant& face_ids,
    bool include_normals,
    bool include_uvs,
    bool include_tangents,
    bool include_feature_ids,
    double deflection,
    double angle)
{
    occtl_graph_t* g = _graph_ptr_mut(graph);
    if (!g) {
        Ref<ArrayMesh> empty;
        empty.instantiate();
        return empty;
    }

    std::vector<int64_t> ids;
    if (!_resolve_ids(face_ids, g, OCCTL_KIND_FACE, ids)) {
        Ref<ArrayMesh> empty;
        empty.instantiate();
        return empty;
    }

    // Ensure mesh data is available (generate on-the-fly if needed)
    _ensure_mesh_generated(g, ids, deflection, angle);

    MeshAccum acc;
    bool have_normals = false;
    bool have_uvs = false;

    for (int64_t fi : ids) {
        occtl_triangulation_view_t tri_view;
        occtl_status_t status = ::occtl_mesh_face_triangulation(
            g, occtl_node_id_t{static_cast<uint64_t>(fi)}, &tri_view);
        if (status != OCCTL_OK) continue;

        int nv = static_cast<int>(tri_view.node_count);
        int nt = static_cast<int>(tri_view.triangle_count);
        if (nv <= 0 || nt <= 0) continue;

        Color fcolor;
        if (include_feature_ids) {
            fcolor = _feature_id_color(fi);
        }

        int base = static_cast<int>(acc.verts.size());
        bool face_has_normals = include_normals && tri_view.normals != nullptr;
        bool face_has_uvs = include_uvs && tri_view.uvs != nullptr;

        // If normals are requested but the triangulation doesn't have them,
        // compute them from the geometry
        std::vector<Vector3> computed_normals;
        if (include_normals && tri_view.normals == nullptr) {
            computed_normals = _compute_triangulation_normals(
                tri_view.nodes, tri_view.node_count,
                tri_view.triangles, tri_view.triangle_count);
            face_has_normals = true;
        }

        for (int j = 0; j < nv; ++j) {
            acc.verts.push_back(Vector3(
                tri_view.nodes[j * 3],
                tri_view.nodes[j * 3 + 1],
                tri_view.nodes[j * 3 + 2]));

            if (face_has_normals) {
                have_normals = true;
                if (!computed_normals.empty()) {
                    acc.normals.push_back(computed_normals[static_cast<size_t>(j)]);
                } else {
                    acc.normals.push_back(Vector3(
                        tri_view.normals[j * 3],
                        tri_view.normals[j * 3 + 1],
                        tri_view.normals[j * 3 + 2]));
                }
            }

            if (face_has_uvs) {
                have_uvs = true;
                acc.uvs.push_back(Vector2(
                    tri_view.uvs[j * 2],
                    tri_view.uvs[j * 2 + 1]));
            }

            if (include_feature_ids) {
                acc.colors.push_back(fcolor);
            }
        }

        for (int j = 0; j < nt; ++j) {
            acc.indices.push_back(base + static_cast<int>(tri_view.triangles[j * 3]));
            acc.indices.push_back(base + static_cast<int>(tri_view.triangles[j * 3 + 1]));
            acc.indices.push_back(base + static_cast<int>(tri_view.triangles[j * 3 + 2]));
        }
    }

    PackedFloat64Array tangents;
    if (include_tangents && have_normals && have_uvs && !acc.verts.empty()) {
        tangents = _compute_tangents(acc.verts, acc.normals, acc.uvs, acc.indices);
    }

    return _finalize_mesh(acc.verts, acc.normals, acc.uvs, acc.colors,
        tangents, acc.indices,
        Mesh::PRIMITIVE_TRIANGLES);
}
