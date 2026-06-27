#ifndef REGULAR_POLYGON_WIRE_H
#define REGULAR_POLYGON_WIRE_H

#include "Wire.h"

#include <godot_cpp/classes/ref.hpp>

class CadPlane;

class RegularPolygonWire : public Wire {
    GDCLASS(RegularPolygonWire, Wire)

protected:
    static void _bind_methods();

public:
    RegularPolygonWire();

    void build_regular_polygon(double p_radius, int p_side_count, const godot::Ref<CadPlane> &p_plane = godot::Ref<CadPlane>(), double p_start_angle_radians = 0.0);
};

#endif // REGULAR_POLYGON_WIRE_H
