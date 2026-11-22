import SwiftUI

/// Style E, Glass lens: a fixed lens over the needle. The ticks spread wide
/// under the lens and close up toward its edges, where the tape runs at its
/// normal pitch. Draws from `ScaleTape`. The look is
/// design-handoff/reference/ScaleE.jpg; the measures are spec 01.
struct GlassLensScale: View {
    let tape: ScaleTape
    /// The entry under the needle.
    let current: Int
    /// The length of the list, for VoiceOver: "record 214 of 612".
    let total: Int
    /// The ambient halo is on: the tape fades, the lens, reading and needle drop to 70%.
    let idle: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True just after a press, while the tape glides: the needle dims slightly.
    @State private var moving = false

    /// The box, 1200 by 72 pt, centred under the cover.
    static let size = CGSize(width: 1200, height: 72)

    var body: some View {
        LensCanvas(
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

/// The lens's geometry. Spacing and tapering are spec 01's Glass lens:
/// 44 pt between ticks at the needle, 16 pt at the edges of a 360 pt lens.
enum GlassLens {
    /// Half the lens's width: 180 pt.
    static let halfWidth = 180.0
    static let cornerRadius = 20.0
    /// Points between ticks at the needle, and at the lens's edges.
    static let centrePitch = 44.0
    static let edgePitch = ScaleTape.pitch
    /// How much closer the ticks sit at the edges than at the needle.
    private static let spread = centrePitch - edgePitch
    /// How many entries lie between the needle and the lens's edge. Inside the
    /// lens the spacing follows `centrePitch - spread * (x / halfWidth)^2`,
    /// which integrates to a tanh; outside it is the plain edge pitch.
    static let edgeEntries = atanh((spread / centrePitch).squareRoot()) * halfWidth
        / (centrePitch * spread).squareRoot()

    /// Screen points from the needle to a tick `entries` entries away
    /// (negative is left). Continuous, with the spacing on each side of the
    /// edge matching, so the ticks run on past the lens without a jump.
    static func offset(entries: Double) -> Double {
        let count = abs(entries)
        let distance: Double
        if count <= edgeEntries {
            let scale = halfWidth * (centrePitch / spread).squareRoot()
            distance = scale * tanh(count * (centrePitch * spread).squareRoot() / halfWidth)
        } else {
            distance = halfWidth + edgePitch * (count - edgeEntries)
        }
        return entries < 0 ? -distance : distance
    }

    /// 1 at the needle, 0 at the lens's edge and beyond. Ticks take their
    /// height and opacity from it.
    static func weight(offset: Double) -> Double {
        let fraction = min(1, abs(offset) / halfWidth)
        return 1 - fraction * fraction
    }
}

/// The drawing, animatable so SwiftUI interpolates the tape's position (and
/// the idle and needle levels) frame by frame. Only the ticks in view are drawn.
private struct LensCanvas: View {
    var tape: ScaleTape
    /// Fractional while the tape glides between two entries.
    var position: Double
    /// 0 when the screen is in use, 1 when the ambient halo is on.
    var idle: Double
    /// Brightness of the needle: 1 when settled, lower while the tape moves.
    var needle: Double

    // Shared measures from spec 01.
    /// Group ticks stand 24 pt high in full white. Record ticks run from 12 pt
    /// at the lens's edges to 20 pt at the needle.
    private let groupHeight: CGFloat = 24
    private let recordHeightAtEdge: CGFloat = 12
    private let recordHeightAtNeedle: CGFloat = 20
    private let tickWidth: CGFloat = 2
    /// The label row and the reading sit on this line.
    private let labelY: CGFloat = 18
    private let needleTop: CGFloat = 40
    private let needleWidth: CGFloat = 4

    var body: some View {
        Canvas { context, size in
            guard !tape.groups.isEmpty else { return }
            drawLens(into: context, size: size)
            drawTape(into: &context, size: size)
            drawReading(into: &context, size: size)
            drawNeedle(into: context, size: size)
            drawLensEdge(into: context, size: size)
        }
    }

    private var lensRect: CGRect {
        CGRect(x: 0, y: 0, width: 2 * GlassLens.halfWidth, height: GlassLensScale.size.height)
    }

    /// The glass body, under the ticks: a grey gradient, lightest at the middle.
    /// Idle drops it to 70%, as the reading, so the glass still reads as a lens.
    private func drawLens(into context: GraphicsContext, size: CGSize) {
        var lens = context
        lens.opacity = 1 - 0.3 * idle
        let rect = lensRect.offsetBy(dx: size.width / 2 - GlassLens.halfWidth, dy: 0)
        let path = Path(roundedRect: rect, cornerRadius: GlassLens.cornerRadius)
        lens.fill(
            path,
            with: .linearGradient(
                Gradient(colors: [.white.opacity(0.16), .white.opacity(0.07)]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                endPoint: CGPoint(x: rect.midX, y: rect.maxY)
            )
        )
        lens.fill(
            path,
            with: .radialGradient(
                Gradient(colors: [.white.opacity(0.06), .clear]),
                center: CGPoint(x: rect.midX, y: rect.midY),
                startRadius: 0,
                endRadius: GlassLens.halfWidth
            )
        )
    }

    /// The thin light rim of the glass, over the ticks.
    private func drawLensEdge(into context: GraphicsContext, size: CGSize) {
        var edge = context
        edge.opacity = 1 - 0.3 * idle
        let rect = lensRect.offsetBy(dx: size.width / 2 - GlassLens.halfWidth, dy: 0)
        edge.stroke(
            Path(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: GlassLens.cornerRadius),
            with: .color(.white.opacity(0.35)),
            lineWidth: 1.5
        )
    }

    /// Ticks and labels: the tape. Idle fades it down to 30%.
    private func drawTape(into context: inout GraphicsContext, size: CGSize) {
        // A long reading keeps more of the tape clear around it.
        let reading = tape.reading(at: Int(position.rounded())) ?? ""
        let readingHalf = ScaleTape.textWidth(reading, size: ScaleTape.readingSize) / 2 + ScaleTape.textGap
        context.opacity = 1 - 0.7 * idle
        let centre = size.width / 2
        // Every tick sits at least 16 pt from its neighbour, so the entries
        // that can fall inside the box are no more than its half width over 16.
        let reach = Int(size.width / 2 / GlassLens.edgePitch) + 2
        let lowest = max(0, Int(position.rounded(.down)) - reach)
        let highest = min(tape.groups.count - 1, Int(position.rounded(.up)) + reach)
        if lowest <= highest {
            for index in lowest...highest {
                let relative = GlassLens.offset(entries: Double(index) - position)
                let x = centre + relative
                let weight = GlassLens.weight(offset: relative)
                let isGroup = tape.isGroupStart(index)
                let height = isGroup ? groupHeight : recordHeightAtEdge + (recordHeightAtNeedle - recordHeightAtEdge) * weight
                let opacity = isGroup ? 1 : 0.4 + 0.6 * weight
                let rect = CGRect(x: x - tickWidth / 2, y: size.height - height, width: tickWidth, height: height)
                context.fill(Path(rect), with: .color(.white.opacity(opacity)))
            }
        }
        let placement: (Double) -> Double = GlassLens.offset(entries:)
        for label in tape.labels(
            current: position,
            readingHalfWidth: max(80, readingHalf),
            placement: placement
        ) {
            let x = centre + label.offset
            context.draw(
                Text(label.text)
                    .font(Theme.mono(Theme.Size.small))
                    .foregroundStyle(Theme.body),
                at: CGPoint(x: x, y: labelY),
                anchor: .leading
            )
        }
    }

    /// The reading: the group under the needle, in yolk. Idle drops it to 70%.
    private func drawReading(into context: inout GraphicsContext, size: CGSize) {
        context.opacity = 1 - 0.3 * idle
        guard let reading = tape.reading(at: Int(position.rounded())) else { return }
        context.draw(
            Text(reading)
                .font(Theme.mono(Theme.Size.reading, medium: true))
                .foregroundStyle(Theme.yolk),
            at: CGPoint(x: size.width / 2, y: labelY),
            anchor: .center
        )
    }

    /// The needle: 4 pt yolk with a soft glow. Idle halves the glow.
    private func drawNeedle(into context: GraphicsContext, size: CGSize) {
        var needleContext = context
        needleContext.opacity = (1 - 0.3 * idle) * needle
        needleContext.addFilter(.shadow(color: Theme.yolk.opacity(0.6), radius: 8 * (1 - 0.5 * idle)))
        let rect = CGRect(
            x: size.width / 2 - needleWidth / 2,
            y: needleTop,
            width: needleWidth,
            height: size.height - needleTop
        )
        needleContext.fill(Path(rect), with: .color(Theme.yolk))
    }
}

extension LensCanvas: @MainActor Animatable {
    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(position, AnimatablePair(idle, needle)) }
        set {
            position = newValue.first
            idle = newValue.second.first
            needle = newValue.second.second
        }
    }
}
