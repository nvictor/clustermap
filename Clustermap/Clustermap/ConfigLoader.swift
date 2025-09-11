//
//  ConfigLoader.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation
import Yams

struct KubeConfig: Codable {
    let clusters: [ClusterEntry]
    let contexts: [ContextEntry]
    let users: [UserEntry]
    let currentContext: String?

    enum CodingKeys: String, CodingKey {
        case clusters, contexts, users
        case currentContext = "current-context"
    }

    struct ClusterEntry: Codable {
        let name: String
        let cluster: Cluster
    }
    struct ContextEntry: Codable {
        let name: String
        let context: Context
    }
    struct UserEntry: Codable {
        let name: String
        let user: User
    }

    struct Cluster: Codable {
        let server: String
        let caData: String?
        let ca: String?
        let insecure: Bool?

        enum CodingKeys: String, CodingKey {
            case server
            case caData = "certificate-authority-data"
            case ca = "certificate-authority"
            case insecure = "insecure-skip-tls-verify"
        }
    }

    struct Context: Codable {
        let cluster: String
        let user: String
    }

    struct User: Codable {
        let token: String?
        let exec: ExecConfig?
        let clientCertificateData: String?
        let clientCertificate: String?

        enum CodingKeys: String, CodingKey {
            case token, exec
            case clientCertificateData = "client-certificate-data"
            case clientCertificate = "client-certificate"
        }
    }

    struct ExecConfig: Codable {
        let command: String
        let args: [String]?
        let env: [EnvVar]?
        struct EnvVar: Codable {
            let name: String
            let value: String
        }
    }
}

enum ConfigLoaderError: Error, LocalizedError {
    case fileNotFound(String)
    case contextNotFound(String)
    case clusterNotFound(String)
    case userNotFound(String)
    case invalidServerURL(String)
    case execCommandFailed(command: String, exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .contextNotFound(let name):
            return "Context '\(name)' not found"
        case .clusterNotFound(let name):
            return "Cluster '\(name)' not found"
        case .userNotFound(let name):
            return "User '\(name)' not found"
        case .invalidServerURL(let url):
            return "Invalid server URL: \(url)"
        case .execCommandFailed(let command, let exitCode, let stderr):
            return "'\(command)' failed with exit code \(exitCode): \(stderr)"
        }
    }
}

final class ConfigLoader {
    static func loadDefaultPath() -> String {
        "~/.kube/config"
    }

    static func parseKubeConfig(at path: String) throws -> KubeConfig {
        let path = expandTilde(path)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw ConfigLoaderError.fileNotFound(path)
        }
        return try YAMLDecoder().decode(KubeConfig.self, from: data)
    }

    static func makeCredentials(_ config: KubeConfig, usingContext contextName: String? = nil)
        async throws -> Credentials
    {
        let context = try findContext(in: config, name: contextName)
        let cluster = try findCluster(in: config, name: context.cluster)
        let user = try findUser(in: config, name: context.user)

        guard let serverURL = URL(string: cluster.server) else {
            throw ConfigLoaderError.invalidServerURL(cluster.server)
        }

        let token = try await getToken(from: user)
        let caData = parseCertificateData(path: cluster.ca, dataString: cluster.caData)
        let certData = parseCertificateData(
            path: user.clientCertificate, dataString: user.clientCertificateData)
        let insecure = cluster.insecure ?? shouldSkipTLSVerifyForServer(serverURL)

        return Credentials(
            server: serverURL, token: token, caData: caData, certData: certData, insecure: insecure)
    }

    private static func findContext(in config: KubeConfig, name: String?) throws
        -> KubeConfig.Context
    {
        let contextName = name ?? config.currentContext ?? config.contexts.first?.name
        guard let name = contextName, let entry = config.contexts.first(where: { $0.name == name })
        else {
            throw ConfigLoaderError.contextNotFound(name ?? "default")
        }
        return entry.context
    }

    private static func findCluster(in config: KubeConfig, name: String) throws
        -> KubeConfig.Cluster
    {
        guard let entry = config.clusters.first(where: { $0.name == name }) else {
            throw ConfigLoaderError.clusterNotFound(name)
        }
        return entry.cluster
    }

    private static func findUser(in config: KubeConfig, name: String) throws -> KubeConfig.User {
        guard let entry = config.users.first(where: { $0.name == name }) else {
            throw ConfigLoaderError.userNotFound(name)
        }
        return entry.user
    }

    private static func getToken(from user: KubeConfig.User) async throws -> String? {
        if let token = user.token {
            return token
        }
        if let exec = user.exec {
            return try await executeForToken(exec)
        }
        return nil
    }

    private static func executeForToken(_ exec: KubeConfig.ExecConfig) async throws -> String {
        struct ExecCredential: Codable {
            struct Status: Codable { let token: String }
            let status: Status
        }
        let env = exec.env?.reduce(into: [:]) { $0[$1.name] = $1.value } ?? [:]
        let tokenData = try await execute(command: exec.command, args: exec.args, extraEnv: env)
        let cred = try JSONDecoder().decode(ExecCredential.self, from: tokenData)
        return cred.status.token
    }

    private static func execute(command: String, args: [String]?, extraEnv: [String: String])
        async throws -> Data
    {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + (args ?? [])

        var env = ProcessInfo.processInfo.environment
        let defaultPaths = [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ]
        env["PATH"] = (env["PATH"].map { "\($0):" } ?? "") + defaultPaths.joined(separator: ":")
        extraEnv.forEach { env[$0] = $1 }
        process.environment = env

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        // It's important to read the data before waiting for the process to exit.
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return outputData
        } else {
            let errorString = String(decoding: errorData, as: UTF8.self)
            throw ConfigLoaderError.execCommandFailed(
                command: command, exitCode: process.terminationStatus, stderr: errorString)
        }
    }

    private static func parseCertificateData(path: String?, dataString: String?) -> Data? {
        if let path = path,
            let fileContent = try? String(
                contentsOf: URL(fileURLWithPath: expandTilde(path)), encoding: .utf8)
        {
            return convertPEMToDER(fileContent)
        }
        if let dataString = dataString, let decodedData = Data(base64Encoded: dataString) {
            // Check if the base64 data is itself a PEM string
            if let pemContent = String(data: decodedData, encoding: .utf8),
                pemContent.contains("-----BEGIN")
            {
                return convertPEMToDER(pemContent)
            }
            return decodedData    // Assume raw DER data
        }
        return nil
    }

    private static func expandTilde(_ path: String) -> String {
        path.replacingOccurrences(
            of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    private static func convertPEMToDER(_ pemString: String) -> Data? {
        let lines = pemString.components(separatedBy: .newlines)
        let base64Content = lines.filter { !$0.hasPrefix("-----") && !$0.isEmpty }.joined()
        return Data(base64Encoded: base64Content)
    }

    private static func shouldSkipTLSVerifyForServer(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        let devPatterns = ["minikube", "localhost", "127.0.0.1", "\\.local$"]
        if let regex = try? NSRegularExpression(pattern: devPatterns.joined(separator: "|")),
            regex.firstMatch(
                in: host, options: [], range: NSRange(location: 0, length: host.utf16.count)) != nil
        {
            return true
        }

        // Check for common private IP ranges
        return host.starts(with: "192.168.") || host.starts(with: "10.")
            || (host.starts(with: "172.")
                && (16...31).contains(Int(host.split(separator: ".")[1]) ?? 0))
    }
}
