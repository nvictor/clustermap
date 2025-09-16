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
        let result: (URLSession.AuthChallengeDisposition, URLCredential?)
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            result = handleServerTrust(challenge)
        case NSURLAuthenticationMethodClientCertificate:
            result = handleClientCertificate(challenge)
        default:
            result = (.performDefaultHandling, nil)
        }
        completionHandler(result.0, result.1)
    }

    private func handleServerTrust(_ challenge: URLAuthenticationChallenge) -> (
        URLSession.AuthChallengeDisposition, URLCredential?
    ) {
        guard let trust = challenge.protectionSpace.serverTrust else {
            Task { @MainActor in
                LogService.shared.log("Server trust challenge failed: no server trust object.", type: .error)
            }
            return (.cancelAuthenticationChallenge, nil)
        }

        // For minikube/local dev, insecure is often true.
        if insecure {
            return (.useCredential, URLCredential(trust: trust))
        }

        // For GKE with a custom CA.
        if validateWithCustomCA(trust) {
            return (.useCredential, URLCredential(trust: trust))
        }

        // If custom CA validation fails, or if there's no custom CA,
        // cancel the challenge. We don't want to fall back to system trust.
        return (.cancelAuthenticationChallenge, nil)
    }

    private func validateWithCustomCA(_ trust: SecTrust) -> Bool {
        guard let ca = caCert else { return false }

        SecTrustSetAnchorCertificates(trust, [ca] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        // For GKE and other cloud providers, a basic X.509 policy is more reliable
        // than a strict SSL policy, as we are already trusting the custom CA.
        SecTrustSetPolicies(trust, SecPolicyCreateBasicX509())

        var error: CFError?
        let isValid = SecTrustEvaluateWithError(trust, &error)

        if !isValid {
            let errorDescription = String(describing: error?.localizedDescription ?? "Unknown error")
            Task { @MainActor in
                LogService.shared.log("Server trust validation failed: \(errorDescription)", type: .error)
            }
        }

        return isValid
    }

    private func handleClientCertificate(_ challenge: URLAuthenticationChallenge) -> (
        URLSession.AuthChallengeDisposition, URLCredential?
    ) {
        // For minikube, an identity is provided.
        if let identity = clientIdentity {
            let credential = URLCredential(identity: identity, certificates: nil, persistence: .forSession)
            return (.useCredential, credential)
        } else {
            // For GKE, no identity is provided, so we continue with token auth.
            // The server requests a cert, but it's optional.
            return (.useCredential, nil)
        }
    }
}