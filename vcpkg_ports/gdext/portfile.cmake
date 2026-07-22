# Portfile for the Godot extension of this project
# ABI change to force rebuild

# The dependencies are specified in vcpkg.json

set(SOURCE_PATH "${CMAKE_CURRENT_LIST_DIR}/../../")

if(EXISTS "${SOURCE_PATH}/__GDEXT_CMAKE_ARGS")
    file(READ "${SOURCE_PATH}/__GDEXT_CMAKE_ARGS" GDEXT_CMAKE_ARGS)
elseif(DEFINED ENV{GDEXT_CMAKE_ARGS})
    set(GDEXT_CMAKE_ARGS "$ENV{GDEXT_CMAKE_ARGS}")
else()
    message(FATAL_ERROR "GDEXT_CMAKE_ARGS environment variable OR ${SOURCE_PATH}/__GDEXT_CMAKE_ARGS file not set.")
endif()
separate_arguments(GDEXT_CMAKE_ARGS UNIX_COMMAND "${GDEXT_CMAKE_ARGS}")

# On Emscripten, use -fexceptions so try/catch syntax compiles (the
# autowrapper catches Standard_Failure), but disable C++ exception handling
# at the LLVM backend level with -mllvm -enable-emscripten-cxx-exceptions=0.
# This prevents the SIDE_MODULE from importing emscripten_longjmp, which
# Godot's main module does not export (see godotengine/godot#104835).
# -sSUPPORT_LONGJMP=wasm is stripped from godot-cpp in CMakeLists.txt so
# there is no conflict with this LLVM flag.
if(VCPKG_TARGET_TRIPLET MATCHES "emscripten")
    set(_gdext_cxx_flags "-fexceptions -mllvm -enable-emscripten-cxx-exceptions=0")
    foreach(_arg IN LISTS GDEXT_CMAKE_ARGS)
        if(_arg MATCHES "^-DGODOTCPP_THREADS[:=](on|ON|1|true|TRUE)$")
            string(APPEND _gdext_cxx_flags " -matomics -mbulk-memory")
            break()
        endif()
    endforeach()
    vcpkg_configure_cmake(
        SOURCE_PATH "${SOURCE_PATH}"
        OPTIONS ${GDEXT_CMAKE_ARGS}
            "-DCMAKE_CXX_FLAGS=${_gdext_cxx_flags}"
        MAYBE_UNUSED_VARIABLES GODOTCPP_PRECISION GODOTCPP_THREADS
    )
else()
    vcpkg_configure_cmake(
        SOURCE_PATH "${SOURCE_PATH}"
        OPTIONS ${GDEXT_CMAKE_ARGS}
        MAYBE_UNUSED_VARIABLES GODOTCPP_PRECISION GODOTCPP_THREADS
    )
endif()

vcpkg_build_cmake(TARGET install)

set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
