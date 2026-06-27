#include "RectangleRoundedWire.h"

#include "Plane.h"
#include "OCCTUtils.h"

#include <godot_cpp/core/error_macros.hpp>

#include <BRepBuilderAPI_MakeEdge.hxx>
#include <BRepBuilderAPI_MakeWire.hxx>
#include <GC_MakeArcOfCircle.hxx>

#include <cmath>

using namespace godot;

namespace {

Ref<CadPlane> default_xy_plane() {
    Ref<CadPlane> plane;
    plane.instantiate();
    plane->set_plane(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0));
    return plane;
}

Vector3 plane_point(const Ref<CadPlane> &p_plane, double p_u, double p_v) {
    return p_plane->get_origin()
        + p_plane->get_x_direction() * static_cast<real_t>(p_u)
        + p_plane->get_y_direction() * static_cast<real_t>(p_v);
}

TopoDS_Edge make_line_edge(const Vector3 &p_start, const Vector3 &p_end) {
    try {
        BRepBuilderAPI_MakeEdge builder(occt_utils::to_occt_point(p_start), occt_utils::to_occt_point(p_end));
        if (!builder.IsDone()) {
            ERR_PRINT(vformat("RectangleRoundedWire: line-edge construction did not complete"));
            return TopoDS_Edge();
        }
        return builder.Edge();
    } catch (const Standard_Failure &e) {
        ERR_PRINT(vformat("RectangleRoundedWire: line-edge construction failed: %s", occt_utils::exception_to_string(e)));
        return TopoDS_Edge();
    }
}

TopoDS_Edge make_arc_edge(const Vector3 &p_start, const Vector3 &p_mid, const Vector3 &p_end) {
    try {
        GC_MakeArcOfCircle builder(
            occt_utils::to_occt_point(p_start),
            occt_utils::to_occt_point(p_mid),
            occt_utils::to_occt_point(p_end));
        if (!builder.IsDone()) {
            ERR_PRINT(vformat("RectangleRoundedWire: arc construction did not complete"));
            return TopoDS_Edge();
        }

        BRepBuilderAPI_MakeEdge edge_builder(builder.Value());
        if (!edge_builder.IsDone()) {
            ERR_PRINT(vformat("RectangleRoundedWire: arc-edge construction did not complete"));
            return TopoDS_Edge();
        }
        return edge_builder.Edge();
    } catch (const Standard_Failure &e) {
        ERR_PRINT(vformat("RectangleRoundedWire: arc construction failed: %s", occt_utils::exception_to_string(e)));
        return TopoDS_Edge();
    }
}

} // namespace

void RectangleRoundedWire::_bind_methods() {
    ClassDB::bind_method(D_METHOD("build_rounded_rectangle", "size", "radius", "plane", "centered"), &RectangleRoundedWire::build_rounded_rectangle, DEFVAL(Ref<CadPlane>()), DEFVAL(true));
}

RectangleRoundedWire::RectangleRoundedWire() = default;

void RectangleRoundedWire::build_rounded_rectangle(const Vector2 &p_size, double p_radius, const Ref<CadPlane> &p_plane, bool p_centered) {
    ERR_FAIL_COND_MSG(p_size.x <= 0.0 || p_size.y <= 0.0, "RectangleRoundedWire.build_rounded_rectangle requires positive size components.");
    ERR_FAIL_COND_MSG(p_radius <= 0.0, "RectangleRoundedWire.build_rounded_rectangle requires a positive radius.");
    ERR_FAIL_COND_MSG(static_cast<double>(p_size.x) <= 2.0 * p_radius || static_cast<double>(p_size.y) <= 2.0 * p_radius,
        "RectangleRoundedWire.build_rounded_rectangle requires width and height greater than 2 * radius.");

    Ref<CadPlane> plane = p_plane;
    if (plane.is_null()) {
        plane = default_xy_plane();
    }

    const double min_u = p_centered ? -static_cast<double>(p_size.x) * 0.5 : 0.0;
    const double min_v = p_centered ? -static_cast<double>(p_size.y) * 0.5 : 0.0;
    const double max_u = min_u + static_cast<double>(p_size.x);
    const double max_v = min_v + static_cast<double>(p_size.y);
    const double radius = p_radius;
    const double diagonal_offset = radius / std::sqrt(2.0);

    const Vector3 bottom_left = plane_point(plane, min_u + radius, min_v);
    const Vector3 bottom_right = plane_point(plane, max_u - radius, min_v);
    const Vector3 right_bottom = plane_point(plane, max_u, min_v + radius);
    const Vector3 right_top = plane_point(plane, max_u, max_v - radius);
    const Vector3 top_right = plane_point(plane, max_u - radius, max_v);
    const Vector3 top_left = plane_point(plane, min_u + radius, max_v);
    const Vector3 left_top = plane_point(plane, min_u, max_v - radius);
    const Vector3 left_bottom = plane_point(plane, min_u, min_v + radius);

    const Vector3 bottom_right_mid = plane_point(plane, max_u - radius + diagonal_offset, min_v + radius - diagonal_offset);
    const Vector3 top_right_mid = plane_point(plane, max_u - radius + diagonal_offset, max_v - radius + diagonal_offset);
    const Vector3 top_left_mid = plane_point(plane, min_u + radius - diagonal_offset, max_v - radius + diagonal_offset);
    const Vector3 bottom_left_mid = plane_point(plane, min_u + radius - diagonal_offset, min_v + radius - diagonal_offset);

    try {
        BRepBuilderAPI_MakeWire wire_builder;
        wire_builder.Add(make_line_edge(bottom_left, bottom_right));
        wire_builder.Add(make_arc_edge(bottom_right, bottom_right_mid, right_bottom));
        wire_builder.Add(make_line_edge(right_bottom, right_top));
        wire_builder.Add(make_arc_edge(right_top, top_right_mid, top_right));
        wire_builder.Add(make_line_edge(top_right, top_left));
        wire_builder.Add(make_arc_edge(top_left, top_left_mid, left_top));
        wire_builder.Add(make_line_edge(left_top, left_bottom));
        wire_builder.Add(make_arc_edge(left_bottom, bottom_left_mid, bottom_left));
        wire_builder.Build();
        if (!wire_builder.IsDone()) {
            ERR_PRINT(vformat("RectangleRoundedWire.build_rounded_rectangle: wire construction did not complete"));
            return;
        }
        set_occt_shape(wire_builder.Wire());
    } catch (const Standard_Failure &e) {
        ERR_PRINT(vformat("RectangleRoundedWire.build_rounded_rectangle failed: %s", occt_utils::exception_to_string(e)));
    }
}
