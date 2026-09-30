import AppKit
import SwiftUI

struct TreemapView: NSViewRepresentable {
    @ObservedObject var state: AppState

    func makeNSView(context: Context) -> TreemapCanvas {
        let view = TreemapCanvas()
        view.state = state
        return view
    }

    func updateNSView(_ view: TreemapCanvas, context: Context) {
        view.state = state
        view.sync()
    }
}

/// The map itself. Layout happens on the main thread (bounded by pixel count), shading on a
/// background queue; the finished bitmap is swapped in only if nothing changed meanwhile.
final class TreemapCanvas: NSView {
    weak var state: AppState?

    private let imageLayer = CALayer()
    private let extensionLayer = CAShapeLayer()
    private let hoverLayer = CAShapeLayer()
    private let selectionLayer = CAShapeLayer()
    private let selectionGlow = CAShapeLayer()

    /// The layout that matches the bitmap currently on screen. Hit-testing and overlays only ever use
    /// this one, so what you click is what you see.
    private var layoutData: TreemapLayout?
    /// Set while a newer layout is being rendered; pointer input waits for it to land.
    private var inFlight: RenderToken?
    private var pendingRender: DispatchWorkItem?
    private static let renderQueue = DispatchQueue(label: "treemap.render", qos: .userInitiated)

    private struct Config: Equatable {
        var root: ObjectIdentifier?
        var version: Int
        var theme: String
        var style: TreemapStyle
        var labels: Bool
        var size: CGSize
        var scale: CGFloat
    }

    private var lastConfig: Config?
    private var lastSelection: FileNode?
    private var lastExtension: UInt16?
    private var hovered: FileNode?
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true

        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .linear
        imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(imageLayer)

        for shape in [extensionLayer, hoverLayer, selectionGlow, selectionLayer] {
            shape.fillColor = nil
            shape.lineCap = .round
            shape.lineJoin = .round
            shape.actions = ["path": NSNull(), "position": NSNull(), "bounds": NSNull()]
            layer?.addSublayer(shape)
        }
        extensionLayer.lineWidth = 1.6
        hoverLayer.lineWidth = 1.6
        selectionGlow.lineWidth = 7
        selectionLayer.lineWidth = 2.4
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [imageLayer, extensionLayer, hoverLayer, selectionLayer, selectionGlow] as [CALayer] {
            l.frame = bounds
        }
        CATransaction.commit()
        sync()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        sync()
    }

    // MARK: - Sync with state

    func sync() {
        guard let state else { return }
        let scale = window?.backingScaleFactor ?? 2
        let config = Config(root: state.viewRoot.map(ObjectIdentifier.init), version: state.treeVersion,
                            theme: state.theme.id, style: state.style, labels: state.showLabels,
                            size: bounds.size, scale: scale)
        let themeColors = state.theme
        layer?.backgroundColor = themeColors.well.cgColor
        selectionLayer.strokeColor = themeColors.accent.cgColor
        selectionGlow.strokeColor = CGColor(gray: 1, alpha: themeColors.isDark ? 0.35 : 0.75)
        hoverLayer.strokeColor = themeColors.ink.cgColor.copy(alpha: 0.85)
        extensionLayer.strokeColor = CGColor(gray: 1, alpha: 0.95)

        if config != lastConfig {
            let sizeOnly = lastConfig.map {
                var c = $0
                c.size = config.size
                return c == config
            } ?? false
            lastConfig = config
            relayout(debounced: sizeOnly)
        }
        if state.selection !== lastSelection {
            lastSelection = state.selection
            updateSelectionOverlay()
        }
        if state.selectedExtension != lastExtension {
            lastExtension = state.selectedExtension
            updateExtensionOverlay()
        }
    }

    private func relayout(debounced: Bool) {
        pendingRender?.cancel()
        if debounced {
            let work = DispatchWorkItem { [weak self] in self?.rebuild() }
            pendingRender = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        } else {
            rebuild()
        }
    }

    private func rebuild() {
        inFlight?.cancel()
        inFlight = nil
        guard let state, let root = state.viewRoot, bounds.width >= 4, bounds.height >= 4 else {
            layoutData = nil
            imageLayer.contents = nil
            refreshOverlays()
            return
        }
        let scale = window?.backingScaleFactor ?? 2
        let pw = Int(bounds.width * scale), ph = Int(bounds.height * scale)
        let layout = TreemapLayout.build(root: root, pixelWidth: pw, pixelHeight: ph, scale: scale,
                                         style: state.style) { [unowned state] in state.color(for: $0) }
        let job = makeJob(layout, state: state, scale: scale)

        let token = RenderToken()
        inFlight = token
        clearHover()
        TreemapCanvas.renderQueue.async { [weak self] in
            let image = TreemapRenderer.render(job, isCancelled: token.isCancelled)
            DispatchQueue.main.async {
                guard let self, self.inFlight === token, !token.isCancelled() else { return }
                self.inFlight = nil
                guard let image else { return }
                // Bitmap and geometry go live together.
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.imageLayer.contents = image
                self.imageLayer.contentsScale = scale
                self.layoutData = layout
                self.refreshOverlays()
                CATransaction.commit()
            }
        }
    }

    private func refreshOverlays() {
        updateSelectionOverlay()
        updateExtensionOverlay()
        updateHoverOverlay()
    }

    private func clearHover() {
        guard hovered != nil else { return }
        hovered = nil
        state?.hover.node = nil
        hoverLayer.path = nil
    }

    private func makeJob(_ layout: TreemapLayout, state: AppState, scale: CGFloat) -> TreemapRenderJob {
        var outlines: [TreemapRenderJob.Outline] = []
        var labels: [TreemapRenderJob.Label] = []
        let maxOutlineDepth = state.style == .sketch ? 2 : 1
        for (i, item) in layout.items.enumerated() where item.depth >= 1 && item.depth <= maxOutlineDepth {
            guard item.rect.width >= 5 * scale, item.rect.height >= 5 * scale else { continue }
            if item.node.isDirectory || item.depth == 1 {
                outlines.append(.init(rect: item.rect, depth: Int(item.depth), seed: UInt64(i) &* 2_654_435_761))
            }
        }
        if state.showLabels {
            for (i, item) in layout.items.enumerated() where item.depth == 1 || (item.depth == 2 && item.node.isDirectory) {
                guard item.rect.width >= 80 * scale, item.rect.height >= 30 * scale else { continue }
                if item.depth == 2 && (item.rect.width < 120 * scale || item.rect.height < 60 * scale) { continue }
                let node = item.node
                labels.append(.init(rect: item.rect,
                                    title: node.isDirectory ? node.name + "/" : node.name,
                                    subtitle: Format.bytes(node.size),
                                    seed: UInt64(i) &+ 99,
                                    prominent: item.depth == 1))
            }
        }
        let theme = state.theme
        return TreemapRenderJob(width: layout.pixelWidth, height: layout.pixelHeight, scale: scale, style: state.style,
                                leaves: layout.leaves, outlines: outlines, labels: labels,
                                background: theme.well, ink: state.style == .sketch ? theme.ink : Palette.slate,
                                tagPaper: theme.paper, isDark: theme.isDark)
    }

    // MARK: - Overlays

    /// Layout pixels → view points. Uses the displayed bitmap's actual stretch, so it stays right
    /// while a resize is still waiting for its re-render.
    private func toView(_ r: CGRect, _ layout: TreemapLayout) -> CGRect {
        let sx = bounds.width / CGFloat(layout.pixelWidth), sy = bounds.height / CGFloat(layout.pixelHeight)
        return CGRect(x: r.minX * sx, y: r.minY * sy, width: r.width * sx, height: r.height * sy)
    }

    private func viewRect(ofItem index: Int) -> CGRect {
        guard let layout = layoutData else { return .zero }
        return toView(layout.item(index).rect, layout)
    }

    private func updateSelectionOverlay() {
        guard let layout = layoutData, let sel = state?.selection, let idx = layout.index(of: sel) else {
            selectionLayer.path = nil
            selectionGlow.path = nil
            return
        }
        let full = viewRect(ofItem: idx)
        // Slivers too thin to inset still get marked, just without the inset.
        let r = full.width > 4 && full.height > 4 ? full.insetBy(dx: 1.5, dy: 1.5) : full
        let path = Sketch.roughRect(r, roughness: 1.6, seed: UInt64(idx) &+ 17)
        selectionGlow.path = path
        selectionLayer.path = path

        // A little "boing" so the eye finds it.
        let pulse = CABasicAnimation(keyPath: "lineWidth")
        pulse.fromValue = 6
        pulse.toValue = 2.4
        pulse.duration = 0.35
        pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        selectionLayer.add(pulse, forKey: "pulse")
    }

    private func updateExtensionOverlay() {
        guard let layout = layoutData, let ext = state?.selectedExtension else {
            extensionLayer.path = nil
            return
        }
        let path = CGMutablePath()
        for leaf in layout.leaves where leaf.isFile && leaf.extID == ext {
            let r = toView(CGRect(x: CGFloat(leaf.x0), y: CGFloat(leaf.y0),
                                  width: CGFloat(leaf.x1 - leaf.x0), height: CGFloat(leaf.y1 - leaf.y0)), layout)
            if r.width >= 2 && r.height >= 2 {
                path.addRect(r.insetBy(dx: 0.8, dy: 0.8))
            } else {
                path.addRect(r)
            }
        }
        extensionLayer.path = path
    }

    private func updateHoverOverlay() {
        guard let layout = layoutData, let node = hovered, node !== state?.selection, let idx = layout.index(of: node) else {
            hoverLayer.path = nil
            return
        }
        let r = viewRect(ofItem: idx).insetBy(dx: 1, dy: 1)
        hoverLayer.path = r.width > 0 && r.height > 0 ? Sketch.roughRect(r, roughness: 1.2, seed: UInt64(idx), passes: 1) : nil
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    private func node(at event: NSEvent) -> FileNode? {
        // Mid-transition the picture on screen is about to change; don't guess.
        guard inFlight == nil, let layout = layoutData, bounds.width > 0, bounds.height > 0 else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        let px = CGPoint(x: p.x * CGFloat(layout.pixelWidth) / bounds.width,
                         y: p.y * CGFloat(layout.pixelHeight) / bounds.height)
        return layout.hitTest(px).map { layout.item($0).node }
    }

    override func mouseMoved(with event: NSEvent) {
        let n = node(at: event)
        guard n !== hovered else { return }
        hovered = n
        state?.hover.node = n
        updateHoverOverlay()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        state?.hover.node = nil
        updateHoverOverlay()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let n = node(at: event) else { return }
        if event.clickCount >= 2 {
            state?.zoom(into: n)
        } else {
            state?.select(n)
        }
        updateHoverOverlay()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let state, let n = node(at: event) else { return nil }
        state.select(n)
        return state.contextMenu(for: n)
    }
}

/// Thread-safe "stop working on this frame" flag shared between the main thread and the renderer.
final class RenderToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func isCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}
