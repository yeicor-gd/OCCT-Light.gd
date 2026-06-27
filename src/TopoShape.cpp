#include "TopoShape.h"

#include "Axis.h"
#include "Compound.h"
#include "Edge.h"
#include "Face.h"
#include "Location.h"
#include "OCCTUtils.h"
#include "Plane.h"
#include "Shell.h"
#include "Solid.h"
#include "Vertex.h"
#include "Wire.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <BRepAlgoAPI_Common.hxx>
#include <BRepAlgoAPI_Cut.hxx>
#include <BRepAlgoAPI_Fuse.hxx>
#include <BRepAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepBuilderAPI_Transform.hxx>
#include <Message.hxx>
#include <Message_Printer.hxx>
#include <NCollection_Sequence.hxx>
#include <BRepBndLib.hxx>
#include <BRepBuilderAPI_Copy.hxx>
#include <BRepGProp.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRep_Tool.hxx>
#include <Bnd_Box.hxx>
#include <GCPnts_QuasiUniformDeflection.hxx>
#include <GProp_GProps.hxx>
#include <IFSelect_ReturnStatus.hxx>
#include <Poly_Triangle.hxx>
#include <STEPControl_Reader.hxx>
#include <STEPControl_Writer.hxx>
#include <StlAPI_Reader.hxx>
#include <StlAPI_Writer.hxx>
#include <TopAbs_Orientation.hxx>
#include <TopAbs_ShapeEnum.hxx>
#include <TopExp.hxx>
#include <TopoDS_Iterator.hxx>
#include <TopExp_Explorer.hxx>
#include <TopLoc_Location.hxx>
#include <NCollection_IndexedMap.hxx>
#include <TopTools_ShapeMapHasher.hxx>
#include <TopoDS.hxx>
#include <gp_Ax1.hxx>
#include <gp_Dir.hxx>
#include <gp_Trsf.hxx>
#include <GeomAbs_CurveType.hxx>
#include <GeomAbs_SurfaceType.hxx>

#include <fstream>
#include <ios>
#include <sstream>
#include <string>
#include <chrono>
#include <filesystem>

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

template <typename TOperation>
Ref<TopoShape> do_boolean_operation(const TopoDS_Shape &p_left, const TopoDS_Shape &p_right) {
    TOperation operation(p_left, p_right);
    operation.Build();
    ERR_FAIL_COND_V_MSG(!operation.IsDone(), Ref<TopoShape>(), "OpenCASCADE boolean operation did not complete.");
    return TopoShape::from_occt(operation.Shape());
}

template <typename TOperation>
Ref<TopoShape> do_boolean_sequence(Ref<TopoShape> p_result, const Array &p_shapes, const char *p_context) {
    ERR_FAIL_COND_V_MSG(p_result.is_null() || p_result->is_null(), Ref<TopoShape>(), p_context);

    for (int64_t index = 0; index < p_shapes.size(); ++index) {
        const Ref<TopoShape> other = p_shapes[index];
        ERR_FAIL_COND_V_MSG(other.is_null() || other->is_null(), Ref<TopoShape>(), p_context);

        p_result = do_boolean_operation<TOperation>(p_result->get_occt_shape(), other->get_occt_shape());
        ERR_FAIL_COND_V_MSG(p_result.is_null(), Ref<TopoShape>(), "OpenCASCADE boolean operation returned a null shape.");
    }

    return p_result;
}

void ensure_shape_present(const TopoDS_Shape &p_shape, const char *p_context) {
    ERR_FAIL_COND_MSG(p_shape.IsNull(), p_context);
}

String globalize_path(const String &p_path) {
    if (p_path.begins_with("res://") || p_path.begins_with("user://")) {
        return ProjectSettings::get_singleton()->globalize_path(p_path);
    }
    return p_path;
}

std::string to_std_string(const String &p_string) {
    CharString utf8 = p_string.utf8();
    return std::string(utf8.get_data(), static_cast<size_t>(utf8.length()));
}

PackedByteArray to_packed_byte_array(const std::string &p_data) {
    PackedByteArray bytes;
    for (unsigned char byte : p_data) {
        bytes.push_back(static_cast<int64_t>(byte));
    }
    return bytes;
}

std::string to_std_string(const PackedByteArray &p_data) {
    if (p_data.is_empty()) {
        return std::string();
    }
    return std::string(reinterpret_cast<const char *>(p_data.ptr()), static_cast<size_t>(p_data.size()));
}

bool read_file_bytes(const std::filesystem::path &p_path, std::string &r_data) {
    std::ifstream input(p_path, std::ios::binary);
    if (!input.is_open()) {
        return false;
    }

    std::ostringstream buffer;
    buffer << input.rdbuf();
    r_data = buffer.str();
    return input.good() || input.eof();
}

bool write_file_bytes(const std::filesystem::path &p_path, const PackedByteArray &p_data) {
    std::ofstream output(p_path, std::ios::binary | std::ios::trunc);
    if (!output.is_open()) {
        return false;
    }

    if (!p_data.is_empty()) {
        output.write(reinterpret_cast<const char *>(p_data.ptr()), p_data.size());
    }
    return output.good();
}

std::filesystem::path make_temp_path(const char *p_extension) {
    const auto base = std::filesystem::temp_directory_path();
    const auto unique = std::to_string(std::chrono::high_resolution_clock::now().time_since_epoch().count());
    return base / ("OCCT_Light_gd_" + unique + p_extension);
}

bool is_status_done(const IFSelect_ReturnStatus p_status) {
    return p_status == IFSelect_RetDone;
}

class ScopedOcctMessengerSilence {
private:
    Handle(Message_Messenger) messenger;
    NCollection_Sequence<Handle(Message_Printer)> printers;

public:
    ScopedOcctMessengerSilence() :
            messenger(Message::DefaultMessenger()),
            printers(messenger->Printers()) {
        messenger->ChangePrinters().Clear();
    }

    ~ScopedOcctMessengerSilence() {
        // Intentionally do NOT restore printers.  The default messenger's cout
        // printers are permanently removed at extension init; restoring them
        // would cause a segfault later when Godot corrupts cout's vtable
        // during shutdown.  Silence is permanent.
        (void)printers;
    }
};

bool import_step_stream_impl(TopoDS_Shape &r_shape, std::istream &p_stream) {
    ScopedOcctMessengerSilence silence;
    STEPControl_Reader reader;
    if (!is_status_done(reader.ReadStream("memory.step", p_stream))) {
        return false;
    }
    if (reader.TransferRoots() <= 0) {
        return false;
    }
    r_shape = reader.OneShape();
    return !r_shape.IsNull();
}

bool export_step_stream_impl(const TopoDS_Shape &p_shape, std::ostream &p_stream) {
    ScopedOcctMessengerSilence silence;
    STEPControl_Writer writer;
    if (!is_status_done(writer.Transfer(p_shape, STEPControl_AsIs))) {
        return false;
    }
    return is_status_done(writer.WriteStream(p_stream));
}

} // namespace

void TopoShape::_bind_methods() {
    ClassDB::bind_method(D_METHOD("is_null"), &TopoShape::is_null);
    ClassDB::bind_method(D_METHOD("copy"), &TopoShape::copy);
    ClassDB::bind_method(D_METHOD("fuse", "other"), &TopoShape::fuse);
    ClassDB::bind_method(D_METHOD("cut", "other"), &TopoShape::cut);
    ClassDB::bind_method(D_METHOD("common", "other"), &TopoShape::common);
    ClassDB::bind_method(D_METHOD("fuse_all", "shapes"), &TopoShape::fuse_all);
    ClassDB::bind_method(D_METHOD("cut_all", "shapes"), &TopoShape::cut_all);
    ClassDB::bind_method(D_METHOD("common_all", "shapes"), &TopoShape::common_all);
    ClassDB::bind_method(D_METHOD("translated", "offset"), &TopoShape::translated);
    ClassDB::bind_method(D_METHOD("rotated", "axis_origin", "axis_direction", "angle_radians"), &TopoShape::rotated);
    ClassDB::bind_method(D_METHOD("scaled", "center", "factor"), &TopoShape::scaled);
    ClassDB::bind_method(D_METHOD("mirrored_about_point", "center"), &TopoShape::mirrored_about_point);
    ClassDB::bind_method(D_METHOD("mirrored_about_axis", "axis"), &TopoShape::mirrored_about_axis);
    ClassDB::bind_method(D_METHOD("mirrored_about_plane", "plane"), &TopoShape::mirrored_about_plane);
    ClassDB::bind_method(D_METHOD("located", "location"), &TopoShape::located);
    ClassDB::bind_method(D_METHOD("get_volume"), &TopoShape::get_volume);
    ClassDB::bind_method(D_METHOD("get_surface_area"), &TopoShape::get_surface_area);
    ClassDB::bind_method(D_METHOD("get_shape_type_name"), &TopoShape::get_shape_type_name);
    ClassDB::bind_method(D_METHOD("get_geom_type_name"), &TopoShape::get_geom_type_name);
    ClassDB::bind_method(D_METHOD("get_center_of_mass"), &TopoShape::get_center_of_mass);
    ClassDB::bind_method(D_METHOD("get_bounding_box_min"), &TopoShape::get_bounding_box_min);
    ClassDB::bind_method(D_METHOD("get_bounding_box_max"), &TopoShape::get_bounding_box_max);
    ClassDB::bind_method(D_METHOD("get_bounding_box_size"), &TopoShape::get_bounding_box_size);
    ClassDB::bind_method(D_METHOD("get_vertices"), &TopoShape::get_vertices);
    ClassDB::bind_method(D_METHOD("get_edges"), &TopoShape::get_edges);
    ClassDB::bind_method(D_METHOD("get_wires"), &TopoShape::get_wires);
    ClassDB::bind_method(D_METHOD("get_faces"), &TopoShape::get_faces);
    ClassDB::bind_method(D_METHOD("get_shells"), &TopoShape::get_shells);
    ClassDB::bind_method(D_METHOD("get_compounds"), &TopoShape::get_compounds);
    ClassDB::bind_method(D_METHOD("get_solids"), &TopoShape::get_solids);
    ClassDB::bind_method(D_METHOD("decompose_compound"), &TopoShape::decompose_compound);
    ClassDB::bind_method(D_METHOD("get_vertex_positions"), &TopoShape::get_vertex_positions);
    ClassDB::bind_method(D_METHOD("get_edge_polylines", "deflection"), &TopoShape::get_edge_polylines, DEFVAL(0.1));
    ClassDB::bind_method(D_METHOD("import_step_file", "file_path"), &TopoShape::import_step_file);
    ClassDB::bind_method(D_METHOD("export_step_file", "file_path"), &TopoShape::export_step_file);
    ClassDB::bind_method(D_METHOD("import_step_bytes", "data"), &TopoShape::import_step_bytes);
    ClassDB::bind_method(D_METHOD("export_step_bytes"), &TopoShape::export_step_bytes);
    ClassDB::bind_method(D_METHOD("import_stl_file", "file_path"), &TopoShape::import_stl_file);
    ClassDB::bind_method(D_METHOD("export_stl_file", "file_path", "ascii"), &TopoShape::export_stl_file, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("import_stl_bytes", "data"), &TopoShape::import_stl_bytes);
    ClassDB::bind_method(D_METHOD("export_stl_bytes", "ascii"), &TopoShape::export_stl_bytes, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("to_array_mesh", "linear_deflection", "angular_deflection"), &TopoShape::to_array_mesh, DEFVAL(0.1), DEFVAL(0.5));
}

TopoShape::TopoShape() = default;

Ref<TopoShape> TopoShape::from_occt(const TopoDS_Shape &p_shape) {
    Ref<TopoShape> result;
    result.instantiate();
    result->occt_shape = p_shape;
    return result;
}

bool TopoShape::is_null() const {
    return occt_shape.IsNull();
}

Ref<TopoShape> TopoShape::copy() const {
    ensure_shape_present(occt_shape, "TopoShape.copy requires a non-null shape.");

    try {
        BRepBuilderAPI_Copy copier(occt_shape, true, false);
        return from_occt(copier.Shape());
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.copy failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<TopoShape>();
    }
}

Ref<TopoShape> TopoShape::fuse(const Ref<TopoShape> &p_other) const {
    ERR_FAIL_COND_V_MSG(p_other.is_null() || p_other->is_null(), Ref<TopoShape>(), "TopoShape.fuse requires a non-null other shape.");
    ensure_shape_present(occt_shape, "TopoShape.fuse requires a non-null shape.");

    try {
        return do_boolean_operation<BRepAlgoAPI_Fuse>(occt_shape, p_other->occt_shape);
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.fuse failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<TopoShape>();
    }
}

Ref<TopoShape> TopoShape::cut(const Ref<TopoShape> &p_other) const {
    ERR_FAIL_COND_V_MSG(p_other.is_null() || p_other->is_null(), Ref<TopoShape>(), "TopoShape.cut requires a non-null other shape.");
    ensure_shape_present(occt_shape, "TopoShape.cut requires a non-null shape.");

    try {
        return do_boolean_operation<BRepAlgoAPI_Cut>(occt_shape, p_other->occt_shape);
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.cut failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<TopoShape>();
    }
}

Ref<TopoShape> TopoShape::common(const Ref<TopoShape> &p_other) const {
    ERR_FAIL_COND_V_MSG(p_other.is_null() || p_other->is_null(), Ref<TopoShape>(), "TopoShape.common requires a non-null other shape.");
    ensure_shape_present(occt_shape, "TopoShape.common requires a non-null shape.");

    try {
        return do_boolean_operation<BRepAlgoAPI_Common>(occt_shape, p_other->occt_shape);
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.common failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<TopoShape>();
    }
}

Ref<TopoShape> TopoShape::fuse_all(const Array &p_shapes) const {
    ensure_shape_present(occt_shape, "TopoShape.fuse_all requires a non-null shape.");

    try {
        Ref<TopoShape> result = copy();
        ERR_FAIL_COND_V_MSG(result.is_null(), Ref<TopoShape>(), "TopoShape.fuse_all could not copy the source shape.");
        return do_boolean_sequence<BRepAlgoAPI_Fuse>(result, p_shapes, "TopoShape.fuse_all requires every shape entry to be a non-null TopoShape.");
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.fuse_all failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<TopoShape>();
    }
}

Ref<TopoShape> TopoShape::cut_all(const Array &p_shapes) const {
    ensure_shape_present(occt_shape, "TopoShape.cut_all requires a non-null shape.");

    try {
        Ref<TopoShape> result = copy();
        ERR_FAIL_COND_V_MSG(result.is_null(), Ref<TopoShape>(), "TopoShape.cut_all could not copy the source shape.");
        return do_boolean_sequence<BRepAlgoAPI_Cut>(result, p_shapes, "TopoShape.cut_all requires every shape entry to be a non-null TopoShape.");
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.cut_all failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<TopoShape>();
    }
}

Ref<TopoShape> TopoShape::common_all(const Array &p_shapes) const {
    ensure_shape_present(occt_shape, "TopoShape.common_all requires a non-null shape.");

    try {
        Ref<TopoShape> result = copy();
        ERR_FAIL_COND_V_MSG(result.is_null(), Ref<TopoShape>(), "TopoShape.common_all could not copy the source shape.");
        return do_boolean_sequence<BRepAlgoAPI_Common>(result, p_shapes, "TopoShape.common_all requires every shape entry to be a non-null TopoShape.");
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.common_all failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<TopoShape>();
    }
}

Ref<TopoShape> TopoShape::translated(const Vector3 &p_offset) const {
    ensure_shape_present(occt_shape, "TopoShape.translated requires a non-null shape.");

    try {
        gp_Trsf transform;
        transform.SetTranslation(occt_utils::to_occt_vec(p_offset));
        BRepBuilderAPI_Transform transformer(occt_shape, transform, true, true);
        return from_occt(transformer.Shape());
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.translated failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<TopoShape>();
    }
}

Ref<TopoShape> TopoShape::rotated(const Vector3 &p_axis_origin, const Vector3 &p_axis_direction, double p_angle_radians) const {
    ensure_shape_present(occt_shape, "TopoShape.rotated requires a non-null shape.");
    ERR_FAIL_COND_V_MSG(p_axis_direction.length() == 0.0, Ref<TopoShape>(), "TopoShape.rotated requires a non-zero axis direction.");

    try {
        gp_Trsf transform;
        transform.SetRotation(
            gp_Ax1(
                occt_utils::to_occt_point(p_axis_origin),
                gp_Dir(
                    static_cast<double>(p_axis_direction.x),
                    static_cast<double>(p_axis_direction.y),
                    static_cast<double>(p_axis_direction.z)
                )
            ),
            p_angle_radians
        );
        BRepBuilderAPI_Transform transformer(occt_shape, transform, true, true);
        return from_occt(transformer.Shape());
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.rotated failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<TopoShape>();
    }
}

Ref<TopoShape> TopoShape::scaled(const Vector3 &p_center, double p_factor) const {
    ensure_shape_present(occt_shape, "TopoShape.scaled requires a non-null shape.");
    ERR_FAIL_COND_V_MSG(p_factor == 0.0, Ref<TopoShape>(), "TopoShape.scaled requires a non-zero scale factor.");

    try {
        gp_Trsf transform;
        transform.SetScale(occt_utils::to_occt_point(p_center), p_factor);
        BRepBuilderAPI_Transform transformer(occt_shape, transform, true, true);
        return from_occt(transformer.Shape());
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.scaled failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<TopoShape>();
    }
}

Ref<TopoShape> TopoShape::mirrored_about_point(const Vector3 &p_center) const {
    ensure_shape_present(occt_shape, "TopoShape.mirrored_about_point requires a non-null shape.");

    try {
        gp_Trsf transform;
        transform.SetMirror(occt_utils::to_occt_point(p_center));
        BRepBuilderAPI_Transform transformer(occt_shape, transform, true, true);
        return from_occt(transformer.Shape());
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.mirrored_about_point failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<TopoShape>();
    }
}

Ref<TopoShape> TopoShape::mirrored_about_axis(const Ref<Axis> &p_axis) const {
    ensure_shape_present(occt_shape, "TopoShape.mirrored_about_axis requires a non-null shape.");
    ERR_FAIL_COND_V_MSG(p_axis.is_null(), Ref<TopoShape>(), "TopoShape.mirrored_about_axis requires a non-null axis.");

    try {
        gp_Trsf transform;
        transform.SetMirror(p_axis->get_occt_axis());
        BRepBuilderAPI_Transform transformer(occt_shape, transform, true, true);
        return from_occt(transformer.Shape());
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.mirrored_about_axis failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<TopoShape>();
    }
}

Ref<TopoShape> TopoShape::mirrored_about_plane(const Ref<CadPlane> &p_plane) const {
    ensure_shape_present(occt_shape, "TopoShape.mirrored_about_plane requires a non-null shape.");
    ERR_FAIL_COND_V_MSG(p_plane.is_null(), Ref<TopoShape>(), "TopoShape.mirrored_about_plane requires a non-null plane.");

    try {
        gp_Trsf transform;
        transform.SetMirror(p_plane->get_occt_plane().Position().Ax2());
        BRepBuilderAPI_Transform transformer(occt_shape, transform, true, true);
        return from_occt(transformer.Shape());
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.mirrored_about_plane failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<TopoShape>();
    }
}

Ref<TopoShape> TopoShape::located(const Ref<Location> &p_location) const {
    ensure_shape_present(occt_shape, "TopoShape.located requires a non-null shape.");
    ERR_FAIL_COND_V_MSG(p_location.is_null(), Ref<TopoShape>(), "TopoShape.located requires a non-null location.");

    try {
        BRepBuilderAPI_Transform transformer(occt_shape, p_location->get_occt_transform(), true, true);
        return from_occt(transformer.Shape());
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.located failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<TopoShape>();
    }
}

double TopoShape::get_volume() const {
    ensure_shape_present(occt_shape, "TopoShape.get_volume requires a non-null shape.");

    try {
        GProp_GProps properties;
        BRepGProp::VolumeProperties(occt_shape, properties);
        return properties.Mass();
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.get_volume failed: %s", occt_utils::exception_to_string(failure)));
        return 0.0;
    }
}

double TopoShape::get_surface_area() const {
    ensure_shape_present(occt_shape, "TopoShape.get_surface_area requires a non-null shape.");

    try {
        GProp_GProps properties;
        BRepGProp::SurfaceProperties(occt_shape, properties);
        return properties.Mass();
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.get_surface_area failed: %s", occt_utils::exception_to_string(failure)));
        return 0.0;
    }
}

String TopoShape::get_shape_type_name() const {
    ensure_shape_present(occt_shape, "TopoShape.get_shape_type_name requires a non-null shape.");

    switch (occt_shape.ShapeType()) {
        case TopAbs_COMPOUND:
            return "COMPOUND";
        case TopAbs_COMPSOLID:
            return "COMPSOLID";
        case TopAbs_SOLID:
            return "SOLID";
        case TopAbs_SHELL:
            return "SHELL";
        case TopAbs_FACE:
            return "FACE";
        case TopAbs_WIRE:
            return "WIRE";
        case TopAbs_EDGE:
            return "EDGE";
        case TopAbs_VERTEX:
            return "VERTEX";
        case TopAbs_SHAPE:
        default:
            return "SHAPE";
    }
}

String TopoShape::get_geom_type_name() const {
    ensure_shape_present(occt_shape, "TopoShape.get_geom_type_name requires a non-null shape.");

    try {
        switch (occt_shape.ShapeType()) {
            case TopAbs_EDGE: {
                const GeomAbs_CurveType curve_type = BRepAdaptor_Curve(TopoDS::Edge(occt_shape)).GetType();
                switch (curve_type) {
                    case GeomAbs_Line: return "LINE";
                    case GeomAbs_Circle: return "CIRCLE";
                    case GeomAbs_Ellipse: return "ELLIPSE";
                    case GeomAbs_Hyperbola: return "HYPERBOLA";
                    case GeomAbs_Parabola: return "PARABOLA";
                    case GeomAbs_BezierCurve: return "BEZIER";
                    case GeomAbs_BSplineCurve: return "BSPLINE";
                    case GeomAbs_OffsetCurve: return "OFFSET";
                    case GeomAbs_OtherCurve:
                    default:
                        return "OTHER";
                }
            }
            case TopAbs_FACE: {
                const GeomAbs_SurfaceType surface_type = BRepAdaptor_Surface(TopoDS::Face(occt_shape)).GetType();
                switch (surface_type) {
                    case GeomAbs_Plane: return "PLANE";
                    case GeomAbs_Cylinder: return "CYLINDER";
                    case GeomAbs_Cone: return "CONE";
                    case GeomAbs_Sphere: return "SPHERE";
                    case GeomAbs_Torus: return "TORUS";
                    case GeomAbs_BezierSurface: return "BEZIER";
                    case GeomAbs_BSplineSurface: return "BSPLINE";
                    case GeomAbs_SurfaceOfRevolution: return "REVOLUTION";
                    case GeomAbs_SurfaceOfExtrusion: return "EXTRUSION";
                    case GeomAbs_OffsetSurface: return "OFFSET";
                    case GeomAbs_OtherSurface:
                    default:
                        return "OTHER";
                }
            }
            default:
                return "OTHER";
        }
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.get_geom_type_name failed: %s", occt_utils::exception_to_string(failure)));
        return String();
    }
}

Vector3 TopoShape::get_center_of_mass() const {
    ensure_shape_present(occt_shape, "TopoShape.get_center_of_mass requires a non-null shape.");

    try {
        GProp_GProps properties;
        BRepGProp::VolumeProperties(occt_shape, properties);
        return occt_utils::to_godot_vector3(properties.CentreOfMass());
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.get_center_of_mass failed: %s", occt_utils::exception_to_string(failure)));
        return Vector3();
    }
}

Vector3 TopoShape::get_bounding_box_min() const {
    ensure_shape_present(occt_shape, "TopoShape.get_bounding_box_min requires a non-null shape.");

    try {
        Bnd_Box bounds;
        BRepBndLib::Add(occt_shape, bounds, false);
        if (bounds.IsVoid()) {
            ERR_PRINT(vformat("TopoShape.get_bounding_box_min failed: could not compute a bounding box for the shape."));
            return Vector3();
        }

        double xmin = 0.0;
        double ymin = 0.0;
        double zmin = 0.0;
        double xmax = 0.0;
        double ymax = 0.0;
        double zmax = 0.0;
        bounds.Get(xmin, ymin, zmin, xmax, ymax, zmax);
        return Vector3(static_cast<real_t>(xmin), static_cast<real_t>(ymin), static_cast<real_t>(zmin));
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.get_bounding_box_min failed: %s", occt_utils::exception_to_string(failure)));
        return Vector3();
    }
}

Vector3 TopoShape::get_bounding_box_max() const {
    ensure_shape_present(occt_shape, "TopoShape.get_bounding_box_max requires a non-null shape.");

    try {
        Bnd_Box bounds;
        BRepBndLib::Add(occt_shape, bounds, false);
        if (bounds.IsVoid()) {
            ERR_PRINT(vformat("TopoShape.get_bounding_box_max failed: could not compute a bounding box for the shape."));
            return Vector3();
        }

        double xmin = 0.0;
        double ymin = 0.0;
        double zmin = 0.0;
        double xmax = 0.0;
        double ymax = 0.0;
        double zmax = 0.0;
        bounds.Get(xmin, ymin, zmin, xmax, ymax, zmax);
        return Vector3(static_cast<real_t>(xmax), static_cast<real_t>(ymax), static_cast<real_t>(zmax));
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.get_bounding_box_max failed: %s", occt_utils::exception_to_string(failure)));
        return Vector3();
    }
}

Vector3 TopoShape::get_bounding_box_size() const {
    return get_bounding_box_max() - get_bounding_box_min();
}

Array TopoShape::get_vertices() const {
    ensure_shape_present(occt_shape, "TopoShape.get_vertices requires a non-null shape.");

    try {
        Array vertices;
        NCollection_IndexedMap<TopoDS_Shape, TopTools_ShapeMapHasher> indexed_vertices;
        TopExp::MapShapes(occt_shape, TopAbs_VERTEX, indexed_vertices);
        for (int index = 1; index <= indexed_vertices.Extent(); ++index) {
            vertices.push_back(Vertex::from_occt(TopoDS::Vertex(indexed_vertices(index))));
        }
        return vertices;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.get_vertices failed: %s", occt_utils::exception_to_string(failure)));
        return Array();
    }
}

Array TopoShape::get_edges() const {
    ensure_shape_present(occt_shape, "TopoShape.get_edges requires a non-null shape.");

    try {
        Array edges;
        NCollection_IndexedMap<TopoDS_Shape, TopTools_ShapeMapHasher> indexed_edges;
        TopExp::MapShapes(occt_shape, TopAbs_EDGE, indexed_edges);
        for (int index = 1; index <= indexed_edges.Extent(); ++index) {
            edges.push_back(Edge::from_occt(TopoDS::Edge(indexed_edges(index))));
        }
        return edges;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.get_edges failed: %s", occt_utils::exception_to_string(failure)));
        return Array();
    }
}

Array TopoShape::get_wires() const {
    ensure_shape_present(occt_shape, "TopoShape.get_wires requires a non-null shape.");

    try {
        Array wires;
        NCollection_IndexedMap<TopoDS_Shape, TopTools_ShapeMapHasher> indexed_wires;
        TopExp::MapShapes(occt_shape, TopAbs_WIRE, indexed_wires);
        for (int index = 1; index <= indexed_wires.Extent(); ++index) {
            wires.push_back(Wire::from_occt(TopoDS::Wire(indexed_wires(index))));
        }
        return wires;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.get_wires failed: %s", occt_utils::exception_to_string(failure)));
        return Array();
    }
}

Array TopoShape::get_faces() const {
    ensure_shape_present(occt_shape, "TopoShape.get_faces requires a non-null shape.");

    try {
        Array faces;
        NCollection_IndexedMap<TopoDS_Shape, TopTools_ShapeMapHasher> indexed_faces;
        TopExp::MapShapes(occt_shape, TopAbs_FACE, indexed_faces);
        for (int index = 1; index <= indexed_faces.Extent(); ++index) {
            faces.push_back(Face::from_occt(TopoDS::Face(indexed_faces(index))));
        }
        return faces;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.get_faces failed: %s", occt_utils::exception_to_string(failure)));
        return Array();
    }
}

Array TopoShape::get_shells() const {
    ensure_shape_present(occt_shape, "TopoShape.get_shells requires a non-null shape.");

    try {
        Array shells;
        NCollection_IndexedMap<TopoDS_Shape, TopTools_ShapeMapHasher> indexed_shells;
        TopExp::MapShapes(occt_shape, TopAbs_SHELL, indexed_shells);
        for (int index = 1; index <= indexed_shells.Extent(); ++index) {
            shells.push_back(Shell::from_occt(TopoDS::Shell(indexed_shells(index))));
        }
        return shells;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.get_shells failed: %s", occt_utils::exception_to_string(failure)));
        return Array();
    }
}

Array TopoShape::get_compounds() const {
    ensure_shape_present(occt_shape, "TopoShape.get_compounds requires a non-null shape.");

    try {
        Array compounds;
        NCollection_IndexedMap<TopoDS_Shape, TopTools_ShapeMapHasher> indexed_compounds;
        TopExp::MapShapes(occt_shape, TopAbs_COMPOUND, indexed_compounds);
        for (int index = 1; index <= indexed_compounds.Extent(); ++index) {
            compounds.push_back(Compound::from_occt(TopoDS::Compound(indexed_compounds(index))));
        }
        return compounds;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.get_compounds failed: %s", occt_utils::exception_to_string(failure)));
        return Array();
    }
}

Array TopoShape::decompose_compound() const {
    Array children;

    try {
        if (occt_shape.IsNull() || occt_shape.ShapeType() != TopAbs_COMPOUND) {
            return children;
        }

        for (TopoDS_Iterator it(occt_shape); it.More(); it.Next()) {
            const TopoDS_Shape &child = it.Value();
            if (!child.IsNull()) {
                children.push_back(TopoShape::from_occt(child));
            }
        }
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.decompose_compound failed: %s", occt_utils::exception_to_string(failure)));
    }

    return children;
}

Array TopoShape::get_solids() const {
    ensure_shape_present(occt_shape, "TopoShape.get_solids requires a non-null shape.");

    try {
        Array solids;
        NCollection_IndexedMap<TopoDS_Shape, TopTools_ShapeMapHasher> indexed_solids;
        TopExp::MapShapes(occt_shape, TopAbs_SOLID, indexed_solids);
        for (int index = 1; index <= indexed_solids.Extent(); ++index) {
            solids.push_back(Solid::from_occt(TopoDS::Solid(indexed_solids(index))));
        }
        return solids;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.get_solids failed: %s", occt_utils::exception_to_string(failure)));
        return Array();
    }
}

PackedVector3Array TopoShape::get_vertex_positions() const {
    ensure_shape_present(occt_shape, "TopoShape.get_vertex_positions requires a non-null shape.");

    try {
        PackedVector3Array vertices;
        NCollection_IndexedMap<TopoDS_Shape, TopTools_ShapeMapHasher> indexed_vertices;
        TopExp::MapShapes(occt_shape, TopAbs_VERTEX, indexed_vertices);
        for (int index = 1; index <= indexed_vertices.Extent(); ++index) {
            vertices.push_back(occt_utils::to_godot_vector3(BRep_Tool::Pnt(TopoDS::Vertex(indexed_vertices(index)))));
        }
        return vertices;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.get_vertex_positions failed: %s", occt_utils::exception_to_string(failure)));
        return PackedVector3Array();
    }
}

Array TopoShape::get_edge_polylines(double p_deflection) const {
    ensure_shape_present(occt_shape, "TopoShape.get_edge_polylines requires a non-null shape.");
    ERR_FAIL_COND_V_MSG(p_deflection <= 0.0, Array(), "TopoShape.get_edge_polylines requires a positive deflection.");

    try {
        Array polylines;
        NCollection_IndexedMap<TopoDS_Shape, TopTools_ShapeMapHasher> indexed_edges;
        TopExp::MapShapes(occt_shape, TopAbs_EDGE, indexed_edges);
        for (int edge_index = 1; edge_index <= indexed_edges.Extent(); ++edge_index) {
            polylines.push_back(sample_edge_polyline(TopoDS::Edge(indexed_edges(edge_index)), p_deflection));
        }
        return polylines;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.get_edge_polylines failed: %s", occt_utils::exception_to_string(failure)));
        return Array();
    }
}

bool TopoShape::import_step_file(const String &p_file_path) {
    try {
        const std::string path = to_std_string(globalize_path(p_file_path));
        std::ifstream stream(path, std::ios::binary);
        if (!stream.is_open()) {
            return false;
        }
        TopoDS_Shape shape;
        if (!import_step_stream_impl(shape, stream)) {
            return false;
        }
        set_occt_shape(shape);
        return !occt_shape.IsNull();
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.import_step_file failed: %s", occt_utils::exception_to_string(failure)));
        return false;
    }
}

bool TopoShape::export_step_file(const String &p_file_path) const {
    ensure_shape_present(occt_shape, "TopoShape.export_step_file requires a non-null shape.");

    try {
        const std::string path = to_std_string(globalize_path(p_file_path));
        std::ofstream stream(path, std::ios::binary | std::ios::trunc);
        if (!stream.is_open()) {
            return false;
        }
        if (!export_step_stream_impl(occt_shape, stream)) {
            return false;
        }
        return stream.good();
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.export_step_file failed: %s", occt_utils::exception_to_string(failure)));
        return false;
    }
}

bool TopoShape::import_step_bytes(const PackedByteArray &p_data) {
    try {
        std::istringstream stream(to_std_string(p_data));
        TopoDS_Shape shape;
        if (!import_step_stream_impl(shape, stream)) {
            return false;
        }
        set_occt_shape(shape);
        return true;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.import_step_bytes failed: %s", occt_utils::exception_to_string(failure)));
        return false;
    }
}

PackedByteArray TopoShape::export_step_bytes() const {
    ensure_shape_present(occt_shape, "TopoShape.export_step_bytes requires a non-null shape.");

    try {
        std::ostringstream stream;
        if (!export_step_stream_impl(occt_shape, stream)) {
            return PackedByteArray();
        }
        return to_packed_byte_array(stream.str());
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.export_step_bytes failed: %s", occt_utils::exception_to_string(failure)));
        return PackedByteArray();
    }
}

bool TopoShape::import_stl_file(const String &p_file_path) {
    try {
        TopoDS_Shape shape;
        StlAPI_Reader reader;
        const std::string path = to_std_string(globalize_path(p_file_path));
        if (!reader.Read(shape, path.c_str())) {
            return false;
        }
        set_occt_shape(shape);
        return !occt_shape.IsNull();
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.import_stl_file failed: %s", occt_utils::exception_to_string(failure)));
        return false;
    }
}

bool TopoShape::export_stl_file(const String &p_file_path, bool p_ascii) const {
    ensure_shape_present(occt_shape, "TopoShape.export_stl_file requires a non-null shape.");

    try {
        BRepMesh_IncrementalMesh mesher(occt_shape, 0.1, false, 0.5, true);
        mesher.Perform();

        StlAPI_Writer writer;
        writer.ASCIIMode() = p_ascii;
        const std::string path = to_std_string(globalize_path(p_file_path));
        return writer.Write(occt_shape, path.c_str());
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.export_stl_file failed: %s", occt_utils::exception_to_string(failure)));
        return false;
    }
}

bool TopoShape::import_stl_bytes(const PackedByteArray &p_data) {
    try {
        const std::filesystem::path temp_path = make_temp_path(".stl");
        if (!write_file_bytes(temp_path, p_data)) {
            return false;
        }

        TopoDS_Shape shape;
        StlAPI_Reader reader;
        const bool success = reader.Read(shape, temp_path.string().c_str()) && !shape.IsNull();
        std::error_code remove_error;
        std::filesystem::remove(temp_path, remove_error);
        if (success) {
            set_occt_shape(shape);
        }
        return success;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.import_stl_bytes failed: %s", occt_utils::exception_to_string(failure)));
        return false;
    }
}

PackedByteArray TopoShape::export_stl_bytes(bool p_ascii) const {
    ensure_shape_present(occt_shape, "TopoShape.export_stl_bytes requires a non-null shape.");

    try {
        const std::filesystem::path temp_path = make_temp_path(".stl");
        StlAPI_Writer writer;
        writer.ASCIIMode() = p_ascii;
        if (!writer.Write(occt_shape, temp_path.string().c_str())) {
            return PackedByteArray();
        }

        std::string data;
        const bool read_ok = read_file_bytes(temp_path, data);
        std::error_code remove_error;
        std::filesystem::remove(temp_path, remove_error);
        if (!read_ok) {
            return PackedByteArray();
        }
        return to_packed_byte_array(data);
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.export_stl_bytes failed: %s", occt_utils::exception_to_string(failure)));
        return PackedByteArray();
    }
}

Ref<ArrayMesh> TopoShape::to_array_mesh(double p_linear_deflection, double p_angular_deflection) const {
    ensure_shape_present(occt_shape, "TopoShape.to_array_mesh requires a non-null shape.");
    ERR_FAIL_COND_V_MSG(p_linear_deflection <= 0.0, Ref<ArrayMesh>(), "TopoShape.to_array_mesh requires a positive linear deflection.");
    ERR_FAIL_COND_V_MSG(p_angular_deflection <= 0.0, Ref<ArrayMesh>(), "TopoShape.to_array_mesh requires a positive angular deflection.");

    try {
        BRepMesh_IncrementalMesh mesher(
            occt_shape,
            static_cast<double>(p_linear_deflection),
        	    false,
        	    static_cast<double>(p_angular_deflection),
        	    true
        	);
        mesher.Perform();

        PackedVector3Array vertices;
        PackedVector3Array normals;
        PackedVector2Array uvs;
        PackedInt32Array indices;

        int32_t vertex_offset = 0;
        for (TopExp_Explorer face_explorer(occt_shape, TopAbs_FACE); face_explorer.More(); face_explorer.Next()) {
            const TopoDS_Face face = TopoDS::Face(face_explorer.Current());
            TopLoc_Location location;
            const Handle(Poly_Triangulation) triangulation = BRep_Tool::Triangulation(face, location);
            if (triangulation.IsNull() || triangulation->NbNodes() == 0 || triangulation->NbTriangles() == 0) {
                continue;
            }

            const auto transform = location.Transformation();
            const bool has_normals = triangulation->HasNormals();
            const bool has_uvs = triangulation->HasUVNodes();

            for (int node_index = 1; node_index <= triangulation->NbNodes(); ++node_index) {
                const gp_Pnt transformed_point = triangulation->Node(node_index).Transformed(transform);
                vertices.push_back(occt_utils::to_godot_vector3(transformed_point));

                if (has_normals) {
                    const gp_Dir transformed_normal = triangulation->Normal(node_index).Transformed(transform);
                    normals.push_back(Vector3(
                        static_cast<real_t>(transformed_normal.X()),
                        static_cast<real_t>(transformed_normal.Y()),
                        static_cast<real_t>(transformed_normal.Z())
                    ));
                }

                if (has_uvs) {
                    const gp_Pnt2d uv = triangulation->UVNode(node_index);
                    uvs.push_back(Vector2(static_cast<real_t>(uv.X()), static_cast<real_t>(uv.Y())));
                }
            }

            for (int triangle_index = 1; triangle_index <= triangulation->NbTriangles(); ++triangle_index) {
                int n1 = 0;
                int n2 = 0;
                int n3 = 0;
                triangulation->Triangle(triangle_index).Get(n1, n2, n3);

                if (face.Orientation() == TopAbs_REVERSED) {
                    std::swap(n2, n3);
                }

                indices.push_back(vertex_offset + (n1 - 1));
                indices.push_back(vertex_offset + (n2 - 1));
                indices.push_back(vertex_offset + (n3 - 1));
            }

            vertex_offset += triangulation->NbNodes();
        }

        ERR_FAIL_COND_V_MSG(vertices.is_empty() || indices.is_empty(), Ref<ArrayMesh>(), "OpenCASCADE could not triangulate the shape into a render mesh.");

        Array arrays;
        arrays.resize(Mesh::ARRAY_MAX);
        arrays[Mesh::ARRAY_VERTEX] = vertices;
        arrays[Mesh::ARRAY_INDEX] = indices;
        if (!normals.is_empty()) {
            arrays[Mesh::ARRAY_NORMAL] = normals;
        }
        if (!uvs.is_empty()) {
            arrays[Mesh::ARRAY_TEX_UV] = uvs;
        }

        Ref<ArrayMesh> mesh;
        mesh.instantiate();
        mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
        return mesh;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("TopoShape.to_array_mesh failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<ArrayMesh>();
    }
}

void TopoShape::set_occt_shape(const TopoDS_Shape &p_shape) {
    occt_shape = p_shape;
}

const TopoDS_Shape &TopoShape::get_occt_shape() const {
    return occt_shape;
}
