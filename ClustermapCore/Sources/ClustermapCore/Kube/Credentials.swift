import Foundation

public struct Credentials: Sendable {
    public let server: URL
    public let token: String?
    /// DER certificate of the cluster's CA.
    public let caData: Data?
    /// PEM client certificate and key, for clusters that authenticate with mutual TLS (minikube, kind).
    public let clientCertificate: Data?
    public let clientKey: Data?
    public let insecure: Bool
    /// When an exec plugin's token stops working.
    public let expiresAt: Date?
}

enum CredentialResolver {
    static func resolve(_ config: KubeConfig, context contextName: String, configPath: String) async throws -> Credentials {
        guard let context = config.contexts.first(where: { $0.name == contextName })?.context else {
            throw KubeError.contextNotFound(contextName)
        }
        guard let cluster = config.clusters.first(where: { $0.name == context.cluster })?.cluster else {
            throw KubeError.clusterNotFound(context.cluster)
        }
        guard let userEntry = config.users.first(where: { $0.name == context.user }) else {
            throw KubeError.userNotFound(context.user)
        }
        guard let server = URL(string: cluster.server), server.host != nil else {
            throw KubeError.invalidServer(cluster.server)
        }
        let user = userEntry.user
        let directory = (KubeConfig.expand(configPath) as NSString).deletingLastPathComponent

        var token = user?.token
        var expiresAt: Date?
        if token == nil, let file = user?.tokenFile {
            token = (try? String(contentsOfFile: absolute(file, relativeTo: directory), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var clientCertificate = pem(path: user?.clientCertificate, base64: user?.clientCertificateData, directory: directory)
        var clientKey = pem(path: user?.clientKey, base64: user?.clientKeyData, directory: directory)
        if token == nil, let exec = user?.exec {
            let credential = try await run(exec)
            token = credential.status.token
            expiresAt = KubeDate.parse(credential.status.expirationTimestamp)
            if let certificate = credential.status.clientCertificateData, let key = credential.status.clientKeyData {
                clientCertificate = Data(certificate.utf8)
                clientKey = Data(key.utf8)
            }
        }

        let caData = pem(path: cluster.ca, base64: cluster.caData, directory: directory).flatMap(der)
        return Credentials(
            server: server, token: token, caData: caData,
            clientCertificate: clientCertificate, clientKey: clientKey,
            // Local clusters without a CA in the kubeconfig usually serve a self-signed certificate.
            insecure: cluster.insecure ?? (caData == nil && isLocal(server)),
            expiresAt: expiresAt)
    }

    // MARK: Exec plugins

    struct ExecCredential: Decodable {
        struct Status: Decodable {
            let token: String?
            let expirationTimestamp: String?
            let clientCertificateData: String?
            let clientKeyData: String?
        }
        let status: Status
    }

    private static func run(_ exec: KubeConfig.ExecConfig) async throws -> ExecCredential {
        var environment: [String: String] = [:]
        for variable in exec.env ?? [] { environment[variable.name] = variable.value }
        let output = try await Shell.run(exec.command, arguments: exec.args ?? [], environment: environment)
        do {
            return try JSONDecoder().decode(ExecCredential.self, from: output)
        } catch {
            throw KubeError.execFailed(command: exec.command, exitCode: 0, stderr: "It did not print an ExecCredential.")
        }
    }

    // MARK: Certificates

    private static func absolute(_ path: String, relativeTo directory: String) -> String {
        let expanded = KubeConfig.expand(path)
        return expanded.hasPrefix("/") ? expanded : (directory as NSString).appendingPathComponent(expanded)
    }

    /// Kubeconfig holds certificates as a file path or as base64 of the PEM text.
    private static func pem(path: String?, base64: String?, directory: String) -> Data? {
        if let path, let data = FileManager.default.contents(atPath: absolute(path, relativeTo: directory)) {
            return data
        }
        if let base64 { return Data(base64Encoded: base64, options: .ignoreUnknownCharacters) }
        return nil
    }

    /// The first certificate in a PEM file as DER. Data that is not PEM is assumed to be DER already.
    static func der(_ data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8), text.contains("-----BEGIN") else { return data }
        var body = ""
        var inside = false
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("-----BEGIN") { inside = true; continue }
            if line.hasPrefix("-----END") { break }
            if inside { body += line.trimmingCharacters(in: .whitespaces) }
        }
        return Data(base64Encoded: body)
    }

    static func isLocal(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local") || host.contains("minikube") {
            return true
        }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 10 || (parts[0] == 192 && parts[1] == 168) || (parts[0] == 172 && (16...31).contains(parts[1]))
    }
}

/// Runs helper programs: kubeconfig exec plugins and `openssl`.
enum Shell {
    /// Apps launched from Finder get a minimal PATH, so the usual install locations are added.
    static var searchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
            "\(home)/google-cloud-sdk/bin",
            "\(home)/Developer/google-cloud-sdk/bin",
            "/usr/local/google-cloud-sdk/bin",
            "/opt/google-cloud-sdk/bin",
            "/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/bin",
            "/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/bin",
            "\(home)/.local/bin",
        ]
    }

    static func run(
        _ command: String, arguments: [String] = [], environment: [String: String] = [:],
        input: Data? = nil, timeout: TimeInterval = 30
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result {
                    try runBlocking(command, arguments: arguments, environment: environment, input: input, timeout: timeout)
                })
            }
        }
    }

    private final class Buffer: @unchecked Sendable {
        var data = Data()
    }

    private static func runBlocking(
        _ command: String, arguments: [String], environment: [String: String], input: Data?, timeout: TimeInterval
    ) throws -> Data {
        var variables = ProcessInfo.processInfo.environment
        variables["PATH"] = ((variables["PATH"].map { [$0] } ?? []) + searchPaths).joined(separator: ":")
        variables.merge(environment) { _, new in new }

        let process = Process()
        if command.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
        }
        process.environment = variables

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw KubeError.execMissing(command)
        }

        // A plugin waiting on a browser login would otherwise hang the refresh forever.
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer { deadline.cancel() }

        if let input { try? stdin.fileHandleForWriting.write(contentsOf: input) }
        try? stdin.fileHandleForWriting.close()

        // Both pipes are drained at once. Reading one to the end first can deadlock on a full buffer.
        let errors = Buffer()
        let group = DispatchGroup()
        let errorHandle = stderr.fileHandleForReading
        DispatchQueue.global().async(group: group) {
            errors.data = errorHandle.readDataToEndOfFile()
        }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            // /usr/bin/env exits with 127 when the command is not in PATH.
            if process.terminationStatus == 127 { throw KubeError.execMissing(command) }
            let message = String(decoding: errors.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw KubeError.execFailed(
                command: command, exitCode: process.terminationStatus,
                stderr: process.terminationReason == .uncaughtSignal ? "It did not finish within \(Int(timeout)) seconds." : message)
        }
        return output
    }
}
