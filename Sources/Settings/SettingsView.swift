import SwiftData
import SwiftUI

/// Settings reachable from the gallery: a manual collection refresh (the
/// fallback to the automatic delta refresh) and sign-out. Sign-out offers the
/// documented choice between keeping the cached library for a faster return or
/// erasing it from this Apple TV.
struct SettingsView: View {
    let authenticator: DiscogsAuthenticator
    let client: DiscogsClient

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]
    @Query private var releases: [CachedRelease]

    @State private var refresh: RefreshState = .idle
    @State private var confirmingSignOut = false

    private enum RefreshState: Equatable {
        case idle
        case running(processed: Int, total: Int)
        case done(stored: Int)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Form {
                    accountSection
                    librarySection
                    signOutSection
                }
            }
            .navigationTitle("Settings")
        }
        .onExitCommand { dismiss() }
        .confirmationDialog(
            "Sign out of Discogs?",
            isPresented: $confirmingSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign Out & Keep Library") {
                Task { await signOut(erase: false) }
            }
            Button("Sign Out & Erase Library", role: .destructive) {
                Task { await signOut(erase: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keep the library to return faster, or erase the \(releases.count) cached releases from this Apple TV.")
        }
    }

    private var accountSection: some View {
        Section("Account") {
            LabeledContent("Discogs", value: username)
        }
    }

    private var librarySection: some View {
        Section("Library") {
            LabeledContent("Vinyl releases", value: "\(releases.count)")
            if let date = preferences.first?.lastSyncDate {
                LabeledContent(
                    "Last refreshed",
                    value: date.formatted(date: .abbreviated, time: .shortened)
                )
            }
            Button {
                Task { await runRefresh() }
            } label: {
                HStack {
                    SwiftUI.Label("Refresh Collection", systemImage: "arrow.clockwise")
                    Spacer()
                    refreshStatus
                }
            }
            .disabled(isRefreshing)
        }
    }

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                confirmingSignOut = true
            } label: {
                SwiftUI.Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    @ViewBuilder
    private var refreshStatus: some View {
        switch refresh {
        case .idle:
            EmptyView()
        case .running(let processed, let total):
            if total > 0 {
                Text("\(processed)/\(total)…")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                ProgressView()
            }
        case .done(let stored):
            Text("Updated \(stored)").foregroundStyle(.secondary)
        case .failed:
            Text("Failed").foregroundStyle(.red)
        }
    }

    private var isRefreshing: Bool {
        if case .running = refresh { return true }
        return false
    }

    private var username: String {
        let name = preferences.first?.discogsUsername ?? ""
        return name.isEmpty ? "Signed in" : name
    }

    private func runRefresh() async {
        refresh = .running(processed: 0, total: 0)
        let service = CollectionSyncService(modelContainer: modelContext.container)
        do {
            let summary = try await service.sync(using: client, forceFullBuild: true) { update in
                Task { @MainActor in
                    refresh = .running(processed: update.processed, total: update.total)
                }
            }
            refresh = .done(stored: summary.storedReleaseCount)
        } catch {
            refresh = .failed(error.localizedDescription)
        }
    }

    private func signOut(erase: Bool) async {
        if erase {
            try? modelContext.delete(model: CachedRelease.self)
            if let prefs = preferences.first {
                prefs.lastSyncDate = nil
                prefs.discogsUsername = ""
            }
            try? modelContext.save()
        }
        await authenticator.signOut()
    }
}
