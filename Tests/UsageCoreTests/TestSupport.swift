import Foundation
@testable import UsageCore

final class BundleToken {}

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: name])
        }
        return try Data(contentsOf: url)
    }
}

/// Returns canned responses and records the requests it received.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    struct Response {
        var status: Int
        var body: Data
        var headers: [String: String] = [:]
    }

    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private let respond: @Sendable (URLRequest) -> Response

    init(_ respond: @escaping @Sendable (URLRequest) -> Response) {
        self.respond = respond
    }

    convenience init(status: Int, body: Data = Data("{}".utf8), headers: [String: String] = [:]) {
        self.init { _ in Response(status: status, body: body, headers: headers) }
    }

    var requests: [URLRequest] {
        lock.withLock { _requests }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _requests.append(request) }
        let response = respond(request)
        let http = HTTPURLResponse(
            url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers)!
        return (response.body, http)
    }
}

/// A unique, empty directory. Call `remove()` in a `defer` when the test ends.
struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "UsageAITests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

extension Date {
    init(utc string: String) {
        self = DateParsing.iso8601(string)!
    }
}

/// Builds an unsigned JWT with the given claims.
func makeJWT(_ claims: [String: Any]) -> String {
    func encode(_ object: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    return "\(encode(["alg": "HS256", "typ": "JWT"])).\(encode(claims)).signature"
}
