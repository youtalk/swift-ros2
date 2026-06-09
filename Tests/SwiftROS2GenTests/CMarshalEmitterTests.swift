import Testing

@testable import SwiftROS2Gen

@Suite("CMarshalEmitter — per-type rosidl marshaller C source")
struct CMarshalEmitterTests {
    private func emit(_ rosTypeName: String) throws -> String {
        let registry = try TestIR.sensorMsgsRegistry()
        let ir = try #require(registry[rosTypeName])
        return CMarshalEmitter.emit(ir, registry: registry)
    }

    @Test("emits Imu marshaller surface")
    func emitsImu() throws {
        let c = try emit("sensor_msgs/msg/Imu")
        #expect(c.contains("#include <sensor_msgs/msg/imu.h>"))
        #expect(c.contains("int crcl_publish_imu("))
        #expect(c.contains("int crcl_serialize_imu("))
        #expect(c.contains("static int fill_imu(sensor_msgs__msg__Imu *msg"))
        #expect(c.contains("rosidl_runtime_c__String__assign(&msg->header.frame_id"))
        #expect(
            c.contains("memcpy(msg->orientation_covariance, orientation_covariance, 9 * sizeof(double))"))
        #expect(c.contains("const rosidl_message_type_support_t *crcl_typesupport_imu(void)"))
        #expect(c.contains("ROSIDL_GET_MSG_TYPE_SUPPORT(sensor_msgs, msg, Imu)"))
        // Symmetric teardown: the wrapper forwards to the rosidl __fini; call
        // sites invoke the wrapper with the stack struct's address.
        #expect(c.contains("static void fini_imu(sensor_msgs__msg__Imu *msg)"))
        #expect(c.contains("sensor_msgs__msg__Imu__fini(msg)"))
        #expect(c.contains("fini_imu(&msg)"))
    }

    @Test("emits PointCloud2 struct-sequence + byte-sequence + cleanup")
    func emitsPointCloud2() throws {
        let c = try emit("sensor_msgs/msg/PointCloud2")
        #expect(c.contains("#include <sensor_msgs/msg/point_cloud2.h>"))
        #expect(c.contains("sensor_msgs__msg__PointField__Sequence__init(&msg->fields, fields_len)"))
        #expect(c.contains("rosidl_runtime_c__String__assign(&msg->fields.data[i].name, fields_name[i]"))
        // uint8[] data -> rosidl uint8 primitive sequence.
        #expect(c.contains("rosidl_runtime_c__uint8__Sequence__init(&msg->data, data_count)"))
        #expect(c.contains("memcpy(msg->data.data, data_data, data_count * sizeof(uint8_t))"))
        // Symmetric teardown via the rosidl-generated __fini, invoked through
        // the fini_point_cloud2 wrapper.
        #expect(c.contains("static void fini_point_cloud2(sensor_msgs__msg__PointCloud2 *msg)"))
        #expect(c.contains("sensor_msgs__msg__PointCloud2__fini(msg)"))
        #expect(c.contains("fini_point_cloud2(&msg)"))
    }
}
