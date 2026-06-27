#ifndef PLANE_H
#define PLANE_H

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <gp_Pln.hxx>

class Location;

class CadPlane : public godot::RefCounted {
    GDCLASS(CadPlane, godot::RefCounted)

protected:
    static void _bind_methods();

    gp_Pln occt_plane;

public:
    CadPlane();

    void set_plane(const godot::Vector3 &p_origin, const godot::Vector3 &p_normal, const godot::Vector3 &p_x_direction = godot::Vector3(1.0, 0.0, 0.0));
    godot::Vector3 get_origin() const;
    godot::Vector3 get_normal() const;
    godot::Vector3 get_x_direction() const;
    godot::Vector3 get_y_direction() const;
    double signed_distance_to_point(const godot::Vector3 &p_point) const;
    godot::Vector3 project_point(const godot::Vector3 &p_point) const;
    godot::Ref<CadPlane> offsetted(double p_distance) const;
    godot::Ref<CadPlane> transformed(const godot::Ref<Location> &p_location) const;

    void set_occt_plane(const gp_Pln &p_plane);
    const gp_Pln &get_occt_plane() const;
};

#endif // PLANE_H
