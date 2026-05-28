import SwiftData
import SwiftUI

struct RootView: View {
    @State private var authenticator = DiscogsAuthenticator()

    var body: some View {
        Group {
            switch authenticator.state {
            case .authenticated(let credentials):
                AuthenticatedRootView(credentials: credentials, authenticator: authenticator)
            default:
                OnboardingView(authenticator: authenticator)
            }
        }
        .task { await authenticator.bootstrap() }
    }
}

/// Shown once signed in: builds the library on first run, then hands off to
/// the main experience.
private struct AuthenticatedRootView: View {
    let credentials: DiscogsCredentials
    let authenticator: DiscogsAuthenticator

    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]
    @State private var didFinishBuild = false
    @State private var client: DiscogsClient

    init(credentials: DiscogsCredentials, authenticator: DiscogsAuthenticator) {
        self.credentials = credentials
        self.authenticator = authenticator
        _client = State(initialValue: DiscogsClient(credentials: credentials))
    }

    private var libraryReady: Bool {
        didFinishBuild || preferences.first?.lastSyncDate != nil
    }

    var body: some View {
        if libraryReady {
            GalleryView(authenticator: authenticator, client: client)
                .environment(\.releaseDetailLoader) { [client] id in
                    try await client.release(id: id)
                }
                .task { await refreshOnLaunch() }
        } else {
            BuildingLibraryView(credentials: credentials) {
                didFinishBuild = true
            }
        }
    }

    /// Delta refresh on each launch: pulls newly-added releases since the last
    /// sync, then resolves any covers still pending. Silent — failures (e.g.
    /// offline) leave the cached library untouched.
    private func refreshOnLaunch() async {
        let container = modelContext.container
        let syncService = CollectionSyncService(modelContainer: container)
        _ = try? await syncService.sync(using: client)
        await CoverArtService(modelContainer: container).resolvePending()
    }
}

#Preview {
    RootView()
        .modelContainer(PersistenceController.preview)
}
