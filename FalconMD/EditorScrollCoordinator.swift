import AppKit

/// Keep a trackpad gesture on its initial axis through its zero-delta end event
/// and momentum. Wheel ticks have no phase and are classified independently.
struct ScrollGestureRouting {
    enum Destination { case page, table }
    private(set) var destination: Destination?

    mutating func route(
        deltaX: CGFloat, deltaY: CGFloat,
        phase: NSEvent.Phase, momentumPhase: NSEvent.Phase,
        overWideTable: Bool
    ) -> Destination? {
        let discrete = phase.isEmpty && momentumPhase.isEmpty
        if discrete || phase.contains(.began) || phase.contains(.mayBegin) {
            destination = nil
        }
        if destination == nil, deltaX != 0 || deltaY != 0 {
            destination = overWideTable && abs(deltaX) > abs(deltaY) ? .table : .page
        }
        let result = destination
        if discrete || phase.contains(.cancelled)
            || momentumPhase.contains(.ended) || momentumPhase.contains(.cancelled) {
            destination = nil
        }
        return result
    }
}

/// The page uses a normal outer ScrollView; the engine only measures content.
/// Route table gestures before the engine's per-event axis test can split them.
/// No timers, synthetic inertia, or global scroll-method replacements are used.
@MainActor
final class EditorScrollCoordinator {
    private weak var textView: NSTextView?
    private weak var pageScrollView: NSScrollView?
    private weak var gestureTable: NSScrollView?
    private var routing = ScrollGestureRouting()
    private var monitor: Any?
    private var findObserver: NSObjectProtocol?

    func attach(to textView: NSTextView, session: EditorSession) {
        guard self.textView !== textView || monitor == nil else { return }
        stop()
        guard let inner = textView.enclosingScrollView,
              let page = inner.enclosingScrollView else { return }
        self.textView = textView
        pageScrollView = page
        page.usesPredominantAxisScrolling = true
        page.horizontalScrollElasticity = .none
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        findObserver = NotificationCenter.default.addObserver(
            forName: FormatAction.name("findResults", session.documentId), object: nil, queue: .main
        ) { [weak self, weak session] note in
            let count = note.userInfo?["count"] as? Int ?? 0
            guard count > 0 else { return }
            // The engine renders highlights before posting results. Reveal in the
            // outer page after SwiftUI has applied any resulting height changes.
            DispatchQueue.main.async {
                guard let session else { return }
                self?.revealFindMatch(query: session.findQuery, index: min(session.findIndex, count - 1))
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let findObserver { NotificationCenter.default.removeObserver(findObserver) }
        monitor = nil
        findObserver = nil
        textView = nil
        pageScrollView = nil
        gestureTable = nil
        routing = ScrollGestureRouting()
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let page = pageScrollView, let window = page.window,
              event.window === window, window.attachedSheet == nil else { return event }
        let point = page.convert(event.locationInWindow, from: nil)
        return route(event, at: point)
    }

    /// Point is in the outer page's coordinates. Kept separate from event-monitor
    /// filtering so routing can be verified with a real, offscreen AppKit hierarchy.
    func route(_ event: NSEvent, at point: NSPoint) -> NSEvent? {
        guard let page = pageScrollView, let window = page.window else { return event }
        let startsGesture = event.phase.contains(.began) || event.phase.contains(.mayBegin)
        let continuesTableGesture = routing.destination == .table && !startsGesture
            && (!event.phase.isEmpty || !event.momentumPhase.isEmpty)
        // End/momentum events still belong to the table if the pointer has moved
        // onto the find bar or outside the page since the gesture began.
        guard page.bounds.contains(point) || continuesTableGesture else { return event }

        let table = wideTable(at: point, in: page)
        if startsGesture {
            gestureTable = nil
        }
        let shiftWheel = event.phase.isEmpty && event.momentumPhase.isEmpty
            && event.modifierFlags.contains(.shift) && event.scrollingDeltaX == 0
        let destination = routing.route(
            deltaX: shiftWheel ? event.scrollingDeltaY : event.scrollingDeltaX,
            deltaY: shiftWheel ? 0 : event.scrollingDeltaY,
            phase: event.phase, momentumPhase: event.momentumPhase,
            overWideTable: table != nil
        )
        guard let destination else {
            // A trackpad can begin with zero deltas. Wait for its direction instead
            // of accidentally starting the page's native tracking loop over a table.
            return table == nil ? event : nil
        }
        switch destination {
        case .page:
            gestureTable = nil
            guard table != nil else { return event }
            page.scrollWheel(with: event)
        case .table:
            if event.phase.contains(.began) || (event.phase.isEmpty && event.momentumPhase.isEmpty) {
                gestureTable = nil
            }
            guard let target = gestureTable ?? table, target.window === window else { return event }
            gestureTable = target
            Self.scrollNatively(target, with: event)
        }
        return nil
    }

    private func wideTable(at point: NSPoint, in page: NSScrollView) -> NSScrollView? {
        var view = page.hitTest(page.convert(point, to: page.superview))
        while let current = view, current !== page {
            if let scroll = current as? NSScrollView,
               scroll.hasHorizontalScroller, !scroll.hasVerticalScroller,
               let document = scroll.documentView,
               document.frame.width + scroll.contentInsets.left + scroll.contentInsets.right
                > scroll.contentSize.width + 1 {
                return scroll
            }
            view = current.superview
        }
        return nil
    }

    /// Call the public NSScrollView implementation on this one table, bypassing
    /// the dependency's scrollWheel override. AppKit still owns delta scaling,
    /// elasticity, scrollers, and live-scroll notifications (offset persistence).
    /// The engine's internal table class is deliberately not named or swizzled.
    static func scrollNatively(_ scrollView: NSScrollView, with event: NSEvent) {
        let selector = #selector(NSScrollView.scrollWheel(with:))
        guard let method = class_getInstanceMethod(NSScrollView.self, selector) else { return }
        typealias ScrollImplementation = @convention(c) (NSScrollView, Selector, NSEvent) -> Void
        let implementation = unsafeBitCast(method_getImplementation(method), to: ScrollImplementation.self)
        implementation(scrollView, selector, event)
    }

    private func revealFindMatch(query: String, index: Int) {
        guard !query.isEmpty, let textView, let page = pageScrollView,
              let document = page.documentView, let layout = textView.textLayoutManager else { return }
        let text = textView.string as NSString
        var searchRange = NSRange(location: 0, length: text.length)
        var match = NSRange(location: NSNotFound, length: 0)
        for _ in 0...max(0, index) {
            match = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
            guard match.location != NSNotFound else { return }
            searchRange = NSRange(location: NSMaxRange(match), length: text.length - NSMaxRange(match))
        }
        guard let location = layout.textContentManager?.location(
            layout.documentRange.location, offsetBy: match.location
        ) else { return }
        layout.enumerateTextLayoutFragments(from: location, options: [.ensuresLayout]) { fragment in
            let rect = textView.convert(
                fragment.layoutFragmentFrame.offsetBy(
                    dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y
                ), to: document
            )
            document.scrollToVisible(rect.insetBy(dx: 0, dy: -20))
            return false
        }
    }
}
