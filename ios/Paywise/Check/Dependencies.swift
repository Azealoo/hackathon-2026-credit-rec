import Foundation

/// Everything a check touches, in one place, so tests and previews can swap any part (the screen reader above all:
/// `VisionScreenReader` plugs in here when on-device reading lands, SPEC §15.7 step 8).
struct AppDependencies: Sendable {
    var screenReader: any ScreenReader
    var api: PaywiseAPI
    var checkStore: CheckStore
    var settings: PaywiseSettings
    var catalog: CardCatalog
    var replay: ReplayStore
    var purchases: PurchaseStoreProvider
    var island: any IslandPresenting
    var now: @Sendable () -> Date = { .now }
    var timeZone: TimeZone = .current
    /// How long an island alert is held before `.immediate` end (§6.3: 4 s).
    var islandHold: Duration = .seconds(4)
    /// The §6.6 G2 switch fallback hold (8 s).
    var fallbackHold: Duration = .seconds(8)
    /// On-device reading gives up after this, keeping the whole intent under 30 s (§6.2).
    var readTimeout: Duration = .seconds(8)

    var walletStore: WalletStore { WalletStore(settings: settings) }

    /// Production. Screen reading is a placeholder that throws until the OCR work is merged.
    static let live = AppDependencies(
        screenReader: VisionScreenReader(),
        api: .live(),
        checkStore: .appGroup,
        settings: .appGroup,
        catalog: .bundled(),
        replay: ReplayStore(),
        purchases: .appGroup,
        island: LiveActivityController.shared
    )
}

enum Dependencies {
    /// Task-local so parallel tests each see their own container; production code reads `.live`.
    @TaskLocal static var current: AppDependencies = .live
}
