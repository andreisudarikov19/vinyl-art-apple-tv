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
            MainPlaceholderView(username: credentials.username)
        } else {
            BuildingLibraryView(credentials: credentials) {
                didFinishBuild = true
            }
        }
    }
}

/// Temporary landing screen until the gallery is built.
private struct MainPlaceholderView: View {
    let username: String

    @Query private var releases: [CachedRelease]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Your library is ready")
                    .font(.system(size: 64, weight: .light, design: .serif))
                Text("\(releases.count) vinyl releases")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.7))
                Text("Signed in as \(username)")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .foregroundStyle(.white)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PersistenceController.preview)
}
