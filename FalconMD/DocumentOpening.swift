import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// All document-opening paths use NSDocumentController, including duplicate files.
@MainActor
enum DocumentOpening {
    static func open(_ urls: [URL]) {
        var seen: Set<URL> = []
        for url in urls where seen.insert(url.standardizedFileURL).inserted {
            let accessed = url.startAccessingSecurityScopedResource()
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if accessed { url.stopAccessingSecurityScopedResource() }
                if let error { NSApp.presentError(error) }
            }
        }
    }

    /// Accept a complete batch of local documents. Images keep their insert behavior;
    /// folders and mixed unsupported batches must not become text in the editor.
    static func droppedDocuments(from pasteboard: NSPasteboard) -> [URL] {
        let urls = fileURLs(from: pasteboard)
        guard !urls.isEmpty, urls.allSatisfy(isSupportedDocument) else { return [] }
        var seen: Set<URL> = []
        return urls.filter { seen.insert($0.standardizedFileURL).inserted }
    }

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []
    }

    static func isSupportedDocument(_ url: URL) -> Bool {
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey]),
              values.isRegularFile == true else { return false }
        // Keep the declared Markdown extensions working even before Launch Services
        // has registered this build, and when another app owns the extension's UTI.
        if ["md", "markdown", "mdown", "mkd"].contains(url.pathExtension.lowercased()) {
            return true
        }
        guard let type = values.contentType else { return false }
        return MarkdownDocument.readableContentTypes.contains { type.conforms(to: $0) }
    }
}

/// Handles the welcome page and the space around the native text view. NSTextView
/// has its own drag destination, wired to the same opening path by EditorDropHook.
struct DocumentFileDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
            && !DocumentOpening.droppedDocuments(from: NSPasteboard(name: .drag)).isEmpty
    }

    func dropEntered(info: DropInfo) { isTargeted = validateDrop(info: info) }
    func dropExited(info: DropInfo) { isTargeted = false }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: isTargeted ? .copy : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        let urls = DocumentOpening.droppedDocuments(from: NSPasteboard(name: .drag))
        guard !urls.isEmpty else { return false }
        DocumentOpening.open(urls)
        return true
    }
}

struct DocumentDropHighlight: View {
    let isTargeted: Bool

    var body: some View {
        if isTargeted {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
                .padding(6)
                .overlay(alignment: .top) {
                    Label("Drop to open documents", systemImage: "doc.badge.plus")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 18)
                }
                .allowsHitTesting(false)
                .accessibilityLabel("Drop to open documents")
        }
    }
}
