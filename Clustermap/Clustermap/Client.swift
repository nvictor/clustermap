//
//  Client.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation
import Security
import os.log

enum ClientError: Error, LocalizedError {
    case httpError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .httpError(let statusCode, let body):
            return "Client: request: HTTP Error: Status \(statusCode)\n\(body)"
        }
    }
}

final class Client {
    private let creds: Credentials
    private let session: URLSession

    private struct ItemList<Item: Decodable>: Decodable {
        let items: [Item]
    }

    init(creds: Credentials) throws {
        self.creds = creds

        let delegate = TLSDelegate(
            caCert: creds.caData.flatMap(IdentityService.createCert),
            clientIdentity: creds.certData.flatMap(IdentityService.find),
            insecure: creds.insecure
        )

        self.session = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    func listNamespaces() async throws -> [KubeNamespace] {
        try await list(path: "/api/v1/namespaces")
    }

    func listDeployments(namespace: String) async throws -> [KubeDeployment] {
        try await list(path: "/apis/apps/v1/namespaces/\(namespace)/deployments")
    }

    func listPods(namespace: String, selector: String?) async throws -> [KubePod] {
        let queryItems: [URLQueryItem]? = selector.flatMap { s in
            s.isEmpty ? nil : [URLQueryItem(name: "labelSelector", value: s)]
        }
        return try await list(path: "/api/v1/namespaces/\(namespace)/pods", queryItems: queryItems)
    }

    func listPodMetrics(namespace: String) async throws -> [PodMetrics] {
        try await list(path: "/apis/metrics.k8s.io/v1beta1/namespaces/\(namespace)/pods")
    }

    private func list<Item: Decodable>(path: String, queryItems: [URLQueryItem]? = nil) async throws
        -> [Item]
    {
        let listResult: ItemList<Item> = try await request(path: path, queryItems: queryItems)
        return listResult.items
    }

    private func request<T: Decodable>(path: String, queryItems: [URLQueryItem]? = nil) async throws
        -> T
    {
        var components = URLComponents(
            url: creds.server.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems

        var req = URLRequest(url: components.url!)
        req.httpMethod = "GET"
        if let token = creds.token {
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        req.addValue("application/json", forHTTPHeaderField: "Accept")
        req.addValue(
            "Clustermap/1.0 (darwin/arm64) kubernetes-client", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await session.data(for: req)
        guard let httpResponse = resp as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            let body = String(decoding: data, as: UTF8.self)
            let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw ClientError.httpError(statusCode: statusCode, body: body)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}
