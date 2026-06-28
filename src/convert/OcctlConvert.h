#ifndef OCCTLCONVERT_H
#define OCCTLCONVERT_H

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/classes/array_mesh.hpp>

#include "occtl/occtl_geom.h"
#include "occtl/occtl_mesh.h"

#include "../autowrapper/OcctlAabb3.h"
#include "../autowrapper/OcctlAxis1Placement.h"
#include "../autowrapper/OcctlAxis2Placement.h"
#include "../autowrapper/OcctlAxis3Placement.h"
#include "../autowrapper/OcctlColorRgba.h"
#include "../autowrapper/OcctlDirection3.h"
#include "../autowrapper/OcctlMeshTriangleBuffersView.h"
#include "../autowrapper/OcctlPoint2.h"
#include "../autowrapper/OcctlPoint3.h"
#include "../autowrapper/OcctlPolygon3dView.h"
#include "../autowrapper/OcctlPolygonOnTriView.h"
#include "../autowrapper/OcctlTransform.h"
#include "../autowrapper/OcctlTriangulationView.h"
#include "../autowrapper/OcctlVector3.h"

using namespace godot;

class OcctlConvert : public godot::RefCounted {
    GDCLASS(OcctlConvert, godot::RefCounted)
protected:
    static void _bind_methods();
public:
    // -- Value type conversions --

    static Vector3 point3_to_vector3(const Ref<OcctlPoint3>& p);
    static Ref<OcctlPoint3> vector3_to_point3(const Vector3& v);

    static Vector3 occtl_vector3_to_godot(const Ref<OcctlVector3>& v);
    static Ref<OcctlVector3> godot_to_occtl_vector3(const Vector3& v);

    static Vector3 direction3_to_vector3(const Ref<OcctlDirection3>& d);
    static Ref<OcctlDirection3> vector3_to_direction3(const Vector3& v);

    static Transform3D transform_to_transform3d(const Ref<OcctlTransform>& t);
    static Ref<OcctlTransform> transform3d_to_transform(const Transform3D& t);

    static AABB aabb3_to_aabb(const Ref<OcctlAabb3>& a);
    static Ref<OcctlAabb3> aabb_to_aabb3(const AABB& a);

    static Color color_rgba_to_color(const Ref<OcctlColorRgba>& c);
    static Ref<OcctlColorRgba> color_to_color_rgba(const Color& c);

    static Vector2 point2_to_vector2(const Ref<OcctlPoint2>& p);
    static Ref<OcctlPoint2> vector2_to_point2(const Vector2& v);

    // -- Axis placement → Transform3D --

    static Transform3D axis1_placement_to_transform3d(const Ref<OcctlAxis1Placement>& a);
    static Transform3D axis2_placement_to_transform3d(const Ref<OcctlAxis2Placement>& a);
    static Transform3D axis3_placement_to_transform3d(const Ref<OcctlAxis3Placement>& a);

    // -- Mesh/Triangulation → ArrayMesh --

    static Ref<ArrayMesh> triangulation_to_array_mesh(const Ref<OcctlTriangulationView>& view);
    static Ref<ArrayMesh> mesh_buffers_to_array_mesh(const Ref<OcctlMeshTriangleBuffersView>& view);

    // -- Polygon views → point arrays --

    static PackedVector3Array polygon3d_to_points(const Ref<OcctlPolygon3dView>& view);
    static PackedVector3Array polygon_on_tri_to_world_points(
        const Ref<OcctlTriangulationView>& tri_view,
        const Ref<OcctlPolygonOnTriView>& poly_view);

    // -- Helper: build ArrayMesh surface arrays from raw pointers (internal) --
private:
    static Ref<ArrayMesh> _build_array_mesh(
        const double* nodes, int node_count,
        const double* normals,
        const double* uvs,
        const uint32_t* triangles, int triangle_count);
};

#endif // OCCTLCONVERT_H
