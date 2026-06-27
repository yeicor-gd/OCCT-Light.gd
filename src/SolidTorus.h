#ifndef SOLID_TORUS_H
#define SOLID_TORUS_H

#include "Solid.h"

class SolidTorus : public Solid {
    GDCLASS(SolidTorus, Solid)

protected:
    static void _bind_methods();

public:
    SolidTorus();

    void build_torus(double p_major_radius, double p_minor_radius, const godot::Vector3 &p_center = godot::Vector3());
};

#endif // SOLID_TORUS_H
