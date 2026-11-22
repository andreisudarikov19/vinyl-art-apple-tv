import Foundation
import Observation

@MainActor
@Observable
final class RecordViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    enum DisplayMode {
        case informative
        case coverFocused
    }

    let release: CachedRelease

    private(set) var loadState: LoadState = .loading
    private(set) var sides: [RecordSide] = []
    /// The country of this pressing, known once the release has loaded.
    private(set) var country: String?
    private(set) var currentSideIndex = 0
    private(set) var displayMode: DisplayMode = .informative

    private let loadDetail: @Sendable (Int) async throws -> ReleaseDetail

    init(release: CachedRelease, loadDetail: @escaping @Sendable (Int) async throws -> ReleaseDetail) {
        self.release = release
        self.loadDetail = loadDetail
    }

    var currentSide: RecordSide? {
        sides.indices.contains(currentSideIndex) ? sides[currentSideIndex] : nil
    }

    /// The duration of every track on every side, for the LENGTH row. A suite
    /// counts once, as the list shows it.
    var durations: [String] {
        sides.flatMap(\.tracks).map(\.duration)
    }

    var isOnFinalSide: Bool {
        currentSideIndex >= sides.count - 1
    }

    func load() async {
        loadState = .loading
        do {
            let detail = try await loadDetail(release.releaseId)
            sides = RecordSides.from(detail.tracklist)
            country = detail.country
            currentSideIndex = 0
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Advances to the next side. Never wraps — the final side stays in place
    /// (the record plays out and the cover remains). Returns whether a flip
    /// actually happened.
    @discardableResult
    func flipToNextSide() -> Bool {
        guard !isOnFinalSide else { return false }
        currentSideIndex += 1
        return true
    }

    /// Steps back one side. Never wraps — the first side stays put. Returns
    /// whether the side actually changed.
    @discardableResult
    func flipToPreviousSide() -> Bool {
        guard currentSideIndex > 0 else { return false }
        currentSideIndex -= 1
        return true
    }

    func enterCoverFocused() { displayMode = .coverFocused }
    func enterInformative() { displayMode = .informative }
}
