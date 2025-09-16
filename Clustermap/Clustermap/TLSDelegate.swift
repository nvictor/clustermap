//
//  TLSDeleagte.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation
import Security
import os.log

final class TLSDelegate: NSObject, URLSessionDelegate {
    private let caCert: SecCertificate?
    private let clientIdentity: SecIdentity?
    private let insecure: Bool

    init(caCert: SecCertificate?, clientIdentity: SecIdentity?, insecure: Bool = false) {
        self.caCert = caCert
        self.clientIdentity = clientIdentity
        self.insecure = insecure
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let result =
            switch challenge.protectionSpace.authenticationMethod {
            case NSURLAuthenticationMethodServerTrust:
                handleServerTrust(challenge)
            case NSURLAuthenticationMethodClientCertificate:
                handleClientCertificate(challenge)
            default:
                (URLSession.AuthChallengeDisposition.performDefaultHandling, nil as URLCredential?)
            }
        completionHandler(result.0, result.1)
    }

    private func handleServerTrust(_ challenge: URLAuthenticationChallenge) -> (
        URLSession.AuthChallengeDisposition, URLCredential?
    ) {
        guard let trust = challenge.protectionSpace.serverTrust else {
            Task { @MainActor in
                LogService.shared.log(
                    "Server trust challenge failed: no server trust object.", type: .error)
            }
            return (.cancelAuthenticationChallenge, nil)
        }

        // If insecure mode is enabled, accept any certificate
        if insecure {
            Task { @MainActor in
                LogService.shared.log(
                    "Insecure mode: Skipping all TLS validation for \(challenge.protectionSpace.host)",
                    type: .info
                )
            }
            return (.useCredential, URLCredential(trust: trust))
        }

        // Try to validate with custom CA if available
        if caCert != nil {
            let isValid = validateWithCustomCA(trust)
            if isValid {
                return (.useCredential, URLCredential(trust: trust))
            } else {
                return (.cancelAuthenticationChallenge, nil)
            }
        }

        // For cloud providers (like GKE) without custom CA, try more permissive validation
        let hostname = challenge.protectionSpace.host
        if isCloudProvider(hostname) {
            Task { @MainActor in
                LogService.shared.log(
                    "Cloud provider detected (\(hostname)): Using permissive certificate validation",
                    type: .info
                )
            }
            let isValid = validateForCloudProvider(trust, hostname: hostname)
            if isValid {
                return (.useCredential, URLCredential(trust: trust))
            }
        }

        // Fall back to default system validation
        return (.performDefaultHandling, nil)
    }

    private func validateWithCustomCA(_ trust: SecTrust) -> Bool {
        guard let ca = caCert else { return false }

        SecTrustSetAnchorCertificates(trust, [ca] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        // When connecting to an IP, the hostname check will fail.
        // Since we are explicitly trusting the CA from the kubeconfig,
        // we can skip the hostname check.
        Task { @MainActor in
            LogService.shared.log(
                "Custom CA validation: Skipping hostname validation (using kubeconfig CA)",
                type: .info
            )
        }
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, nil))

        var error: CFError?
        let isValid = SecTrustEvaluateWithError(trust, &error)

        if !isValid {
            let errorDescription = String(
                describing: error?.localizedDescription ?? "Unknown error")
            Task { @MainActor in
                LogService.shared.log(
                    "Server trust validation failed: \(errorDescription)", type: .error)
            }
        }

        return isValid
    }

    private func isCloudProvider(_ hostname: String) -> Bool {
        let cloudProviderPatterns = [
            // Google Cloud (GKE)
            "\\.googleapis\\.com$",
            "\\.gke\\.goog$",
            "\\d+\\.\\d+\\.\\d+\\.\\d+",    // IP addresses (common for GKE)
            // AWS (EKS)
            "\\.eks\\.amazonaws\\.com$",
            "\\.elb\\.amazonaws\\.com$",
            // Azure (AKS)
            "\\.azmk8s\\.io$",
            "\\.azure\\.com$",
            // DigitalOcean
            "\\.k8s\\.ondigitalocean\\.com$",
        ]

        for pattern in cloudProviderPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                regex.firstMatch(
                    in: hostname, options: [],
                    range: NSRange(location: 0, length: hostname.utf16.count)) != nil
            {
                return true
            }
        }
        return false
    }

    private func validateForCloudProvider(_ trust: SecTrust, hostname: String) -> Bool {
        // For cloud providers, use a more permissive SSL policy that doesn't require
        // strict certificate chain validation but still validates the certificate signature
        let policy = SecPolicyCreateSSL(true, hostname as CFString)
        SecTrustSetPolicies(trust, [policy] as CFArray)

        // Allow system root certificates
        SecTrustSetAnchorCertificatesOnly(trust, false)

        var error: CFError?
        let isValid = SecTrustEvaluateWithError(trust, &error)

        if !isValid {
            let errorDescription = error?.localizedDescription ?? "Unknown error"
            Task { @MainActor in
                LogService.shared.log(
                    "Cloud provider certificate validation failed for \(hostname): \(errorDescription)",
                    type: .error
                )
            }
        } else {
            Task { @MainActor in
                LogService.shared.log(
                    "Cloud provider certificate validation succeeded for \(hostname)",
                    type: .info
                )
            }
        }

        return isValid
    }

    private func handleClientCertificate(_ challenge: URLAuthenticationChallenge) -> (
        URLSession.AuthChallengeDisposition, URLCredential?
    ) {
        guard let identity = clientIdentity else {
            return (.performDefaultHandling, nil)
        }

        let credential = URLCredential(
            identity: identity, certificates: nil, persistence: .forSession)
        return (.useCredential, credential)
    }
}
