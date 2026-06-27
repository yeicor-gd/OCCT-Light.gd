#include "OcctlCoreWrapper.h" // NOLINT(misc-include-cleaner)

#include <godot_cpp/classes/ref.hpp> // NOLINT(misc-include-cleaner)
#include <godot_cpp/core/class_db.hpp> // NOLINT(misc-include-cleaner)
#include <godot_cpp/variant/string.hpp> // NOLINT(misc-include-cleaner)
#include "occtl_core.h" // NOLINT(misc-include-cleaner)

void OcctlCoreWrapper::_bind_methods() {
    godot::ClassDB::bind_method(godot::D_METHOD("version_major"), &OcctlCoreWrapper::version_major);
    godot::ClassDB::bind_method(godot::D_METHOD("version_minor"), &OcctlCoreWrapper::version_minor);
    godot::ClassDB::bind_method(godot::D_METHOD("version_patch"), &OcctlCoreWrapper::version_patch);
}

int OcctlCoreWrapper::version_major(void) { // NOLINT(readability-convert-member-functions-to-static)
    return OCCTL_VERSION_MAJOR;
}

int OcctlCoreWrapper::version_minor(void) { // NOLINT(readability-convert-member-functions-to-static)
    return OCCTL_VERSION_MINOR;
}

int OcctlCoreWrapper::version_patch(void) { // NOLINT(readability-convert-member-functions-to-static)
    return OCCTL_VERSION_PATCH;
}
