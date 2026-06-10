# Hand-assembled stand-in for the ament zenoh_cpp_vendor package.
# The real package is an ament_vendor wrapper whose only consumer-visible
# effect is `ament_export_dependencies(zenohc zenohcxx)`; replicate that by
# forwarding to the hand-assembled zenohc / zenohcxx configs.

include(CMakeFindDependencyMacro)
find_dependency(zenohc)
find_dependency(zenohcxx)

set(zenoh_cpp_vendor_FOUND TRUE)
