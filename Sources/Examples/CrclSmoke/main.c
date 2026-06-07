#include <stdio.h>
#include "rcl_bridge.h"

int main(void) {
    // Smoke exits on first failure; the process teardown reclaims resources,
    // so error paths intentionally skip explicit destroy calls.
    crcl_context_t *ctx = crcl_context_create(0);
    if (!ctx) { printf("context FAIL: %s\n", crcl_last_error()); return 1; }

    crcl_node_t *node = crcl_node_create(ctx, "crcl_smoke", "/swift_ros2");
    if (!node) { printf("node FAIL: %s\n", crcl_last_error()); return 1; }

    crcl_qos_t qos = {.reliability = 1, .durability = 0, .history = 0, .depth = 10};
    crcl_publisher_t *pub = crcl_publisher_create(node, "sensor_msgs/msg/Imu", "/imu", qos);
    if (!pub) { printf("publisher FAIL: %s\n", crcl_last_error()); return 1; }

    uint8_t cdr[8] = {0x00, 0x01, 0x00, 0x00, 0, 0, 0, 0};
    int rc = crcl_publish_serialized(pub, cdr, sizeof(cdr));
    if (rc != 0) { printf("publish FAIL (%d): %s\n", rc, crcl_last_error()); return 1; }

    crcl_publisher_destroy(pub);
    crcl_node_destroy(node);
    crcl_context_destroy(ctx);
    printf("crcl_smoke OK: publish path exercised\n");
    return 0;
}
