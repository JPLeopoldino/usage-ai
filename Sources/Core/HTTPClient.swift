import Foundation

/// Sends HTTP requests. Swapped for a stub in tests.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public final class URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        session = URLSession(configuration: configuration, delegate: SameHostRedirectGuard(), delegateQueue: nil)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// Refuses redirects to another host so credentials never leak to a third party.
private final class SameHostRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    // The completion-handler form: the async form crashes the Swift 6.4 compiler when it emits the ObjC thunk.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        let from = task.originalRequest?.url?.host()
        let to = request.url?.host()
        completionHandler(from != nil && from == to ? request : nil)
    }
}

public enum HTTP {
    public static let userAgent: String = {
        let version = Bundle(for: URLSessionTransport.self).object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "0"
        return "UsageAI/\(version) (macOS)"
    }()

    public static func request(_ url: URL, method: String = "GET", headers: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    /// Sends a request and maps transport failures to `ProviderError`. Any HTTP status is returned.
    public static func send(
        _ request: URLRequest,
        using transport: any HTTPTransport
    ) async throws(ProviderError) -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                .dnsLookupFailed, .timedOut, .internationalRoamingOff, .dataNotAllowed:
                throw .offline
            default:
                throw .other("URLError \(error.code.rawValue)")
            }
        } catch {
            throw .other(String(describing: type(of: error)))
        }
    }

    /// Seconds from a `Retry-After` header (delta-seconds form only).
    public static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)), seconds > 0
        else { return nil }
        return seconds
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws(ProviderError) -> T {
        do {
            return try DateParsing.decoder().decode(type, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw .unexpectedShape("missing key \(key.stringValue)")
        } catch let DecodingError.typeMismatch(_, context) {
            throw .unexpectedShape("type mismatch at \(context.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch {
            throw .unexpectedShape("invalid JSON")
        }
    }
}
