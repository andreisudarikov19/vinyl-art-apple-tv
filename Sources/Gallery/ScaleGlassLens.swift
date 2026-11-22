import SwiftUI

/// Style E, Glass lens: a fixed lens over the needle. The ticks spread wide
/// under the lens and close up toward its edges, where the tape runs at its
/// normal pitch. Draws from `ScaleTape`. The look is
/// design-handoff/reference/ScaleE.jpg; the measures are spec 01.
///
/// The lens is a pill that lies over the tape: the ticks pass under the
/// glass, and the reading and the needle sit on it. On tvOS 26 the pill is
/// the system's Liquid Glass, which bends the ticks at its round ends. On
/// tvOS 18 to 25, which have no such material, it is drawn as a glass plate.
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
        ZStack {
            if usesSystemGlass {
                // Bottom to top: the tape, the glass, then what sits on it.
                canvas(.tape)
                lensGlass
                canvas(.marks)
            } else {
                canvas(.all, drawsGlass: true)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .task(id: current) {
            moving = true
            try? await Task.sleep(for: .milliseconds(500))
            moving = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// One layer of the drawing, with the fades and the glide every layer
    /// shares, so the tape and what sits on the glass move as one.
    private func canvas(_ layers: LensCanvas.Layers, drawsGlass: Bool = false) -> some View {
        LensCanvas(
            tape: tape,
            position: Double(current),
            idle: idle ? 1 : 0,
            needle: moving ? 0.75 : 1,
            layers: layers,
            drawsGlass: drawsGlass
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
    }

    /// Whether the system has Liquid Glass to draw the lens with.
    private var usesSystemGlass: Bool {
        if #available(tvOS 26.0, *) {
            return true
        }
        return false
    }

    /// The lens as Liquid Glass: a pill 360 by 72 pt, centred on the needle,
    /// over the tape and under the reading and the needle. It stays put while
    /// the tape glides. Idle drops it to 70%, as the reading.
    ///
    /// The clear variant, so the ticks under it stay sharp; the regular one
    /// frosts what lies beneath. No tint and not interactive: the lens is
    /// not a control.
    @ViewBuilder
    private var lensGlass: some View {
        if #available(tvOS 26.0, *) {
            Color.clear
                .frame(width: 2 * GlassLens.halfWidth, height: Self.size.height)
                .glassEffect(.clear, in: Capsule())
                .opacity(idle ? ScaleIdleLook.reading : 1)
                .animation(.easeInOut(duration: 0.8), value: idle)
        }
    }

    private var accessibilityText: String {
        guard let reading = tape.reading(at: current) else { return "No records" }
        return "\(reading), record \(current + 1) of \(total)"
    }
}

/// The lens's geometry. Spacing and tapering are spec 01's Glass lens:
/// 44 pt between ticks at the needle, 16 pt at the edges of a 360 pt lens.
/// A short tape is spread wider than 16 pt (`ScaleTape.spacing`), so a lens
/// is made for a tape's pitch: the ticks at the needle are then 1.6 times
/// that pitch apart, and never closer than 44 pt.
struct GlassLens: Equatable, Sendable {
    /// Half the lens's width: 180 pt.
    static let halfWidth = 180.0
    /// The lens is a pill: its ends are half circles, 36 pt on a 72 pt box.
    static let cornerRadius = 36.0
    /// Points between ticks at the needle, and at the lens's edges, on a
    /// tape at the closest pitch.
    static let centrePitch = 44.0
    static let edgePitch = ScaleTape.pitch
    /// How much wider the ticks at the needle sit on a spread tape.
    static let magnification = 1.6
    /// The lens for a tape at the closest pitch.
    static let standard = GlassLens(pitch: edgePitch)

    /// Points between ticks outside the lens: the tape's own spacing.
    let pitch: Double
    /// Points between ticks at the needle.
    let needlePitch: Double
    /// How much closer the ticks sit at the edges than at the needle.
    private let spread: Double
    /// How many entries lie between the needle and the lens's edge. Inside the
    /// lens the spacing follows `needlePitch - spread * (x / halfWidth)^2`,
    /// which integrates to a tanh; outside it is the plain pitch.
    let entriesToEdge: Double

    init(pitch: Double) {
        let needlePitch = max(Self.centrePitch, pitch * Self.magnification)
        let spread = needlePitch - pitch
        self.pitch = pitch
        self.needlePitch = needlePitch
        self.spread = spread
        entriesToEdge = atanh((spread / needlePitch).squareRoot()) * Self.halfWidth
            / (needlePitch * spread).squareRoot()
    }

    /// Screen points from the needle to a tick `entries` entries away
    /// (negative is left). Continuous, with the spacing on each side of the
    /// edge matching, so the ticks run on past the lens without a jump.
    func distance(entries: Double) -> Double {
        let count = abs(entries)
        let far: Double
        if count <= entriesToEdge {
            let scale = Self.halfWidth * (needlePitch / spread).squareRoot()
            far = scale * tanh(count * (needlePitch * spread).squareRoot() / Self.halfWidth)
        } else {
            far = Self.halfWidth + pitch * (count - entriesToEdge)
        }
        return entries < 0 ? -far : far
    }

    /// The standard lens's edge and offsets, for a tape at the closest pitch.
    static var edgeEntries: Double { standard.entriesToEdge }
    static func offset(entries: Double) -> Double { standard.distance(entries: entries) }

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
    /// Which parts this canvas draws. On tvOS 26 the tape and the marks are
    /// two canvases, with the system's glass between them.
    var layers: Layers = .all
    /// Draw the glass plate and its rim here. False when the system's Liquid
    /// Glass is the lens (tvOS 26).
    var drawsGlass = true

    struct Layers: OptionSet {
        let rawValue: Int
        /// The ticks and the labels, which pass under the glass.
        static let tape = Layers(rawValue: 1)
        /// The reading and the needle, which sit on the glass.
        static let marks = Layers(rawValue: 2)
        static let all: Layers = [.tape, .marks]
    }

    // Shared measures from spec 01.
    /// Outside the lens ticks are as tall as on the Slide rule. Under it,
    /// record ticks grow to 20 pt at the needle.
    private let recordHeightAtNeedle: CGFloat = 20
    private let tickWidth: CGFloat = 2
    /// The label row and the reading sit on this line.
    private let labelY: CGFloat = 18
    private let needleTop: CGFloat = 40
    private let needleWidth: CGFloat = 4

    var body: some View {
        Canvas { context, size in
            guard !tape.groups.isEmpty else { return }
            if layers.contains(.tape) {
                // On a copy: the tape leaves its own opacity behind.
                var tapeContext = context
                drawTape(into: &tapeContext, size: size)
            }
            if drawsGlass {
                drawLens(into: context, size: size)
            }
            if layers.contains(.marks) {
                drawReading(into: &context, size: size)
                drawNeedle(into: context, size: size)
            }
            if drawsGlass {
                drawLensEdge(into: context, size: size)
            }
        }
    }

    private var lensRect: CGRect {
        CGRect(x: 0, y: 0, width: 2 * GlassLens.halfWidth, height: GlassLensScale.size.height)
    }

    /// The glass body, over the ticks: a grey gradient, lightest at the middle.
    /// Idle drops it to 70%, as the reading, so the glass still reads as a lens.
    private func drawLens(into context: GraphicsContext, size: CGSize) {
        var lens = context
        lens.opacity = ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.reading, idle: idle)
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

    /// The thin light rim of the glass, over everything.
    private func drawLensEdge(into context: GraphicsContext, size: CGSize) {
        var edge = context
        edge.opacity = ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.reading, idle: idle)
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
        context.opacity = ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.tape, idle: idle)
        let centre = size.width / 2
        // Every tick sits at least the tape's spacing from its neighbour, so
        // the entries that can fall inside the box are no more than its half
        // width over that spacing.
        let lens = GlassLens(pitch: tape.spacing)
        let reach = Int(size.width / 2 / tape.spacing) + 2
        let lowest = max(0, Int(position.rounded(.down)) - reach)
        let highest = min(tape.groups.count - 1, Int(position.rounded(.up)) + reach)
        if lowest <= highest {
            for index in lowest...highest {
                let relative = lens.distance(entries: Double(index) - position)
                let x = centre + relative
                let weight = GlassLens.weight(offset: relative)
                // Outside the lens a tick looks as on the Slide rule. Under
                // it, record ticks grow to 20 pt and every tick brightens.
                let look = ScaleTickLook(tape.tick(at: index))
                let grown = max(look.height, recordHeightAtNeedle)
                let height = look.height + (grown - look.height) * CGFloat(weight)
                let opacity = look.opacity + (1 - look.opacity) * weight
                let rect = CGRect(x: x - tickWidth / 2, y: size.height - height, width: tickWidth, height: height)
                let kept = ScaleIdleLook.tapeReach(at: Double(x), width: Double(size.width), idle: idle)
                context.fill(Path(rect), with: .color(.white.opacity(opacity * kept)))
            }
        }
        let tapeOpacity = context.opacity
        // Labels stay outside the glass, which holds the reading alone.
        let labels = tape.labels(
            current: position,
            readingHalfWidth: max(readingHalf, GlassLens.halfWidth + ScaleTape.textGap),
            labelWidth: 0,
            placement: { lens.distance(entries: $0) }
        )
        for label in labels {
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

    /// The needle: 4 pt yolk with a soft glow. Idle drops it to 70% and halves the glow.
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
