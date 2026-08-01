import SwiftUI

/// App entry point. Configures the shared `MudbaseSDKAPIConfiguration` once at launch (see
/// `MudbaseSDKBootstrap`) and owns the app-wide `SessionStore` as a `@StateObject` so it survives
/// view identity churn across the whole app lifetime.
@main
struct MudbaseShowcaseEventsApp: App {
    private let configResult: Result<AppConfig, ConfigurationError>
    @StateObject private var sessionStore: SessionStore

    init() {
        let result = AppConfig.load()
        configResult = result
        switch result {
        case .success(let config):
            MudbaseSDKBootstrap.configure(baseURL: config.baseURL)
            _sessionStore = StateObject(wrappedValue: SessionStore(config: config))
        case .failure:
            // Placeholder config — never used, since `body` renders `ConfigurationRequiredView`
            // instead of `RootView` in this case. A concrete (if inert) value keeps the
            // `@StateObject` property non-optional. `URL(fileURLWithPath:)` is non-failable, so
            // this never needs a force-unwrap even though the URL string itself is a valid constant.
            let placeholder = AppConfig(
                projectId: "",
                baseURL: URL(string: "https://cloud.mudbase.dev") ?? URL(fileURLWithPath: "/"),
                eventsCollectionId: "",
                bookingsCollectionId: "",
                activityCollectionId: ""
            )
            _sessionStore = StateObject(wrappedValue: SessionStore(config: placeholder))
        }
    }

    var body: some Scene {
        WindowGroup {
            switch configResult {
            case .success(let config):
                RootView(config: config)
                    .environmentObject(sessionStore)
                    .environment(\.appConfig, config)
            case .failure(let error):
                ConfigurationRequiredView(error: error)
            }
        }
    }
}
