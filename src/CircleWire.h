#ifndef CIRCLE_WIRE_H
#define CIRCLE_WIRE_H

#include "Wire.h"

#include <godot_cpp/classes/ref.hpp>

class CadPlane;

class CircleWire : public Wire {
    GDCLASS(CircleWire, Wire)

protected:
    static void _bind_methods();

public:
    CircleWire();

    void build_circle(double p_radius, const godot::Ref<CadPlane> &p_plane = godot::Ref<CadPlane>());
};

#endif // CIRCLE_WIRE_H
