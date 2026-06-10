# Hand-assembled zenohc package config for the M9 Apple spike.
# Mirrors the zenohc::static / zenohc::lib targets that zenoh-c's
# install/PackageConfig.cmake.in would generate for a static,
# no-shared-memory build (BUILD_SHARED_LIBS=OFF).

set(ZENOHC_BUILD_WITH_UNSTABLE_API TRUE)
set(ZENOHC_BUILD_WITH_SHARED_MEMORY FALSE)

get_filename_component(_zenohc_prefix "${CMAKE_CURRENT_LIST_FILE}" PATH)
get_filename_component(_zenohc_prefix "${_zenohc_prefix}" PATH)
get_filename_component(_zenohc_prefix "${_zenohc_prefix}" PATH)
get_filename_component(_zenohc_prefix "${_zenohc_prefix}" PATH)

if(NOT TARGET __zenohc_static)
    add_library(__zenohc_static STATIC IMPORTED GLOBAL)
    add_library(zenohc::static ALIAS __zenohc_static)
    # Frameworks the Rust staticlib needs at final link on Apple platforms.
    target_link_libraries(__zenohc_static INTERFACE
        "-framework Security" "-framework SystemConfiguration" "-framework CoreFoundation" "-framework IOKit")
    set_target_properties(__zenohc_static PROPERTIES
        IMPORTED_LOCATION "${_zenohc_prefix}/lib/libzenohc.a"
        INTERFACE_INCLUDE_DIRECTORIES "${_zenohc_prefix}/include"
    )
endif()

if(NOT TARGET zenohc::lib)
    add_library(zenohc::lib ALIAS __zenohc_static)
endif()

set(zenohc_FOUND TRUE)
