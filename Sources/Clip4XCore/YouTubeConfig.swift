import Foundation

/// OAuth + endpoint configuration for YouTube upload.
///
/// Clip4X is open source, so it ships no baked-in Google credentials. Each user
/// creates their own Google Cloud "Desktop app" OAuth client (one-time setup,
/// see youtube-setup.html) and exposes the Client ID to the app via an
/// environment variable. Because every user runs in their own Testing-mode
/// project where they are the sole authorized user, no Google OAuth app
/// verification is required and each user gets their own private quota.
public struct YouTubeConfig: Sendable {
    /// Environment variable holding the user's OAuth Client ID.
    public static let clientIDKey = "CLIP4X_YT_CLIENT_ID"
    /// Optional. Desktop OAuth clients may omit a secret when using PKCE.
    public static let clientSecretKey = "CLIP4X_YT_CLIENT_SECRET"

    public let clientID: String
    public let clientSecret: String?

    /// Narrowest scope that allows uploads. Avoids triggering the heavier
    /// restricted-scope / security-assessment review path.
    public static let scope = "https://www.googleapis.com/auth/youtube.upload"

    public static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    public static let resumableUploadEndpoint = URL(
        string: "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status"
    )!

    /// Keychain service identifier for the persisted auth state.
    public static let keychainService = "audio.witch.clip4x.youtube"

    public init(clientID: String, clientSecret: String?) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    /// Builds config from the environment, or `nil` when the Client ID is unset.
    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> YouTubeConfig? {
        guard let clientID = environment[clientIDKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clientID.isEmpty else {
            return nil
        }
        let secret = environment[clientSecretKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return YouTubeConfig(clientID: clientID, clientSecret: secret?.isEmpty == true ? nil : secret)
    }

    /// Builds config from credentials saved in-app (UserDefaults), falling back
    /// to the environment. UserDefaults wins because GUI apps launched from
    /// Finder/Dock do NOT inherit shell environment variables — so a Client ID
    /// exported in `.zshrc` only reaches the app when launched from a terminal.
    public static func load(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> YouTubeConfig? {
        func cleaned(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed?.isEmpty == false) ? trimmed : nil
        }
        guard let clientID = cleaned(defaults.string(forKey: clientIDKey))
            ?? cleaned(environment[clientIDKey]) else {
            return nil
        }
        let secret = cleaned(defaults.string(forKey: clientSecretKey))
            ?? cleaned(environment[clientSecretKey])
        return YouTubeConfig(clientID: clientID, clientSecret: secret)
    }

    /// Persists in-app entered credentials so subsequent GUI launches (which
    /// lack shell environment) pick them up. Pass an empty/`nil` Client ID to
    /// clear the stored credentials.
    public static func save(
        clientID: String,
        clientSecret: String?,
        to defaults: UserDefaults = .standard
    ) {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty {
            defaults.removeObject(forKey: clientIDKey)
            defaults.removeObject(forKey: clientSecretKey)
            return
        }
        defaults.set(id, forKey: clientIDKey)
        let secret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let secret, !secret.isEmpty {
            defaults.set(secret, forKey: clientSecretKey)
        } else {
            defaults.removeObject(forKey: clientSecretKey)
        }
    }
}
