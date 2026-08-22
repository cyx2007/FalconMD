import AppKit
import MarkdownEngine
import MarkdownEngineCodeBlocks
import SwiftUI

struct MarkdownEditorView: View {
    @Binding var document: MarkdownDocument
    var fileURL: URL?

    @State private var session = EditorSession()

    var body: some View {
        VStack(spacing: 0) {
            if session.isFindPresented {
                FindReplaceBar(session: session)
            }

            NativeTextViewWrapper(
                text: $document.text,
                configuration: configuration,
                fontName: "SF Pro",
                fontSize: 16,
                documentId: session.documentId,
                onPasteImage: { pasteboard in
                    PastedImageWriter.markdown(
                        from: pasteboard,
                        documentURL: fileURL,
                        sessionID: session.documentId
                    )
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
        .frame(minWidth: 560, minHeight: 400)
        .background(Color(nsColor: .textBackgroundColor))
        .background {
            EditorTextViewHook { pasteboard in
                PastedImageWriter.markdown(
                    from: pasteboard,
                    documentURL: fileURL,
                    sessionID: session.documentId
                )
            }
        }
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
        .onChange(of: fileURL) { oldURL, newURL in
            guard oldURL == nil, let newURL else { return }
            document.text = DocumentAssets.consumeUnsavedAssets(
                sessionID: session.documentId,
                into: newURL,
                text: document.text
            )
        }
    }

    private var configuration: MarkdownEditorConfiguration {
        var config = MarkdownEditorConfiguration.default
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
