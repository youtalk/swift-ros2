import Testing

@testable import SwiftROS2Gen

@Suite("MarshalFlattener — IR → flat C params")
struct MarshalFlattenerTests {
    private func flatten(_ rosTypeName: String) throws -> [FlatParam] {
        let registry = try TestIR.sensorMsgsRegistry()
        let ir = try #require(registry[rosTypeName])
        return MarshalFlattener.flatten(ir, registry: registry)
    }

    @Test("flattens Imu nested Header + scalars + fixed array")
    func flattensImu() throws {
        let params = try flatten("sensor_msgs/msg/Imu")
        let names = params.map(\.paramName)

        // Header flattens to scalar stamp fields + heap frame_id, in order.
        #expect(Array(names.prefix(3)) == ["header_stamp_sec", "header_stamp_nanosec", "header_frame_id"])

        let frameId = try #require(params.first { $0.paramName == "header_frame_id" })
        #expect(frameId.kind == .heapString)
        #expect(frameId.cParamDecl == "const char *header_frame_id")
        #expect(frameId.cStructPath == "msg->header.frame_id")
        #expect(frameId.swiftValuePath == "header.frameId")

        let orientationX = try #require(params.first { $0.paramName == "orientation_x" })
        #expect(orientationX.kind == .scalar)
        #expect(orientationX.cParamDecl == "double orientation_x")
        #expect(orientationX.cStructPath == "msg->orientation.x")
        #expect(orientationX.swiftValuePath == "orientation.x")

        let covariance = try #require(params.first { $0.paramName == "orientation_covariance" })
        #expect(covariance.kind == .fixedArray(elementC: "double", length: 9))
        #expect(covariance.cParamDecl == "const double *orientation_covariance")
    }

    @Test("flattens Joy scalar sequence")
    func flattensJoy() throws {
        let params = try flatten("sensor_msgs/msg/Joy")
        let axes = try #require(params.first { $0.paramName == "axes" })
        #expect(axes.kind == .scalarSequence(elementC: "float"))
        #expect(axes.cParamDecl == "const float *axes_data, size_t axes_count")
    }

    @Test("flattens PointCloud2 struct sequence (struct-of-arrays)")
    func flattensPointCloud2() throws {
        let params = try flatten("sensor_msgs/msg/PointCloud2")
        let fields = try #require(params.first { $0.paramName == "fields" })

        guard case .structSequence(let elementType, let members) = fields.kind else {
            Issue.record("fields kind is not a structSequence: \(fields.kind)")
            return
        }
        #expect(elementType == "sensor_msgs__msg__PointField")
        #expect(
            members.map(\.paramName) == ["fields_name", "fields_offset", "fields_datatype", "fields_count"])
        #expect(
            fields.cParamDecl
                == "const char *const *fields_name, const uint32_t *fields_offset, "
                + "const uint8_t *fields_datatype, const uint32_t *fields_count, size_t fields_len")
    }
}
