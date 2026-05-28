import SwiftData
import SwiftUI

struct RootView: View {
    @State private var authenticator = DiscogsAuthenticator()

    var body: some View {
        Group {
            switch authenticator.state {
            case .authenticated(let credentials):
                AuthenticatedRootView(credentials: credentials)
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

    @Query private var preferences: [UserPreferences]
    @State private var didFinishBuild = false

    private var libraryReady: Bool {
        didFinishBuild || preferences.first?.lastSyncDate != nil
    }

    var body: some View {
        if libraryReady {
            GalleryView()
        } else {
            BuildingLibraryView(credentials: credentials) {
                didFinishBuild = true
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PersistenceController.preview)
}
