import Foundation
import Security

/// Trusts the cluster's own CA and presents the client identity when the kubeconfig has one.
final class TLSDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let caCertificate: SecCertificate?
    private let clientIdentity: SecIdentity?
    private let insecure: Bool

    init(caCertificate: SecCertificate?, clientIdentity: SecIdentity?, insecure: Bool) {
        self.caCertificate = caCertificate
        self.clientIdentity = clientIdentity
        self.insecure = insecure
    }

    func urlSession(
        _ session: URLSession, didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            return serverTrust(challenge)
        case NSURLAuthenticationMethodClientCertificate:
            // Token-authenticated clusters (GKE, EKS) also ask for a certificate. It is optional there.
            guard let clientIdentity else { return (.useCredential, nil) }
            return (.useCredential, URLCredential(identity: clientIdentity, certificates: nil, persistence: .forSession))
        default:
            return (.performDefaultHandling, nil)
        }
    }

    private func serverTrust(_ challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let trust = challenge.protectionSpace.serverTrust else { return (.cancelAuthenticationChallenge, nil) }
        if insecure { return (.useCredential, URLCredential(trust: trust)) }
        // No CA in the kubeconfig: the cluster has a publicly trusted certificate, or the request fails.
        guard let caCertificate else { return (.performDefaultHandling, nil) }

        SecTrustSetAnchorCertificates(trust, [caCertificate] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        // API servers are often reached by IP. The kubeconfig's CA is the trust decision, so the
        // chain is checked against it without the hostname rules of the SSL policy.
        SecTrustSetPolicies(trust, SecPolicyCreateBasicX509())
        var error: CFError?
        return SecTrustEvaluateWithError(trust, &error)
            ? (.useCredential, URLCredential(trust: trust))
            : (.cancelAuthenticationChallenge, nil)
    }
}
