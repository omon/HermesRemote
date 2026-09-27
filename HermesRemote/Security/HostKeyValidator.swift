import Crypto
import Foundation
import NIO
import NIOSSH

final class HostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    struct Candidate: Sendable {
        let openSSHKey: String
        let fingerprint: String
    }

    private let knownKey: String?
    private let lock = NSLock()
    private var _candidate: Candidate?

    init(knownKey: String?) { self.knownKey = knownKey }

    var candidate: Candidate? {
        lock.lock(); defer { lock.unlock() }
        return _candidate
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let encoded = String(openSSHPublicKey: hostKey)
        let fingerprint = Self.fingerprint(forOpenSSHKey: encoded)
        if let knownKey {
            if knownKey == encoded {
                validationCompletePromise.succeed(())
            } else {
                validationCompletePromise.fail(HermesRemoteError.hostKeyMismatch(
                    expected: Self.fingerprint(forOpenSSHKey: knownKey), actual: fingerprint
                ))
            }
            return
        }
        lock.lock()
        _candidate = Candidate(openSSHKey: encoded, fingerprint: fingerprint)
        lock.unlock()
        validationCompletePromise.fail(HermesRemoteError.untrustedHostKey(fingerprint))
    }

    static func fingerprint(forOpenSSHKey key: String) -> String {
        let fields = key.split(separator: " ")
        guard fields.count >= 2, let blob = Data(base64Encoded: String(fields[1])) else {
            return "SHA256:invalid"
        }
        return "SHA256:" + Data(SHA256.hash(data: blob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }
}
