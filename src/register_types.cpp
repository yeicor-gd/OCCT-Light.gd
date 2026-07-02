// register_types.cpp - Entry point for OCCT-Light.gd GDExtension
// This file bridges the autowrapper-generated bindings with the OCCT
// messenger workaround needed at startup.

#include "register_types.h"

// Autowrapper-generated module registration
#include "autowrapper/module.h"

// OCCT-Light core runtime
#include <occtl/occtl_core.h>

#if defined(_MSC_VER)
#include <crtdbg.h>
#endif

// OCCT fix: Godot destroys std::cout before OCCT's static destructors run
// during exit(). When Message_PrinterOStream::~Message_PrinterOStream calls
// Close(), it tries to flush the already-destroyed stream and crashes.
// Nullify the private myStream pointer so Close() returns immediately.
#include <Message.hxx>
#include <Message_Messenger.hxx>
#include <Message_PrinterOStream.hxx>

static void clear_messenger_printers() {
    const Handle(Message_Messenger)& messenger = Message::DefaultMessenger();
    if (messenger.IsNull()) {
        return;
    }

    const auto& printers = messenger->Printers();
    size_t n_printers = static_cast<size_t>(printers.Size());
    for (size_t i = 1; i <= n_printers; i++) {
        Handle(Message_PrinterOStream) osp =
            Handle(Message_PrinterOStream)::DownCast(printers.Value(i));
        if (!osp.IsNull()) {
            // Nullify the private myStream field at known offset so that
            // Close() (which calls myStream->flush()) becomes a no-op.
            // Layout on 64-bit Linux:
            //   Standard_Transient: vtable(8) + refcount(4)
            //   Message_Printer:    myTraceLevel(4)
            //   Message_PrinterOStream: myStream(8) + myIsFile(1) + myToColorize(1)
            // myStream is at offset 8+4+4 = 16 bytes from the object start.
            *reinterpret_cast<void**>(reinterpret_cast<char*>(osp.get()) + 16) = nullptr;
        }
    }

    messenger->ChangePrinters().Clear();
}

static bool occtl_runtime_was_shutdown = false;

static void occtl_runtime_shutdown_once() {
    if (!occtl_runtime_was_shutdown) {
        occtl_runtime_was_shutdown = true;
        // Clear messenger printers first to prevent crashes during exit()
        // that occur when OCCT's static destructors try to flush std::cout
        // after Godot has already destroyed it.
        clear_messenger_printers();
        ::occtl_runtime_shutdown();
    }
}

static void occtl_light_gd_initialize(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }

#if !defined(NDEBUG)
    // Enable OCCT stack traces for Standard_Failure exceptions in debug
    // builds. The default stack trace length is 0 (no stack trace), we set
    // it to 32 for debugging context.
    Standard_Failure::SetDefaultStackTraceLength(32);
#endif

#if defined(_MSC_VER)
    // Suppress CRT assert dialog on Windows so the headless test runner won't
    // hang waiting for user interaction when OCCT's Standard_ASSERT fires
    // (e.g. BRepTools_History rejecting unsupported shape types in debug).
    // Route assertions to stderr (visible in console) and debugger output.
    _CrtSetReportMode(_CRT_ASSERT, _CRTDBG_MODE_FILE | _CRTDBG_MODE_DEBUG);
    _CrtSetReportFile(_CRT_ASSERT, _CRTDBG_FILE_STDERR);
#endif

    // Register autowrapper-generated classes
    gdext_initialize_module_auto(p_level);

    // Register an atexit handler as a safety net: if Godot calls exit()
    // directly (bypassing GDExtension uninitialize), this ensures OCCT's
    // messenger printers are nullified before C++ static destructors run.
    // The guard flag prevents double-shutdown if uninitialize runs first.
    std::atexit(occtl_runtime_shutdown_once);
}

static void occtl_light_gd_uninitialize(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    gdext_uninitialize_module_auto(p_level);

    // Shut down the OCCT-Light runtime. Messenger printers are cleared
    // inside occtl_runtime_shutdown_once() to prevent the crash when
    // Godot destroys std::cout before OCCT's static destructors run.
    //
    // We call shutdown here (rather than in GDScript tests) because
    // Godot frees scene objects first, then calls GDExtension
    // uninitialize. If runtime_shutdown were called from GDScript,
    // remaining graph-handle destructors would access freed OCCT data.
    occtl_runtime_shutdown_once();
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
