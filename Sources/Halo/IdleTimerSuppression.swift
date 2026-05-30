import SwiftUI
import UIKit

/// Suppresses the tvOS screensaver while a flag is true. tvOS will silently
/// re-enable `isIdleTimerDisabled` in some scenarios (reported on Apple's
/// Developer Forums), so we re-assert it on a 30-second cadence while the
/// flag stays true. Clears it when the flag flips or the view disappears.
private struct IdleTimerSuppression: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .task(id: isActive) {
                UIApplication.shared.isIdleTimerDisabled = isActive
                guard isActive else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    if Task.isCancelled { return }
                    UIApplication.shared.isIdleTimerDisabled = true
                }
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
    }
}

extension View {
    /// While `isActive` is true, suppresses the tvOS screensaver. Releases it
    /// when the value flips back or the view disappears. Use sparingly — the
    /// halo's job is to provide moving pixels so the screen still gets
    /// burn-in protection while the system screensaver is held back.
    func suppressesScreensaver(_ isActive: Bool) -> some View {
        modifier(IdleTimerSuppression(isActive: isActive))
    }
}
