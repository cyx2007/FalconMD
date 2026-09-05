import AppKit
import SwiftUI
import Testing
@testable import FalconMD

@MainActor
struct DocumentDropTests {
    @Test func acceptsDocumentBatchAndPreservesUnicodeNames() throws {
        let fixture = try DropFixture()
        defer { fixture.remove() }
        let urls = try ["笔记 (final).MD", "second.markdown", "third.mdown", "fourth.mkd", "plain.txt"].map {
            try fixture.file($0)
        }
        fixture.pasteboard.writeObjects(urls.map { $0 as NSURL })
        #expect(DocumentOpening.droppedDocuments(from: fixture.pasteboard) == urls)
    }

    @Test func rejectsFoldersImagesAndMixedBatches() throws {
        let fixture = try DropFixture()
        defer { fixture.remove() }
        let markdown = try fixture.file("note.md")
        let image = try fixture.file("image.png")
        let folder = fixture.root.appendingPathComponent("folder.md", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for urls in [[image], [folder], [markdown, image], [markdown, folder]] {
            fixture.pasteboard.clearContents()
            fixture.pasteboard.writeObjects(urls.map { $0 as NSURL })
            #expect(DocumentOpening.droppedDocuments(from: fixture.pasteboard).isEmpty)
        }
    }

    @Test func pastedTextAndWebURLsAreNotDocuments() throws {
        let fixture = try DropFixture()
        defer { fixture.remove() }
        fixture.pasteboard.setString("/tmp/note.md", forType: .string)
        #expect(DocumentOpening.droppedDocuments(from: fixture.pasteboard).isEmpty)
        #expect(!DocumentOpening.isSupportedDocument(URL(string: "https://example.com/note.md")!))
    }

    @Test func rejectsMissingFilesAndDeduplicatesFiles() throws {
        let fixture = try DropFixture()
        defer { fixture.remove() }
        #expect(!DocumentOpening.isSupportedDocument(fixture.root.appendingPathComponent("missing.md")))
        let url = try fixture.file("note.md")
        fixture.pasteboard.writeObjects([url as NSURL, url as NSURL])
        #expect(DocumentOpening.droppedDocuments(from: fixture.pasteboard) == [url])
    }

    @Test func textViewDropOpensDocumentsWithoutReplacingUnsavedText() throws {
        let fixture = try DropFixture()
        defer { fixture.remove() }
        let url = try fixture.file("新文档.md")
        fixture.pasteboard.writeObjects([url as NSURL])
        let view = NSTextView()
        view.string = "Unsaved writing"
        view.setSelectedRange(NSRange(location: 0, length: 7))
        var opened: [URL] = []
        var targeted = false
        var imageCalls = 0
        let info = TestDraggingInfo(pasteboard: fixture.pasteboard)
        EditorDropHook.attach(to: view, onDocumentTargetChanged: { targeted = $0 }, openDocuments: { opened = $0 }) {
            _ in imageCalls += 1; return nil
        }
        #expect(view.draggingEntered(info) == .copy)
        #expect(targeted)
        // SwiftUI redraws when the highlight changes; refreshing the callbacks
        // must preserve the active drag session's acceptance state.
        EditorDropHook.attach(to: view, onDocumentTargetChanged: { targeted = $0 }, openDocuments: { opened = $0 }) {
            _ in imageCalls += 1; return nil
        }
        #expect(view.draggingUpdated(info) == .copy)
        #expect(view.prepareForDragOperation(info))
        #expect(view.performDragOperation(info))
        #expect(opened == [url])
        #expect(view.string == "Unsaved writing")
        #expect(imageCalls == 0)
        #expect(!targeted)
    }

    @Test func unsupportedFileDropCannotInsertAPath() throws {
        let fixture = try DropFixture()
        defer { fixture.remove() }
        let url = try fixture.file("unsupported.pdf")
        fixture.pasteboard.writeObjects([url as NSURL])
        let view = NSTextView()
        view.string = "Keep this text"
        let info = TestDraggingInfo(pasteboard: fixture.pasteboard)
        EditorDropHook.attach(to: view, openDocuments: { _ in Issue.record("Unexpected document open") }) { _ in
            Issue.record("Unexpected image import"); return nil
        }
        #expect(view.draggingEntered(info).isEmpty)
        #expect(view.draggingUpdated(info).isEmpty)
        #expect(!view.prepareForDragOperation(info))
        #expect(!view.performDragOperation(info))
        #expect(view.string == "Keep this text")
    }

    @Test func imageDropStillInsertsMarkdown() throws {
        let fixture = try DropFixture()
        defer { fixture.remove() }
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let image = fixture.root.appendingPathComponent("image.png")
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: image)
        fixture.pasteboard.writeObjects([image as NSURL])
        let view = NSTextView()
        view.string = "Before"
        view.setSelectedRange(NSRange(location: 6, length: 0))
        let info = TestDraggingInfo(pasteboard: fixture.pasteboard)
        EditorDropHook.attach(to: view, openDocuments: { _ in Issue.record("Image opened as a document") }) { _ in
            "![](note.assets/image.png)"
        }
        #expect(view.draggingEntered(info) == .copy)
        #expect(view.performDragOperation(info))
        #expect(view.string == "Before\n![](note.assets/image.png)")
    }
}

@MainActor
private final class TestDraggingInfo: NSObject, @preconcurrency NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    init(pasteboard: NSPasteboard) { draggingPasteboard = pasteboard }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?,
        classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
}

@MainActor
struct NativeScrollTests {
    @Test func nestedTableAndPageReceiveOnlyTheirOwnAxis() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let page = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        page.hasVerticalScroller = true
        let pageContent = FlippedTestView(frame: NSRect(x: 0, y: 0, width: 400, height: 2000))
        window.contentView = page
        page.documentView = pageContent
        let inner = NSScrollView(frame: pageContent.bounds)
        pageContent.addSubview(inner)
        let container = FlippedTestView(frame: pageContent.bounds)
        inner.documentView = container
        let textView = NSTextView(frame: container.bounds)
        container.addSubview(textView)
        let table = InterceptingScrollView(frame: NSRect(x: 0, y: 40, width: 380, height: 150))
        table.hasHorizontalScroller = true
        table.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1400, height: 130))
        container.addSubview(table)
        page.tile()
        inner.tile()
        table.tile()
        let coordinator = EditorScrollCoordinator()
        coordinator.attach(to: textView, session: EditorSession())
        defer { coordinator.stop() }
        let horizontal = try #require(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
            wheel1: 0, wheel2: -100, wheel3: 0
        ).flatMap(NSEvent.init(cgEvent:)))
        #expect(coordinator.route(horizontal, at: NSPoint(x: 200, y: 100)) == nil)
        try await Task.sleep(for: .milliseconds(100))
        var tableX = table.contentView.bounds.origin.x
        #expect(tableX > 0)
        #expect(page.contentView.bounds.origin.y == 0)
        #expect(!table.receivedOverride)
        let shiftedCGEvent = try #require(CGEvent(
            scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
            wheel1: -3, wheel2: 0, wheel3: 0
        ))
        shiftedCGEvent.flags = .maskShift
        let shifted = try #require(NSEvent(cgEvent: shiftedCGEvent))
        #expect(coordinator.route(shifted, at: NSPoint(x: 200, y: 100)) == nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(table.contentView.bounds.origin.x > tableX)
        #expect(page.contentView.bounds.origin.y == 0)
        tableX = table.contentView.bounds.origin.x
        let vertical = try #require(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
            wheel1: -100, wheel2: 0, wheel3: 0
        ).flatMap(NSEvent.init(cgEvent:)))
        #expect(coordinator.route(vertical, at: NSPoint(x: 200, y: 100)) == nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(page.contentView.bounds.origin.y > 0)
        #expect(table.contentView.bounds.origin.x == tableX)
    }

    @Test func nativeTableScrollingBypassesPerEventOverride() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let scroll = InterceptingScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        window.contentView = scroll
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1400, height: 150))
        scroll.tile()
        let event = try #require(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
            wheel1: 0, wheel2: -120, wheel3: 0
        ).flatMap(NSEvent.init(cgEvent:)))
        #expect(event.scrollingDeltaX < 0)
        EditorScrollCoordinator.scrollNatively(scroll, with: event)
        try await Task.sleep(for: .milliseconds(100))
        #expect(scroll.contentView.bounds.origin.x > 0)
        #expect(scroll.contentView.bounds.origin.y == 0)
        #expect(!scroll.receivedOverride)
    }
}

@MainActor
private final class FlippedTestView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class InterceptingScrollView: NSScrollView {
    var receivedOverride = false
    override func scrollWheel(with event: NSEvent) { receivedOverride = true }
}

@MainActor
private struct DropFixture {
    let root: URL
    let pasteboard = NSPasteboard.withUniqueName()

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("FalconMD-drop-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func file(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data("# Test\n".utf8).write(to: url)
        return url
    }

    func remove() {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: root)
    }
}

struct ScrollGestureTests {
    @Test func horizontalGestureRetainsAxisThroughJitterEndAndMomentum() {
        var routing = ScrollGestureRouting()
        #expect(routing.route(deltaX: 12, deltaY: 1, phase: .began, momentumPhase: [], overWideTable: true) == .table)
        #expect(routing.route(deltaX: 1, deltaY: 4, phase: .changed, momentumPhase: [], overWideTable: true) == .table)
        #expect(routing.route(deltaX: 0, deltaY: 0, phase: .ended, momentumPhase: [], overWideTable: true) == .table)
        #expect(routing.route(deltaX: 8, deltaY: 1, phase: [], momentumPhase: .began, overWideTable: false) == .table)
        #expect(routing.route(deltaX: 0, deltaY: 0, phase: [], momentumPhase: .ended, overWideTable: false) == .table)
        #expect(routing.destination == nil)
    }

    @Test func verticalGestureStaysOnPageWhileCrossingATable() {
        var routing = ScrollGestureRouting()
        #expect(routing.route(deltaX: 1, deltaY: 12, phase: .began, momentumPhase: [], overWideTable: false) == .page)
        #expect(routing.route(deltaX: 5, deltaY: 2, phase: .changed, momentumPhase: [], overWideTable: true) == .page)
    }

    @Test func zeroDeltaStartWaitsForDirectionAndNewGestureResetsAxis() {
        var routing = ScrollGestureRouting()
        #expect(routing.route(deltaX: 0, deltaY: 0, phase: .began, momentumPhase: [], overWideTable: true) == nil)
        #expect(routing.route(deltaX: 9, deltaY: 0, phase: .changed, momentumPhase: [], overWideTable: true) == .table)
        #expect(routing.route(deltaX: 0, deltaY: 9, phase: .began, momentumPhase: [], overWideTable: true) == .page)
        _ = routing.route(deltaX: 0, deltaY: 0, phase: .cancelled, momentumPhase: [], overWideTable: true)
        #expect(routing.destination == nil)
    }

    @Test func mouseWheelTicksAreIndependentAndNarrowTablesUsePage() {
        var routing = ScrollGestureRouting()
        #expect(routing.route(deltaX: 10, deltaY: 0, phase: [], momentumPhase: [], overWideTable: true) == .table)
        #expect(routing.route(deltaX: 0, deltaY: 10, phase: [], momentumPhase: [], overWideTable: true) == .page)
        #expect(routing.route(deltaX: 10, deltaY: 0, phase: .began, momentumPhase: [], overWideTable: false) == .page)
    }
}
