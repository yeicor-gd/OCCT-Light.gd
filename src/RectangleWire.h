#ifndef RECTANGLE_WIRE_H
#define RECTANGLE_WIRE_H

#include "Wire.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/vector2.hpp>

class CadPlane;

class RectangleWire : public Wire {
    GDCLASS(RectangleWire, Wire)

protected:
    static void _bind_methods();

public:
    RectangleWire();

    void build_rectangle(const godot::Vector2 &p_size, const godot::Ref<CadPlane> &p_plane = godot::Ref<CadPlane>(), bool p_centered = true);
};

#endif // RECTANGLE_WIRE_H
