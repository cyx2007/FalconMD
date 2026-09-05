import AppKit
import Foundation
import MarkdownEngine
import SwiftUI
import UniformTypeIdentifiers

/// Resolves `![alt](path)` and `![[name]]` against the open document's folder.
///
/// Remote `http(s)` URLs are ignored on purpose: the engine asks for images
/// synchronously during styling, so a network fetch would hitch typing.
struct LocalImageProvider: EmbeddedImageProvider {
    let baseDirectory: URL?

    func image(for request: EmbeddedImageRequest) -> NSImage? {
        let name = request.id ?? request.name
        guard let url = Self.resolve(name, relativeTo: baseDirectory) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    func fingerprint() -> AnyHashable {
        baseDirectory?.standardizedFileURL.path ?? ""
    }

    /// Returns a local file URL, or `nil` for empty / remote references.
    static func resolve(_ raw: String, relativeTo baseDirectory: URL?) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return nil
        }

        if lower.hasPrefix("file://"), let url = URL(string: trimmed) {
            return url
        }

        let decoded = trimmed.removingPercentEncoding ?? trimmed
        if decoded.hasPrefix("/") {
            return URL(fileURLWithPath: decoded)
        }

        guard let baseDirectory else { return nil }
        return URL(fileURLWithPath: decoded, relativeTo: baseDirectory).standardizedFileURL
    }
}

/// Sidecar folder for pasted / dropped images.
///
/// Saved documents use Typora's `{stem}.assets` next to the file. Unsaved
/// documents write under Application Support until the first save, then their
/// files and Markdown paths migrate next to the new file.
enum DocumentAssets {
    private static let staleUnsavedAssetAge: TimeInterval = 7 * 24 * 60 * 60

    static func unsavedRoot() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("FalconMD/Unsaved", isDirectory: true)
    }

    static func unsavedFolder(sessionID: String, root: URL = DocumentAssets.unsavedRoot()) -> URL {
        root.appendingPathComponent(sessionID, isDirectory: true)
    }

    /// Directory that relative image paths are resolved against.
    static func imageBase(documentURL: URL?, sessionID: String) -> URL {
        if let documentURL {
            return documentURL.deletingLastPathComponent()
        }
        return unsavedRoot()
    }

    /// Folder that newly pasted or dropped images are written into.
    static func assetsFolder(documentURL: URL?, sessionID: String) -> URL {
        if let documentURL {
            return PastedImageWriter.assetsFolder(for: documentURL)
        }
        return unsavedFolder(sessionID: sessionID)
    }

    /// Copies assets to match a document URL change and rewrites their Markdown
    /// references. Saved assets stay in place so Save As preserves the original.
    static func migrateAssets(
        sessionID: String,
        from oldDocumentURL: URL?,
        to newDocumentURL: URL,
        text: String,
        unsavedRoot: URL = DocumentAssets.unsavedRoot()
    ) throws -> String {
        let source: URL
        let oldFolderName: String
        let removeSourceAfterCopy: Bool
        if let oldDocumentURL {
            source = PastedImageWriter.assetsFolder(for: oldDocumentURL)
            oldFolderName = source.lastPathComponent
            removeSourceAfterCopy = false
        } else {
            source = unsavedFolder(sessionID: sessionID, root: unsavedRoot)
            oldFolderName = sessionID
            removeSourceAfterCopy = true
        }

        let dest = PastedImageWriter.assetsFolder(for: newDocumentURL)
        let fm = FileManager.default
        let rewritten = rewritten(
            rewritten(text, replacingFolder: oldFolderName, with: dest.lastPathComponent),
            replacingFolder: source.path,
            with: dest.lastPathComponent
        )

        guard source.standardizedFileURL != dest.standardizedFileURL else {
            return rewritten
        }
        guard fm.fileExists(atPath: source.path) else { return text }

        let destinationExisted = fm.fileExists(atPath: dest.path)
        var copiedItems: [URL] = []
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            try copyAssetContents(
                from: source,
                to: dest,
                fileManager: fm,
                copiedItems: &copiedItems
            )
        } catch {
            for item in copiedItems.reversed() {
                try? fm.removeItem(at: item)
            }
            if !destinationExisted {
                try? fm.removeItem(at: dest)
            }
            throw AssetError.migrationFailed(source: source, destination: dest, underlying: error)
        }

        if removeSourceAfterCopy {
            try? fm.removeItem(at: source)
        }
        return rewritten
    }

    private static func copyAssetContents(
        from source: URL,
        to destination: URL,
        fileManager fm: FileManager,
        copiedItems: inout [URL]
    ) throws {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey]
        let items = try fm.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: Array(keys),
            options: []
        )
        for item in items {
            let values = try item.resourceValues(forKeys: keys)
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if values.isDirectory == true {
                if fm.fileExists(atPath: target.path) {
                    let targetValues = try target.resourceValues(forKeys: [.isDirectoryKey])
                    guard targetValues.isDirectory == true else {
                        throw AssetError.destinationConflict(target)
                    }
                    try copyAssetContents(
                        from: item,
                        to: target,
                        fileManager: fm,
                        copiedItems: &copiedItems
                    )
                } else {
                    try fm.copyItem(at: item, to: target)
                    copiedItems.append(target)
                }
            } else if values.isRegularFile == true {
                if fm.fileExists(atPath: target.path) {
                    guard fm.contentsEqual(atPath: item.path, andPath: target.path) else {
                        throw AssetError.destinationConflict(target)
                    }
                } else {
                    try fm.copyItem(at: item, to: target)
                    copiedItems.append(target)
                }
            }
        }
    }

    static func rewritten(_ text: String, replacingFolder old: String, with new: String) -> String {
        let encodedOld = PastedImageWriter.encodedMarkdownPath(old)
        let encodedNew = PastedImageWriter.encodedMarkdownPath(new)
        return text
            .replacingOccurrences(of: "](\(old)/", with: "](\(encodedNew)/")
            .replacingOccurrences(of: "](\(encodedOld)/", with: "](\(encodedNew)/")
    }

    /// Keeps images usable when a URL-change migration fails by pointing only
    /// the affected asset references at their original absolute folder.
    static func preservingSourceReferences(
        sessionID: String,
        oldDocumentURL: URL?,
        text: String,
        unsavedRoot: URL = DocumentAssets.unsavedRoot()
    ) -> String {
        let source: URL
        let oldFolderName: String
        if let oldDocumentURL {
            source = PastedImageWriter.assetsFolder(for: oldDocumentURL)
            oldFolderName = source.lastPathComponent
        } else {
            source = unsavedFolder(sessionID: sessionID, root: unsavedRoot)
            oldFolderName = sessionID
        }
        return rewritten(text, replacingFolder: oldFolderName, with: source.path)
    }

    /// Removes abandoned unsaved-image sessions. Successful first saves are
    /// cleaned immediately; this catches discarded documents and crashes.
    static func cleanupStaleUnsavedAssets(
        now: Date = Date(),
        maximumAge: TimeInterval = staleUnsavedAssetAge,
        root: URL = DocumentAssets.unsavedRoot()
    ) {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for folder in folders {
            guard let values = try? folder.resourceValues(
                forKeys: [.contentModificationDateKey, .isDirectoryKey]
            ), values.isDirectory == true,
                  let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) >= maximumAge else { continue }
            try? fm.removeItem(at: folder)
        }
    }
}

enum PastedImageWriter {
    /// Writes a pasteboard image into `assetsFolder` and returns Markdown to insert.
    static func markdown(from pasteboard: NSPasteboard, assetsFolder: URL) throws -> String {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: assetsFolder, withIntermediateDirectories: true)
            let fileURL: URL
            if let source = PasteboardImageReader.imageFileURL(from: pasteboard) {
                fileURL = try copyImageFile(source, into: assetsFolder)
            } else {
                guard let png = PasteboardImageReader.imageData(from: pasteboard)
                        ?? pngData(from: NSImage(pasteboard: pasteboard)) else {
                    throw AssetError.noImageData
                }
                let filename = "pasted-\(UUID().uuidString.lowercased()).png"
                fileURL = assetsFolder.appendingPathComponent(filename)
                try png.write(to: fileURL, options: .atomic)
            }
            let relative = encodedMarkdownPath(
                "\(assetsFolder.lastPathComponent)/\(fileURL.lastPathComponent)"
            )
            return "![](\(relative))"
        } catch {
            throw AssetError.importFailed(destination: assetsFolder, underlying: error)
        }
    }

    static func markdown(from pasteboard: NSPasteboard, documentURL: URL?, sessionID: String) throws -> String {
        try markdown(
            from: pasteboard,
            assetsFolder: DocumentAssets.assetsFolder(documentURL: documentURL, sessionID: sessionID)
        )
    }

    static func markdown(from imageURL: URL, documentURL: URL?, sessionID: String) throws -> String {
        let destination = try markdownDestination(
            from: imageURL,
            documentURL: documentURL,
            sessionID: sessionID
        )
        return "![](\(destination))"
    }

    static func markdownDestination(
        from imageURL: URL,
        documentURL: URL?,
        sessionID: String
    ) throws -> String {
        let assetsFolder = DocumentAssets.assetsFolder(documentURL: documentURL, sessionID: sessionID)
        do {
            try FileManager.default.createDirectory(at: assetsFolder, withIntermediateDirectories: true)
            let copied = try copyImageFile(imageURL, into: assetsFolder)
            return encodedMarkdownPath(
                "\(assetsFolder.lastPathComponent)/\(copied.lastPathComponent)"
            )
        } catch {
            throw AssetError.importFailed(destination: assetsFolder, underlying: error)
        }
    }

    static func encodedMarkdownPath(_ raw: String) -> String {
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/"
        )
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }

    static func assetsFolder(for documentURL: URL) -> URL {
        let stem = documentURL.deletingPathExtension().lastPathComponent
        return documentURL.deletingLastPathComponent().appendingPathComponent("\(stem).assets")
    }

    static func pngData(from image: NSImage?) -> Data? {
        guard let image,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func copyImageFile(_ source: URL, into assetsFolder: URL) throws -> URL {
        var ext = source.pathExtension.lowercased()
        if ext.isEmpty { ext = "png" }
        let filename = "pasted-\(UUID().uuidString.lowercased()).\(ext)"
        let destination = assetsFolder.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
}

enum AssetError: LocalizedError {
    case noImageData
    case destinationConflict(URL)
    case importFailed(destination: URL, underlying: Error)
    case migrationFailed(source: URL, destination: URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noImageData:
            return "The pasteboard does not contain a readable image."
        case .destinationConflict(let url):
            return "A different asset already exists at \(url.path)."
        case .importFailed(let destination, let underlying):
            return "Could not copy the image into \(destination.path): \(underlying.localizedDescription)"
        case .migrationFailed(let source, let destination, let underlying):
            return "Could not migrate assets from \(source.path) to \(destination.path): \(underlying.localizedDescription)"
        }
    }
}

// MARK: - Drop hook

/// Finds the engine's `NSTextView` in this window and:
/// - turns off the system find bar (we own ⌘F)
/// - opens dropped documents and imports images into the document assets folder
/// - connects native page/table scrolling and find-result reveal
struct EditorTextViewHook: NSViewRepresentable {
    var session: EditorSession
    var onDocumentTargetChanged: (Bool) -> Void
    var onImage: (NSPasteboard) -> String?

    func makeNSView(context: Context) -> HookView {
        let view = HookView()
        view.session = session
        view.onDocumentTargetChanged = onDocumentTargetChanged
        view.onImage = onImage
        return view
    }

    func updateNSView(_ view: HookView, context: Context) {
        view.session = session
        view.onDocumentTargetChanged = onDocumentTargetChanged
        view.onImage = onImage
        view.installIfNeeded()
    }

    static func dismantleNSView(_ view: HookView, coordinator: ()) {
        view.scrollCoordinator.stop()
    }

    final class HookView: NSView {
        var session: EditorSession?
        var onDocumentTargetChanged: ((Bool) -> Void)?
        var onImage: ((NSPasteboard) -> String?)?
        let scrollCoordinator = EditorScrollCoordinator()

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { scrollCoordinator.stop() }
            DispatchQueue.main.async { [weak self] in
                self?.installIfNeeded()
            }
        }

        func installIfNeeded() {
            guard let textView = firstDocumentTextView() else { return }
            textView.usesFindBar = false
            textView.usesFindPanel = false
            textView.isIncrementalSearchingEnabled = false
            EditorDropHook.attach(
                to: textView,
                onDocumentTargetChanged: { [weak self] in self?.onDocumentTargetChanged?($0) },
                handler: { [weak self] in self?.onImage?($0) }
            )
            if let session { scrollCoordinator.attach(to: textView, session: session) }
        }

        private func firstDocumentTextView() -> NSTextView? {
            guard let root = window?.contentView else { return nil }
            return Self.findTextView(in: root)
        }

        private static func findTextView(in view: NSView) -> NSTextView? {
            if let textView = view as? NSTextView, !textView.isFieldEditor {
                return textView
            }
            for child in view.subviews {
                if let found = findTextView(in: child) { return found }
            }
            return nil
        }
    }
}

private final class EditorDropHandlerBox: NSObject {
    var handle: (NSPasteboard) -> String?
    var onDocumentTargetChanged: (Bool) -> Void
    var openDocuments: ([URL]) -> Void
    var documents: [URL] = []
    var rejectsFiles = false
    init(
        _ handle: @escaping (NSPasteboard) -> String?,
        onDocumentTargetChanged: @escaping (Bool) -> Void,
        openDocuments: @escaping ([URL]) -> Void
    ) {
        self.handle = handle
        self.onDocumentTargetChanged = onDocumentTargetChanged
        self.openDocuments = openDocuments
    }
}

@MainActor
enum EditorDropHook {
    nonisolated(unsafe) private static let handlerKey = UnsafeRawPointer(bitPattern: 0xF1A6_E01D)!

    private static let swizzleOnce: Void = {
        swizzle(#selector(NSTextView.performDragOperation(_:)),
                #selector(NSTextView.falconmd_performDragOperation(_:)))
        swizzle(#selector(NSTextView.draggingEntered(_:)),
                #selector(NSTextView.falconmd_draggingEntered(_:)))
        swizzle(#selector(NSTextView.draggingUpdated(_:)),
                #selector(NSTextView.falconmd_draggingUpdated(_:)))
        swizzle(#selector(NSTextView.draggingExited(_:)),
                #selector(NSTextView.falconmd_draggingExited(_:)))
        swizzle(#selector(NSTextView.draggingEnded(_:)),
                #selector(NSTextView.falconmd_draggingEnded(_:)))
        swizzle(#selector(NSTextView.prepareForDragOperation(_:)),
                #selector(NSTextView.falconmd_prepareForDragOperation(_:)))
    }()

    private static func swizzle(_ original: Selector, _ swizzled: Selector) {
        let cls = NSTextView.self
        guard let originalMethod = class_getInstanceMethod(cls, original),
              let swizzledMethod = class_getInstanceMethod(cls, swizzled) else { return }
        let added = class_addMethod(
            cls,
            original,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )
        if added {
            class_replaceMethod(
                cls,
                swizzled,
                method_getImplementation(originalMethod),
                method_getTypeEncoding(originalMethod)
            )
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }

    static func attach(
        to textView: NSTextView,
        onDocumentTargetChanged: @escaping (Bool) -> Void = { _ in },
        openDocuments: @escaping ([URL]) -> Void = { DocumentOpening.open($0) },
        handler: @escaping (NSPasteboard) -> String?
    ) {
        _ = swizzleOnce
        textView.registerForDraggedTypes([.fileURL])
        if let existing = Self.handler(for: textView) {
            existing.handle = handler
            existing.onDocumentTargetChanged = onDocumentTargetChanged
            existing.openDocuments = openDocuments
            return
        }
        objc_setAssociatedObject(
            textView,
            handlerKey,
            EditorDropHandlerBox(
                handler, onDocumentTargetChanged: onDocumentTargetChanged, openDocuments: openDocuments
            ),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    fileprivate static func handler(for textView: NSTextView) -> EditorDropHandlerBox? {
        objc_getAssociatedObject(textView, handlerKey) as? EditorDropHandlerBox
    }
}

extension NSTextView {
    @objc func falconmd_draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let handler = EditorDropHook.handler(for: self) {
            handler.documents = DocumentOpening.droppedDocuments(from: sender.draggingPasteboard)
            let files = DocumentOpening.fileURLs(from: sender.draggingPasteboard)
            handler.rejectsFiles = !files.isEmpty && handler.documents.isEmpty && !files.allSatisfy {
                guard let values = try? $0.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey]) else { return false }
                return values.isRegularFile == true && values.contentType?.conforms(to: .image) == true
            }
            handler.onDocumentTargetChanged(!handler.documents.isEmpty)
            if !handler.documents.isEmpty { return .copy }
            if handler.rejectsFiles { return [] }
        }
        if EditorDropHook.handler(for: self) != nil,
           PasteboardImageReader.canPasteImage(from: sender.draggingPasteboard) {
            return .copy
        }
        return falconmd_draggingEntered(sender)
    }

    @objc func falconmd_draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if EditorDropHook.handler(for: self)?.rejectsFiles == true { return [] }
        if let handler = EditorDropHook.handler(for: self), !handler.documents.isEmpty { return .copy }
        return falconmd_draggingUpdated(sender)
    }

    @objc func falconmd_prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if EditorDropHook.handler(for: self)?.rejectsFiles == true { return false }
        if let handler = EditorDropHook.handler(for: self), !handler.documents.isEmpty { return true }
        return falconmd_prepareForDragOperation(sender)
    }

    @objc func falconmd_draggingExited(_ sender: NSDraggingInfo?) {
        if let handler = EditorDropHook.handler(for: self) {
            handler.documents = []
            handler.rejectsFiles = false
            handler.onDocumentTargetChanged(false)
        }
        falconmd_draggingExited(sender)
    }

    @objc func falconmd_draggingEnded(_ sender: NSDraggingInfo) {
        if let handler = EditorDropHook.handler(for: self) {
            handler.documents = []
            handler.rejectsFiles = false
            handler.onDocumentTargetChanged(false)
        }
        falconmd_draggingEnded(sender)
    }

    @objc func falconmd_performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let handler = EditorDropHook.handler(for: self) {
            handler.onDocumentTargetChanged(false)
            let acceptedDocuments = handler.documents
            handler.documents = []
            if handler.rejectsFiles { return false }
            let documents = acceptedDocuments.isEmpty
                ? DocumentOpening.droppedDocuments(from: sender.draggingPasteboard)
                : acceptedDocuments
            if !documents.isEmpty {
                handler.openDocuments(documents)
                return true
            }
        }
        if let handler = EditorDropHook.handler(for: self),
           PasteboardImageReader.canPasteImage(from: sender.draggingPasteboard),
           let markdown = handler.handle(sender.draggingPasteboard),
           !markdown.isEmpty {
            insertImageMarkdown(markdown)
            return true
        }
        return falconmd_performDragOperation(sender)
    }

    fileprivate func insertImageMarkdown(_ embed: String) {
        let sel = selectedRange()
        let nsText = string as NSString
        var prefix = ""
        var suffix = ""
        if sel.location > 0, nsText.character(at: sel.location - 1) != 0x0A {
            prefix = "\n"
        }
        let afterLocation = sel.location + sel.length
        if afterLocation < nsText.length, nsText.character(at: afterLocation) != 0x0A {
            suffix = "\n"
        }
        breakUndoCoalescing()
        insertText(prefix + embed + suffix, replacementRange: sel)
        undoManager?.setActionName("Insert Image")
        breakUndoCoalescing()
    }
}
