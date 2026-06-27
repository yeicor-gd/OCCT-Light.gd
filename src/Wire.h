#ifndef WIRE_H
#define WIRE_H

#include "TopoShape.h"

#include <TopoDS_Wire.hxx>

class Solid;
class Axis;

class Wire : public TopoShape {
    GDCLASS(Wire, TopoShape)

protected:
    static void _bind_methods();

public:
    Wire();

    static godot::Ref<Wire> from_occt(const TopoDS_Wire &p_wire);

    void build_polygon(const godot::PackedVector3Array &p_points, bool p_closed = true);
    godot::Ref<TopoShape> lofted_to(const godot::Ref<Wire> &p_other, bool p_make_solid = true, bool p_ruled = false) const;
    godot::Ref<TopoShape> swept_along(const godot::Ref<Wire> &p_spine) const;
    godot::Ref<Wire> offset_2d(double p_distance) const;
    godot::Ref<Solid> extruded(const godot::Vector3 &p_direction, bool p_only_plane = true) const;
    godot::Ref<Solid> revolved(const godot::Ref<Axis> &p_axis, double p_angle_radians = 6.28318530717958647692, bool p_only_plane = true) const;
    bool is_closed() const;
    double get_length() const;
    godot::Array get_edges() const;
    godot::PackedVector3Array get_polyline(double p_deflection = 0.1) const;
};

#endif // WIRE_H
