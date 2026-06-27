#include "Face.h"

#include "Axis.h"
#include "OCCTUtils.h"
#include "Solid.h"
#include "Wire.h"

#include <godot_cpp/core/error_macros.hpp>

#include <BRepAdaptor_Surface.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepBuilderAPI_MakePolygon.hxx>
#include <BRepPrimAPI_MakePrism.hxx>
#include <BRepPrimAPI_MakeRevol.hxx>
#include <BRepTools.hxx>
#include <BRep_Tool.hxx>
#include <GeomAbs_SurfaceType.hxx>
#include <GeomLProp_SLProps.hxx>
#include <TopAbs_ShapeEnum.hxx>
#include <TopExp_Explorer.hxx>
#include <TopoDS.hxx>

using namespace godot;

namespace {

void build_face_from_wires_impl(Face *p_face, const Ref<Wire> &p_outer_wire, const Array &p_inner_wires, bool p_only_plane) {
    ERR_FAIL_COND_MSG(p_outer_wire.is_null() || p_outer_wire->is_null(), "Face.build_from_wires requires a non-null outer wire.");

    try {
        BRepBuilderAPI_MakeFace builder(TopoDS::Wire(p_outer_wire->get_occt_shape()), p_only_plane ? true : false);
        for (int64_t index = 0; index < p_inner_wires.size(); ++index) {
            const Ref<Wire> inner_wire = p_inner_wires[index];
            ERR_FAIL_COND_MSG(inner_wire.is_null() || inner_wire->is_null(), "Face.build_from_wires requires every inner wire entry to be a non-null Wire.");
            TopoDS_Wire occt_inner_wire = TopoDS::Wire(inner_wire->get_occt_shape());
            occt_inner_wire.Reverse();
            builder.Add(occt_inner_wire);
        }
        builder.Build();
        if (!builder.IsDone()) {
            ERR_PRINT(vformat("Face.build_from_wires failed: OpenCASCADE face construction did not complete."));
            return;
        }
        p_face->set_occt_shape(builder.Shape());
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Face.build_from_wires failed: %s", occt_utils::exception_to_string(failure)));
    }
}

} // namespace

void Face::_bind_methods() {
    ClassDB::bind_method(D_METHOD("build_from_wire", "wire", "only_plane"), &Face::build_from_wire, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("build_from_wires", "outer_wire", "inner_wires", "only_plane"), &Face::build_from_wires, DEFVAL(Array()), DEFVAL(false));
    ClassDB::bind_method(D_METHOD("build_polygon", "points", "only_plane"), &Face::build_polygon, DEFVAL(true));
    ClassDB::bind_method(D_METHOD("offset_2d", "distance"), &Face::offset_2d);
    ClassDB::bind_method(D_METHOD("extruded", "direction"), &Face::extruded);
    ClassDB::bind_method(D_METHOD("revolved", "axis", "angle_radians"), &Face::revolved, DEFVAL(6.28318530717958647692));
    ClassDB::bind_method(D_METHOD("is_planar"), &Face::is_planar);
    ClassDB::bind_method(D_METHOD("get_outer_wire"), &Face::get_outer_wire);
    ClassDB::bind_method(D_METHOD("get_inner_wires"), &Face::get_inner_wires);
    ClassDB::bind_method(D_METHOD("get_normal"), &Face::get_normal);
}

Face::Face() = default;

Ref<Face> Face::from_occt(const TopoDS_Face &p_face) {
    Ref<Face> result;
    result.instantiate();
    result->set_occt_shape(p_face);
    return result;
}

void Face::build_from_wire(const Ref<Wire> &p_wire, bool p_only_plane) {
    build_face_from_wires_impl(this, p_wire, Array(), p_only_plane);
}

void Face::build_from_wires(const Ref<Wire> &p_outer_wire, const Array &p_inner_wires, bool p_only_plane) {
    build_face_from_wires_impl(this, p_outer_wire, p_inner_wires, p_only_plane);
}

void Face::build_polygon(const PackedVector3Array &p_points, bool p_only_plane) {
    if (p_points.size() < 3) {
        ERR_PRINT(vformat("Face.build_polygon failed: requires at least 3 points."));
        return;
    }

    try {
        BRepBuilderAPI_MakePolygon polygon_builder;
        for (int64_t index = 0; index < p_points.size(); ++index) {
            polygon_builder.Add(occt_utils::to_occt_point(p_points[index]));
        }
        polygon_builder.Close();
        polygon_builder.Build();
        if (!polygon_builder.IsDone()) {
            ERR_PRINT(vformat("Face.build_polygon failed: OpenCASCADE polygon wire construction did not complete."));
            return;
        }

        BRepBuilderAPI_MakeFace face_builder(TopoDS::Wire(polygon_builder.Shape()), p_only_plane ? true : false);
        face_builder.Build();
        if (!face_builder.IsDone()) {
            ERR_PRINT(vformat("Face.build_polygon failed: OpenCASCADE polygon face construction did not complete."));
            return;
        }
        set_occt_shape(face_builder.Shape());
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Face.build_polygon failed: %s", occt_utils::exception_to_string(failure)));
    }
}

Ref<Face> Face::offset_2d(double p_distance) const {
    if (is_null()) {
        ERR_PRINT(vformat("Face.offset_2d failed: requires a non-null face."));
        return Ref<Face>();
    }
    if (p_distance == 0.0) {
        ERR_PRINT(vformat("Face.offset_2d failed: requires a non-zero distance."));
        return Ref<Face>();
    }
    if (!is_planar()) {
        ERR_PRINT(vformat("Face.offset_2d failed: currently requires a planar face."));
        return Ref<Face>();
    }

    try {
        const Vector3 source_normal = get_normal();
        Ref<Wire> outer_wire = get_outer_wire();
        if (outer_wire.is_null() || outer_wire->is_null()) {
            ERR_PRINT(vformat("Face.offset_2d failed: requires a valid outer wire."));
            return Ref<Face>();
        }

        Ref<Wire> offset_outer_wire = outer_wire->offset_2d(p_distance);
        if (offset_outer_wire.is_null() || offset_outer_wire->is_null()) {
            ERR_PRINT(vformat("Face.offset_2d failed: could not offset the outer wire."));
            return Ref<Face>();
        }

        Array offset_inner_wires;
        const Array inner_wires = get_inner_wires();
        for (int64_t index = 0; index < inner_wires.size(); ++index) {
            const Ref<Wire> inner_wire = inner_wires[index];
            if (inner_wire.is_null() || inner_wire->is_null()) {
                continue;
            }

            Ref<Wire> offset_inner_wire = inner_wire->offset_2d(-p_distance);
            if (offset_inner_wire.is_null() || offset_inner_wire->is_null()) {
                continue;
            }
            offset_inner_wires.push_back(offset_inner_wire);
        }

        Ref<Face> result;
        result.instantiate();
        result->build_from_wires(offset_outer_wire, offset_inner_wires, true);

        if (result->get_normal().dot(source_normal) < 0.0f) {
            result->set_occt_shape(TopoDS::Face(result->get_occt_shape().Reversed()));
        }

        return result;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Face.offset_2d failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<Face>();
    }
}

Ref<Solid> Face::extruded(const Vector3 &p_direction) const {
    if (is_null()) {
        ERR_PRINT(vformat("Face.extruded failed: requires a non-null face."));
        return Ref<Solid>();
    }
    if (p_direction.length() == 0.0) {
        ERR_PRINT(vformat("Face.extruded failed: requires a non-zero direction."));
        return Ref<Solid>();
    }

    try {
        BRepPrimAPI_MakePrism builder(get_occt_shape(), occt_utils::to_occt_vec(p_direction), true, true);
        builder.Build();
        if (!builder.IsDone()) {
            ERR_PRINT(vformat("Face.extruded failed: OpenCASCADE prism extrusion did not complete."));
            return Ref<Solid>();
        }

        const TopoDS_Shape result = builder.Shape();
        if (result.IsNull()) {
            ERR_PRINT(vformat("Face.extruded failed: OpenCASCADE prism extrusion returned a null shape."));
            return Ref<Solid>();
        }
        if (result.ShapeType() != TopAbs_SOLID) {
            ERR_PRINT(vformat("Face.extruded failed: expected a solid result, got %d", static_cast<int>(result.ShapeType())));
            return Ref<Solid>();
        }
        return Solid::from_occt(TopoDS::Solid(result));
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Face.extruded failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<Solid>();
    }
}

Ref<Solid> Face::revolved(const Ref<Axis> &p_axis, double p_angle_radians) const {
    if (is_null()) {
        ERR_PRINT(vformat("Face.revolved failed: requires a non-null face."));
        return Ref<Solid>();
    }
    if (p_axis.is_null()) {
        ERR_PRINT(vformat("Face.revolved failed: requires a non-null axis."));
        return Ref<Solid>();
    }
    if (p_angle_radians == 0.0) {
        ERR_PRINT(vformat("Face.revolved failed: requires a non-zero angle."));
        return Ref<Solid>();
    }

    try {
        BRepPrimAPI_MakeRevol builder(get_occt_shape(), p_axis->get_occt_axis(), p_angle_radians, true);
        builder.Build();
        if (!builder.IsDone()) {
            ERR_PRINT(vformat("Face.revolved failed: OpenCASCADE revolve operation did not complete."));
            return Ref<Solid>();
        }

        const TopoDS_Shape result = builder.Shape();
        if (result.IsNull()) {
            ERR_PRINT(vformat("Face.revolved failed: OpenCASCADE revolve operation returned a null shape."));
            return Ref<Solid>();
        }
        if (result.ShapeType() != TopAbs_SOLID) {
            ERR_PRINT(vformat("Face.revolved failed: expected a solid result, got %d", static_cast<int>(result.ShapeType())));
            return Ref<Solid>();
        }
        return Solid::from_occt(TopoDS::Solid(result));
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Face.revolved failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<Solid>();
    }
}

bool Face::is_planar() const {
    if (is_null()) {
        ERR_PRINT(vformat("Face.is_planar failed: requires a non-null shape."));
        return false;
    }

    try {
        return BRepAdaptor_Surface(TopoDS::Face(get_occt_shape())).GetType() == GeomAbs_Plane;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Face.is_planar failed: %s", occt_utils::exception_to_string(failure)));
        return false;
    }
}

Ref<Wire> Face::get_outer_wire() const {
    if (is_null()) {
        ERR_PRINT(vformat("Face.get_outer_wire failed: requires a non-null shape."));
        return Ref<Wire>();
    }

    try {
        const TopoDS_Wire outer_wire = BRepTools::OuterWire(TopoDS::Face(get_occt_shape()));
        if (outer_wire.IsNull()) {
            ERR_PRINT(vformat("Face.get_outer_wire failed: OpenCASCADE could not determine an outer wire for the face."));
            return Ref<Wire>();
        }
        return Wire::from_occt(outer_wire);
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Face.get_outer_wire failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<Wire>();
    }
}

Array Face::get_inner_wires() const {
    if (is_null()) {
        ERR_PRINT(vformat("Face.get_inner_wires failed: requires a non-null shape."));
        return Array();
    }

    try {
        const TopoDS_Face face = TopoDS::Face(get_occt_shape());
        const TopoDS_Wire outer_wire = BRepTools::OuterWire(face);

        Array inner_wires;
        for (TopExp_Explorer explorer(face, TopAbs_WIRE); explorer.More(); explorer.Next()) {
            const TopoDS_Wire wire = TopoDS::Wire(explorer.Current());
            if (!outer_wire.IsNull() && wire.IsSame(outer_wire)) {
                continue;
            }
            inner_wires.push_back(Wire::from_occt(wire));
        }
        return inner_wires;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Face.get_inner_wires failed: %s", occt_utils::exception_to_string(failure)));
        return Array();
    }
}

Vector3 Face::get_normal() const {
    if (is_null()) {
        ERR_PRINT(vformat("Face.get_normal failed: requires a non-null shape."));
        return Vector3();
    }

    try {
        const TopoDS_Face face = TopoDS::Face(get_occt_shape());
        double umin = 0.0;
        double umax = 0.0;
        double vmin = 0.0;
        double vmax = 0.0;
        BRepTools::UVBounds(face, umin, umax, vmin, vmax);

        const Handle(Geom_Surface) surface = BRep_Tool::Surface(face);
        if (surface.IsNull()) {
            ERR_PRINT(vformat("Face.get_normal failed: OpenCASCADE could not determine a supporting surface for the face."));
            return Vector3();
        }

        GeomLProp_SLProps properties(surface, (umin + umax) * 0.5, (vmin + vmax) * 0.5, 1, 1e-9);
        if (!properties.IsNormalDefined()) {
            ERR_PRINT(vformat("Face.get_normal failed: OpenCASCADE could not determine the face normal."));
            return Vector3();
        }

        gp_Dir normal = properties.Normal();
        if (face.Orientation() == TopAbs_REVERSED) {
            normal.Reverse();
        }
        return Vector3(
            static_cast<real_t>(normal.X()),
            static_cast<real_t>(normal.Y()),
            static_cast<real_t>(normal.Z())
        );
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Face.get_normal failed: %s", occt_utils::exception_to_string(failure)));
        return Vector3();
    }
}
