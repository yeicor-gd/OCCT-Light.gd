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

# On Emscripten the triplet adds -mllvm -enable-emscripten-cxx-exceptions=0 to
# CMAKE_CXX_FLAGS for OCCT/OCCTL, but godot-cpp (built as a subdirectory of
# this package) adds -sSUPPORT_LONGJMP=wasm which conflicts with that LLVM
# flag.  Override CMAKE_CXX_FLAGS here so only the godot-cpp-compatible flags
# remain.  Use -fexceptions (not -fno-exceptions): the GDExtension autowrapper
# generates try/catch blocks catching Standard_Failure.
if(VCPKG_TARGET_TRIPLET MATCHES "emscripten")
    set(_gdext_cxx_flags "-fexceptions")
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
