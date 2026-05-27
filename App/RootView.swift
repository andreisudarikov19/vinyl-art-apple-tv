import SwiftUI

struct RootView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Text("Vinyl for Apple TV")
                    .font(.system(size: 72, weight: .light, design: .serif))
                    .foregroundStyle(.white)
                Text("v0.1 — bootstrap")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

#Preview {
    RootView()
}
