import AppKit
import MarkdownEngine
import SwiftUI

/// Per-window editor state shared with the menu bar via `focusedSceneValue`.
///
/// Format and find notifications are namespaced by `documentId` so a command
/// posted for the key window cannot land on every open document.
@Observable
@MainActor
final class EditorSession {
    let documentId = UUID().uuidString

    var showRawSource = false

    var isFindPresented = false
    var showsReplace = false
    var findQuery = ""
    var findReplacement = ""
    var findIndex = 0
    var findCount = 0
    var findFocusNonce = 0

    var bus: MarkdownEditorBus { FormatAction.bus(for: documentId) }

    func presentFind(replace: Bool) {
        showsReplace = replace
        isFindPresented = true
        findFocusNonce &+= 1
        if let selected = EditorSession.selectedEditorText(), findQuery.isEmpty {
            findQuery = selected
        }
        runFind(resetIndex: true)
    }

    func dismissFind() {
        isFindPresented = false
        showsReplace = false
        FormatAction.post(bus.findClearHighlights)
    }

    func runFind(resetIndex: Bool) {
        if resetIndex { findIndex = 0 }
        let query = findQuery
        if query.isEmpty {
            findCount = 0
            FormatAction.post(bus.findClearHighlights)
            return
        }
        FormatAction.post(bus.findQuery, userInfo: [
            "query": query,
            "currentIndex": findIndex,
        ])
    }

    func findNext() {
        if !isFindPresented {
            presentFind(replace: false)
            return
        }
        guard findCount > 0 else { return }
        findIndex = (findIndex + 1) % findCount
        runFind(resetIndex: false)
    }

    func findPrevious() {
        if !isFindPresented {
            presentFind(replace: false)
            return
        }
        guard findCount > 0 else { return }
        findIndex = (findIndex - 1 + findCount) % findCount
        runFind(resetIndex: false)
    }

    func useSelectionForFind() {
        if let selected = EditorSession.selectedEditorText(), !selected.isEmpty {
            findQuery = selected
        }
        presentFind(replace: showsReplace)
    }

    func replaceCurrentMatch() {
        guard !findQuery.isEmpty else { return }
        FormatAction.post(bus.replaceCurrent, userInfo: [
            "query": findQuery,
            "replacement": findReplacement,
            "currentIndex": findIndex,
        ])
    }

    func replaceAllMatches() {
        guard !findQuery.isEmpty else { return }
        FormatAction.post(bus.replaceAll, userInfo: [
            "query": findQuery,
            "replacement": findReplacement,
        ])
    }

    /// Visible selection in the key window's document editor, ignoring the
    /// find bar's field editor.
    static func selectedEditorText() -> String? {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
              !textView.isFieldEditor else {
            return nil
        }
        let range = textView.selectedRange()
        guard range.length > 0 else { return nil }
        return (textView.string as NSString).substring(with: range)
    }
}

enum EditorSessionKey: FocusedValueKey {
    typealias Value = EditorSession
}

extension FocusedValues {
    var editorSession: EditorSession? {
        get { self[EditorSessionKey.self] }
        set { self[EditorSessionKey.self] = newValue }
    }
}

enum FormatAction {
    static func bus(for documentId: String) -> MarkdownEditorBus {
        MarkdownEditorBus(
            applyBoldRequest: name("applyBold", documentId),
            applyItalicRequest: name("applyItalic", documentId),
            applyHeadingRequest: name("applyHeading", documentId),
            applyInlineCodeRequest: name("applyInlineCode", documentId),
            applyBlockquoteRequest: name("applyQuote", documentId),
            applyUnorderedListRequest: name("applyUnorderedList", documentId),
            applyOrderedListRequest: name("applyOrderedList", documentId),
            applyLinkRequest: name("applyLink", documentId),
            applyCodeBlockRequest: name("applyCodeBlock", documentId),
            applyImageRequest: name("applyImage", documentId),
            findClearHighlights: name("findClear", documentId),
            findQuery: name("findQuery", documentId),
            findResults: name("findResults", documentId),
            replaceCurrent: name("replaceCurrent", documentId),
            replaceAll: name("replaceAll", documentId)
        )
    }

    static func name(_ suffix: String, _ documentId: String) -> Notification.Name {
        Notification.Name("FalconMD.\(suffix).\(documentId)")
    }

    static func post(_ name: Notification.Name?, userInfo: [AnyHashable: Any]? = nil) {
        guard let name else { return }
        NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
    }
}

struct MarkdownFormatCommands: Commands {
    @FocusedValue(\.editorSession) private var session

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find…") { session?.presentFind(replace: false) }
                .keyboardShortcut("f")
                .disabled(session == nil)
            Button("Find and Replace…") { session?.presentFind(replace: true) }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(session == nil)
            Button("Find Next") { session?.findNext() }
                .keyboardShortcut("g")
                .disabled(session == nil)
            Button("Find Previous") { session?.findPrevious() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(session == nil)
            Button("Use Selection for Find") { session?.useSelectionForFind() }
                .keyboardShortcut("e")
                .disabled(session == nil)
        }

        CommandGroup(after: .toolbar) {
            Toggle("Raw Source", isOn: rawSourceBinding)
                .keyboardShortcut("\\", modifiers: [.command])
                .disabled(session == nil)
        }

        CommandMenu("Format") {
            Button("Bold") { post(session?.bus.applyBoldRequest) }
                .keyboardShortcut("b")
                .disabled(session == nil)
            Button("Italic") { post(session?.bus.applyItalicRequest) }
                .keyboardShortcut("i")
                .disabled(session == nil)
            Button("Inline Code") { post(session?.bus.applyInlineCodeRequest) }
                .keyboardShortcut("`", modifiers: [.command])
                .disabled(session == nil)

            Divider()

            Menu("Heading") {
                Button("Heading 1") { postHeading(1) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("Heading 2") { postHeading(2) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button("Heading 3") { postHeading(3) }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Button("Heading 4") { postHeading(4) }
                    .keyboardShortcut("4", modifiers: [.command, .option])
                Button("Heading 5") { postHeading(5) }
                    .keyboardShortcut("5", modifiers: [.command, .option])
                Button("Heading 6") { postHeading(6) }
                    .keyboardShortcut("6", modifiers: [.command, .option])
            }
            .disabled(session == nil)

            Button("Quote") { post(session?.bus.applyBlockquoteRequest) }
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .disabled(session == nil)
            Button("Bulleted List") { post(session?.bus.applyUnorderedListRequest) }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(session == nil)
            Button("Numbered List") { post(session?.bus.applyOrderedListRequest) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(session == nil)
            Button("Code Block") { post(session?.bus.applyCodeBlockRequest) }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(session == nil)

            Divider()

            Button("Link…") { insertLink() }
                .keyboardShortcut("k")
                .disabled(session == nil)
            Button("Image…") { insertImage() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(session == nil)
        }
    }

    private var rawSourceBinding: Binding<Bool> {
        Binding(
            get: { session?.showRawSource ?? false },
            set: { session?.showRawSource = $0 }
        )
    }

    private func post(_ name: Notification.Name?, userInfo: [AnyHashable: Any]? = nil) {
        FormatAction.post(name, userInfo: userInfo)
    }

    private func postHeading(_ level: Int) {
        post(session?.bus.applyHeadingRequest, userInfo: ["level": level])
    }

    private func insertLink() {
        let url = prompt(title: "Insert Link", placeholder: "https://") ?? "https://"
        post(session?.bus.applyLinkRequest, userInfo: ["url": url])
    }

    private func insertImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an image to insert"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let documentId = session?.documentId else { return }
        post(FormatAction.name("importImage", documentId), userInfo: ["url": url])
    }

    private func prompt(title: String, placeholder: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "The selected text becomes the label."
        alert.addButton(withTitle: "Insert")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: placeholder)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? placeholder : value
    }
}
