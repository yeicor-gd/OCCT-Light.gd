#include "OcctlConvert.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <cstring>

void OcctlConvert::_bind_methods() {
    // --- Value conversions ---
    ClassDB::bind_static_method("OcctlConvert", D_METHOD("point3_to_vector3", "p"), &OcctlConvert::point3_to_vector3);
    ClassDB::bind_static_method("OcctlConvert", D_METHOD("vector3_to_point3", "v"), &OcctlConvert::vector3_to_point3);

    ClassDB::bind_static_method("OcctlConvert", D_METHOD("occtl_vector3_to_godot", "v"), &OcctlConvert::occtl_vector3_to_godot);
    ClassDB::bind_static_method("OcctlConvert", D_METHOD("godot_to_occtl_vector3", "v"), &OcctlConvert::godot_to_occtl_vector3);

    ClassDB::bind_static_method("OcctlConvert", D_METHOD("direction3_to_vector3", "d"), &OcctlConvert::direction3_to_vector3);
    ClassDB::bind_static_method("OcctlConvert", D_METHOD("vector3_to_direction3", "v"), &OcctlConvert::vector3_to_direction3);

    ClassDB::bind_static_method("OcctlConvert", D_METHOD("transform_to_transform3d", "t"), &OcctlConvert::transform_to_transform3d);
    ClassDB::bind_static_method("OcctlConvert", D_METHOD("transform3d_to_transform", "t"), &OcctlConvert::transform3d_to_transform);

    ClassDB::bind_static_method("OcctlConvert", D_METHOD("aabb3_to_aabb", "a"), &OcctlConvert::aabb3_to_aabb);
    ClassDB::bind_static_method("OcctlConvert", D_METHOD("aabb_to_aabb3", "a"), &OcctlConvert::aabb_to_aabb3);

    ClassDB::bind_static_method("OcctlConvert", D_METHOD("color_rgba_to_color", "c"), &OcctlConvert::color_rgba_to_color);
    ClassDB::bind_static_method("OcctlConvert", D_METHOD("color_to_color_rgba", "c"), &OcctlConvert::color_to_color_rgba);

    ClassDB::bind_static_method("OcctlConvert", D_METHOD("point2_to_vector2", "p"), &OcctlConvert::point2_to_vector2);
    ClassDB::bind_static_method("OcctlConvert", D_METHOD("vector2_to_point2", "v"), &OcctlConvert::vector2_to_point2);

    // --- Axis placement to Transform3D ---
    ClassDB::bind_static_method("OcctlConvert", D_METHOD("axis1_placement_to_transform3d", "a"), &OcctlConvert::axis1_placement_to_transform3d);
    ClassDB::bind_static_method("OcctlConvert", D_METHOD("axis2_placement_to_transform3d", "a"), &OcctlConvert::axis2_placement_to_transform3d);
    ClassDB::bind_static_method("OcctlConvert", D_METHOD("axis3_placement_to_transform3d", "a"), &OcctlConvert::axis3_placement_to_transform3d);

    // --- Mesh/Triangulation to ArrayMesh ---
    ClassDB::bind_static_method("OcctlConvert", D_METHOD("triangulation_to_array_mesh", "view"), &OcctlConvert::triangulation_to_array_mesh);
    ClassDB::bind_static_method("OcctlConvert", D_METHOD("mesh_buffers_to_array_mesh", "view"), &OcctlConvert::mesh_buffers_to_array_mesh);

    // --- Polygon views ---
    ClassDB::bind_static_method("OcctlConvert", D_METHOD("polygon3d_to_points", "view"), &OcctlConvert::polygon3d_to_points);
    ClassDB::bind_static_method("OcctlConvert", D_METHOD("polygon_on_tri_to_world_points", "tri_view", "poly_view"), &OcctlConvert::polygon_on_tri_to_world_points);
}

// ========================================================================
// Point3 <-> Vector3
// ========================================================================

Vector3 OcctlConvert::point3_to_vector3(const Ref<OcctlPoint3>& p) {
    const occtl_point3_t c = p->to_c();
    return Vector3(c.x, c.y, c.z);
}

Ref<OcctlPoint3> OcctlConvert::vector3_to_point3(const Vector3& v) {
    occtl_point3_t c;
    c.x = v.x;
    c.y = v.y;
    c.z = v.z;
    return OcctlPoint3::from_c(c);
}

// ========================================================================
// OCCT Vector3 <-> Godot Vector3
// ========================================================================

Vector3 OcctlConvert::occtl_vector3_to_godot(const Ref<OcctlVector3>& v) {
    const occtl_vector3_t c = v->to_c();
    return Vector3(c.x, c.y, c.z);
}

Ref<OcctlVector3> OcctlConvert::godot_to_occtl_vector3(const Vector3& v) {
    occtl_vector3_t c;
    c.x = v.x;
    c.y = v.y;
    c.z = v.z;
    return OcctlVector3::from_c(c);
}

// ========================================================================
// Direction3 <-> Vector3
// ========================================================================

Vector3 OcctlConvert::direction3_to_vector3(const Ref<OcctlDirection3>& d) {
    const occtl_direction3_t c = d->to_c();
    return Vector3(c.x, c.y, c.z);
}

Ref<OcctlDirection3> OcctlConvert::vector3_to_direction3(const Vector3& v) {
    occtl_direction3_t c;
    c.x = v.x;
    c.y = v.y;
    c.z = v.z;
    return OcctlDirection3::from_c(c);
}

// ========================================================================
// Transform <-> Transform3D
//
// occtl_transform_t is row-major 3x4:
//   m[0..3]  row 0: [a00 a01 a02 tx]
//   m[4..7]  row 1: [a10 a11 a12 ty]
//   m[8..11] row 2: [a20 a21 a22 tz]
//
// Godot Transform3D stores basis as 3 row vectors + origin.
//   basis.rows[0] = (m[0], m[1], m[2])   = x basis vector
//   basis.rows[1] = (m[4], m[5], m[6])   = y basis vector
//   basis.rows[2] = (m[8], m[9], m[10])  = z basis vector
//   origin        = (m[3], m[7], m[11])
// ========================================================================

Transform3D OcctlConvert::transform_to_transform3d(const Ref<OcctlTransform>& t) {
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

Ref<OcctlTransform> OcctlConvert::transform3d_to_transform(const Transform3D& t) {
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

AABB OcctlConvert::aabb3_to_aabb(const Ref<OcctlAabb3>& a) {
    const occtl_aabb3_t c = a->to_c();
    return AABB(
        Vector3(c.min.x, c.min.y, c.min.z),
        Vector3(c.max.x - c.min.x, c.max.y - c.min.y, c.max.z - c.min.z));
}

Ref<OcctlAabb3> OcctlConvert::aabb_to_aabb3(const AABB& a) {
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

Color OcctlConvert::color_rgba_to_color(const Ref<OcctlColorRgba>& c) {
    const occtl_color_rgba_t cc = c->to_c();
    return Color(cc.r, cc.g, cc.b, cc.a);
}

Ref<OcctlColorRgba> OcctlConvert::color_to_color_rgba(const Color& c) {
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

Vector2 OcctlConvert::point2_to_vector2(const Ref<OcctlPoint2>& p) {
    const occtl_point2_t c = p->to_c();
    return Vector2(c.x, c.y);
}

Ref<OcctlPoint2> OcctlConvert::vector2_to_point2(const Vector2& v) {
    occtl_point2_t c;
    c.x = v.x;
    c.y = v.y;
    return OcctlPoint2::from_c(c);
}

// ========================================================================
// Axis placement -> Transform3D
//
// These construct a frame->world Transform3D directly, without going
// through occtl_transform_from_axis* (which returns world->frame).
//
// AXIS1:  Z = direction,  X = any perpendicular to Z,  Y = Z x X
// AXIS2:  X = x_dir,      Y = component of x_dir_ref orthogonal to X,  Z = X x Y
// AXIS3:  X = x_dir,      Y = y_dir,  Z = z_dir
// ========================================================================

Transform3D OcctlConvert::axis1_placement_to_transform3d(const Ref<OcctlAxis1Placement>& a) {
    const occtl_axis1_placement_t c = a->to_c();

    // Z = direction.  Pick X as a perpendicular vector.
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

Transform3D OcctlConvert::axis2_placement_to_transform3d(const Ref<OcctlAxis2Placement>& a) {
    const occtl_axis2_placement_t c = a->to_c();

    const double x_x = c.x_dir.x, x_y = c.x_dir.y, x_z = c.x_dir.z;
    // Y = component of x_dir_ref orthogonal to x_dir
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

Transform3D OcctlConvert::axis3_placement_to_transform3d(const Ref<OcctlAxis3Placement>& a) {
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
// Triangulation -> ArrayMesh
// ========================================================================

Ref<ArrayMesh> OcctlConvert::triangulation_to_array_mesh(const Ref<OcctlTriangulationView>& view) {
    const double* tri_nodes = reinterpret_cast<const double*>(static_cast<uintptr_t>(view->nodes));
    const double* tri_normals = reinterpret_cast<const double*>(static_cast<uintptr_t>(view->normals));
    const double* tri_uvs = reinterpret_cast<const double*>(static_cast<uintptr_t>(view->uvs));
    const uint32_t* tri_indices = reinterpret_cast<const uint32_t*>(static_cast<uintptr_t>(view->triangles));
    return _build_array_mesh(tri_nodes, view->node_count, tri_normals, tri_uvs, tri_indices, view->triangle_count);
}

Ref<ArrayMesh> OcctlConvert::mesh_buffers_to_array_mesh(const Ref<OcctlMeshTriangleBuffersView>& view) {
    const double* buf_nodes = reinterpret_cast<const double*>(static_cast<uintptr_t>(view->nodes));
    const uint32_t* buf_triangles = reinterpret_cast<const uint32_t*>(static_cast<uintptr_t>(view->triangles));
    return _build_array_mesh(buf_nodes, view->node_count, nullptr, nullptr, buf_triangles, view->triangle_count);
}

// ========================================================================
// Polygon3d -> PackedVector3Array
// ========================================================================

PackedVector3Array OcctlConvert::polygon3d_to_points(const Ref<OcctlPolygon3dView>& view) {
    PackedVector3Array points;
    if (view.is_null()) { return points; }
    const int64_t raw_nodes = view->get_nodes();
    if (raw_nodes == 0 || view->get_node_count() <= 0) {
        return points;
    }
    const double* nodes_ptr = reinterpret_cast<const double*>(static_cast<uintptr_t>(raw_nodes));
    points.resize(view->get_node_count());
    for (int i = 0; i < view->get_node_count(); ++i) {
        points.set(i, Vector3(nodes_ptr[i * 3], nodes_ptr[i * 3 + 1], nodes_ptr[i * 3 + 2]));
    }
    return points;
}

// ========================================================================
// PolygonOnTri -> world-space 3D points
// ========================================================================

PackedVector3Array OcctlConvert::polygon_on_tri_to_world_points(
    const Ref<OcctlTriangulationView>& tri_view,
    const Ref<OcctlPolygonOnTriView>& poly_view)
{
    PackedVector3Array points;
    const int64_t raw_tri_nodes = tri_view->nodes;
    const int64_t raw_node_indices = poly_view->node_indices;
    if (raw_tri_nodes == 0 || raw_node_indices == 0 || poly_view->node_count <= 0) {
        return points;
    }
    const double* tri_nodes = reinterpret_cast<const double*>(static_cast<uintptr_t>(raw_tri_nodes));
    const uint32_t* node_indices = reinterpret_cast<const uint32_t*>(static_cast<uintptr_t>(raw_node_indices));
    points.resize(poly_view->node_count);
    for (int i = 0; i < poly_view->node_count; ++i) {
        const uint32_t ni = node_indices[i];
        if (static_cast<int>(ni) < tri_view->node_count) {
            points.set(i, Vector3(tri_nodes[ni * 3], tri_nodes[ni * 3 + 1], tri_nodes[ni * 3 + 2]));
        } else {
            points.set(i, Vector3());
        }
    }
    return points;
}

// ========================================================================
// Internal: build ArrayMesh surface from raw mesh data
// ========================================================================

Ref<ArrayMesh> OcctlConvert::_build_array_mesh(
    const double* nodes, int node_count,
    const double* normals,
    const double* uvs,
    const uint32_t* triangles, int triangle_count)
{
    Ref<ArrayMesh> mesh;
    mesh.instantiate();
    if (nodes == nullptr || triangles == nullptr || node_count <= 0 || triangle_count <= 0) {
        return mesh;
    }

    PackedVector3Array verts;
    verts.resize(node_count);
    for (int i = 0; i < node_count; ++i) {
        verts.set(i, Vector3(nodes[i * 3], nodes[i * 3 + 1], nodes[i * 3 + 2]));
    }

    PackedVector3Array norms;
    if (normals != nullptr) {
        norms.resize(node_count);
        for (int i = 0; i < node_count; ++i) {
            norms.set(i, Vector3(normals[i * 3], normals[i * 3 + 1], normals[i * 3 + 2]));
        }
    }

    PackedVector2Array uv_arr;
    if (uvs != nullptr) {
        uv_arr.resize(node_count);
        for (int i = 0; i < node_count; ++i) {
            uv_arr.set(i, Vector2(uvs[i * 2], uvs[i * 2 + 1]));
        }
    }

    const int idx_count = triangle_count * 3;
    PackedInt32Array indices;
    indices.resize(idx_count);
    for (int i = 0; i < idx_count; ++i) {
        indices.set(i, static_cast<int32_t>(triangles[i]));
    }

    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = verts;
    arrays[Mesh::ARRAY_INDEX] = indices;
    if (normals != nullptr) {
        arrays[Mesh::ARRAY_NORMAL] = norms;
    }
    if (uvs != nullptr) {
        arrays[Mesh::ARRAY_TEX_UV] = uv_arr;
    }

    mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    return mesh;
}
