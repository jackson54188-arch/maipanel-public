import SwiftUI
import UIKit

/// Ring geometry copied from the cabinet panel. The complete app maps the 34
/// touch zones onto this ring; the shell only draws it.
enum Ring {
    /// Squarish cabinet blocks, pushed out until the ring almost touches the
    /// screen edge on the left and right.
    static let innerScale: CGFloat = 1.02
    static let outerScale: CGFloat = 1.35
    /// Half the angular width of one button.
    static let halfSpan: CGFloat = 8.25 * CGFloat.pi / 180
    /// Clearance between a button and the filler piece beside it.
    static let gap: CGFloat = 2.0 * CGFloat.pi / 180
    /// Button centres follow the cabinet's A1...A8 angles: A1 top-right,
    /// clockwise.
    static let angles: [CGFloat] = [-67.1, -22.1, 22.2, 67.1, 112.9, 157.8, -157.8, -112.9]
        .map { $0 * CGFloat.pi / 180 }

    static func innerRadius(_ panelRadius: CGFloat) -> CGFloat { panelRadius * innerScale }
    static func outerRadius(_ panelRadius: CGFloat) -> CGFloat { panelRadius * outerScale }

    /// Slot between button `index` and the next one, shrunk by `gap` on both
    /// sides so the filler piece does not touch either button.
    static func fillerSpan(_ index: Int) -> (center: CGFloat, half: CGFloat) {
        let next = (index + 1) % angles.count
        var delta = angles[next] - angles[index]
        while delta <= 0 { delta += 2 * .pi }
        return (angles[index] + delta / 2, delta / 2 - halfSpan - gap)
    }
}

@MainActor
final class ShellModel: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var hasVideo = false
    @Published private(set) var slot: Int

    private static let slotKey = "panelSlot"
    private let server = ShellServer()

    init() {
        slot = UserDefaults.standard.integer(forKey: Self.slotKey) == 2 ? 2 : 1
        server.onConnected = { [weak self] in
            Task { @MainActor in self?.connected = true }
        }
        server.onDisconnected = { [weak self] in
            Task { @MainActor in
                self?.connected = false
                self?.hasVideo = false
                VideoSink.shared.clear()
            }
        }
        server.onVideo = { data in
            VideoSink.shared.push(data)
        }
        server.onVideoStarted = { [weak self] in
            Task { @MainActor in self?.hasVideo = true }
        }
        server.start(port: panelPort(for: slot), slot: slot)
    }

    /// Switch between the two panels; the listener moves to the matching port
    /// so the PC's USB forward pairs with it again.
    func setSlot(_ next: Int) {
        let next = next == 2 ? 2 : 1
        guard next != slot else { return }
        slot = next
        UserDefaults.standard.set(slot, forKey: Self.slotKey)
        connected = false
        hasVideo = false
        VideoSink.shared.clear()
        server.start(port: panelPort(for: slot), slot: slot)
    }
}

struct ShellView: View {
    @StateObject private var model = ShellModel()

    /// The game is a 9:16 portrait picture: a menu strip on top and the play
    /// disc pinned to the bottom edge.
    private let gameAspect: CGFloat = 9.0 / 16.0
    /// Measured from the real screen: circle radius 28.15% of the height,
    /// centre 71.9% down.
    private let gameRadius: CGFloat = 0.2815
    private let gameCenterY: CGFloat = 0.719
    /// Ring outer radius plus the picture above the circle centre, in disc
    /// radii; keeps the mirrored frame from running off the top edge.
    private var frameDepth: CGFloat { Ring.outerScale + gameCenterY / gameRadius }
    private let screenMargin: CGFloat = 6
    /// 53.98 x 85.60 mm, same proportions as the cabinet's card reader.
    private let cardAspect: CGFloat = 53.98 / 85.60
    private let backingAspect: CGFloat = 0.563
    /// The pink frame around the top picture, with an even gap inside it.
    private let mirrorBorderWidth: CGFloat = 3
    private let mirrorBorderGap: CGFloat = 2
    private let frameColor = Color(red: 1.0, green: 0.41, blue: 0.706)

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let gameWidth = min(size.width, size.height * gameAspect)
            // The ring is the widest element, so it decides the disc radius;
            // its bottom edge sits screenMargin above the bottom.
            let radius = min(
                gameWidth * 0.485,
                (size.width / 2 - screenMargin - 18) / Ring.outerScale,
                (size.height - screenMargin - 2) / frameDepth
            )
            let ringOuter = radius * Ring.outerScale
            let center = CGPoint(x: size.width / 2, y: size.height - screenMargin - ringOuter)
            let side = sideLayout(size: size, center: center, ringOuter: ringOuter, slot: model.slot)

            ZStack {
                Color.black.ignoresSafeArea()

                // Sits under the video layers: it only shows while the disc
                // has no frame to paint.
                Text("NO SIGNAL")
                    .font(.system(size: max(11, radius * 0.05), weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.22))
                    .position(center)

                mirror(center: center, radius: radius)

                RingView(center: center, panelRadius: radius)
                    .frame(width: size.width, height: size.height)

                billboard(width: size.width, height: size.height)

                readerCard(side)
                triangleKey(side)

                slotChip(side)
            }
            .overlay(alignment: .topLeading) {
                statusView.padding(14)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    private var statusView: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.connected ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
                Text(statusLine)
            }
            Text(statusHint)
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.9))
        .allowsHitTesting(false)
    }

    private var statusLine: String {
        let slotLabel = model.slot == 2 ? "2P" : "1P"
        let pc = model.connected ? "PC 已连接" : "PC 未连接"
        return "\(slotLabel) · \(pc) · 端口 \(panelPort(for: model.slot))"
    }

    private var statusHint: String {
        if !model.connected { return "等待电脑连接…" }
        return model.hasVideo ? "正在接收串流" : "等待视频帧…"
    }

    /// The cabinet's top billboard becomes a full-width strip hugging the
    /// tablet's top edge, 7% of the screen tall, only its bottom corners
    /// rounded.
    private func billboard(width: CGFloat, height: CGFloat) -> some View {
        let barHeight = max(4, height * 0.07)
        let corner = min(barHeight * 0.45, 18)
        return BottomRoundedBar(corner: corner)
            .fill(Color.white.opacity(0.06))
            .frame(width: width, height: barHeight)
            .position(x: width / 2, y: barHeight / 2)
            .allowsHitTesting(false)
    }

    /// The top strip stretched to the cabinet's width plus the round play
    /// area under the touch disc. Both come from the same 9:16 frame at
    /// different scales.
    private struct MirrorLayout {
        var stroke: CGRect
        var bounds: CGRect
        var strip: CGRect
        var video: CGRect
        var corner: CGFloat
        var innerCorner: CGFloat
    }

    private func mirrorLayout(center: CGPoint, radius: CGFloat) -> MirrorLayout {
        let video = videoRect(center: center, radius: radius)
        // Key 2 sits at 22.1 degrees above the horizontal and is half a span
        // wide, so its upper outer corner is halfSpan + 22.1 away from +x.
        let halfWidth = Ring.outerRadius(radius) * cos(Ring.halfSpan + 22.1 * .pi / 180)
        let inset = mirrorBorderWidth + mirrorBorderGap
        let stripWidth = halfWidth * 2 - inset * 2
        let stroke = CGRect(
            x: center.x - halfWidth,
            y: video.minY - inset,
            width: halfWidth * 2,
            height: stripWidth * MirrorImageView.stripAspect + inset * 2
        )
        let strip = stroke.insetBy(dx: inset, dy: inset)
        let bounds = video.union(stroke)
        let corner = max(10, radius * 0.06)
        return MirrorLayout(
            stroke: stroke,
            bounds: bounds,
            strip: strip.offsetBy(dx: -bounds.minX, dy: -bounds.minY),
            video: video.offsetBy(dx: -bounds.minX, dy: -bounds.minY),
            corner: corner,
            innerCorner: max(0, corner - inset)
        )
    }

    private func mirror(center: CGPoint, radius: CGFloat) -> some View {
        let layout = mirrorLayout(center: center, radius: radius)
        return ZStack {
            MirrorView(strip: layout.strip, video: layout.video, corner: layout.innerCorner)
                .frame(width: layout.bounds.width, height: layout.bounds.height)
                .position(x: layout.bounds.midX, y: layout.bounds.midY)
            RoundedRectangle(cornerRadius: layout.corner, style: .continuous)
                .strokeBorder(frameColor, lineWidth: mirrorBorderWidth)
                .frame(width: layout.stroke.width, height: layout.stroke.height)
                .position(x: layout.stroke.midX, y: layout.stroke.midY)
        }
        .allowsHitTesting(false)
    }

    /// The mirrored 9:16 frame placed so the game's circle lands exactly under
    /// the touch disc.
    private func videoRect(center: CGPoint, radius: CGFloat) -> CGRect {
        let height = radius / gameRadius
        let width = height * gameAspect
        return CGRect(
            x: center.x - 0.4984 * width,
            y: center.y - gameCenterY * height,
            width: width,
            height: height
        )
    }

    /// Cabinet parts that flank the disc: the card reader at the upper outer
    /// corner, the triangle key under it and the slot chip in the side bezel.
    /// 2P is the mirror image.
    private struct SideLayout {
        var column: CGRect
        var card: CGRect
        var backing: CGRect
        var triangle: CGRect
    }

    private func sideLayout(size: CGSize, center: CGPoint, ringOuter: CGFloat, slot: Int) -> SideLayout {
        let is2P = slot == 2
        let side: CGFloat = is2P ? -1 : 1
        let margin: CGFloat = 8
        let columnWidth = max(70, ringOuter * 0.292)
        let columnHeight = max(44, ringOuter * 0.135)
        let preferredX = is2P
            ? center.x + ringOuter * 0.96 - columnWidth
            : center.x - ringOuter * 0.96
        let columnX = min(max(preferredX, margin),
                          max(margin, size.width - margin - columnWidth))
        let columnTop = center.y - ringOuter * 1.145
        let column = CGRect(x: columnX, y: columnTop, width: columnWidth, height: columnHeight)

        let cardWidth = ringOuter * 0.193
        let cardHeight = cardWidth / cardAspect
        let cardCenter = CGPoint(
            x: center.x + side * ringOuter * 0.891,
            y: center.y - ringOuter * 0.894
        )
        let card = CGRect(
            x: cardCenter.x - cardWidth / 2,
            y: cardCenter.y - cardHeight / 2,
            width: cardWidth,
            height: cardHeight
        )
        let backingWidth = ringOuter * 0.257
        let backingHeight = backingWidth / backingAspect
        let backing = CGRect(
            x: cardCenter.x - backingWidth / 2,
            y: card.maxY + ringOuter * 0.025 - backingHeight,
            width: backingWidth,
            height: backingHeight
        )
        let triangleWidth = ringOuter * 0.124
        let triangleHeight = ringOuter * 0.139
        let triangle = CGRect(
            x: center.x + side * ringOuter * 0.945 - triangleWidth / 2,
            y: center.y - ringOuter * 0.596 - triangleHeight / 2,
            width: triangleWidth,
            height: triangleHeight
        )
        return SideLayout(column: column, card: card, backing: backing, triangle: triangle)
    }

    /// The card reader as a blank white card on its dark plate. The full app
    /// draws the aime mark and follows the reader lamp; the shell has neither.
    private func readerCard(_ layout: SideLayout) -> some View {
        let card = layout.card
        let corner = max(4, card.width * 0.09)
        let backingCorner = max(6, layout.backing.width * 0.09)
        return ZStack {
            RoundedRectangle(cornerRadius: backingCorner, style: .continuous)
                .fill(Color(white: 0.15))
                .frame(width: layout.backing.width, height: layout.backing.height)
                .position(x: layout.backing.midX, y: layout.backing.midY)
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.white)
                .frame(width: card.width, height: card.height)
                .position(x: card.midX, y: card.midY)
            RoundedRectangle(cornerRadius: corner * 0.6, style: .continuous)
                .fill(Color(white: 0.12))
                .frame(width: card.width * 0.62, height: card.height * 0.10)
                .position(x: card.midX, y: card.maxY - card.height * 0.20)
            Text("CARD")
                .font(.system(size: max(8, card.width * 0.18), weight: .bold, design: .monospaced))
                .foregroundStyle(Color(white: 0.35))
                .position(x: card.midX, y: card.minY + card.height * 0.42)
        }
        .allowsHitTesting(false)
    }

    /// The cabinet's triangle key; 2P is the mirrored, red shape.
    private func triangleKey(_ layout: SideLayout) -> some View {
        let rect = layout.triangle
        let pointsRight = model.slot == 2
        return TriangleShape(pointsRight: pointsRight)
            .fill(pointsRight
                  ? Color(red: 1.0, green: 0.353, blue: 0.373)
                  : Color(red: 0.388, green: 0.6, blue: 1.0))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    /// One chip in the bezel; tapping it moves this panel to the other slot.
    private func slotChip(_ layout: SideLayout) -> some View {
        Button {
            model.setSlot(model.slot == 2 ? 1 : 2)
        } label: {
            Text(model.slot == 2 ? "2P" : "1P")
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .buttonStyle(.plain)
        .frame(width: layout.column.width, height: layout.column.height)
        .position(x: layout.column.midX, y: layout.column.midY)
    }
}

/// The eight cabinet ring buttons plus the filler pieces between them.
/// Drawing only; the complete app also resolves touches against this ring.
struct RingView: UIViewRepresentable {
    let center: CGPoint
    let panelRadius: CGFloat

    func makeUIView(context: Context) -> PadRingView {
        let view = PadRingView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        view.update(center: center, panelRadius: panelRadius)
        return view
    }

    func updateUIView(_ view: PadRingView, context: Context) {
        view.update(center: center, panelRadius: panelRadius)
    }
}

final class PadRingView: UIView {
    private var padCenter: CGPoint = .zero
    private var panelRadius: CGFloat = 0

    private var innerRadius: CGFloat { Ring.innerRadius(panelRadius) }
    private var outerRadius: CGFloat { Ring.outerRadius(panelRadius) }
    private var thickness: CGFloat { outerRadius - innerRadius }

    func update(center: CGPoint, panelRadius: CGFloat) {
        padCenter = center
        self.panelRadius = panelRadius
        setNeedsDisplay()
    }

    private func point(radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(x: padCenter.x + cos(angle) * radius, y: padCenter.y + sin(angle) * radius)
    }

    /// Sampled instead of `addArc` so the sweep direction never depends on
    /// the flipped UIKit coordinate system; the spans here are small either
    /// way.
    private func addArc(to path: UIBezierPath, radius: CGFloat, from start: CGFloat, to end: CGFloat) {
        let steps = 16
        for step in 0...steps {
            let angle = start + (end - start) * CGFloat(step) / CGFloat(steps)
            let next = point(radius: radius, angle: angle)
            if path.isEmpty {
                path.move(to: next)
            } else {
                path.addLine(to: next)
            }
        }
    }

    private func segmentPath(center: CGFloat, half: CGFloat, grow: CGFloat = 0) -> UIBezierPath {
        let path = UIBezierPath()
        addArc(to: path, radius: innerRadius, from: center - half, to: center + half)
        addArc(to: path, radius: outerRadius + grow, from: center + half, to: center - half)
        path.close()
        return path
    }

    private func buttonPath(_ index: Int, grow: CGFloat = 0, anglePad: CGFloat = 0) -> UIBezierPath {
        segmentPath(center: Ring.angles[index], half: Ring.halfSpan + anglePad, grow: grow)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), panelRadius > 0 else { return }

        // The gaps between buttons are cabinet ring, not buttons: same arc
        // trapezoids but flat and dimmer.
        for index in Ring.angles.indices {
            let slot = Ring.fillerSpan(index)
            guard slot.half > 0 else { continue }
            let path = segmentPath(center: slot.center, half: slot.half)
            context.setFillColor(UIColor.white.withAlphaComponent(0.18).cgColor)
            path.fill()
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.42).cgColor)
            context.setLineWidth(max(1, thickness * 0.05))
            path.stroke()
        }

        for index in 0..<8 {
            // Backlight halo: four arc segments of falling alpha growing
            // outward and sideways, so the glow follows the segment shape.
            for step in stride(from: 4, through: 1, by: -1) {
                let grow = thickness * 0.35 * CGFloat(step) / 4
                let pad = Ring.halfSpan * 0.12 * CGFloat(step) / 4
                let alpha = 0.04 * CGFloat(5 - step) / 4
                context.setFillColor(UIColor.white.withAlphaComponent(alpha).cgColor)
                buttonPath(index, grow: grow, anglePad: pad).fill()
            }
            // Frosted acrylic body: white, semi-transparent when idle.
            let path = buttonPath(index)
            context.setFillColor(UIColor.white.withAlphaComponent(0.30).cgColor)
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.60).cgColor)
            context.setLineWidth(max(1, thickness * 0.07))
            path.fill()
            path.stroke()
        }
    }
}

private struct TriangleShape: Shape {
    let pointsRight: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointsRight {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

/// Rectangle with rounded bottom corners only, for the billboard strip that
/// hangs off the top edge.
private struct BottomRoundedBar: Shape {
    let corner: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(corner, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}
