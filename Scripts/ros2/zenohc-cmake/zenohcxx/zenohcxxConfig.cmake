# Hand-assembled zenohcxx package config for the M9 Apple spike.
# Mirrors zenoh-cpp's install/PackageConfig.cmake.in: an INTERFACE target
# zenohcxx::zenohc wrapping the header-only C++ API over zenohc::lib.

include(CMakeFindDependencyMacro)
find_dependency(zenohc)

get_filename_component(_zenohcxx_prefix "${CMAKE_CURRENT_LIST_FILE}" PATH)
get_filename_component(_zenohcxx_prefix "${_zenohcxx_prefix}" PATH)
get_filename_component(_zenohcxx_prefix "${_zenohcxx_prefix}" PATH)
get_filename_component(_zenohcxx_prefix "${_zenohcxx_prefix}" PATH)

if(NOT TARGET zenohcxx)
    add_library(zenohcxx INTERFACE IMPORTED)
    target_include_directories(zenohcxx INTERFACE "${_zenohcxx_prefix}/include")
endif()

if(TARGET zenohc::lib AND NOT TARGET zenohcxx_zenohc)
    add_library(zenohcxx_zenohc INTERFACE IMPORTED)
    target_compile_definitions(zenohcxx_zenohc INTERFACE ZENOHCXX_ZENOHC)
    target_include_directories(zenohcxx_zenohc INTERFACE "${_zenohcxx_prefix}/include")
    target_link_libraries(zenohcxx_zenohc INTERFACE zenohc::lib)
    add_library(zenohcxx::zenohc ALIAS zenohcxx_zenohc)
endif()

set(zenohcxx_FOUND TRUE)
