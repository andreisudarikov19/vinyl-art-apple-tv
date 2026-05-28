import SwiftData
import SwiftUI

/// First-launch blocking screen: builds the local library from the Discogs
/// collection, showing "Fetching 247/812 albums…". Not cancellable.
struct BuildingLibraryView: View {
    let credentials: DiscogsCredentials
    var onFinished: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var progress: SyncProgress?
    @State private var failureMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let failureMessage {
                failure(failureMessage)
            } else {
                building
            }
        }
        .foregroundStyle(.white)
        .task { await build() }
    }

    private var building: some View {
        VStack(spacing: 28) {
            ProgressView()
                .controlSize(.large)
            Text("Building your library")
                .font(.title.weight(.semibold))
            Text(progressLabel)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.6))
                .monospacedDigit()
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 56))
                .foregroundStyle(.yellow)
            Text("Couldn't build your library")
                .font(.title.weight(.semibold))
            Text(message)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button("Retry") {
                failureMessage = nil
                Task { await build() }
            }
            Button("Continue anyway", action: onFinished)
        }
    }

    private var progressLabel: String {
        guard let progress, progress.total > 0 else { return "Fetching your collection…" }
        return "Fetching \(progress.processed)/\(progress.total) albums…"
    }

    private func build() async {
        let container = modelContext.container
        let client = DiscogsClient(credentials: credentials)
        let service = CollectionSyncService(modelContainer: container)
        do {
            _ = try await service.sync(using: client) { update in
                Task { @MainActor in progress = update }
            }
            onFinished()
        } catch {
            failureMessage = error.localizedDescription
        }
    }
}
