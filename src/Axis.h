#ifndef AXIS_H
#define AXIS_H

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <gp_Ax1.hxx>

class Location;

class Axis : public godot::RefCounted {
    GDCLASS(Axis, godot::RefCounted)

protected:
    static void _bind_methods();

    gp_Ax1 occt_axis;

public:
    Axis();

    void set_axis(const godot::Vector3 &p_origin, const godot::Vector3 &p_direction);
    godot::Vector3 get_origin() const;
    godot::Vector3 get_direction() const;
    godot::Ref<Axis> reversed() const;
    godot::Ref<Axis> transformed(const godot::Ref<Location> &p_location) const;

    void set_occt_axis(const gp_Ax1 &p_axis);
    const gp_Ax1 &get_occt_axis() const;
};

#endif // AXIS_H
