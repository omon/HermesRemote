import Crypto
import Foundation
import Testing
@testable import HermesRemote

struct HermesRemoteTests {
    @Test func safeLocalComponentsRejectTraversal() {
        #expect(LocalFileStore.isSafeComponent("result.txt"))
        #expect(!LocalFileStore.isSafeComponent(".."))
        #expect(!LocalFileStore.isSafeComponent("a/b"))
        #expect(!LocalFileStore.isSafeComponent("disk:c"))
    }

    @Test func fingerprintUsesOpenSSHBlob() {
        let blob = Data("host-key".utf8)
        let key = "ssh-ed25519 \(blob.base64EncodedString())"
        let expected = "SHA256:" + Data(SHA256.hash(data: blob)).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        #expect(HostKeyValidator.fingerprint(forOpenSSHKey: key) == expected)
    }

    @Test @MainActor func defaultsAreMVPDefaults() {
        let suite = "HermesRemoteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.port == 22)
        #expect(settings.authenticationKind == .password)
        #expect(settings.startupCommand == "tmux new-session -A -s hermes")
        #expect(settings.hermesDirectory == "~/hermes-share")
    }
}
