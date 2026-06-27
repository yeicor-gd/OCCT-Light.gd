# Portfile for occtl: builds OCCT-Light from the git submodule.
#
# The OCCT-Light repository lives as a submodule at <project-root>/OCCT-Light.
# From this port's location (vcpkg_ports/occtl/) the relative path to the
# submodule root is ../../OCCT-Light.

set(SOURCE_PATH "${CMAKE_CURRENT_LIST_DIR}/../../OCCT-Light")
get_filename_component(SOURCE_PATH "${SOURCE_PATH}" ABSOLUTE)

if(NOT EXISTS "${SOURCE_PATH}/CMakeLists.txt")
  message(FATAL_ERROR
    "OCCT-Light submodule not found at '${SOURCE_PATH}'. "
    "Did you run 'git submodule update --init --recursive'?")
endif()

vcpkg_cmake_configure(
  SOURCE_PATH "${SOURCE_PATH}"
  OPTIONS
    -DOCCTL_BUILD_TESTING=OFF
    -DOCCTL_BUILD_VIZ=OFF
    -DOCCTL_BUILD_BINDINGS_CSHARP=OFF
    -DOCCTL_BUILD_BINDINGS_PYTHON=OFF
    -DOCCTL_BUILD_BINDINGS_WASM=OFF
    -DOCCTL_BUILD_GEOM=ON
    -DOCCTL_BUILD_TOPO=ON
    -DOCCTL_BUILD_PRIM=ON
    -DOCCTL_BUILD_TEXT=ON
    -DOCCTL_BUILD_BOOL=ON
    -DOCCTL_BUILD_MESH=ON
    -DOCCTL_BUILD_HEAL=ON
    -DOCCTL_BUILD_IO_BREP=ON
    -DOCCTL_BUILD_IO_STEP=ON
    -DOCCTL_BUILD_IO_IGES=ON
    -DOCCTL_BUILD_IO_STL=ON
    -DOCCTL_BUILD_IO_OBJ=ON
    -DOCCTL_BUILD_IO_GLTF=ON
    -DOCCTL_BUILD_IO_VRML=ON
    -DOCCTL_BUILD_IO_PLY=ON
    -DOCCTL_BUILD_DE=ON
)

vcpkg_cmake_install()

vcpkg_cmake_config_fixup(CONFIG_PATH lib/cmake/OCCTL)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE_AGPL_30.txt")

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")
