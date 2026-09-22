import AppKit

/// Invisible resize handles for the borderless window: 8 edge/corner strips.
/// No system API exists for borderless live-resize, so each strip drives
/// `setFrame` by hand. Laid out above the content but transparent to clicks
/// outside the strips, so right-click/move still reach the content below.
final class ResizeHandlesView: NSView {
    struct Edge: OptionSet {
        let rawValue: Int
        static let left = Edge(rawValue: 1 << 0)
        static let right = Edge(rawValue: 1 << 1)
        static let top = Edge(rawValue: 1 << 2)
        static let bottom = Edge(rawValue: 1 << 3)
    }

    static let handleWidth: CGFloat = 8

    private var handles: [(view: NSView, edges: Edge)] = []
    private var dragStartFrame = NSRect.zero
    private var dragStartMouse = NSPoint.zero
    private var dragEdges: Edge = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        let combos: [(Edge, NSCursor)] = [
            ([.left], .frameResize(position: .left, directions: .all)),
            ([.right], .frameResize(position: .right, directions: .all)),
            ([.top], .frameResize(position: .top, directions: .all)),
            ([.bottom], .frameResize(position: .bottom, directions: .all)),
            ([.left, .top], .frameResize(position: .topLeft, directions: .all)),
            ([.right, .top], .frameResize(position: .topRight, directions: .all)),
            ([.left, .bottom], .frameResize(position: .bottomLeft, directions: .all)),
            ([.right, .bottom], .frameResize(position: .bottomRight, directions: .all)),
        ]
        for (edges, cursor) in combos {
            let view = HandleView(edges: edges, cursor: cursor, owner: self)
            addSubview(view)
            handles.append((view, edges))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Only the 8 strips claim events; clicks elsewhere fall through to the
    /// clock content below (context menu, drag-to-move).
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        return view === self ? nil : view
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        let t = Self.handleWidth
        for (view, edges) in handles {
            view.frame = frame(for: edges, in: NSSize(width: w, height: h), t: t)
        }
    }

    private func frame(for edges: Edge, in size: NSSize, t: CGFloat) -> NSRect {
        let w = size.width
        let h = size.height
        switch (edges.contains(.left), edges.contains(.right), edges.contains(.top), edges.contains(.bottom)) {
        case (true, false, false, false):   return NSRect(x: 0, y: t, width: t, height: h - 2 * t) // left
        case (false, true, false, false):   return NSRect(x: w - t, y: t, width: t, height: h - 2 * t) // right
        case (false, false, true, false):   return NSRect(x: t, y: h - t, width: w - 2 * t, height: t) // top
        case (false, false, false, true):   return NSRect(x: t, y: 0, width: w - 2 * t, height: t) // bottom
        case (true, false, true, false):    return NSRect(x: 0, y: h - t, width: t, height: t) // top-left
        case (false, true, true, false):    return NSRect(x: w - t, y: h - t, width: t, height: t) // top-right
        case (true, false, false, true):    return NSRect(x: 0, y: 0, width: t, height: t) // bottom-left
        case (false, true, false, true):    return NSRect(x: w - t, y: 0, width: t, height: t) // bottom-right
        default:                            return .zero
        }
    }

    // MARK: Resize drag (driven by HandleView)

    fileprivate func beginDrag(edges: Edge, event: NSEvent) {
        guard let window else { return }
        dragEdges = edges
        dragStartFrame = window.frame
        dragStartMouse = NSEvent.mouseLocation
    }

    fileprivate func continueDrag(event: NSEvent) {
        guard let window, !dragEdges.isEmpty else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - dragStartMouse.x
        let dy = mouse.y - dragStartMouse.y
        var frame = dragStartFrame

        let minSize = ClockPanel.minSize
        let maxSize = ClockPanel.maxSize

        if dragEdges.contains(.left) {
            var newWidth = dragStartFrame.width - dx
            newWidth = min(max(newWidth, minSize.width), maxSize.width)
            frame.origin.x = dragStartFrame.maxX - newWidth
            frame.size.width = newWidth
        }
        if dragEdges.contains(.right) {
            var newWidth = dragStartFrame.width + dx
            newWidth = min(max(newWidth, minSize.width), maxSize.width)
            frame.size.width = newWidth
        }
        if dragEdges.contains(.top) {
            var newHeight = dragStartFrame.height + dy
            newHeight = min(max(newHeight, minSize.height), maxSize.height)
            frame.size.height = newHeight
        }
        if dragEdges.contains(.bottom) {
            var newHeight = dragStartFrame.height - dy
            newHeight = min(max(newHeight, minSize.height), maxSize.height)
            frame.origin.y = dragStartFrame.maxY - newHeight
            frame.size.height = newHeight
        }

        window.setFrame(frame, display: true)
    }

    fileprivate func endDrag() {
        dragEdges = []
        (window as? ClockPanel)?.noteResized()
    }
}

/// One invisible strip; only claims left-button drags (right-click falls
/// through to the content's context menu).
private final class HandleView: NSView {
    let edges: ResizeHandlesView.Edge
    let cursor: NSCursor
    weak var owner: ResizeHandlesView?

    init(edges: ResizeHandlesView.Edge, cursor: NSCursor, owner: ResizeHandlesView) {
        self.edges = edges
        self.cursor = cursor
        self.owner = owner
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        owner?.beginDrag(edges: edges, event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        owner?.continueDrag(event: event)
    }

    override func mouseUp(with event: NSEvent) {
        owner?.endDrag()
    }

    override func rightMouseDown(with event: NSEvent) {
        // Let the context menu pass through to the content underneath.
        superview?.rightMouseDown(with: event)
    }
}
