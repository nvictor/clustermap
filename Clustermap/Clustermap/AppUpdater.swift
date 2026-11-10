import Combine
import Sparkle

@MainActor
final class AppUpdater: ObservableObject {
    /// Local builds have no public key, so the updater stays idle until a release build injects one.
    let isConfigured = !(Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "").isEmpty

    private let controller: SPUStandardUpdaterController
    private var observation: AnyCancellable?

    @Published var canCheckForUpdates = false

    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            if automaticallyChecksForUpdates != controller.updater.automaticallyChecksForUpdates {
                controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            }
        }
    }

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: isConfigured, updaterDelegate: nil, userDriverDelegate: nil)
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        // Sparkle disables checking while a check is already running.
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 && self?.isConfigured == true }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
