#include "SlotOverallWire.h"

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
    BRepBuilderAPI_MakeEdge builder(occt_utils::to_occt_point(p_start), occt_utils::to_occt_point(p_end));
    if (!builder.IsDone()) {
        ERR_PRINT("make_line_edge: operation did not complete");
        return TopoDS_Edge();
    }
    return builder.Edge();
}

TopoDS_Edge make_arc_edge(const Vector3 &p_start, const Vector3 &p_mid, const Vector3 &p_end) {
    GC_MakeArcOfCircle builder(
        occt_utils::to_occt_point(p_start),
        occt_utils::to_occt_point(p_mid),
        occt_utils::to_occt_point(p_end));
    if (!builder.IsDone()) {
        ERR_PRINT("make_arc_edge: arc construction did not complete");
        return TopoDS_Edge();
    }

    BRepBuilderAPI_MakeEdge edge_builder(builder.Value());
    if (!edge_builder.IsDone()) {
        ERR_PRINT("make_arc_edge: edge construction did not complete");
        return TopoDS_Edge();
    }
    return edge_builder.Edge();
}

} // namespace

void SlotOverallWire::_bind_methods() {
    ClassDB::bind_method(D_METHOD("build_slot_overall", "width", "height", "plane", "centered"), &SlotOverallWire::build_slot_overall, DEFVAL(Ref<CadPlane>()), DEFVAL(true));
}

SlotOverallWire::SlotOverallWire() = default;

void SlotOverallWire::build_slot_overall(double p_width, double p_height, const Ref<CadPlane> &p_plane, bool p_centered) {
    ERR_FAIL_COND_MSG(p_width <= 0.0, vformat("SlotOverallWire.build_slot_overall: requires positive width, got %f", p_width));
    ERR_FAIL_COND_MSG(p_height <= 0.0, vformat("SlotOverallWire.build_slot_overall: requires positive height, got %f", p_height));
    ERR_FAIL_COND_MSG(p_width < p_height, vformat("SlotOverallWire.build_slot_overall: requires width >= height, got width=%f height=%f", p_width, p_height));

    Ref<CadPlane> plane = p_plane;
    if (plane.is_null()) {
        plane = default_xy_plane();
    }

    // Degenerate slot becomes a circle.
    if (std::abs(p_width - p_height) <= 1e-9) {
        const double radius = p_width * 0.5;
        const double min_u = p_centered ? -radius : 0.0;
        const double center_u = p_centered ? 0.0 : radius;
        const double center_v = p_centered ? 0.0 : radius;

        const Vector3 left = plane_point(plane, min_u, center_v);
        const Vector3 top = plane_point(plane, center_u, center_v + radius);
        const Vector3 right = plane_point(plane, center_u + radius, center_v);
        const Vector3 bottom = plane_point(plane, center_u, center_v - radius);

        try {
            BRepBuilderAPI_MakeWire wire_builder;
            wire_builder.Add(make_arc_edge(left, top, right));
            wire_builder.Add(make_arc_edge(right, bottom, left));
            wire_builder.Build();
            if (!wire_builder.IsDone()) {
                ERR_PRINT("SlotOverallWire.build_slot_overall: circular slot wire construction did not complete");
                return;
            }
            set_occt_shape(wire_builder.Wire());
        } catch (const Standard_Failure &failure) {
            ERR_PRINT(vformat("SlotOverallWire.build_slot_overall failed: %s", occt_utils::exception_to_string(failure)));
        }
        return;
    }

    const double radius = p_height * 0.5;
    const double min_u = p_centered ? -p_width * 0.5 : 0.0;
    const double min_v = p_centered ? -p_height * 0.5 : 0.0;
    const double max_u = min_u + p_width;
    const double max_v = min_v + p_height;
    const double left_center_u = min_u + radius;
    const double right_center_u = max_u - radius;
    const double center_v = min_v + radius;

    const Vector3 left_bottom = plane_point(plane, left_center_u, min_v);
    const Vector3 right_bottom = plane_point(plane, right_center_u, min_v);
    const Vector3 right_top = plane_point(plane, right_center_u, max_v);
    const Vector3 left_top = plane_point(plane, left_center_u, max_v);
    const Vector3 far_right = plane_point(plane, max_u, center_v);
    const Vector3 far_left = plane_point(plane, min_u, center_v);

    try {
        BRepBuilderAPI_MakeWire wire_builder;
        wire_builder.Add(make_line_edge(left_bottom, right_bottom));
        wire_builder.Add(make_arc_edge(right_bottom, far_right, right_top));
        wire_builder.Add(make_line_edge(right_top, left_top));
        wire_builder.Add(make_arc_edge(left_top, far_left, left_bottom));
        wire_builder.Build();
        if (!wire_builder.IsDone()) {
            ERR_PRINT("SlotOverallWire.build_slot_overall: slot wire construction did not complete");
            return;
        }
        set_occt_shape(wire_builder.Wire());
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("SlotOverallWire.build_slot_overall failed: %s", occt_utils::exception_to_string(failure)));
    }
}
