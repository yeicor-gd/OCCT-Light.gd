#ifndef OPENCASCADE_VERSION_H
#define OPENCASCADE_VERSION_H

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>

class OpenCascadeVersion : public godot::Object {
    GDCLASS(OpenCascadeVersion, godot::Object)

protected:
    static void _bind_methods();

public:
    godot::String get_version_string() const;
    int64_t get_version_major() const;
    int64_t get_version_minor() const;
    int64_t get_version_maintenance() const;
};

#endif // OPENCASCADE_VERSION_H
