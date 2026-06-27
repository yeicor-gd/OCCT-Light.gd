#ifndef FACE_H
#define FACE_H

#include "TopoShape.h"

#include <TopoDS_Face.hxx>

class Wire;
class Solid;
class Axis;

class Face : public TopoShape {
    GDCLASS(Face, TopoShape)

protected:
    static void _bind_methods();

public:
    Face();

    static godot::Ref<Face> from_occt(const TopoDS_Face &p_face);

    void build_from_wire(const godot::Ref<Wire> &p_wire, bool p_only_plane = false);
    void build_from_wires(const godot::Ref<Wire> &p_outer_wire, const godot::Array &p_inner_wires, bool p_only_plane = false);
    void build_polygon(const godot::PackedVector3Array &p_points, bool p_only_plane = true);
    godot::Ref<Face> offset_2d(double p_distance) const;
    godot::Ref<Solid> extruded(const godot::Vector3 &p_direction) const;
    godot::Ref<Solid> revolved(const godot::Ref<Axis> &p_axis, double p_angle_radians = 6.28318530717958647692) const;
    bool is_planar() const;
    godot::Ref<Wire> get_outer_wire() const;
    godot::Array get_inner_wires() const;
    godot::Vector3 get_normal() const;
};

#endif // FACE_H
