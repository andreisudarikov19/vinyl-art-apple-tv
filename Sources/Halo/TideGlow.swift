import SwiftUI

/// The tide's glow: one radial gradient in an ellipse, drawn over whatever
/// is behind it. `reach` 0 is low tide, 1 high tide.
struct TideGlow: View {
    let shape: TideShape
    let main: OKLab
    let reach: Double

    var body: some View {
        Canvas { context, size in
            let centre = shape.centre(in: size)
            let radii = shape.radii(reach: reach, in: size)
            let stops = shape.stops(reach: reach, main: main).map {
                Gradient.Stop(color: $0.colour.rgb.color, location: $0.location)
            }
            // Draw a circle in a space squashed to the ellipse's proportions:
            // the gradient runs out to radii.width horizontally, radii.height vertically.
            context.translateBy(x: centre.x, y: centre.y)
            context.scaleBy(x: 1, y: radii.height / radii.width)
            let extent = max(size.width, size.height) * 4
            context.fill(
                Path(CGRect(x: -extent, y: -extent, width: 2 * extent, height: 2 * extent)),
                with: .radialGradient(
                    Gradient(stops: stops),
                    center: .zero,
                    startRadius: 0,
                    endRadius: radii.width
                )
            )
        }
    }
}
