// register_types.cpp - Entry point for OCCT-Light.gd GDExtension
// This file bridges the autowrapper-generated bindings with the OCCT
// messenger workaround needed at startup.

#include "register_types.h"

// Autowrapper-generated module registration
#include "autowrapper/module.h"

static void occtl_light_gd_initialize(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }

    // Register autowrapper-generated classes
    gdext_initialize_module_auto(p_level);
}

static void occtl_light_gd_uninitialize(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    gdext_uninitialize_module_auto(p_level);
}

extern "C" {
GDExtensionBool GDE_EXPORT gdext_library_init(
    GDExtensionInterfaceGetProcAddress p_get_proc_address,
    GDExtensionClassLibraryPtr p_library,
    GDExtensionInitialization *r_initialization
) {
    const godot::GDExtensionBinding::InitObject init_obj(
        p_get_proc_address, p_library, r_initialization
    );

    init_obj.register_initializer(occtl_light_gd_initialize);
    init_obj.register_terminator(occtl_light_gd_uninitialize);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

    return init_obj.init();
}
}
