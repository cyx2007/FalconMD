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
/// documents write under Application Support until the first save, then the
/// files and Markdown paths move next to the new file.
enum DocumentAssets {
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

    /// Moves unsaved image files next to `documentURL` and rewrites Markdown paths.
    static func consumeUnsavedAssets(
        sessionID: String,
        into documentURL: URL,
        text: String,
        unsavedRoot: URL = DocumentAssets.unsavedRoot()
    ) -> String {
        let source = unsavedFolder(sessionID: sessionID, root: unsavedRoot)
        let dest = PastedImageWriter.assetsFolder(for: documentURL)
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return text }

        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
        if let items = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            for item in items {
                let target = dest.appendingPathComponent(item.lastPathComponent)
                if fm.fileExists(atPath: target.path) {
                    try? fm.removeItem(at: target)
                }
                try? fm.moveItem(at: item, to: target)
            }
        }
        try? fm.removeItem(at: source)
        return rewritten(text, replacingFolder: sessionID, with: dest.lastPathComponent)
    }

    static func rewritten(_ text: String, replacingFolder old: String, with new: String) -> String {
        text.replacingOccurrences(of: "](\(old)/", with: "](\(new)/")
    }
}

enum PastedImageWriter {
    /// Writes a pasteboard image into `assetsFolder` and returns Markdown to insert.
    static func markdown(from pasteboard: NSPasteboard, assetsFolder: URL) -> String? {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: assetsFolder, withIntermediateDirectories: true)
            let fileURL: URL
            if let source = PasteboardImageReader.imageFileURL(from: pasteboard) {
                var ext = source.pathExtension.lowercased()
                if ext.isEmpty { ext = "png" }
                let filename = "pasted-\(UUID().uuidString.lowercased()).\(ext)"
                fileURL = assetsFolder.appendingPathComponent(filename)
                if fm.fileExists(atPath: fileURL.path) {
                    try fm.removeItem(at: fileURL)
                }
                try fm.copyItem(at: source, to: fileURL)
            } else {
                guard let png = PasteboardImageReader.imageData(from: pasteboard)
                        ?? pngData(from: NSImage(pasteboard: pasteboard)) else {
                    return nil
                }
                let filename = "pasted-\(UUID().uuidString.lowercased()).png"
                fileURL = assetsFolder.appendingPathComponent(filename)
                try png.write(to: fileURL, options: .atomic)
            }
            let relative = "\(assetsFolder.lastPathComponent)/\(fileURL.lastPathComponent)"
            return "![](\(relative))"
        } catch {
            return nil
        }
    }

    static func markdown(from pasteboard: NSPasteboard, documentURL: URL?, sessionID: String) -> String? {
        markdown(
            from: pasteboard,
            assetsFolder: DocumentAssets.assetsFolder(documentURL: documentURL, sessionID: sessionID)
        )
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
}

// MARK: - Drop hook

/// Finds the engine's `NSTextView` in the key window and:
/// - turns off the system find bar (we own ⌘F)
/// - intercepts image file drops so they land in the document assets folder
struct EditorTextViewHook: NSViewRepresentable {
    var onImage: (NSPasteboard) -> String?

    func makeNSView(context: Context) -> HookView {
        let view = HookView()
        view.onImage = onImage
        return view
    }

    func updateNSView(_ view: HookView, context: Context) {
        view.onImage = onImage
        view.installIfNeeded()
    }

    final class HookView: NSView {
        var onImage: ((NSPasteboard) -> String?)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.installIfNeeded()
            }
        }

        func installIfNeeded() {
            guard let textView = firstDocumentTextView() else { return }
            textView.usesFindBar = false
            textView.usesFindPanel = false
            textView.isIncrementalSearchingEnabled = false
            ImageDropHook.attach(to: textView) { [weak self] pasteboard in
                self?.onImage?(pasteboard)
            }
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

private final class ImageDropHandlerBox: NSObject {
    let handle: (NSPasteboard) -> String?
    init(_ handle: @escaping (NSPasteboard) -> String?) {
        self.handle = handle
    }
}

enum ImageDropHook {
    nonisolated(unsafe) private static let handlerKey = UnsafeRawPointer(bitPattern: 0xF1A6_E01D)!

    private static let swizzleOnce: Void = {
        swizzle(#selector(NSTextView.performDragOperation(_:)),
                #selector(NSTextView.falconmd_performDragOperation(_:)))
        swizzle(#selector(NSTextView.draggingEntered(_:)),
                #selector(NSTextView.falconmd_draggingEntered(_:)))
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

    static func attach(to textView: NSTextView, handler: @escaping (NSPasteboard) -> String?) {
        _ = swizzleOnce
        objc_setAssociatedObject(
            textView,
            handlerKey,
            ImageDropHandlerBox(handler),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    fileprivate static func handler(for textView: NSTextView) -> ((NSPasteboard) -> String?)? {
        (objc_getAssociatedObject(textView, handlerKey) as? ImageDropHandlerBox)?.handle
    }
}

extension NSTextView {
    @objc func falconmd_draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if ImageDropHook.handler(for: self) != nil,
           PasteboardImageReader.canPasteImage(from: sender.draggingPasteboard) {
            return .copy
        }
        return falconmd_draggingEntered(sender)
    }

    @objc func falconmd_performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let handler = ImageDropHook.handler(for: self),
           PasteboardImageReader.canPasteImage(from: sender.draggingPasteboard),
           let markdown = handler(sender.draggingPasteboard),
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
