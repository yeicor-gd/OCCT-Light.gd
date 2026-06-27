#include "OpenCascadeVersion.h"

#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <Standard_Version.hxx>
#include <Standard_Failure.hxx>

void OpenCascadeVersion::_bind_methods() {
    godot::ClassDB::bind_method(godot::D_METHOD("get_version_string"), &OpenCascadeVersion::get_version_string);
    godot::ClassDB::bind_method(godot::D_METHOD("get_version_major"), &OpenCascadeVersion::get_version_major);
    godot::ClassDB::bind_method(godot::D_METHOD("get_version_minor"), &OpenCascadeVersion::get_version_minor);
    godot::ClassDB::bind_method(godot::D_METHOD("get_version_maintenance"), &OpenCascadeVersion::get_version_maintenance);
}

godot::String OpenCascadeVersion::get_version_string() const {
    try {
        return godot::String(OCC_VERSION_STRING);
    } catch (const Standard_Failure &e) {
        ERR_PRINT(godot::vformat("OpenCascadeVersion.get_version_string failed: %s", e.what()));
        return godot::String();
    }
}

int64_t OpenCascadeVersion::get_version_major() const {
    try {
        return static_cast<int64_t>(OCC_VERSION_MAJOR);
    } catch (const Standard_Failure &e) {
        ERR_PRINT(godot::vformat("OpenCascadeVersion.get_version_major failed: %s", e.what()));
        return 0;
    }
}

int64_t OpenCascadeVersion::get_version_minor() const {
    try {
        return static_cast<int64_t>(OCC_VERSION_MINOR);
    } catch (const Standard_Failure &e) {
        ERR_PRINT(godot::vformat("OpenCascadeVersion.get_version_minor failed: %s", e.what()));
        return 0;
    }
}

int64_t OpenCascadeVersion::get_version_maintenance() const {
    try {
        return static_cast<int64_t>(OCC_VERSION_MAINTENANCE);
    } catch (const Standard_Failure &e) {
        ERR_PRINT(godot::vformat("OpenCascadeVersion.get_version_maintenance failed: %s", e.what()));
        return 0;
    }
}
