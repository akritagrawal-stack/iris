import Foundation
import Security
@testable import IrisAccountSession

final class InMemorySessionStorage: @unchecked Sendable {
    var readResult: Result<String?, KeychainStoreError>
    var storedRefreshToken: String?
    var reconnectResult: Result<String?, KeychainStoreError>?
    var reconnectMakesReadable = false
    var saveErrors: [Error] = []
    var deleteError: Error?
    var readCount = 0
    var reconnectCount = 0
    var saveCount = 0
    var deleteCount = 0
    var operations: [String] = []

    init(refreshToken: String? = nil) {
        storedRefreshToken = refreshToken
        readResult = .success(refreshToken)
    }

    @MainActor
    func accountStorage() -> AccountSessionStorage {
        AccountSessionStorage(
            read: { [weak self] in
                guard let self else { return .success(nil) }
                self.readCount += 1
                self.operations.append("read")
                if case .success = self.readResult {
                    return .success(self.storedRefreshToken)
                }
                return self.readResult
            },
            save: { [weak self] refreshToken in
                guard let self else { return }
                self.saveCount += 1
                self.operations.append("save")
                if !self.saveErrors.isEmpty {
                    throw self.saveErrors.removeFirst()
                }
                self.storedRefreshToken = refreshToken
                self.readResult = .success(refreshToken)
            },
            delete: { [weak self] in
                guard let self else { return }
                self.deleteCount += 1
                self.operations.append("delete")
                if let deleteError = self.deleteError {
                    throw deleteError
                }
                self.storedRefreshToken = nil
                self.readResult = .success(nil)
            },
            reconnect: { [weak self] in
                guard let self else { return .success(nil) }
                self.reconnectCount += 1
                self.operations.append("reconnect")
                let result = self.reconnectResult ?? {
                    if case .success = self.readResult {
                        return Result<String?, KeychainStoreError>.success(self.storedRefreshToken)
                    }
                    return self.readResult
                }()
                if self.reconnectMakesReadable {
                    self.readResult = .success(self.storedRefreshToken)
                }
                return result
            }
        )
    }
}

/// A disposable storage adapter that blocks only its explicit reconnect call.
/// It never touches Security.framework or an installed Iris profile.
final class BlockingReconnectSessionStorage: @unchecked Sendable {
    private let condition = NSCondition()
    private var reconnectIsBlocked = true
    private var reconnectStarted = false
    private(set) var readCount = 0
    private(set) var reconnectCount = 0
    private(set) var deleteCount = 0
    var storedRefreshToken: String?
    var readResult: Result<String?, KeychainStoreError>

    init(refreshToken: String) {
        self.storedRefreshToken = refreshToken
        self.readResult = .failure(.keychainOperationFailed(status: errSecInteractionNotAllowed))
    }

    func accountStorage() -> AccountSessionStorage {
        AccountSessionStorage(
            read: { [weak self] in
                guard let self else { return .success(nil) }
                self.condition.lock()
                defer { self.condition.unlock() }
                self.readCount += 1
                if case .success = self.readResult { return .success(self.storedRefreshToken) }
                return self.readResult
            },
            save: { [weak self] token in
                guard let self else { return }
                self.condition.lock()
                self.storedRefreshToken = token
                self.readResult = .success(token)
                self.condition.unlock()
            },
            delete: { [weak self] in
                guard let self else { return }
                self.condition.lock()
                self.deleteCount += 1
                self.storedRefreshToken = nil
                self.readResult = .success(nil)
                self.condition.unlock()
            },
            reconnect: { [weak self] in
                guard let self else { return .success(nil) }
                self.condition.lock()
                self.reconnectCount += 1
                self.reconnectStarted = true
                self.condition.broadcast()
                while self.reconnectIsBlocked {
                    self.condition.wait()
                }
                self.readResult = .success(self.storedRefreshToken)
                self.condition.unlock()
                return .success(self.storedRefreshToken)
            }
        )
    }

    func hasStartedReconnect() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        return reconnectStarted
    }

    func releaseReconnect() {
        condition.lock()
        reconnectIsBlocked = false
        condition.broadcast()
        condition.unlock()
    }
}

enum SessionFixtureError: Error, Equatable {
    case offline
    case keychainWriteDenied
    case keychainDeleteDenied
}

struct StubResponsePlan: Sendable {
    let statusCode: Int?
    let body: Data
    let gateID: Int?
    let transportError: URLError?

    static func response(statusCode: Int, body: Data, gateID: Int? = nil) -> Self {
        Self(statusCode: statusCode, body: body, gateID: gateID, transportError: nil)
    }

    static func offline(gateID: Int? = nil) -> Self {
        Self(
            statusCode: nil,
            body: Data(),
            gateID: gateID,
            transportError: URLError(.notConnectedToInternet)
        )
    }
}

/// Per-host response state. The URLProtocol never forwards a request.
final class StubResponseSequence: @unchecked Sendable {
    private let condition = NSCondition()
    private var responsePlans: [StubResponsePlan]
    private var releasedGateIDs: Set<Int> = []
    private(set) var requestCount = 0
    private(set) var observedRequests: [URLRequest] = []

    init(responsePlans: [StubResponsePlan]) {
        self.responsePlans = responsePlans
    }

    func takeNextPlan(for request: URLRequest) -> StubResponsePlan {
        condition.lock()
        defer {
            requestCount += 1
            observedRequests.append(Self.requestWithMaterializedBody(request))
            condition.broadcast()
            condition.unlock()
        }
        if responsePlans.isEmpty {
            return .offline()
        }
        return responsePlans.removeFirst()
    }

    private static func requestWithMaterializedBody(_ request: URLRequest) -> URLRequest {
        guard request.httpBody == nil, let bodyStream = request.httpBodyStream else { return request }
        bodyStream.open()
        defer { bodyStream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while bodyStream.hasBytesAvailable {
            let count = bodyStream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            body.append(buffer, count: count)
        }
        var materializedRequest = request
        materializedRequest.httpBody = body
        materializedRequest.httpBodyStream = nil
        return materializedRequest
    }

    func waitForRequestCount(_ expectedCount: Int, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if requestCountHasReached(expectedCount) { return }
            guard Date() < deadline else { throw SessionFixtureError.offline }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func requestCountHasReached(_ expectedCount: Int) -> Bool {
        condition.lock()
        let hasEnoughRequests = requestCount >= expectedCount
        condition.unlock()
        return hasEnoughRequests
    }

    func release(gateID: Int) {
        condition.lock()
        releasedGateIDs.insert(gateID)
        condition.broadcast()
        condition.unlock()
    }

    func waitForRelease(of gateID: Int, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        while !releasedGateIDs.contains(gateID) {
            guard condition.wait(until: deadline) else { break }
        }
        condition.unlock()
    }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var sequences: [String: StubResponseSequence] = [:]
    }

    private static let registry = Registry()

    static func register(_ sequence: StubResponseSequence, forHost host: String) {
        registry.lock.lock()
        registry.sequences[host] = sequence
        registry.lock.unlock()
    }

    static func unregister(host: String) {
        registry.lock.lock()
        registry.sequences.removeValue(forKey: host)
        registry.lock.unlock()
    }

    private static func sequence(forHost host: String) -> StubResponseSequence? {
        registry.lock.lock()
        defer { registry.lock.unlock() }
        return registry.sequences[host]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host,
              let sequence = Self.sequence(forHost: host) else {
            client?.urlProtocol(self, didFailWithError: SessionFixtureError.offline)
            return
        }

        let plan = sequence.takeNextPlan(for: request)
        let responseURL = request.url
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if let gateID = plan.gateID {
                sequence.waitForRelease(of: gateID)
            }

            if let transportError = plan.transportError {
                self.client?.urlProtocol(self, didFailWithError: transportError)
                return
            }

            guard let statusCode = plan.statusCode,
                  let responseURL,
                  let response = HTTPURLResponse(
                      url: responseURL,
                      statusCode: statusCode,
                      httpVersion: nil,
                      headerFields: ["Content-Type": "application/json"]
                  ) else {
                self.client?.urlProtocol(self, didFailWithError: SessionFixtureError.offline)
                return
            }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: plan.body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

@MainActor
final class AccountTestHarness {
    let host: String
    let sequence: StubResponseSequence
    let service: AccountService

    convenience init(
        storage: InMemorySessionStorage,
        responsePlans: [StubResponsePlan],
        savedSessionReconnectWaitNanoseconds: UInt64 = 15_000_000_000
    ) {
        self.init(
            sessionStorage: storage.accountStorage(), responsePlans: responsePlans,
            savedSessionReconnectWaitNanoseconds: savedSessionReconnectWaitNanoseconds
        )
    }

    init(
        sessionStorage: AccountSessionStorage,
        responsePlans: [StubResponsePlan],
        savedSessionReconnectWaitNanoseconds: UInt64 = 15_000_000_000
    ) {
        self.host = "fixture-\(UUID().uuidString.lowercased()).account-session.test"
        self.sequence = StubResponseSequence(responsePlans: responsePlans)
        StubURLProtocol.register(sequence, forHost: host)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        let projectURL = URL(string: "https://\(host)")!
        self.service = AccountService(
            urlSession: urlSession,
            sessionStorage: sessionStorage,
            projectConfiguration: { (projectURL, "fixture-anon-key") },
            loadOtherCredentials: false,
            savedSessionReconnectWaitNanoseconds: savedSessionReconnectWaitNanoseconds
        )
    }

    deinit {
        StubURLProtocol.unregister(host: host)
    }
}

func sessionBody(
    accessToken: String = "access-fixture",
    refreshToken: String = "refresh-fixture",
    emailAddress: String? = "reader@example.test",
    expiresInSeconds: Int = 3600
) -> Data {
    var fields: [String: Any] = [
        "access_token": accessToken,
        "refresh_token": refreshToken,
        "expires_in": expiresInSeconds,
    ]
    if let emailAddress {
        fields["user"] = ["id": "user-fixture", "email": emailAddress]
    }
    return try! JSONSerialization.data(withJSONObject: fields)
}

func authFailureBody(code: String? = nil) -> Data {
    var fields: [String: Any] = ["message": "fixture auth response"]
    if let code { fields["error_code"] = code }
    return try! JSONSerialization.data(withJSONObject: fields)
}
