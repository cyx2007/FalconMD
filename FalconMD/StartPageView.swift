import AppKit
import SwiftUI

enum StartPage {
    static let windowID = "welcome"
    static let windowTitle = "Welcome to FalconMD"

    /// File name as shown in the recents list, including the extension.
    static func displayName(for url: URL) -> String {
        url.lastPathComponent
    }

    /// Parent folder, with the home directory shortened to `~`.
    static func locationLabel(for url: URL) -> String {
        (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }

    /// Recents that still exist on disk, preserving NSDocumentController order.
    static func existingRecents(
        from urls: [URL],
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [URL] {
        urls.filter { fileExists($0.path) }
    }
}

/// Launch pad shown when FalconMD starts with no document windows.
struct StartPageView: View {
    var previewRecents: [URL]? = nil

    @State private var recents: [URL] = []
    @State private var isDocumentDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            actionsColumn
                .frame(width: 280)

            Divider()
                .padding(.top, 12)

            recentsColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 740, height: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [.fileURL], delegate: DocumentFileDropDelegate(isTargeted: $isDocumentDropTargeted))
        .overlay { DocumentDropHighlight(isTargeted: isDocumentDropTargeted) }
        .onAppear(perform: reloadRecents)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            reloadRecents()
        }
    }

    private var actionsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("#")
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .foregroundStyle(.tint)
                Text("FalconMD")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
            }
            .padding(.bottom, 8)

            Text("A lightweight Markdown editor.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.bottom, 28)

            VStack(alignment: .leading, spacing: 4) {
                StartActionButton(
                    title: "New Document",
                    shortcut: "⌘N",
                    systemImage: "square.and.pencil",
                    action: createDocument
                )
                StartActionButton(
                    title: "Open…",
                    shortcut: "⌘O",
                    systemImage: "folder",
                    action: openFromPanel
                )
            }

            Spacer(minLength: 0)

            Text("Drop Markdown files here to open.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 36)
        .padding(.trailing, 24)
        .padding(.top, 40)
        .padding(.bottom, 28)
    }

    private var recentsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recents")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.top, 40)
                .padding(.horizontal, 20)

            if recents.isEmpty {
                Text("Documents you open will appear here.")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(recents, id: \.self) { url in
                            RecentDocumentRow(url: url) {
                                open(url)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private func reloadRecents() {
        let urls = previewRecents ?? NSDocumentController.shared.recentDocumentURLs
        recents = StartPage.existingRecents(from: urls)
    }

    private func createDocument() {
        NSDocumentController.shared.newDocument(nil)
    }

    private func openFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MarkdownDocument.readableContentTypes
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.title = "Open Markdown"
        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }

    private func open(_ url: URL) {
        open([url])
    }

    private func open(_ urls: [URL]) {
        DocumentOpening.open(urls)
    }
}

private struct StartActionButton: View {
    let title: String
    let shortcut: String
    let systemImage: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 8)
                Text(shortcut)
                    .font(.system(size: 11, weight: .medium).monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Color.primary.opacity(0.06) : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct RecentDocumentRow: View {
    let url: URL
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(StartPage.displayName(for: url))
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Text(StartPage.locationLabel(for: url))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Color.accentColor.opacity(0.14) : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(url.path)
    }
}

#Preview {
    StartPageView(previewRecents: [
        URL(fileURLWithPath: "/Users/demo/Notes/journal.md"),
        URL(fileURLWithPath: "/Users/demo/Projects/readme.md"),
    ])
}
