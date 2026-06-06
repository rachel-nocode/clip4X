import AppAuth
import AppKit
import Clip4XCore
import Foundation
import Security

/// Drives the Google OAuth flow (AppAuth, loopback redirect + PKCE) and persists
/// the resulting auth state in the macOS Keychain. The access token is refreshed
/// transparently on demand.
@MainActor
final class YouTubeAuthManager: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var lastError: String?

    /// `nil` when the user has not set `CLIP4X_YT_CLIENT_ID`.
    let config: YouTubeConfig?
    var isConfigured: Bool { config != nil }

    private var authState: OIDAuthState? {
        didSet { isConnected = authState?.isAuthorized ?? false }
    }
    /// Retained so AppAuth's loopback HTTP listener survives the async flow.
    private var redirectHandler: OIDRedirectHTTPHandler?

    init(config: YouTubeConfig? = YouTubeConfig.fromEnvironment()) {
        self.config = config
        self.authState = Self.loadFromKeychain()
        self.isConnected = authState?.isAuthorized ?? false
    }

    // MARK: - Connect / disconnect

    func connect() async {
        guard let config else {
            lastError = "Set \(YouTubeConfig.clientIDKey) before connecting."
            return
        }
        lastError = nil

        let serviceConfig = OIDServiceConfiguration(
            authorizationEndpoint: YouTubeConfig.authorizationEndpoint,
            tokenEndpoint: YouTubeConfig.tokenEndpoint
        )

        // AppAuth spins up a 127.0.0.1 listener and opens the system browser.
        let successURL = URL(string: "https://openid.github.io/AppAuth-iOS/redirect/")!
        let handler = OIDRedirectHTTPHandler(successURL: successURL)
        redirectHandler = handler
        let redirectURI = handler.startHTTPListener(nil)
        let window = NSApp.mainWindow ?? NSApp.windows.first ?? NSWindow()

        let request = OIDAuthorizationRequest(
            configuration: serviceConfig,
            clientId: config.clientID,
            clientSecret: config.clientSecret,
            scopes: [YouTubeConfig.scope],
            redirectURL: redirectURI,
            responseType: OIDResponseTypeCode,
            additionalParameters: ["access_type": "offline", "prompt": "consent"]
        )

        do {
            let box: SendableBox<OIDAuthState> = try await withCheckedThrowingContinuation { continuation in
                // AppAuth invokes this callback on a background thread. Route it
                // through a nonisolated factory so it does NOT inherit this
                // method's @MainActor isolation (which would trip the Swift
                // concurrency executor assertion and crash).
                handler.currentAuthorizationFlow = OIDAuthState.authState(
                    byPresenting: request,
                    presenting: window,
                    callback: Self.authCallback(continuation)
                )
            }
            authState = box.value
            saveToKeychain(box.value)
        } catch {
            lastError = (error as NSError).localizedDescription
        }
        redirectHandler = nil
    }

    func disconnect() {
        authState = nil
        Self.deleteFromKeychain()
    }

    /// Builds the AppAuth completion callback in a nonisolated context so it can
    /// safely run on whatever thread AppAuth chooses.
    private nonisolated static func authCallback(
        _ continuation: CheckedContinuation<SendableBox<OIDAuthState>, Error>
    ) -> (OIDAuthState?, Error?) -> Void {
        return { state, error in
            if let state {
                continuation.resume(returning: SendableBox(state))
            } else {
                continuation.resume(throwing: error ?? YouTubeAuthError.cancelled)
            }
        }
    }

    private nonisolated static func tokenCallback(
        _ continuation: CheckedContinuation<String, Error>
    ) -> (String?, String?, Error?) -> Void {
        return { accessToken, _, error in
            if let accessToken {
                continuation.resume(returning: accessToken)
            } else {
                continuation.resume(throwing: error ?? YouTubeAuthError.notConnected)
            }
        }
    }

    // MARK: - Token access

    /// Returns a fresh access token, refreshing transparently if needed.
    func validToken() async throws -> String {
        guard let authState else { throw YouTubeAuthError.notConnected }
        let token: String = try await withCheckedThrowingContinuation { continuation in
            authState.performAction(freshTokens: Self.tokenCallback(continuation))
        }
        // performAction may have refreshed tokens — persist the latest state.
        saveToKeychain(authState)
        return token
    }

    // MARK: - Keychain

    private func saveToKeychain(_ state: OIDAuthState) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true) else {
            return
        }
        Self.deleteFromKeychain()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: YouTubeConfig.keychainService,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func loadFromKeychain() -> OIDAuthState? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: YouTubeConfig.keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data)
    }

    private static func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: YouTubeConfig.keychainService
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Bridges a non-Sendable AppAuth value across the continuation boundary.
/// Safe here: the value is produced and consumed on the main actor.
private struct SendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

enum YouTubeAuthError: LocalizedError {
    case notConnected
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConnected: "Not connected to YouTube."
        case .cancelled: "Authorization was cancelled."
        }
    }
}
