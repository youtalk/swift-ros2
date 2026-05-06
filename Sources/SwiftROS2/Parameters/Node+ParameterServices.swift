// Phase 3 of the Parameter API: bind the six rcl_interfaces parameter
// service handlers on a node's fully-qualified name. Handlers route
// through the existing per-node ParameterStore created in phase 2.

import SwiftROS2Messages

extension ROS2Node {
    /// Register the six standard parameter services on
    /// `<fullyQualifiedName>/<service>`.
    ///
    /// `ROS2Context.createNode(...)` calls this automatically when
    /// `ROS2NodeOptions.startParameterServices` is `true` (the default).
    /// Calling it manually after opting out is supported. A repeated call
    /// is a no-op.
    public func startParameterServices() async throws {
        guard await parameterStore.markServicesStarted() else { return }

        let store = parameterStore  // captured by handler closures (actor → Sendable)
        let fqn = fullyQualifiedName

        _ = try await createService(
            GetParametersSrv.self,
            name: "\(fqn)/get_parameters",
            qos: .servicesDefault
        ) { req in
            await Self.handleGetParameters(req, store: store)
        }

        _ = try await createService(
            SetParametersSrv.self,
            name: "\(fqn)/set_parameters",
            qos: .servicesDefault
        ) { req in
            await Self.handleSetParameters(req, store: store)
        }

        _ = try await createService(
            SetParametersAtomicallySrv.self,
            name: "\(fqn)/set_parameters_atomically",
            qos: .servicesDefault
        ) { req in
            await Self.handleSetParametersAtomically(req, store: store)
        }

        _ = try await createService(
            ListParametersSrv.self,
            name: "\(fqn)/list_parameters",
            qos: .servicesDefault
        ) { req in
            await Self.handleListParameters(req, store: store)
        }

        _ = try await createService(
            DescribeParametersSrv.self,
            name: "\(fqn)/describe_parameters",
            qos: .servicesDefault
        ) { req in
            await Self.handleDescribeParameters(req, store: store)
        }

        _ = try await createService(
            GetParameterTypesSrv.self,
            name: "\(fqn)/get_parameter_types",
            qos: .servicesDefault
        ) { req in
            await Self.handleGetParameterTypes(req, store: store)
        }
    }

    // MARK: - Handler stubs (filled in tasks 4–9)
    //
    // Each handler is a `static` async function so it doesn't capture `self`
    // implicitly — only the Sendable `ParameterStore` actor crosses the
    // closure boundary, which keeps the @Sendable handler closure clean.

    static func handleGetParameters(
        _ request: GetParametersRequest, store: ParameterStore
    ) async -> GetParametersResponse {
        var values: [SwiftROS2Messages.ParameterValue] = []
        values.reserveCapacity(request.names.count)
        for name in request.names {
            let entry = await store.entry(name: name)
            let swiftValue = entry?.value ?? .notSet
            values.append(swiftValue.toWire())
        }
        return GetParametersResponse(values: values)
    }

    static func handleSetParameters(
        _ request: SetParametersRequest, store: ParameterStore
    ) async -> SetParametersResponse {
        var results: [SwiftROS2Messages.SetParametersResult] = []
        results.reserveCapacity(request.parameters.count)
        for wireParam in request.parameters {
            let swiftParam = ROS2Parameter(wire: wireParam)
            let r = await store.set(swiftParam)
            results.append(
                SwiftROS2Messages.SetParametersResult(
                    successful: r.successful, reason: r.reason))
        }
        return SetParametersResponse(results: results)
    }

    static func handleSetParametersAtomically(
        _ request: SetParametersAtomicallyRequest, store: ParameterStore
    ) async -> SetParametersAtomicallyResponse {
        let swiftParams = request.parameters.map { ROS2Parameter(wire: $0) }
        let r = await store.setAtomically(swiftParams)
        return SetParametersAtomicallyResponse(
            result: SwiftROS2Messages.SetParametersResult(
                successful: r.successful, reason: r.reason))
    }

    static func handleListParameters(
        _ request: ListParametersRequest, store: ParameterStore
    ) async -> ListParametersResponse {
        let r = await store.list(prefixes: request.prefixes, depth: request.depth)
        return ListParametersResponse(
            result: SwiftROS2Messages.ListParametersResult(
                names: r.names, prefixes: r.prefixes))
    }

    static func handleDescribeParameters(
        _ request: DescribeParametersRequest, store: ParameterStore
    ) async -> DescribeParametersResponse {
        var out: [SwiftROS2Messages.ParameterDescriptor] = []
        out.reserveCapacity(request.names.count)
        for name in request.names {
            if let entry = await store.entry(name: name) {
                out.append(entry.descriptor.toWire())
            } else {
                // rclcpp returns a descriptor whose name echoes the request and
                // whose type slot is PARAMETER_NOT_SET. Mirror that.
                var stub = SwiftROS2Messages.ParameterDescriptor()
                stub.name = name
                stub.type = 0
                out.append(stub)
            }
        }
        return DescribeParametersResponse(descriptors: out)
    }

    static func handleGetParameterTypes(
        _ request: GetParameterTypesRequest, store: ParameterStore
    ) async -> GetParameterTypesResponse {
        var types: [UInt8] = []
        types.reserveCapacity(request.names.count)
        for name in request.names {
            let entry = await store.entry(name: name)
            types.append(entry?.descriptor.type.rawValue ?? 0)
        }
        return GetParameterTypesResponse(types: types)
    }
}
