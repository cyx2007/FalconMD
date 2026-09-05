import AppKit
import MarkdownEngine
import MarkdownEngineCodeBlocks
import SwiftUI

struct MarkdownEditorView: View {
    @Binding var document: MarkdownDocument
    var fileURL: URL?

    @State private var session = EditorSession()
    @State private var assetErrorMessage: String?
    @State private var isDocumentDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if session.isFindPresented {
                FindReplaceBar(session: session)
            }

            GeometryReader { geometry in
                ScrollView(.vertical) {
                    editor
                        .frame(minHeight: geometry.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(minWidth: 560, minHeight: 400)
        .background(Color(nsColor: .textBackgroundColor))
        .background {
            EditorTextViewHook(
                session: session,
                onDocumentTargetChanged: { isDocumentDropTargeted = $0 },
                onImage: { importPastedImage(from: $0) }
            )
        }
        .onDrop(of: [.fileURL], delegate: DocumentFileDropDelegate(isTargeted: $isDocumentDropTargeted))
        .overlay { DocumentDropHighlight(isTargeted: isDocumentDropTargeted) }
        .focusedSceneValue(\.editorSession, session)
        .focusedValue(\.editorSession, session)
        .onReceive(NotificationCenter.default.publisher(for: FormatAction.name("findResults", session.documentId))) { note in
            session.findCount = note.userInfo?["count"] as? Int ?? 0
            if session.findCount == 0 {
                session.findIndex = 0
            } else {
                session.findIndex = min(session.findIndex, session.findCount - 1)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: FormatAction.name("importImage", session.documentId))) { note in
            guard let imageURL = note.userInfo?["url"] as? URL else { return }
            importImageFile(at: imageURL)
        }
        .onChange(of: fileURL) { oldURL, newURL in
            guard let newURL, oldURL != newURL else { return }
            do {
                document.text = try DocumentAssets.migrateAssets(
                    sessionID: session.documentId,
                    from: oldURL,
                    to: newURL,
                    text: document.text
                )
            } catch {
                document.text = DocumentAssets.preservingSourceReferences(
                    sessionID: session.documentId,
                    oldDocumentURL: oldURL,
                    text: document.text
                )
                presentAssetError(error)
            }
        }
        .alert("Image Asset Error", isPresented: assetErrorPresented) {
            Button("OK", role: .cancel) {
                assetErrorMessage = nil
            }
        } message: {
            Text(assetErrorMessage ?? "An unknown image error occurred.")
        }
    }

    private var editor: some View {
        NativeTextViewWrapper(
            text: $document.text,
            configuration: configuration,
            fontName: "SF Pro",
            fontSize: 16,
            documentId: session.documentId,
            onPasteImage: { pasteboard in
                importPastedImage(from: pasteboard)
            },
            placeholder: NSAttributedString(
                string: "Start writing…",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 16),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]
            )
        )
    }

    private var assetErrorPresented: Binding<Bool> {
        Binding(
            get: { assetErrorMessage != nil },
            set: { if !$0 { assetErrorMessage = nil } }
        )
    }

    private func importPastedImage(from pasteboard: NSPasteboard) -> String? {
        do {
            return try PastedImageWriter.markdown(
                from: pasteboard,
                documentURL: fileURL,
                sessionID: session.documentId
            )
        } catch {
            presentAssetError(error)
            return nil
        }
    }

    private func importImageFile(at imageURL: URL) {
        do {
            let destination = try PastedImageWriter.markdownDestination(
                from: imageURL,
                documentURL: fileURL,
                sessionID: session.documentId
            )
            FormatAction.post(session.bus.applyImageRequest, userInfo: ["url": destination])
        } catch {
            presentAssetError(error)
        }
    }

    private func presentAssetError(_ error: Error) {
        assetErrorMessage = error.localizedDescription
    }

    private var configuration: MarkdownEditorConfiguration {
        var config = MarkdownEditorConfiguration.default
        // The outer page owns scrolling. This avoids the engine's repeated
        // full-layout bottom clamp while preserving its content-height updates.
        config.heightBehavior = .fitsContent
        config.readingWidth = 720
        config.textInsets = TextInsets(horizontal: 28, vertical: 36)
        config.rawSourceMode = session.showRawSource
        config.services.syntaxHighlighter = SharedHighlighter.bridge
        config.services.images = LocalImageProvider(
            baseDirectory: DocumentAssets.imageBase(
                documentURL: fileURL,
                sessionID: session.documentId
            )
        )
        config.services.bus = session.bus
        return config
    }
}

/// HighlighterSwift's JSCore bridge is expensive; share one instance.
@MainActor
enum SharedHighlighter {
    static let bridge = HighlighterSwiftBridge()
}
