import NukeUI
import SwiftUI

/// A sleeve drawn whole. The picture is fitted inside the square the caller
/// gives it, and any gap takes the sleeve's own main colour, so a non-square
/// cover reads as a mat rather than black bars. Corners are square.
///
/// The caller sets the frame (or an aspect ratio of 1). See spec 07.
struct FittedSleeve: View {
    let url: URL?

    var body: some View {
        LazyImage(url: url) { state in
            if let container = state.imageContainer {
                ZStack {
                    Rectangle().fill(CoverColor.extract(from: container.image))
                    Image(uiImage: container.image)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                Rectangle().fill(.white.opacity(0.06))
            }
        }
    }
}
