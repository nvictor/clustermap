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

        let shouldAcceptTrust = insecure || validateWithCustomCA(
            trust, host: challenge.protectionSpace.host)

        if shouldAcceptTrust {
            return (.useCredential, URLCredential(trust: trust))
        } else if caCert != nil {
            return (.cancelAuthenticationChallenge, nil)
        } else {
            return (.performDefaultHandling, nil)
        }
    }

    private func validateWithCustomCA(_ trust: SecTrust, host: String) -> Bool {
        guard let ca = caCert else { return false }

        SecTrustSetAnchorCertificates(trust, [ca] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))

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
