import Foundation
import Security

enum IdentityService {
    static func certificate(der: Data) -> SecCertificate? {
        SecCertificateCreateWithData(nil, der as CFData)
    }

    /// A client identity for mutual TLS.
    ///
    /// Looks in the keychain first, for setups where the key was imported by hand. Otherwise the PEM
    /// certificate and key are packed into a PKCS#12 blob and imported in memory, so nothing is
    /// written to the user's keychain.
    static func identity(certificatePEM: Data, keyPEM: Data?) async throws -> SecIdentity {
        if let der = CredentialResolver.der(certificatePEM), let certificate = certificate(der: der) {
            var identity: SecIdentity?
            if SecIdentityCreateWithCertificate(nil, certificate, &identity) == errSecSuccess, let identity {
                return identity
            }
        }
        guard let keyPEM else {
            throw KubeError.identity("The kubeconfig has a client certificate but no client key.")
        }

        // Security.framework has no public call that pairs a loose key with a certificate.
        // The bundle sits in a private temporary file for the length of the openssl call, then is removed.
        let password = UUID().uuidString
        var bundle = certificatePEM
        bundle.append(Data("\n".utf8))
        bundle.append(keyPEM)
        // openssl reads the bundle twice (key, then certificate), so it has to be a file, not a pipe.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("clustermap-\(UUID().uuidString).pem")
        defer { try? FileManager.default.removeItem(at: file) }
        let archive: Data
        do {
            guard FileManager.default.createFile(atPath: file.path, contents: bundle, attributes: [.posixPermissions: 0o600])
            else { throw KubeError.identity("") }
            archive = try await Shell.run(
                "/usr/bin/openssl", arguments: ["pkcs12", "-export", "-passout", "pass:\(password)", "-in", file.path])
        } catch {
            throw KubeError.identity("openssl could not read the client certificate and key.")
        }

        var items: CFArray?
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: password,
            kSecImportToMemoryOnly as String: true,
        ]
        let status = SecPKCS12Import(archive as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess,
            let first = (items as? [[String: Any]])?.first,
            let value = first[kSecImportItemIdentity as String]
        else {
            throw KubeError.identity("The client certificate and key could not be imported (status \(status)).")
        }
        return value as! SecIdentity
    }
}
