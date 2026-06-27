#ifndef RECTANGLE_ROUNDED_WIRE_H
#define RECTANGLE_ROUNDED_WIRE_H

#include "Wire.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/vector2.hpp>

class CadPlane;

class RectangleRoundedWire : public Wire {
    GDCLASS(RectangleRoundedWire, Wire)

protected:
    static void _bind_methods();

public:
    RectangleRoundedWire();

    void build_rounded_rectangle(const godot::Vector2 &p_size, double p_radius, const godot::Ref<CadPlane> &p_plane = godot::Ref<CadPlane>(), bool p_centered = true);
};

#endif // RECTANGLE_ROUNDED_WIRE_H
