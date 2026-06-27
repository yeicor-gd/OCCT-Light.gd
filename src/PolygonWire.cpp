#include "PolygonWire.h"

#include "Plane.h"
#include "OCCTUtils.h"

#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

namespace {

Ref<CadPlane> default_xy_plane() {
    Ref<CadPlane> plane;
    plane.instantiate();
    plane->set_plane(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0));
    return plane;
}

Vector3 plane_point(const Ref<CadPlane> &p_plane, const Vector2 &p_point) {
    return p_plane->get_origin()
        + p_plane->get_x_direction() * p_point.x
        + p_plane->get_y_direction() * p_point.y;
}

} // namespace

void PolygonWire::_bind_methods() {
    ClassDB::bind_method(D_METHOD("build_polygon_2d", "points", "plane", "closed"), &PolygonWire::build_polygon_2d, DEFVAL(Ref<CadPlane>()), DEFVAL(true));
}

PolygonWire::PolygonWire() = default;

void PolygonWire::build_polygon_2d(const PackedVector2Array &p_points, const Ref<CadPlane> &p_plane, bool p_closed) {
    ERR_FAIL_COND_MSG(p_points.size() < (p_closed ? 3 : 2), "PolygonWire.build_polygon_2d requires at least 3 points for closed polygons or 2 for open ones.");

    Ref<CadPlane> plane = p_plane;
    if (plane.is_null()) {
        plane = default_xy_plane();
    }

    try {
        PackedVector3Array points_3d;
        points_3d.resize(p_points.size());
        for (int64_t index = 0; index < p_points.size(); ++index) {
            points_3d.set(index, plane_point(plane, p_points[index]));
        }

        build_polygon(points_3d, p_closed);
    } catch (const Standard_Failure &e) {
        ERR_PRINT(vformat("PolygonWire.build_polygon_2d failed: %s", occt_utils::exception_to_string(e)));
    }
}
