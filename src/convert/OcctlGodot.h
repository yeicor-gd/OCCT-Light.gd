#ifndef OCCTLGODOT_H
#define OCCTLGODOT_H

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/array_mesh.hpp>

#include "occtl/occtl_core.h"
#include "occtl/occtl_mesh.h"
#include "occtl/occtl_topo.h"

#include "../autowrapper/OcctlGraphHandle.h"
#include "../autowrapper/OcctlTriangulationView.h"
#include "../autowrapper/OcctlPolygon3dView.h"
#include "../autowrapper/OcctlPoint2.h"
#include "../autowrapper/OcctlPoint3.h"
#include "../autowrapper/OcctlDirection3.h"
#include "../autowrapper/OcctlVector3.h"
#include "../autowrapper/OcctlTransform.h"
#include "../autowrapper/OcctlAabb3.h"
#include "../autowrapper/OcctlColorRgba.h"
#include "../autowrapper/OcctlAxis1Placement.h"
#include "../autowrapper/OcctlAxis2Placement.h"
#include "../autowrapper/OcctlAxis3Placement.h"

#include <vector>
#include <cstdint>
#include <cmath>

using namespace godot;

class OcctlGodot : public godot::RefCounted {
    GDCLASS(OcctlGodot, godot::RefCounted)
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

    // -- Value type → Godot conversion helpers (documented in OcctlGodot.xml) --

    // -- Edge batch → single mesh (tube if radius>0, line strip if radius==0) --
    // When edge_ids is null (default), all edges in the graph are exported.
    static Ref<ArrayMesh> edges_to_mesh(
        const Ref<OcctlGraphHandle>& graph,
        const Variant& edge_ids = Variant(),
        double radius = 0.0,
        bool include_normals = true,
        bool include_feature_ids = false);

    // -- Vertex batch → single mesh (tetrahedron markers) --
    // When vertex_ids is null (default), all vertices in the graph are exported.
    static Ref<ArrayMesh> vertices_to_mesh(
        const Ref<OcctlGraphHandle>& graph,
        const Variant& vertex_ids = Variant(),
        bool include_normals = true,
        bool include_feature_ids = false);

    // -- Face triangulation batch → single mesh --
    // When face_ids is null (default), all faces in the graph are exported.
    static Ref<ArrayMesh> faces_to_mesh(
        const Ref<OcctlGraphHandle>& graph,
        const Variant& face_ids = Variant(),
        bool include_normals = true,
        bool include_uvs = true,
        bool include_tangents = false,
        bool include_feature_ids = false);
};

#endif // OCCTLGODOT_H
