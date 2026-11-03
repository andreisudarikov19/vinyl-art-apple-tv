import SwiftUI

/// Drives the Discogs OAuth sign-in, rendering one screen per
/// `DiscogsAuthenticator.State`.
struct OnboardingView: View {
    @Bindable var authenticator: DiscogsAuthenticator

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
                .frame(maxWidth: 1100)
                .padding(80)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch authenticator.state {
        case .loading, .requestingToken:
            BusyView(message: "Connecting to Discogs…")
        case .exchangingToken:
            BusyView(message: "Signing you in…")
        case .idle:
            WelcomeView(notice: authenticator.notice) { await authenticator.startAuthorization() }
        case .awaitingVerifier(let authorizeURL):
            VerifierView(authorizeURL: authorizeURL) { verifier in
                await authenticator.submitVerifier(verifier)
            }
        case .failed(let message):
            FailureView(message: message) { authenticator.reset() }
        case .authenticated:
            // The root view swaps away from onboarding once authenticated;
            // show a brief confirmation in case of overlap.
            BusyView(message: "Signed in.")
        }
    }
}

private struct WelcomeView: View {
    /// Why the user is back here, e.g. Discogs stopped accepting the sign-in.
    var notice: String?
    var onSignIn: () async -> Void

    var body: some View {
        VStack(spacing: 40) {
            Text("Vinyl for Apple TV")
                .font(.system(size: 80, weight: .light, design: .serif))
                .foregroundStyle(.white)
            Text("Display your Discogs vinyl collection on the big screen.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            if let notice {
                SwiftUI.Label(notice, systemImage: "exclamationmark.circle")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 32)
                    .padding(.vertical, 20)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
            }
            Button {
                Task { await onSignIn() }
            } label: {
                Text("Sign in with Discogs")
                    .padding(.horizontal, 24)
            }
            .padding(.top, 20)
        }
    }
}

private struct VerifierView: View {
    let authorizeURL: URL
    var onSubmit: (String) async -> Void

    @State private var verifier = ""

    var body: some View {
        HStack(spacing: 80) {
            VStack(spacing: 24) {
                if let qr = QRCode.image(from: authorizeURL.absoluteString) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 360, height: 360)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    Text(authorizeURL.absoluteString)
                        .font(.footnote)
                        .foregroundStyle(.white)
                }
                Text("Scan with your phone")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 28) {
                stepsList
                TextField("Verification code", text: $verifier)
                    .textContentType(.oneTimeCode)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.black)
                    .frame(maxWidth: 480)
                    .padding(7)
                    .background(Color.white, in: Capsule())
                Button {
                    Task { await onSubmit(verifier) }
                } label: {
                    Text("Continue").padding(.horizontal, 24)
                }
                .disabled(verifier.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .foregroundStyle(.white)
    }

    private var stepsList: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Authorize on your phone")
                .font(.title2.weight(.semibold))
            SwiftUI.Label("Scan the code and sign in to Discogs", systemImage: "1.circle")
            SwiftUI.Label("Approve access to your collection", systemImage: "2.circle")
            SwiftUI.Label("Enter the code Discogs shows you", systemImage: "3.circle")
        }
        .font(.title3)
        .foregroundStyle(.white.opacity(0.85))
    }
}

private struct FailureView: View {
    let message: String
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)
            Text("Couldn't sign in")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button("Try again", action: onRetry)
                .padding(.top, 12)
        }
    }
}

private struct BusyView: View {
    let message: String

    var body: some View {
        VStack(spacing: 28) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
