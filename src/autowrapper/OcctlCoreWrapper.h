#ifndef OCCTLCOREWRAPPER_H
#define OCCTLCOREWRAPPER_H

#include <godot_cpp/classes/object.hpp> // NOLINT(misc-include-cleaner)
#include <godot_cpp/classes/ref.hpp> // NOLINT(misc-include-cleaner)
#include <godot_cpp/core/class_db.hpp> // NOLINT(misc-include-cleaner)
#include <godot_cpp/variant/callable.hpp> // NOLINT(misc-include-cleaner)
#include <godot_cpp/variant/array.hpp> // NOLINT(misc-include-cleaner)
#include <godot_cpp/variant/utility_functions.hpp> // NOLINT(misc-include-cleaner)
#include "occtl_core.h" // NOLINT(misc-include-cleaner)

using namespace godot;

class OcctlCoreWrapper : public godot::RefCounted { // NOLINT(cppcoreguidelines-special-member-functions, hicpp-special-member-functions)
    GDCLASS(OcctlCoreWrapper, godot::RefCounted) // NOLINT
protected:
    static void _bind_methods();
public:
    int version_major(void); // NOLINT(readability-convert-member-functions-to-static)
    int version_minor(void); // NOLINT(readability-convert-member-functions-to-static)
    int version_patch(void); // NOLINT(readability-convert-member-functions-to-static)
};


#endif // OCCTLCOREWRAPPER_H
