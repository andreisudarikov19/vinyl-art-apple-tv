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

    var isOnFinalSide: Bool {
        currentSideIndex >= sides.count - 1
    }

    func load() async {
        loadState = .loading
        do {
            let detail = try await loadDetail(release.releaseId)
            sides = RecordSides.from(detail.tracklist)
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

    func enterCoverFocused() { displayMode = .coverFocused }
    func enterInformative() { displayMode = .informative }
}
