#include "Wire.h"

#include "Axis.h"
#include "Edge.h"
#include "Face.h"
#include "OCCTUtils.h"
#include "Solid.h"

#include <godot_cpp/core/error_macros.hpp>

#include <BRepAdaptor_Curve.hxx>
#include <BRepBuilderAPI_MakeEdge.hxx>
#include <BRepBuilderAPI_MakePolygon.hxx>
#include <BRepBuilderAPI_MakeWire.hxx>
#include <BRepGProp.hxx>
#include <BRepOffsetAPI_MakeOffset.hxx>
#include <BRepOffsetAPI_MakePipe.hxx>
#include <BRepOffsetAPI_ThruSections.hxx>
#include <BRepTools_WireExplorer.hxx>
#include <BRep_Tool.hxx>
#include <GCPnts_QuasiUniformDeflection.hxx>
#include <GeomAbs_JoinType.hxx>
#include <GProp_GProps.hxx>
#include <TopExp_Explorer.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Iterator.hxx>

using namespace godot;

namespace {

PackedVector3Array sample_edge_polyline(const TopoDS_Edge &p_edge, double p_deflection) {
    BRepAdaptor_Curve curve(p_edge);
    GCPnts_QuasiUniformDeflection sampler(curve, p_deflection, curve.FirstParameter(), curve.LastParameter());

    PackedVector3Array polyline;
    if (sampler.IsDone() && sampler.NbPoints() >= 2) {
        for (int index = 1; index <= sampler.NbPoints(); ++index) {
            polyline.push_back(occt_utils::to_godot_vector3(sampler.Value(index)));
        }
    } else {
        polyline.push_back(occt_utils::to_godot_vector3(curve.Value(curve.FirstParameter())));
        polyline.push_back(occt_utils::to_godot_vector3(curve.Value(curve.LastParameter())));
    }

    return polyline;
}

bool points_match(const Vector3 &p_a, const Vector3 &p_b, double p_tolerance = 1e-9) {
    return p_a.distance_squared_to(p_b) <= static_cast<real_t>(p_tolerance * p_tolerance);
}

} // namespace

void Wire::_bind_methods() {
    ClassDB::bind_method(D_METHOD("build_polygon", "points", "closed"), &Wire::build_polygon, DEFVAL(true));
    ClassDB::bind_method(D_METHOD("lofted_to", "other", "make_solid", "ruled"), &Wire::lofted_to, DEFVAL(true), DEFVAL(false));
    ClassDB::bind_method(D_METHOD("swept_along", "spine"), &Wire::swept_along);
    ClassDB::bind_method(D_METHOD("offset_2d", "distance"), &Wire::offset_2d);
    ClassDB::bind_method(D_METHOD("extruded", "direction", "only_plane"), &Wire::extruded, DEFVAL(true));
    ClassDB::bind_method(D_METHOD("revolved", "axis", "angle_radians", "only_plane"), &Wire::revolved, DEFVAL(6.28318530717958647692), DEFVAL(true));
    ClassDB::bind_method(D_METHOD("is_closed"), &Wire::is_closed);
    ClassDB::bind_method(D_METHOD("get_length"), &Wire::get_length);
    ClassDB::bind_method(D_METHOD("get_edges"), &Wire::get_edges);
    ClassDB::bind_method(D_METHOD("get_polyline", "deflection"), &Wire::get_polyline, DEFVAL(0.1));
}

Wire::Wire() = default;

Ref<Wire> Wire::from_occt(const TopoDS_Wire &p_wire) {
    Ref<Wire> result;
    result.instantiate();
    result->set_occt_shape(p_wire);
    return result;
}

void Wire::build_polygon(const PackedVector3Array &p_points, bool p_closed) {
    ERR_FAIL_COND_MSG(p_points.size() < (p_closed ? 3 : 2), "Wire.build_polygon requires at least 3 points for closed wires or 2 for open wires.");

    try {
        BRepBuilderAPI_MakePolygon builder;
        for (int64_t index = 0; index < p_points.size(); ++index) {
            builder.Add(occt_utils::to_occt_point(p_points[index]));
        }
        if (p_closed) {
            builder.Close();
        }
        builder.Build();
        if (!builder.IsDone()) {
            ERR_PRINT(vformat("Wire.build_polygon failed: OpenCASCADE wire construction did not complete."));
            return;
        }
        set_occt_shape(builder.Shape());
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Wire.build_polygon failed: %s", occt_utils::exception_to_string(failure)));
    }
}

Ref<TopoShape> Wire::lofted_to(const Ref<Wire> &p_other, bool p_make_solid, bool p_ruled) const {
    ERR_FAIL_COND_V_MSG(is_null(), Ref<TopoShape>(), "Wire.lofted_to requires a non-null source wire.");
    ERR_FAIL_COND_V_MSG(p_other.is_null() || p_other->is_null(), Ref<TopoShape>(), "Wire.lofted_to requires a non-null target wire.");
    ERR_FAIL_COND_V_MSG(!is_closed(), Ref<TopoShape>(), "Wire.lofted_to requires the source wire to be closed.");
    ERR_FAIL_COND_V_MSG(!p_other->is_closed(), Ref<TopoShape>(), "Wire.lofted_to requires the target wire to be closed.");

    try {
        BRepOffsetAPI_ThruSections builder(p_make_solid ? true : false, p_ruled ? true : false, 1.0e-6);
        builder.SetMutableInput(false);
        builder.CheckCompatibility(true);
        builder.AddWire(TopoDS::Wire(get_occt_shape()));
        builder.AddWire(TopoDS::Wire(p_other->get_occt_shape()));
        builder.Build();
        if (!builder.IsDone()) {
            ERR_PRINT(vformat("Wire.lofted_to failed: OpenCASCADE loft operation did not complete."));
            return Ref<TopoShape>();
        }
        const TopoDS_Shape result = builder.Shape();
        if (result.IsNull()) {
            ERR_PRINT(vformat("Wire.lofted_to failed: OpenCASCADE loft operation returned a null shape."));
            return Ref<TopoShape>();
        }
        return TopoShape::from_occt(result);
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Wire.lofted_to failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<TopoShape>();
    }
}

Ref<TopoShape> Wire::swept_along(const Ref<Wire> &p_spine) const {
    ERR_FAIL_COND_V_MSG(is_null(), Ref<TopoShape>(), "Wire.swept_along requires a non-null profile wire.");
    ERR_FAIL_COND_V_MSG(p_spine.is_null() || p_spine->is_null(), Ref<TopoShape>(), "Wire.swept_along requires a non-null spine wire.");
    ERR_FAIL_COND_V_MSG(!is_closed(), Ref<TopoShape>(), "Wire.swept_along requires the profile wire to be closed.");

    try {
        Ref<Face> profile;
        profile.instantiate();
        profile->build_from_wire(Wire::from_occt(TopoDS::Wire(get_occt_shape())), true);

        BRepOffsetAPI_MakePipe builder(TopoDS::Wire(p_spine->get_occt_shape()), profile->get_occt_shape());
        builder.Build();
        if (!builder.IsDone()) {
            ERR_PRINT(vformat("Wire.swept_along failed: OpenCASCADE sweep operation did not complete."));
            return Ref<TopoShape>();
        }
        const TopoDS_Shape result = builder.Shape();
        if (result.IsNull()) {
            ERR_PRINT(vformat("Wire.swept_along failed: OpenCASCADE sweep operation returned a null shape."));
            return Ref<TopoShape>();
        }
        return TopoShape::from_occt(result);
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Wire.swept_along failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<TopoShape>();
    }
}

Ref<Wire> Wire::offset_2d(double p_distance) const {
    ERR_FAIL_COND_V_MSG(is_null(), Ref<Wire>(), "Wire.offset_2d requires a non-null wire.");
    ERR_FAIL_COND_V_MSG(p_distance == 0.0, Ref<Wire>(), "Wire.offset_2d requires a non-zero distance.");

    try {
        TopoDS_Wire source_wire = TopoDS::Wire(get_occt_shape());

        // OCCT offsetting is unreliable for analytic single-edge wires such as circles,
        // so rebuild them as two-edge wires first.
        TopExp_Explorer edge_counter(source_wire, TopAbs_EDGE);
        if (edge_counter.More()) {
            const TopoDS_Edge source_edge = TopoDS::Edge(edge_counter.Current());
            edge_counter.Next();
            if (!edge_counter.More()) {
                BRepAdaptor_Curve curve(source_edge);
                const double first = curve.FirstParameter();
                const double last = curve.LastParameter();
                const double mid = first + (last - first) * 0.5;

                TopoDS_Edge first_half = BRepBuilderAPI_MakeEdge(curve.Curve().Curve(), first, mid).Edge();
                TopoDS_Edge second_half = BRepBuilderAPI_MakeEdge(curve.Curve().Curve(), mid, last).Edge();
                BRepBuilderAPI_MakeWire wire_builder;
                wire_builder.Add(first_half);
                wire_builder.Add(second_half);
                wire_builder.Build();
                if (!wire_builder.IsDone()) {
                    ERR_PRINT(vformat("Wire.offset_2d failed: OpenCASCADE single-edge wire preparation for offset did not complete."));
                    return Ref<Wire>();
                }
                source_wire = wire_builder.Wire();
            }
        }

        BRepOffsetAPI_MakeOffset builder;
        builder.Init(GeomAbs_Arc);
        builder.AddWire(source_wire);
        builder.Perform(p_distance);

        TopoDS_Shape result = builder.Shape();
        if (result.IsNull()) {
            ERR_PRINT(vformat("Wire.offset_2d failed: OpenCASCADE 2D offset returned a null shape."));
            return Ref<Wire>();
        }

        if (result.ShapeType() == TopAbs_COMPOUND) {
            TopoDS_Shape first_wire;
            int wire_count = 0;
            for (TopoDS_Iterator iterator(result); iterator.More(); iterator.Next()) {
                const TopoDS_Shape child = iterator.Value();
                if (child.ShapeType() != TopAbs_WIRE) {
                    continue;
                }
                if (wire_count == 0) {
                    first_wire = child;
                }
                ++wire_count;
            }
            if (wire_count == 0 || first_wire.IsNull()) {
                return Ref<Wire>();
            }
            if (wire_count != 1) {
                ERR_PRINT(vformat("Wire.offset_2d failed: expected a single wire result, got %d", wire_count));
                return Ref<Wire>();
            }
            result = first_wire;
        }

        if (result.ShapeType() != TopAbs_WIRE) {
            ERR_PRINT(vformat("Wire.offset_2d failed: expected a wire result, got %d", static_cast<int>(result.ShapeType())));
            return Ref<Wire>();
        }
        return Wire::from_occt(TopoDS::Wire(result));
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Wire.offset_2d failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<Wire>();
    }
}

Ref<Solid> Wire::extruded(const Vector3 &p_direction, bool p_only_plane) const {
    ERR_FAIL_COND_V_MSG(is_null(), Ref<Solid>(), "Wire.extruded requires a non-null wire.");
    ERR_FAIL_COND_V_MSG(!is_closed(), Ref<Solid>(), "Wire.extruded requires a closed wire.");

    Ref<Face> profile;
    profile.instantiate();
    profile->build_from_wire(Wire::from_occt(TopoDS::Wire(get_occt_shape())), p_only_plane);
    return profile->extruded(p_direction);
}

Ref<Solid> Wire::revolved(const Ref<Axis> &p_axis, double p_angle_radians, bool p_only_plane) const {
    ERR_FAIL_COND_V_MSG(is_null(), Ref<Solid>(), "Wire.revolved requires a non-null wire.");
    ERR_FAIL_COND_V_MSG(!is_closed(), Ref<Solid>(), "Wire.revolved requires a closed wire.");

    Ref<Face> profile;
    profile.instantiate();
    profile->build_from_wire(Wire::from_occt(TopoDS::Wire(get_occt_shape())), p_only_plane);
    return profile->revolved(p_axis, p_angle_radians);
}

bool Wire::is_closed() const {
    ERR_FAIL_COND_V_MSG(is_null(), false, "Wire.is_closed requires a non-null shape.");

    try {
        return BRep_Tool::IsClosed(get_occt_shape());
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Wire.is_closed failed: %s", occt_utils::exception_to_string(failure)));
        return false;
    }
}

double Wire::get_length() const {
    ERR_FAIL_COND_V_MSG(is_null(), 0.0, "Wire.get_length requires a non-null shape.");

    try {
        GProp_GProps properties;
        BRepGProp::LinearProperties(get_occt_shape(), properties);
        return properties.Mass();
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Wire.get_length failed: %s", occt_utils::exception_to_string(failure)));
        return 0.0;
    }
}

Array Wire::get_edges() const {
    ERR_FAIL_COND_V_MSG(is_null(), Array(), "Wire.get_edges requires a non-null shape.");

    try {
        Array edges;
        BRepTools_WireExplorer explorer(TopoDS::Wire(get_occt_shape()));
        for (; explorer.More(); explorer.Next()) {
            edges.push_back(Edge::from_occt(explorer.Current()));
        }
        return edges;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Wire.get_edges failed: %s", occt_utils::exception_to_string(failure)));
        return Array();
    }
}

PackedVector3Array Wire::get_polyline(double p_deflection) const {
    ERR_FAIL_COND_V_MSG(is_null(), PackedVector3Array(), "Wire.get_polyline requires a non-null shape.");
    ERR_FAIL_COND_V_MSG(p_deflection <= 0.0, PackedVector3Array(), "Wire.get_polyline requires a positive deflection.");

    try {
        PackedVector3Array polyline;
        BRepTools_WireExplorer explorer(TopoDS::Wire(get_occt_shape()));
        for (; explorer.More(); explorer.Next()) {
            const PackedVector3Array edge_polyline = sample_edge_polyline(explorer.Current(), p_deflection);
            for (int64_t index = 0; index < edge_polyline.size(); ++index) {
                const Vector3 point = edge_polyline[index];
                if (!polyline.is_empty() && index == 0 && points_match(polyline[polyline.size() - 1], point)) {
                    continue;
                }
                polyline.push_back(point);
            }
        }
        return polyline;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Wire.get_polyline failed: %s", occt_utils::exception_to_string(failure)));
        return PackedVector3Array();
    }
}
