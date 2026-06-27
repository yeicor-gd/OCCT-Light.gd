#ifndef ELLIPSE_WIRE_H
#define ELLIPSE_WIRE_H

#include "Wire.h"

#include <godot_cpp/classes/ref.hpp>

class CadPlane;

class EllipseWire : public Wire {
    GDCLASS(EllipseWire, Wire)

protected:
    static void _bind_methods();

public:
    EllipseWire();

    void build_ellipse(double p_major_radius, double p_minor_radius, const godot::Ref<CadPlane> &p_plane = godot::Ref<CadPlane>());
};

#endif // ELLIPSE_WIRE_H
