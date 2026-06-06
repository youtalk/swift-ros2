#include <stdio.h>
#include <rcl/rcl.h>

int main(void) {
  rcl_init_options_t opts = rcl_get_zero_initialized_init_options();
  rcl_allocator_t alloc = rcl_get_default_allocator();
  if (rcl_init_options_init(&opts, alloc) != RCL_RET_OK) { printf("init_options FAIL\n"); return 1; }

  rcl_context_t ctx = rcl_get_zero_initialized_context();
  if (rcl_init(0, NULL, &opts, &ctx) != RCL_RET_OK) { printf("rcl_init FAIL\n"); return 1; }

  rcl_node_t node = rcl_get_zero_initialized_node();
  rcl_node_options_t nopts = rcl_node_get_default_options();
  if (rcl_node_init(&node, "rcl_smoke", "/swift_ros2", &ctx, &nopts) != RCL_RET_OK) {
    printf("node_init FAIL\n"); return 1;
  }
  printf("rcl_smoke OK: context+node initialized\n");

  rcl_node_fini(&node);
  rcl_shutdown(&ctx);
  rcl_context_fini(&ctx);
  return 0;
}
