//
// ZenohClient.swift
// Swift wrapper for zenoh-pico C-FFI bridge, the default ZenohClientProtocol implementation
//
// Provides a Swift-friendly API for Zenoh operations with proper error handling,
// resource management, and type safety. Conforms to ZenohClientProtocol so that
// SwiftROS2Transport can drive the session without a C dependency.
//

import CZenohBridge
import Foundation
import SwiftROS2Transport

#if canImport(os.log)
    import os.log
#else
    /// Minimal shim so the os.log call sites compile on Linux. Logs are
    /// discarded — debug output on Linux is currently the C-layer fprintf.
    public struct Logger {
        public init(subsystem: String, category: String) {}
        public func info(_ message: @autoclosure () -> String) {}
        public func error(_ message: @autoclosure () -> String) {}
        public func debug(_ message: @autoclosure () -> String) {}
        public func warning(_ message: @autoclosure () -> String) {}
    }
#endif

// MARK: - Declared Key Expression

/// Represents a declared key expression for efficient reuse
public class DeclaredKeyExpr {
    private var handle: OpaquePointer?
    private weak var session: ZenohClient?

    fileprivate init(handle: OpaquePointer, session: ZenohClient) {
        self.handle = handle
        self.session = session
    }

    fileprivate var opaqueHandle: OpaquePointer? {
        return handle
    }

    deinit {
        // Undeclare keyexpr on deallocation
        if let h = handle, let sess = session, let sessionHandle = sess.sessionHandle {
            var mutableHandle: OpaquePointer? = h
            _ = zenoh_undeclare_keyexpr(sessionHandle, &mutableHandle)
            handle = nil
        }
    }
}

// MARK: - Subscriber

/// Represents an active subscription
public class ZenohSubscriber {
    private var handle: OpaquePointer?
    private weak var session: ZenohClient?
    private var handler: (ZenohSample) -> Void
    private var contextBox: Unmanaged<SubscriberContext>?

    fileprivate init(
        handle: OpaquePointer,
        session: ZenohClient,
        handler: @escaping (ZenohSample) -> Void,
        contextBox: Unmanaged<SubscriberContext>
    ) {
        self.handle = handle
        self.session = session
        self.handler = handler
        self.contextBox = contextBox
    }

    /// Closes the subscription
    public func close() throws {
        guard let h = handle else {
            throw ZenohError.internalError("Subscriber already closed")
        }

        // Release Swift-side resources regardless of the C-side outcome so a
        // failed undeclare does not leak the retained context or leave the
        // handle pointing at freed state for a subsequent close() attempt.
        defer {
            handle = nil
            contextBox?.release()
            contextBox = nil
        }

        guard let sess = session, let sessionHandle = sess.sessionHandle else {
            throw ZenohError.internalError("Session is no longer valid")
        }

        var mutableHandle: OpaquePointer? = h
        let result = zenoh_undeclare_subscriber(sessionHandle, &mutableHandle)

        if result < 0 {
            throw ZenohError.unsubscribeFailed("Error code: \(result)")
        }
    }

    deinit {
        // Try to close on deallocation
        try? close()
    }
}

// MARK: - Liveliness Token

/// Represents an active liveliness token for ROS 2 discovery
public class LivelinessToken {
    private var handle: OpaquePointer?
    private weak var session: ZenohClient?

    fileprivate init(handle: OpaquePointer, session: ZenohClient) {
        self.handle = handle
        self.session = session
    }

    /// Closes the liveliness token
    public func close() throws {
        guard let h = handle else {
            throw ZenohError.internalError("Liveliness token already closed")
        }

        guard let sess = session, let sessionHandle = sess.sessionHandle else {
            throw ZenohError.internalError("Session is no longer valid")
        }

        var mutableHandle: OpaquePointer? = h
        let result = zenoh_undeclare_liveliness_token(sessionHandle, &mutableHandle)

        if result < 0 {
            throw ZenohError.internalError("Failed to undeclare liveliness token: error code \(result)")
        }

        handle = nil
    }

    deinit {
        // Try to close on deallocation
        try? close()
    }
}

// MARK: - Zenoh Client

/// Default `ZenohClientProtocol` implementation backed by zenoh-pico via `CZenohBridge`.
/// Runs on every platform the package supports (iOS, iPadOS, macOS, Mac Catalyst,
/// visionOS, and Linux — the Linux build swaps in a no-op `Logger` shim for `os.log`).
/// Manages a Zenoh session and provides methods for publishing and subscribing.
///
/// Thread-safety: `ZenohClient` is NOT safe for concurrent calls to `open` / `close` /
/// `put` / `subscribe` across multiple threads. Callers must serialize these calls themselves
/// (e.g., via `ZenohTransportSession` or an actor). The internal `resourceLock` only protects
/// the tracked-resource arrays, not the `session` pointer itself.
public class ZenohClient: ZenohClientProtocol {
    private let log = Logger(subsystem: "com.youtalk.swift-ros2", category: "Zenoh")

    private var session: OpaquePointer?
    private var declaredKeyExprs: [DeclaredKeyExpr] = []
    private var subscribers: [ZenohSubscriber] = []
    private var livelinessTokens: [LivelinessToken] = []
    private let resourceLock = NSLock()

    // Internal access for nested types
    fileprivate var sessionHandle: OpaquePointer? {
        return session
    }

    /// Initializes the Zenoh client (session not yet opened)
    public init() {
        // Empty init - call open() to connect
    }

    // MARK: - Session Management

    /// Opens a Zenoh session
    /// - Parameter locator: Connection string (e.g., "tcp/127.0.0.1:7447")
    /// - Throws: ZenohError if the session cannot be opened
    public func open(locator: String) throws {
        guard session == nil else {
            throw ZenohError.sessionCreationFailed("Session already open")
        }

        log.debug("Opening session with locator: \(locator)")

        var sessionPtr: OpaquePointer?
        let result = locator.withCString { locatorPtr in
            return zenoh_open_session(locatorPtr, &sessionPtr)
        }

        if result < 0 || sessionPtr == nil {
            log.error("Session creation failed with code \(result)")
            throw ZenohError.sessionCreationFailed(
                "Connection failed (error code: \(result)). Please verify:\n"
                    + "• Router address and port\n"
                    + "• Network connectivity\n"
                    + "• Local Network permission is enabled in Settings"
            )
        }

        log.info("Session opened successfully")
        session = sessionPtr
    }

    /// Closes the Zenoh session and cleans up all resources
    /// - Throws: ZenohError if the session cannot be closed
    public func close() throws {
        guard let sess = session else {
            throw ZenohError.sessionCloseFailed("Session not open")
        }

        // Copy resources under lock, then close/release outside lock so that
        // DeclaredKeyExpr / ZenohSubscriber / LivelinessToken deinits — which
        // call back into zenoh_undeclare_* — do not run while we hold
        // resourceLock. `keyExprsToRelease` keeps the declared-keyexpr refs
        // alive across the unlock so their deinits fire when it goes out of
        // scope at the end of this method.
        let tokensToClose: [LivelinessToken]
        let subscribersToClose: [ZenohSubscriber]
        let keyExprsToRelease: [DeclaredKeyExpr]
        resourceLock.lock()
        tokensToClose = livelinessTokens
        subscribersToClose = subscribers
        keyExprsToRelease = declaredKeyExprs
        livelinessTokens.removeAll()
        subscribers.removeAll()
        declaredKeyExprs.removeAll()
        resourceLock.unlock()

        // Clean up liveliness tokens
        for token in tokensToClose {
            try? token.close()
        }

        // Clean up subscribers
        for subscriber in subscribersToClose {
            try? subscriber.close()
        }

        // keyExprsToRelease is intentionally kept alive until method exit.
        _ = keyExprsToRelease

        // Close the session
        var mutableSess: OpaquePointer? = sess
        let result = zenoh_close_session(&mutableSess)

        if result < 0 {
            throw ZenohError.sessionCloseFailed("Error code: \(result)")
        }

        session = nil
    }

    /// Gets the Zenoh session ID as a hex string
    /// - Returns: The session ID (32 hex characters)
    /// - Throws: ZenohError if the session is not open or if getting the ID fails
    public func getSessionId() throws -> String {
        guard let sess = session else {
            throw ZenohError.internalError("Session not open")
        }

        var buffer = [CChar](repeating: 0, count: 33)  // 32 hex chars + null terminator
        let result = zenoh_get_session_id(sess, &buffer, 33)

        if result < 0 {
            throw ZenohError.internalError("Failed to get session ID: error code \(result)")
        }

        return String(cString: buffer)
    }

    /// Checks if the Zenoh session is healthy and can safely publish.
    /// This performs a lightweight health check to detect stale sessions
    /// after sleep/wake cycles.
    /// - Returns: true if session is healthy, false if stale or not connected
    public func isSessionHealthy() -> Bool {
        guard let sess = session else {
            return false
        }
        return zenoh_is_session_healthy(sess)
    }

    // MARK: - Key Expression Management

    /// Declares a key expression for efficient reuse
    /// - Parameter keyExpr: The key expression string to declare
    /// - Returns: A handle conforming to ZenohKeyExprHandle
    /// - Throws: ZenohError if declaration fails
    public func declareKeyExpr(_ keyExpr: String) throws -> any ZenohKeyExprHandle {
        guard let sess = session else {
            throw ZenohError.keyExprDeclarationFailed("Session not open")
        }

        var keyExprPtr: OpaquePointer?
        let result = keyExpr.withCString { keyExprCStr in
            zenoh_declare_keyexpr(sess, keyExprCStr, &keyExprPtr)
        }

        guard result >= 0, let keyExprHandle = keyExprPtr else {
            throw ZenohError.keyExprDeclarationFailed("Error code: \(result)")
        }

        let declared = DeclaredKeyExpr(handle: keyExprHandle, session: self)
        resourceLock.lock()
        declaredKeyExprs.append(declared)
        resourceLock.unlock()
        return declared
    }

    // MARK: - Publishing

    /// Publishes data to a declared key expression handle (protocol method).
    /// - Parameters:
    ///   - keyExpr: A ZenohKeyExprHandle (must be a DeclaredKeyExpr from this client)
    ///   - payload: The data to publish
    ///   - attachment: Optional attachment data (for ROS 2 metadata)
    /// - Throws: ZenohError if the put operation fails or the handle type is foreign
    public func put(keyExpr: any ZenohKeyExprHandle, payload: Data, attachment: Data?) throws {
        guard let declared = keyExpr as? DeclaredKeyExpr else {
            throw ZenohError.invalidParameter("foreign key-expression handle")
        }
        try putDeclared(keyExpr: declared, payload: payload, attachment: attachment)
    }

    /// Publishes data to a key expression string (without prior declaration)
    /// - Parameters:
    ///   - keyExpr: The key expression string
    ///   - payload: The data to publish
    ///   - attachment: Optional attachment data (for ROS 2 metadata)
    /// - Throws: ZenohError if the put operation fails
    public func put(keyExpr: String, payload: Data, attachment: Data?) throws {
        guard let sess = session else {
            throw ZenohError.putFailed("Session not open")
        }

        let result = keyExpr.withCString { keyExprPtr in
            payload.withUnsafeBytes { payloadPtr in
                if let attachment = attachment {
                    return attachment.withUnsafeBytes { attachmentPtr in
                        zenoh_put_str(
                            sess,
                            keyExprPtr,
                            payloadPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                            payload.count,
                            attachmentPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                            attachment.count
                        )
                    }
                } else {
                    return zenoh_put_str(
                        sess,
                        keyExprPtr,
                        payloadPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        payload.count,
                        nil,
                        0
                    )
                }
            }
        }

        if result == -2 {
            // Session disconnected - router connection lost
            session = nil
            throw ZenohError.sessionDisconnected("Router connection lost")
        } else if result < 0 {
            throw ZenohError.putFailed("Error code: \(result)")
        }
    }

    // MARK: - Subscription

    /// Subscribes to a key expression with a callback handler
    /// - Parameters:
    ///   - keyExpr: The key expression to subscribe to
    ///   - handler: Callback to invoke when samples are received
    /// - Returns: A handle conforming to ZenohSubscriberHandle
    /// - Throws: ZenohError if subscription fails
    public func subscribe(
        keyExpr: String,
        handler: @escaping (ZenohSample) -> Void
    ) throws -> any ZenohSubscriberHandle {
        guard let sess = session else {
            throw ZenohError.subscribeFailed("Session not open")
        }

        // Create a boxed handler that Swift can pass to C
        let contextBox = Unmanaged.passRetained(SubscriberContext(handler: handler))
        let context = UnsafeMutableRawPointer(contextBox.toOpaque())

        var subscriberPtr: OpaquePointer?
        let result = keyExpr.withCString { keyExprCStr in
            zenoh_declare_subscriber(sess, keyExprCStr, subscriberCallbackBridge, context, &subscriberPtr)
        }

        guard result >= 0, let subHandle = subscriberPtr else {
            contextBox.release()
            throw ZenohError.subscribeFailed("Error code: \(result)")
        }

        let subscriber = ZenohSubscriber(
            handle: subHandle,
            session: self,
            handler: handler,
            contextBox: contextBox
        )
        resourceLock.lock()
        subscribers.append(subscriber)
        resourceLock.unlock()
        return subscriber
    }

    // MARK: - Liveliness Tokens

    /// Declares a liveliness token for ROS 2 entity discovery
    /// - Parameter keyExpr: The liveliness token key expression (e.g., "@ros2_lv/0/...")
    /// - Returns: A handle conforming to ZenohLivelinessTokenHandle
    /// - Throws: ZenohError if declaration fails
    public func declareLivelinessToken(_ keyExpr: String) throws -> any ZenohLivelinessTokenHandle {
        guard let sess = session else {
            throw ZenohError.internalError("Session not open")
        }

        var tokenPtr: OpaquePointer?
        let result = keyExpr.withCString { keyExprCStr in
            zenoh_declare_liveliness_token(sess, keyExprCStr, &tokenPtr)
        }

        guard result >= 0, let tokenHandle = tokenPtr else {
            throw ZenohError.internalError("Failed to declare liveliness token: error code \(result)")
        }

        let token = LivelinessToken(handle: tokenHandle, session: self)
        resourceLock.lock()
        livelinessTokens.append(token)
        resourceLock.unlock()
        return token
    }

    deinit {
        // Clean up session on deallocation
        try? close()
    }

    // MARK: - Internal typed put (for DeclaredKeyExpr)

    private func putDeclared(keyExpr: DeclaredKeyExpr, payload: Data, attachment: Data?) throws {
        guard let sess = session else {
            throw ZenohError.putFailed("Session not open")
        }

        guard let keyExprHandle = keyExpr.opaqueHandle else {
            throw ZenohError.putFailed("Invalid key expression")
        }

        let result = payload.withUnsafeBytes { payloadPtr in
            if let attachment = attachment {
                return attachment.withUnsafeBytes { attachmentPtr in
                    zenoh_put(
                        sess,
                        keyExprHandle,
                        payloadPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        payload.count,
                        attachmentPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        attachment.count
                    )
                }
            } else {
                return zenoh_put(
                    sess,
                    keyExprHandle,
                    payloadPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    payload.count,
                    nil,
                    0
                )
            }
        }

        if result == -2 {
            // Session disconnected - router connection lost
            session = nil
            throw ZenohError.sessionDisconnected("Router connection lost")
        } else if result < 0 {
            throw ZenohError.putFailed("Error code: \(result)")
        }
    }
}

// MARK: - Internal Subscriber Context

/// Internal context for passing Swift closures to C callbacks
private class SubscriberContext {
    let handler: (ZenohSample) -> Void

    init(handler: @escaping (ZenohSample) -> Void) {
        self.handler = handler
    }
}

/// C callback bridge that converts C callback to Swift closure
private func subscriberCallbackBridge(
    keyExpr: UnsafePointer<CChar>?,
    payload: UnsafePointer<UInt8>?,
    payloadLen: Int,
    attachment: UnsafePointer<UInt8>?,
    attachmentLen: Int,
    context: UnsafeMutableRawPointer?
) {
    guard let context = context else { return }

    let contextBox = Unmanaged<SubscriberContext>.fromOpaque(context)
    let subscriberContext = contextBox.takeUnretainedValue()

    // Convert C strings and data to Swift types
    let keyExprString = keyExpr.flatMap { String(cString: $0) } ?? ""

    let payloadData: Data
    if let payload = payload, payloadLen > 0 {
        payloadData = Data(bytes: payload, count: payloadLen)
    } else {
        payloadData = Data()
    }

    let attachmentData: Data?
    if let attachment = attachment, attachmentLen > 0 {
        attachmentData = Data(bytes: attachment, count: attachmentLen)
    } else {
        attachmentData = nil
    }

    // ZenohSample is the SwiftROS2Transport canonical type
    let sample = ZenohSample(keyExpr: keyExprString, payload: payloadData, attachment: attachmentData)

    // Invoke Swift handler
    subscriberContext.handler(sample)
}

// MARK: - Protocol Conformance Extensions

extension DeclaredKeyExpr: ZenohKeyExprHandle {}
extension ZenohSubscriber: ZenohSubscriberHandle {}
extension LivelinessToken: ZenohLivelinessTokenHandle {}

// MARK: - Queryable / Query / Get (Services)

/// Internal context for passing a Swift queryable handler to the C closure.
private final class QueryableContext {
    let handler: @Sendable (any ZenohQueryHandle) -> Void

    init(handler: @escaping @Sendable (any ZenohQueryHandle) -> Void) {
        self.handler = handler
    }
}

/// Internal context for passing Swift get callbacks (per-reply + finish) to
/// the C closure.
private final class GetContext {
    let handler: @Sendable (Result<ZenohSample, ZenohError>) -> Void
    let onFinish: @Sendable () -> Void

    init(
        handler: @escaping @Sendable (Result<ZenohSample, ZenohError>) -> Void,
        onFinish: @escaping @Sendable () -> Void
    ) {
        self.handler = handler
        self.onFinish = onFinish
    }
}

/// Concrete `ZenohQueryHandle` backed by a `zenoh_query_t*`. The bridge frees
/// the underlying query exactly once: on the first successful reply / replyError
/// call. After consumption, this wrapper marks itself as consumed so further
/// reply attempts throw.
final class QueryHandleImpl: ZenohQueryHandle, @unchecked Sendable {
    let keyExpr: String
    let payload: Data
    let attachment: Data?

    private let lock = NSLock()
    private var queryHandle: OpaquePointer?

    init(handle: OpaquePointer, keyExpr: String, payload: Data, attachment: Data?) {
        self.queryHandle = handle
        self.keyExpr = keyExpr
        self.payload = payload
        self.attachment = attachment
    }

    func reply(payload: Data, attachment: Data?) throws {
        lock.lock()
        guard let handle = queryHandle else {
            lock.unlock()
            throw ZenohError.invalidParameter("query already replied")
        }
        // Mark consumed up-front; the C call frees the handle whether it
        // succeeds or fails.
        queryHandle = nil
        lock.unlock()

        let result = payload.withUnsafeBytes { payloadPtr -> Int8 in
            let payloadBase = payloadPtr.baseAddress?.assumingMemoryBound(to: UInt8.self)
            if let attachment = attachment {
                return attachment.withUnsafeBytes { attPtr in
                    zenoh_query_reply(
                        handle,
                        payloadBase,
                        payload.count,
                        attPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        attachment.count
                    )
                }
            } else {
                return zenoh_query_reply(handle, payloadBase, payload.count, nil, 0)
            }
        }

        if result < 0 {
            throw ZenohError.internalError("zenoh_query_reply failed: error code \(result)")
        }
    }

    func replyError(message: String) throws {
        lock.lock()
        guard let handle = queryHandle else {
            lock.unlock()
            throw ZenohError.invalidParameter("query already replied")
        }
        queryHandle = nil
        lock.unlock()

        let result = message.withCString { ptr -> Int8 in
            zenoh_query_reply_err(handle, ptr, strlen(ptr))
        }

        if result < 0 {
            throw ZenohError.internalError("zenoh_query_reply_err failed: error code \(result)")
        }
    }
}

/// Represents a declared queryable handle. Mirrors `ZenohSubscriber`.
public final class ZenohQueryable: ZenohQueryableHandle {
    private var handle: OpaquePointer?
    private weak var session: ZenohClient?
    private var contextBox: Unmanaged<QueryableContext>?

    fileprivate init(
        handle: OpaquePointer,
        session: ZenohClient,
        contextBox: Unmanaged<QueryableContext>
    ) {
        self.handle = handle
        self.session = session
        self.contextBox = contextBox
    }

    public func close() throws {
        guard let h = handle else {
            throw ZenohError.internalError("Queryable already closed")
        }

        // Always release Swift-side resources, even if the C-side undeclare
        // fails, so we don't leak the retained context box.
        defer {
            handle = nil
            contextBox?.release()
            contextBox = nil
        }

        guard let sess = session, let sessionHandle = sess.sessionHandle else {
            throw ZenohError.internalError("Session is no longer valid")
        }

        var mutableHandle: OpaquePointer? = h
        let result = zenoh_undeclare_queryable(sessionHandle, &mutableHandle)
        if result < 0 {
            throw ZenohError.internalError("Failed to undeclare queryable: error code \(result)")
        }
    }

    deinit {
        try? close()
    }
}

/// C bridge for the queryable callback. Reconstructs Swift types and calls the
/// user handler with a `QueryHandleImpl` wrapping the bridge-owned query.
private func queryableCallbackBridge(
    query: OpaquePointer?,
    keyExpr: UnsafePointer<CChar>?,
    payload: UnsafePointer<UInt8>?,
    payloadLen: Int,
    attachment: UnsafePointer<UInt8>?,
    attachmentLen: Int,
    context: UnsafeMutableRawPointer?
) {
    guard let query = query, let context = context else { return }

    let contextBox = Unmanaged<QueryableContext>.fromOpaque(context)
    let queryableContext = contextBox.takeUnretainedValue()

    let keyExprString = keyExpr.flatMap { String(cString: $0) } ?? ""

    let payloadData: Data
    if let payload = payload, payloadLen > 0 {
        payloadData = Data(bytes: payload, count: payloadLen)
    } else {
        payloadData = Data()
    }

    let attachmentData: Data?
    if let attachment = attachment, attachmentLen > 0 {
        attachmentData = Data(bytes: attachment, count: attachmentLen)
    } else {
        attachmentData = nil
    }

    let queryHandle = QueryHandleImpl(
        handle: query,
        keyExpr: keyExprString,
        payload: payloadData,
        attachment: attachmentData
    )

    queryableContext.handler(queryHandle)
}

/// C bridge for per-reply notifications from a get. Builds a `ZenohSample` (or
/// a `ZenohError` for error replies) and dispatches to the Swift handler.
private func getReplyBridge(
    keyExpr: UnsafePointer<CChar>?,
    payload: UnsafePointer<UInt8>?,
    payloadLen: Int,
    attachment: UnsafePointer<UInt8>?,
    attachmentLen: Int,
    isError: Bool,
    context: UnsafeMutableRawPointer?
) {
    guard let context = context else { return }

    let contextBox = Unmanaged<GetContext>.fromOpaque(context)
    let getContext = contextBox.takeUnretainedValue()

    let keyExprString = keyExpr.flatMap { String(cString: $0) } ?? ""

    let payloadData: Data
    if let payload = payload, payloadLen > 0 {
        payloadData = Data(bytes: payload, count: payloadLen)
    } else {
        payloadData = Data()
    }

    let attachmentData: Data?
    if let attachment = attachment, attachmentLen > 0 {
        attachmentData = Data(bytes: attachment, count: attachmentLen)
    } else {
        attachmentData = nil
    }

    if isError {
        let message = String(data: payloadData, encoding: .utf8) ?? "<non-UTF8 error payload>"
        getContext.handler(.failure(.internalError("query reply error: \(message)")))
    } else {
        let sample = ZenohSample(keyExpr: keyExprString, payload: payloadData, attachment: attachmentData)
        getContext.handler(.success(sample))
    }
}

/// C bridge for the closure-drop signal. Fires exactly once per get when the
/// reply closure is dropped (after the final reply or the timeout). Also
/// frees the retained Swift context box.
private func getFinishBridge(context: UnsafeMutableRawPointer?) {
    guard let context = context else { return }

    let contextBox = Unmanaged<GetContext>.fromOpaque(context)
    let getContext = contextBox.takeUnretainedValue()
    getContext.onFinish()
    contextBox.release()
}

extension ZenohClient {
    // MARK: - Queryable

    /// Declares a queryable on the given key expression. Mirrors `subscribe`.
    public func declareQueryable(
        _ keyExpr: String,
        handler: @escaping @Sendable (any ZenohQueryHandle) -> Void
    ) throws -> any ZenohQueryableHandle {
        guard let sess = sessionHandle else {
            throw ZenohError.invalidParameter("Session not open")
        }

        let contextBox = Unmanaged.passRetained(QueryableContext(handler: handler))
        let context = UnsafeMutableRawPointer(contextBox.toOpaque())

        var queryablePtr: OpaquePointer?
        let result = keyExpr.withCString { keyExprCStr in
            zenoh_declare_queryable(sess, keyExprCStr, queryableCallbackBridge, context, &queryablePtr)
        }

        guard result >= 0, let queryableHandle = queryablePtr else {
            contextBox.release()
            throw ZenohError.internalError("Failed to declare queryable: error code \(result)")
        }

        return ZenohQueryable(handle: queryableHandle, session: self, contextBox: contextBox)
    }

    // MARK: - Get

    /// Issues a query (Service Client side) against the given key expression.
    public func get(
        keyExpr: String,
        payload: Data?,
        attachment: Data?,
        timeoutMs: UInt32,
        handler: @escaping @Sendable (Result<ZenohSample, ZenohError>) -> Void,
        onFinish: @escaping @Sendable () -> Void
    ) throws {
        guard let sess = sessionHandle else {
            throw ZenohError.invalidParameter("Session not open")
        }

        let contextBox = Unmanaged.passRetained(GetContext(handler: handler, onFinish: onFinish))
        let context = UnsafeMutableRawPointer(contextBox.toOpaque())

        let result = keyExpr.withCString { keyExprCStr -> Int8 in
            withOptionalUnsafeBytes(payload) { payloadPtr, payloadLen in
                withOptionalUnsafeBytes(attachment) { attachmentPtr, attachmentLen in
                    zenoh_get(
                        sess,
                        keyExprCStr,
                        payloadPtr,
                        payloadLen,
                        attachmentPtr,
                        attachmentLen,
                        timeoutMs,
                        getReplyBridge,
                        getFinishBridge,
                        context
                    )
                }
            }
        }

        if result < 0 {
            // The bridge calls the finish handler whenever zenoh-pico drops the
            // closure, which includes the failure path of z_get. Releasing
            // here would double-free the box, so we leave it to the C drop
            // hook. Instead surface the error to Swift.
            throw ZenohError.internalError("zenoh_get failed: error code \(result)")
        }
    }
}

/// Helper that runs `body` with `(ptr, count)` for an optional `Data`,
/// or `(nil, 0)` if the data is nil/empty.
private func withOptionalUnsafeBytes<R>(
    _ data: Data?,
    _ body: (UnsafePointer<UInt8>?, Int) -> R
) -> R {
    guard let data = data, !data.isEmpty else {
        return body(nil, 0)
    }
    return data.withUnsafeBytes { raw in
        body(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), data.count)
    }
}
