import Foundation

/// Read-only Kubernetes API client. Three list calls cover everything Clustermap shows.
public final class KubeClient: Sendable {
    private let credentials: Credentials
    private let session: URLSession

    public static func make(_ credentials: Credentials) async throws -> KubeClient {
        var identity: SecIdentity?
        if let certificate = credentials.clientCertificate {
            identity = try await IdentityService.identity(certificatePEM: certificate, keyPEM: credentials.clientKey)
        }
        let delegate = TLSDelegate(
            caCertificate: credentials.caData.flatMap(IdentityService.certificate(der:)),
            clientIdentity: identity,
            insecure: credentials.insecure)
        return KubeClient(credentials: credentials, delegate: delegate)
    }

    private init(credentials: Credentials, delegate: TLSDelegate) {
        self.credentials = credentials
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    public var expiresAt: Date? { credentials.expiresAt }

    public func listPods() async throws -> [Pod] {
        try await list("/api/v1/pods")
    }

    public func listPodMetrics() async throws -> [PodMetrics] {
        try await list("/apis/metrics.k8s.io/v1beta1/pods")
    }

    public func listWarningEvents() async throws -> [Event] {
        try await list("/api/v1/events", query: [URLQueryItem(name: "fieldSelector", value: "type=Warning")])
    }

    private struct ListResponse<Item: Decodable>: Decodable {
        struct Metadata: Decodable {
            let `continue`: String?
        }
        let items: [Item]
        let metadata: Metadata?
    }

    private struct Status: Decodable {
        let message: String?
    }

    /// Follows `continue` tokens so large clusters arrive in pages of 500.
    private func list<Item: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> [Item] {
        var items: [Item] = []
        var token: String?
        repeat {
            var pageQuery = query + [URLQueryItem(name: "limit", value: "500")]
            if let token { pageQuery.append(URLQueryItem(name: "continue", value: token)) }
            let page: ListResponse<Item> = try await get(path, query: pageQuery)
            items += page.items
            token = page.metadata?.continue.flatMap { $0.isEmpty ? nil : $0 }
        } while token != nil
        return items
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(url: credentials.server.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Clustermap (darwin/arm64) kubernetes-client", forHTTPHeaderField: "User-Agent")
        if let token = credentials.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code != .cancelled {
            throw KubeError.unreachable("\(credentials.server.absoluteString): \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw KubeError.unreachable(credentials.server.absoluteString)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(Status.self, from: data))?.message
            throw KubeError.http(status: http.statusCode, message: message ?? String(decoding: data.prefix(300), as: UTF8.self))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
