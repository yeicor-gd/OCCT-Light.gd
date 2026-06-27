#include "module.h" // NOLINT(misc-include-cleaner)
#include "OcctlCoreWrapper.h" // NOLINT(misc-include-cleaner)
#include <gdextension_interface.h> // NOLINT(misc-include-cleaner)
#include <godot_cpp/godot.hpp> // NOLINT(misc-include-cleaner)
#include <godot_cpp/core/class_db.hpp> // NOLINT(misc-include-cleaner)
#include <godot_cpp/core/defs.hpp> // NOLINT(misc-include-cleaner)

void gdext_initialize_module_auto(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }

    // Register wrapped classes
    GDREGISTER_CLASS(OcctlCoreWrapper);
    GDREGISTER_CLASS(OcctlRuntimeInitInfoTHandle);
    GDREGISTER_CLASS(Uint64THandle);
}

void gdext_uninitialize_module_auto(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    // Teardown logic (if any) goes here.
}

extern "C" {
    GDExtensionBool GDE_EXPORT gdext_library_init_auto(
        GDExtensionInterfaceGetProcAddress p_get_proc_address,
        GDExtensionClassLibraryPtr p_library,
        GDExtensionInitialization *r_initialization
    ) {
        const godot::GDExtensionBinding::InitObject init_obj(
            p_get_proc_address, p_library, r_initialization
        );

        init_obj.register_initializer(gdext_initialize_module_auto);
        init_obj.register_terminator(gdext_uninitialize_module_auto);
        init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

        return init_obj.init();
    }
}
