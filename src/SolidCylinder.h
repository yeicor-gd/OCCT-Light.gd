#ifndef SOLID_CYLINDER_H
#define SOLID_CYLINDER_H

#include "Solid.h"

class SolidCylinder : public Solid {
    GDCLASS(SolidCylinder, Solid)

protected:
    static void _bind_methods();

public:
    SolidCylinder();

    void build_cylinder(double p_radius, double p_height, const godot::Vector3 &p_origin = godot::Vector3());
};

#endif // SOLID_CYLINDER_H
