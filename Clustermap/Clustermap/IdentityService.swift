//
//  IdentityService.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation
import Security

struct IdentityService {
    static func createCert(from data: Data) -> SecCertificate? {
        guard let cert = SecCertificateCreateWithData(nil, data as CFData) else {
            Task { @MainActor in
                LogService.shared.log("Cannot create certificate from data.", type: .error)
            }
            return nil
        }
        return cert
    }

    static func find(with data: Data) -> SecIdentity? {
        guard let cert = createCert(from: data) else {
            return nil
        }
        var identity: SecIdentity?
        let status = SecIdentityCreateWithCertificate(nil, cert, &identity)
        if status != errSecSuccess {
            Task { @MainActor in
                LogService.shared.log("Cannot find SecIdentity (status: \(status)).", type: .error)
            }
            return nil
        }
        return identity
    }
}
