#ifndef POLYGON_WIRE_H
#define POLYGON_WIRE_H

#include "Wire.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

class CadPlane;

class PolygonWire : public Wire {
    GDCLASS(PolygonWire, Wire)

protected:
    static void _bind_methods();

public:
    PolygonWire();

    void build_polygon_2d(const godot::PackedVector2Array &p_points, const godot::Ref<CadPlane> &p_plane = godot::Ref<CadPlane>(), bool p_closed = true);
};

#endif // POLYGON_WIRE_H
