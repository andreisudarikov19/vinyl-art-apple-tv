import SwiftUI

/// Style A, Slide rule (the default scale): bare ticks on a rule, labels
/// above, the reading in yolk above the needle. Draws from `ScaleTape`.
/// The look is design-handoff/reference/ScaleA.jpg; the measures are spec 01.
struct SlideRuleScale: View {
    let tape: ScaleTape
    /// The entry under the needle.
    let current: Int
    /// The length of the list, for VoiceOver: "record 214 of 612".
    let total: Int
    /// The ambient halo is on: the tape fades, the reading drops to 70%, the needle glows.
    let idle: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True just after a press, while the tape glides: the needle dims slightly.
    @State private var moving = false

    /// The box, 1200 by 72 pt, centred under the cover.
    static let size = CGSize(width: 1200, height: 72)

    var body: some View {
        ScaleCanvas(
            tape: tape,
            position: Double(current),
            idle: idle ? 1 : 0,
            needle: moving ? 0.75 : 1
        )
        .frame(width: Self.size.width, height: Self.size.height)
        // Labels and ticks fade at the ends of the box, never by changing colour.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: 0.1),
                    .init(color: .white, location: 0.9),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        // The glide: a fixed half second, however far the tape moves. With
        // Reduce Motion, the tape cross-fades to its new place instead.
        .id(reduceMotion ? current : 0)
        .transition(.opacity)
        .animation(reduceMotion ? .easeInOut(duration: 0.3) : .easeInOut(duration: 0.5), value: current)
        .animation(.easeInOut(duration: 0.8), value: idle)
        .animation(.easeInOut(duration: 0.3), value: moving)
        // The needle's idle glow, behind the drawing and free to spill past the box.
        .background { ScaleNeedleGlow(idle: idle) }
        .task(id: current) {
            moving = true
            try? await Task.sleep(for: .milliseconds(500))
            moving = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let reading = tape.reading(at: current) else { return "No records" }
        return "\(reading), record \(current + 1) of \(total)"
    }
}

/// The drawing, animatable so SwiftUI interpolates the tape's position (and
/// the idle and needle levels) frame by frame. Only the ticks in view are drawn.
private struct ScaleCanvas: View {
    var tape: ScaleTape
    /// Fractional while the tape glides between two entries.
    var position: Double
    /// 0 when the screen is in use, 1 when the ambient halo is on.
    var idle: Double
    /// Brightness of the needle: 1 when settled, lower while the tape moves.
    var needle: Double

    // Shared measures from spec 01.
    /// Ticks stand on the bottom edge, 2 pt wide.
    private let tickWidth: CGFloat = 2
    /// The label row and the reading sit on this line.
    private let labelY: CGFloat = 18
    private let needleTop: CGFloat = 40
    private let needleWidth: CGFloat = 4

    var body: some View {
        Canvas { context, size in
            guard !tape.groups.isEmpty else { return }
            drawTape(into: &context, size: size)
            drawReading(into: &context, size: size)
            drawNeedle(into: context, size: size)
        }
    }

    /// Ticks and labels: the tape. Idle fades it down to 30%.
    private func drawTape(into context: inout GraphicsContext, size: CGSize) {
        // A long reading keeps more of the tape clear around it.
        let reading = tape.reading(at: Int(position.rounded())) ?? ""
        let readingHalf = ScaleTape.textWidth(reading, size: ScaleTape.readingSize) / 2 + ScaleTape.textGap
        context.opacity = ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.tape, idle: idle)
        let centre = size.width / 2
        // Only the entries that can fall inside the box, plus a margin.
        let reach = Int(size.width / 2 / tape.spacing) + 2
        let lowest = max(0, Int(position.rounded(.down)) - reach)
        let highest = min(tape.groups.count - 1, Int(position.rounded(.up)) + reach)
        if lowest <= highest {
            for index in lowest...highest {
                let x = centre + tape.offset(of: index, current: position)
                let look = ScaleTickLook(tape.tick(at: index))
                let rect = CGRect(x: x - tickWidth / 2, y: size.height - look.height, width: tickWidth, height: look.height)
                let kept = ScaleIdleLook.tapeReach(at: Double(x), width: Double(size.width), idle: idle)
                context.fill(Path(rect), with: .color(.white.opacity(look.opacity * kept)))
            }
        }
        let tapeOpacity = context.opacity
        for label in tape.labels(current: position, readingHalfWidth: readingHalf, labelWidth: 0) {
            let x = centre + label.offset
            // A label fades by whichever of its two ends is nearer the box's end.
            let far = Double(x) + ScaleTape.textWidth(label.text, size: ScaleTape.labelSize)
            let kept = min(
                ScaleIdleLook.tapeReach(at: Double(x), width: Double(size.width), idle: idle),
                ScaleIdleLook.tapeReach(at: far, width: Double(size.width), idle: idle)
            )
            context.opacity = tapeOpacity * label.opacity * kept
            context.draw(
                Text(label.text)
                    .font(Theme.mono(Theme.Size.small))
                    .foregroundStyle(Theme.body),
                at: CGPoint(x: x, y: labelY),
                anchor: .leading
            )
        }
        context.opacity = tapeOpacity
    }

    /// The reading: the group under the needle, in yolk. Idle drops it to 70%.
    private func drawReading(into context: inout GraphicsContext, size: CGSize) {
        context.opacity = ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.reading, idle: idle)
        guard let reading = tape.reading(at: Int(position.rounded())) else { return }
        context.draw(
            Text(reading)
                .font(Theme.mono(Theme.Size.reading, medium: true))
                .foregroundStyle(Theme.yolk),
            at: CGPoint(x: size.width / 2, y: labelY),
            anchor: .center
        )
    }

    /// The needle: 4 pt yolk with a soft glow. It stays lit at idle, when `ScaleNeedleGlow` comes up around it.
    private func drawNeedle(into context: GraphicsContext, size: CGSize) {
        var needleContext = context
        needleContext.opacity = ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.needle, idle: idle) * needle
        let glow = ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.glow, idle: idle)
        needleContext.addFilter(.shadow(color: Theme.yolk.opacity(0.6 * glow), radius: 8))
        let rect = CGRect(
            x: size.width / 2 - needleWidth / 2,
            y: needleTop,
            width: needleWidth,
            height: size.height - needleTop
        )
        needleContext.fill(Path(rect), with: .color(Theme.yolk))
    }
}

extension ScaleCanvas: @MainActor Animatable {
    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(position, AnimatablePair(idle, needle)) }
        set {
            position = newValue.first
            idle = newValue.second.first
            needle = newValue.second.second
        }
    }
}
