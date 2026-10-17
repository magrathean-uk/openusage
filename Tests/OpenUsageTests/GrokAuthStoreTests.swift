import XCTest
@testable import OpenUsage

final class GrokAuthStoreTests: XCTestCase {
    func testCustomHomeLoadsAndSavesRotatedCredentialsWithoutTouchingDefaultHome() throws {
        for home in ["/custom/grok", "/custom/grok/", "  /custom/grok  ", "~/custom-grok"] {
            let path = URL(fileURLWithPath: expandHome(home.trimmingCharacters(in: .whitespacesAndNewlines)))
                .appendingPathComponent("auth.json").path
            let defaultJSON = #"{"default":{"key":"default-token"}}"#
            let files = FakeFiles([
                path: #"{"custom":{"key":"custom-token","refresh_token":"refresh"},"other":{"key":"other-token"}}"#,
                GrokAuthStore.authPath: defaultJSON,
            ])
            let store = GrokAuthStore(environment: FakeEnvironment(["GROK_HOME": home]), files: files)
            var state = try XCTUnwrap(store.loadAuthCandidates().first { $0.entryKey == "custom" })
            XCTAssertEqual(state.token, "custom-token")

            state.entry.key = "rotated-token"
            state.entry.refreshToken = "rotated-refresh"
            try store.save(state)

            let saved = try XCTUnwrap(GrokAuthStore.parseAuth(files.files[path]!))
            XCTAssertEqual(saved["custom"]?.key, "rotated-token")
            XCTAssertEqual(saved["custom"]?.refreshToken, "rotated-refresh")
            XCTAssertEqual(saved["other"]?.key, "other-token")
            XCTAssertEqual(files.files[GrokAuthStore.authPath], defaultJSON)
        }
    }

    func testBlankHomeUsesDefaultAuthFile() throws {
        let files = FakeFiles([GrokAuthStore.authPath: #"{"default":{"key":"token"}}"#])
        for home in ["", " \n\t"] {
            let store = GrokAuthStore(environment: FakeEnvironment(["GROK_HOME": home]), files: files)
            XCTAssertEqual(try store.loadAuthCandidates().first?.token, "token")
        }
    }

    func testMissingCustomAuthDoesNotFallBackToAnotherAccount() {
        let files = FakeFiles([GrokAuthStore.authPath: #"{"default":{"key":"wrong-account"}}"#])
        let store = GrokAuthStore(environment: FakeEnvironment(["GROK_HOME": "/custom/grok"]), files: files)
        XCTAssertThrowsError(try store.loadAuthCandidates()) {
            XCTAssertEqual($0 as? GrokAuthError, .notLoggedIn)
        }
    }

    func testSaveRefusesToOverwriteCorruptCustomAuth() throws {
        let path = "/custom/grok/auth.json"
        let files = FakeFiles([path: #"{"custom":{"key":"token"}}"#])
        let store = GrokAuthStore(environment: FakeEnvironment(["GROK_HOME": "/custom/grok"]), files: files)
        let state = try XCTUnwrap(store.loadAuthCandidates().first)
        files.files[path] = "corrupt"
        XCTAssertThrowsError(try store.save(state))
        XCTAssertEqual(files.files[path], "corrupt")
        XCTAssertNil(files.files[GrokAuthStore.authPath])
    }

    func testReadsTokenExpiryFromJWT() {
        let store = GrokAuthStore(environment: FakeEnvironment(), now: { OpenUsageISO8601.date(from: "2026-02-02T00:00:00.000Z")! })
        let token = makeJWT(exp: 1_770_000_000)

        let expiry = store.tokenExpiresAt(token)

        XCTAssertEqual(expiry?.timeIntervalSince1970, 1_770_000_000)
    }

    func testLoadsAuthCandidatesFromGrokAuthFile() throws {
        let files = FakeFiles([
            GrokAuthStore.authPath: #"{"https://auth.x.ai::client":{"key":"token","refresh_token":"refresh"}}"#
        ])
        let store = GrokAuthStore(environment: FakeEnvironment(), files: files)

        let candidates = try store.loadAuthCandidates()

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.token, "token")
        XCTAssertEqual(candidates.first?.entryKey, "https://auth.x.ai::client")
    }

    func testSaveRefusesToOverwriteACorruptAuthFile() throws {
        // A present-but-corrupt auth.json must NOT be silently rebuilt from in-memory state (which
        // would drop other accounts' entries). save() must throw and leave the file untouched.
        let validJSON = #"{"https://auth.x.ai::client":{"key":"token","refresh_token":"refresh","expires_at":"2026-07-01T00:00:00.000Z"}}"#
        let files = FakeFiles([GrokAuthStore.authPath: validJSON])
        let store = GrokAuthStore(environment: FakeEnvironment(), files: files, now: { OpenUsageISO8601.date(from: "2026-02-02T00:00:00.000Z")! })
        var state = try XCTUnwrap(store.loadAuthCandidates().first)
        state.entry.key = "rotated-token"

        // Corrupt the file on disk, then attempt to persist the rotation.
        let corrupt = "{ not valid json"
        files.files[GrokAuthStore.authPath] = corrupt

        XCTAssertThrowsError(try store.save(state))
        XCTAssertEqual(files.files[GrokAuthStore.authPath], corrupt, "corrupt file must be left untouched, not clobbered")
    }
}

private func makeJWT(exp: Int) -> String {
    let header = base64URL(Data(#"{"alg":"none"}"#.utf8))
    let payload = base64URL(Data(#"{"exp":\#(exp)}"#.utf8))
    return "\(header).\(payload).signature"
}

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
