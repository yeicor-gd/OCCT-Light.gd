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

if(_threads_enabled)
  set(VCPKG_CMAKE_CONFIGURE_OPTIONS ${VCPKG_CMAKE_CONFIGURE_OPTIONS}
    "-DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS} -matomics -mbulk-memory"  # Required for threads support in wasm32
    "-DCMAKE_C_FLAGS=${CMAKE_C_FLAGS} -matomics -mbulk-memory"  # Required for threads support in wasm32
  )
endif()
