import Foundation
import Yams

public struct KubeConfig: Decodable, Sendable {
    public struct ClusterEntry: Decodable, Sendable {
        public let name: String
        public let cluster: Cluster
    }

    public struct ContextEntry: Decodable, Sendable {
        public let name: String
        public let context: Context
    }

    public struct UserEntry: Decodable, Sendable {
        public let name: String
        public let user: User?
    }

    public struct Cluster: Decodable, Sendable {
        public let server: String
        public let caData: String?
        public let ca: String?
        public let insecure: Bool?

        enum CodingKeys: String, CodingKey {
            case server
            case caData = "certificate-authority-data"
            case ca = "certificate-authority"
            case insecure = "insecure-skip-tls-verify"
        }
    }

    public struct Context: Decodable, Sendable {
        public let cluster: String
        public let user: String
    }

    public struct User: Decodable, Sendable {
        public let token: String?
        public let tokenFile: String?
        public let exec: ExecConfig?
        public let clientCertificateData: String?
        public let clientCertificate: String?
        public let clientKeyData: String?
        public let clientKey: String?

        enum CodingKeys: String, CodingKey {
            case token, exec
            case tokenFile = "tokenFile"
            case clientCertificateData = "client-certificate-data"
            case clientCertificate = "client-certificate"
            case clientKeyData = "client-key-data"
            case clientKey = "client-key"
        }
    }

    public struct ExecConfig: Decodable, Sendable {
        public struct EnvVar: Decodable, Sendable {
            public let name: String
            public let value: String
        }

        public let command: String
        public let args: [String]?
        public let env: [EnvVar]?
    }

    public let clusters: [ClusterEntry]
    public let contexts: [ContextEntry]
    public let users: [UserEntry]
    public let currentContext: String?

    enum CodingKeys: String, CodingKey {
        case clusters, contexts, users
        case currentContext = "current-context"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clusters = try container.decodeIfPresent([ClusterEntry].self, forKey: .clusters) ?? []
        contexts = try container.decodeIfPresent([ContextEntry].self, forKey: .contexts) ?? []
        users = try container.decodeIfPresent([UserEntry].self, forKey: .users) ?? []
        currentContext = try container.decodeIfPresent(String.self, forKey: .currentContext)
    }

    public static let defaultPath = "~/.kube/config"

    public static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    public static func load(path: String) throws -> KubeConfig {
        let expanded = expand(path)
        guard let data = FileManager.default.contents(atPath: expanded) else {
            throw KubeError.configNotFound(expanded)
        }
        return try parse(String(decoding: data, as: UTF8.self))
    }

    public static func parse(_ yaml: String) throws -> KubeConfig {
        do {
            return try YAMLDecoder().decode(KubeConfig.self, from: yaml)
        } catch {
            throw KubeError.configInvalid(String(describing: error))
        }
    }

    public var contextNames: [String] { contexts.map(\.name) }

    /// The preferred context when it exists, then the file's current context, then the first one.
    public func contextName(preferring preferred: String?) -> String? {
        let names = contextNames
        if let preferred, names.contains(preferred) { return preferred }
        if let currentContext, names.contains(currentContext) { return currentContext }
        return names.first
    }
}

public enum KubeError: Error, LocalizedError, Sendable, Equatable {
    case configNotFound(String)
    case configInvalid(String)
    case noContext
    case contextNotFound(String)
    case clusterNotFound(String)
    case userNotFound(String)
    case invalidServer(String)
    case execMissing(String)
    case execFailed(command: String, exitCode: Int32, stderr: String)
    case identity(String)
    case http(status: Int, message: String)
    case unreachable(String)

    public var errorDescription: String? {
        switch self {
        case .configNotFound(let path): "No kubeconfig at \(path)"
        case .configInvalid: "The kubeconfig could not be read"
        case .noContext: "The kubeconfig has no contexts"
        case .contextNotFound(let name): "Context \"\(name)\" is not in the kubeconfig"
        case .clusterNotFound(let name): "Cluster \"\(name)\" is not in the kubeconfig"
        case .userNotFound(let name): "User \"\(name)\" is not in the kubeconfig"
        case .invalidServer(let url): "Invalid server URL: \(url)"
        case .execMissing(let command): "\(command) was not found"
        case .execFailed(let command, let code, _): "\(command) failed with exit code \(code)"
        case .identity: "The client certificate could not be loaded"
        case .http(let status, _):
            switch status {
            case 401: "The cluster rejected the credentials (401)"
            case 403: "The cluster denied access (403)"
            default: "The cluster answered with HTTP \(status)"
            }
        case .unreachable: "The cluster is unreachable"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .configNotFound: "Choose a kubeconfig file in Settings."
        case .configInvalid(let detail): detail
        case .noContext, .contextNotFound, .clusterNotFound, .userNotFound: "Check the kubeconfig file."
        case .invalidServer: "Check the cluster's server field in the kubeconfig."
        case .execMissing(let command):
            command == "gke-gcloud-auth-plugin"
                ? "Install it with: gcloud components install gke-gcloud-auth-plugin"
                : "Install \(command) and make sure it is in /opt/homebrew/bin, /usr/local/bin, or your PATH."
        case .execFailed(_, _, let stderr): stderr
        case .identity(let detail): detail
        case .http(let status, let message):
            status == 403
                ? "Clustermap needs to list pods and events in all namespaces. \(message)" : message
        case .unreachable(let detail): detail
        }
    }
}
