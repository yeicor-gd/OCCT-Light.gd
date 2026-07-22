include("triplets/community/wasm32-emscripten.cmake")

# CUSTOM:
set(VCPKG_CMAKE_CONFIGURE_OPTIONS ${VCPKG_CMAKE_CONFIGURE_OPTIONS}
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON  # -fPIC required for wasm32 module
)

if(EXISTS "${SOURCE_PATH}/__GDEXT_CMAKE_ARGS")
  file(READ "${SOURCE_PATH}/__GDEXT_CMAKE_ARGS" GDEXT_CMAKE_ARGS)
elseif(DEFINED ENV{GDEXT_CMAKE_ARGS})
  set(GDEXT_CMAKE_ARGS "$ENV{GDEXT_CMAKE_ARGS}")
else()
  message(FATAL_ERROR "GDEXT_CMAKE_ARGS environment variable OR ${SOURCE_PATH}/__GDEXT_CMAKE_ARGS file not set.")
endif()
separate_arguments(GDEXT_CMAKE_ARGS UNIX_COMMAND "${GDEXT_CMAKE_ARGS}")

# Make detection more flexible: match -DGODOTCPP_THREADS=on or -DGODOTCPP_THREADS=ON or -DGODOTCPP_THREADS:on, etc.
set(_threads_enabled OFF)
foreach(_arg IN LISTS GDEXT_CMAKE_ARGS)
  if(_arg MATCHES "^-DGODOTCPP_THREADS[:=](on|ON|1|true|TRUE)$")
    set(_threads_enabled ON)
    break()
  endif()
endforeach()

# Collect extra C/CXX flags. Use a single -DCMAKE_CXX_FLAGS / -DCMAKE_C_FLAGS
# so that later entries don't silently overwrite earlier ones.
set(_extra_cxx_flags "")
set(_extra_c_flags "")

if(_threads_enabled)
  set(_extra_cxx_flags "${_extra_cxx_flags} -matomics -mbulk-memory")  # Required for threads support in wasm32
  set(_extra_c_flags "${_extra_c_flags} -matomics -mbulk-memory")
endif()

# Keep -fexceptions so OCCT try/catch syntax compiles, but disable C++
# exception handling at the LLVM backend level.  Any throw becomes an
# unreachable trap (abort).  This avoids importing __cpp_exception Tag or
# emscripten_longjmp — neither is available in a SIDE_MODULE linked against
# Godot's main module (see godotengine/godot#104835).
# NOTE: This flag only affects vcpkg packages (opencascade, occtl), NOT the
# gdext package — the gdext portfile overrides CMAKE_CXX_FLAGS to strip it,
# because godot-cpp's -sSUPPORT_LONGJMP=wasm conflicts with this LLVM flag.
set(_extra_cxx_flags "${_extra_cxx_flags} -fexceptions -mllvm -enable-emscripten-cxx-exceptions=0")

set(VCPKG_CMAKE_CONFIGURE_OPTIONS ${VCPKG_CMAKE_CONFIGURE_OPTIONS}
  "-DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS} ${_extra_cxx_flags}"
  "-DCMAKE_C_FLAGS=${CMAKE_C_FLAGS} ${_extra_c_flags}"
)
