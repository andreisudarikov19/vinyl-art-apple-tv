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
        // A 401 from any request (launch sync, refresh, tracklist, first-run
        // build) means Discogs dropped this sign-in: back to onboarding.
        _client = State(initialValue: DiscogsClient(
            credentials: credentials,
            onUnauthorized: { [authenticator] in await authenticator.signInExpired() }
        ))
    }

    private var libraryReady: Bool {
        didFinishBuild || preferences.first?.hasLibrary(for: credentials.username) == true
    }

    var body: some View {
        if libraryReady {
            GalleryView(authenticator: authenticator, client: client)
                .environment(\.releaseDetailLoader) { [client] id in
                    try await client.release(id: id)
                }
                .environment(\.coverResolver) { [container = modelContext.container] id in
                    await CoverArtService(modelContainer: container).resolveOne(releaseId: id)
                }
                .task { await refreshOnLaunch() }
        } else {
            BuildingLibraryView(client: client) {
                didFinishBuild = true
            }
        }
    }

    /// Delta refresh on each launch: pulls newly-added releases since the last
    /// sync, then resolves any covers still pending. Silent — failures (e.g.
    /// offline) leave the cached library untouched, and a revoked sign-in
    /// returns to onboarding through the client's `onUnauthorized` hook.
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
