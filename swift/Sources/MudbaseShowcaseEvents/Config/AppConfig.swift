import Foundation
import SwiftUI

/// Reads deployment configuration from `Config.plist` in the app bundle (copy it from
/// `Config.example.plist` at the repo root and add it as a resource in your Xcode run target — see
/// README "Configuration"). Deliberately NOT declared as an SPM `resources:` entry: that would make
/// `swift build` fail whenever `Config.plist` hasn't been created yet, and this repo's own
/// verification step (`swift build`) must succeed out of the box with no local secrets present. The
/// cost is that config is only checked at runtime, not at compile time — `AppConfig` surfaces that
/// as a typed, recoverable state (`ConfigurationError`) rather than crashing, so the app can show a
/// real "Configuration Required" screen instead of dying at launch.
struct AppConfig: Sendable, Equatable {
    let projectId: String
    let baseURL: URL
    let eventsCollectionId: String
    let bookingsCollectionId: String
    let activityCollectionId: String

    private static let defaultBaseURLString = "https://cloud.mudbase.dev"

    /// Loads from `Config.plist` in the main bundle first, then falls back to process environment
    /// variables (handy for `swift run` / scheme-level env vars during development).
    static func load(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) -> Result<AppConfig, ConfigurationError> {
        let plistValues = readPlist(bundle: bundle)

        func value(_ plistKey: String, envKey: String) -> String? {
            let fromPlist = plistValues[plistKey]
            if let fromPlist, !fromPlist.isEmpty { return fromPlist }
            let fromEnv = environment[envKey]
            if let fromEnv, !fromEnv.isEmpty { return fromEnv }
            return nil
        }

        guard let projectId = value("MudbaseProjectId", envKey: "MUDBASE_PROJECT_ID") else {
            return .failure(.missingKey("MudbaseProjectId"))
        }
        guard let eventsCollectionId = value("EventsCollectionId", envKey: "MUDBASE_EVENTS_COLLECTION_ID") else {
            return .failure(.missingKey("EventsCollectionId"))
        }
        guard let bookingsCollectionId = value("BookingsCollectionId", envKey: "MUDBASE_BOOKINGS_COLLECTION_ID") else {
            return .failure(.missingKey("BookingsCollectionId"))
        }
        guard let activityCollectionId = value("ActivityCollectionId", envKey: "MUDBASE_ACTIVITY_COLLECTION_ID") else {
            return .failure(.missingKey("ActivityCollectionId"))
        }
        let baseURLString = value("MudbaseBaseURL", envKey: "MUDBASE_BASE_URL") ?? defaultBaseURLString

        guard let baseURL = URL(string: baseURLString) else {
            return .failure(.invalidURL("MudbaseBaseURL", baseURLString))
        }

        return .success(
            AppConfig(
                projectId: projectId,
                baseURL: baseURL,
                eventsCollectionId: eventsCollectionId,
                bookingsCollectionId: bookingsCollectionId,
                activityCollectionId: activityCollectionId
            )
        )
    }

    private static func readPlist(bundle: Bundle) -> [String: String] {
        guard let url = bundle.url(forResource: "Config", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let raw = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            return [:]
        }
        return raw.compactMapValues { $0 as? String }
    }
}

enum ConfigurationError: Error, Equatable, CustomStringConvertible {
    case missingKey(String)
    case invalidURL(String, String)

    var description: String {
        switch self {
        case .missingKey(let key):
            return "Missing required configuration key \"\(key)\". Copy Config.example.plist to Config.plist, fill in your Mudbase project's IDs, and add it as a resource of your Xcode run target."
        case .invalidURL(let key, let value):
            return "Configuration key \"\(key)\" is not a valid URL: \"\(value)\"."
        }
    }
}

/// Lets any view reach the resolved `AppConfig` via `@Environment(\.appConfig)` without threading it
/// through every intermediate view's init — used only for read access; view models that need it are
/// still constructed explicitly by their parent view (see README "Architecture") so DI stays visible
/// at each call site rather than hidden behind environment lookups.
private struct AppConfigKey: EnvironmentKey {
    static let defaultValue: AppConfig? = nil
}

extension EnvironmentValues {
    var appConfig: AppConfig? {
        get { self[AppConfigKey.self] }
        set { self[AppConfigKey.self] = newValue }
    }
}
