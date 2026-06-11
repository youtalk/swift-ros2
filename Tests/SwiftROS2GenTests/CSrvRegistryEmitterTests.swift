import Testing

@testable import SwiftROS2Gen

@Suite("CSrvRegistryEmitter — generated RCL service typesupport registry")
struct CSrvRegistryEmitterTests {
    private let services: [CSrvRegistryEmitter.ServiceRef] = [
        .init(package: "std_srvs", typeName: "SetBool"),
        .init(package: "example_interfaces", typeName: "AddTwoInts"),
    ]

    @Test("emits the per-service typesupport + create/destroy wrapper surface")
    func emitsWrapperSurface() throws {
        let c = CSrvRegistryEmitter.emit(services)
        // rosidl umbrella include (snake_case file name).
        #expect(c.contains("#include <std_srvs/srv/set_bool.h>"))
        #expect(c.contains("#include <example_interfaces/srv/add_two_ints.h>"))
        // Service typesupport via the documented macro.
        #expect(c.contains("ROSIDL_GET_SRV_TYPE_SUPPORT(std_srvs, srv, SetBool)"))
        // Request / response MESSAGE typesupports — note the `srv` subfolder.
        #expect(c.contains("ROSIDL_GET_MSG_TYPE_SUPPORT(std_srvs, srv, SetBool_Request)"))
        #expect(c.contains("ROSIDL_GET_MSG_TYPE_SUPPORT(std_srvs, srv, SetBool_Response)"))
        // rosidl __create / __destroy wrappers with the typed cast.
        #expect(c.contains("return std_srvs__srv__SetBool_Request__create();"))
        #expect(
            c.contains(
                "std_srvs__srv__SetBool_Request__destroy((std_srvs__srv__SetBool_Request *)request);"))
        #expect(c.contains("return std_srvs__srv__SetBool_Response__create();"))
        #expect(
            c.contains(
                "std_srvs__srv__SetBool_Response__destroy((std_srvs__srv__SetBool_Response *)response);"))
        // Lookup over the canonical "pkg/srv/Type" key.
        #expect(c.contains(".name = \"std_srvs/srv/SetBool\","))
        #expect(c.contains("const crcl_srv_entry_t *crcl_srv_registry_lookup(const char *srv_type_name)"))
        // Table size is pinned to the generated header's count macro.
        #expect(c.contains("_Static_assert("))
        #expect(c.contains("CRCL_SRV_REGISTRY_ENTRY_COUNT"))
    }

    @Test("emits the count + key list header")
    func emitsHeader() throws {
        let h = CSrvRegistryEmitter.emitHeader(services)
        #expect(h.contains("#define CRCL_SRV_REGISTRY_ENTRY_COUNT 2"))
        #expect(h.contains("//   example_interfaces/srv/AddTwoInts"))
        #expect(h.contains("//   std_srvs/srv/SetBool"))
    }

    @Test("entries are sorted by canonical name regardless of input order")
    func sortsDeterministically() throws {
        let reversed = CSrvRegistryEmitter.emit(services.reversed())
        #expect(reversed == CSrvRegistryEmitter.emit(services))
        let addTwoInts = try #require(
            reversed.range(of: ".name = \"example_interfaces/srv/AddTwoInts\""))
        let setBool = try #require(reversed.range(of: ".name = \"std_srvs/srv/SetBool\""))
        #expect(addTwoInts.lowerBound < setBool.lowerBound)
    }
}
