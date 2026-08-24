import Foundation
import Testing
@testable import FalconMD

struct MarkdownDocumentTests {
    @Test func emptyDataDecodesToEmptyString() throws {
        #expect(try MarkdownDocument.decode(Data()) == "")
    }

    @Test func utf8RoundTrip() throws {
        let original = "# Hello\n\n**bold** and *italic*\n"
        let decoded = try MarkdownDocument.decode(Data(original.utf8))
        #expect(decoded == original)
    }

    @Test func stripsUTF8BOM() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(contentsOf: Data("# Title".utf8))
        #expect(try MarkdownDocument.decode(data) == "# Title")
    }

    @Test func rejectsInvalidUTF8() {
        let data = Data([0x80, 0x81, 0x82])
        #expect(throws: Error.self) {
            _ = try MarkdownDocument.decode(data)
        }
    }

    @Test func storesPlainUTF8Text() {
        let document = MarkdownDocument(text: "# Saved")
        #expect(Data(document.text.utf8) == Data("# Saved".utf8))
    }
}

struct LocalImageProviderTests {
    @Test func ignoresRemoteURLs() {
        #expect(LocalImageProvider.resolve("https://example.com/a.png", relativeTo: nil) == nil)
        #expect(LocalImageProvider.resolve("http://example.com/a.png", relativeTo: nil) == nil)
    }

    @Test func ignoresEmptyAndWhitespace() {
        #expect(LocalImageProvider.resolve("  ", relativeTo: nil) == nil)
        #expect(LocalImageProvider.resolve("", relativeTo: nil) == nil)
    }

    @Test func resolvesAbsolutePaths() {
        let url = LocalImageProvider.resolve("/tmp/photo.png", relativeTo: nil)
        #expect(url?.path == "/tmp/photo.png")
    }

    @Test func relativePathsNeedABaseDirectory() {
        #expect(LocalImageProvider.resolve("images/a.png", relativeTo: nil) == nil)
    }

    @Test func resolvesRelativePaths() {
        let base = URL(fileURLWithPath: "/Users/demo/Notes", isDirectory: true)
        let url = LocalImageProvider.resolve("./images/a.png", relativeTo: base)
        #expect(url?.path == "/Users/demo/Notes/images/a.png")
    }

    @Test func assetsFolderMirrorsTyporaConvention() {
        let document = URL(fileURLWithPath: "/Notes/diary.md")
        let folder = PastedImageWriter.assetsFolder(for: document)
        #expect(folder.path == "/Notes/diary.assets")
    }

    @Test func unsavedAssetsLiveUnderSessionFolder() {
        let session = "SESSION-ID"
        let folder = DocumentAssets.assetsFolder(documentURL: nil, sessionID: session)
        #expect(folder.lastPathComponent == session)
        #expect(DocumentAssets.imageBase(documentURL: nil, sessionID: session) == DocumentAssets.unsavedRoot())
    }

    @Test func savedAssetsLiveBesideTheDocument() {
        let document = URL(fileURLWithPath: "/Notes/diary.md")
        let folder = DocumentAssets.assetsFolder(documentURL: document, sessionID: "unused")
        #expect(folder.path == "/Notes/diary.assets")
        #expect(DocumentAssets.imageBase(documentURL: document, sessionID: "unused").path == "/Notes")
    }

    @Test func migrateRewritesUnsavedImagePaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FalconMD-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let session = UUID().uuidString
        let unsaved = DocumentAssets.unsavedFolder(sessionID: session, root: root)
        try FileManager.default.createDirectory(at: unsaved, withIntermediateDirectories: true)
        let image = unsaved.appendingPathComponent("pasted-abc.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: image)

        let saved = root.appendingPathComponent("note.md")
        let text = "see ![](\(session)/pasted-abc.png)"
        let rewritten = try DocumentAssets.migrateAssets(
            sessionID: session,
            from: nil,
            to: saved,
            text: text,
            unsavedRoot: root
        )

        #expect(rewritten == "see ![](note.assets/pasted-abc.png)")
        let dest = PastedImageWriter.assetsFolder(for: saved).appendingPathComponent("pasted-abc.png")
        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(!FileManager.default.fileExists(atPath: unsaved.path))
    }

    @Test func saveAsCopiesAssetsAndPreservesTheOriginal() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FalconMD-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let original = root.appendingPathComponent("Original Note.md")
        let originalAssets = PastedImageWriter.assetsFolder(for: original)
        try FileManager.default.createDirectory(at: originalAssets, withIntermediateDirectories: true)
        let image = originalAssets.appendingPathComponent("pasted-abc.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: image)

        let copyFolder = root.appendingPathComponent("Copies", isDirectory: true)
        try FileManager.default.createDirectory(at: copyFolder, withIntermediateDirectories: true)
        let copy = copyFolder.appendingPathComponent("Copy (Final).md")
        let text = "![](Original Note.assets/pasted-abc.png)"
        let rewritten = try DocumentAssets.migrateAssets(
            sessionID: "unused",
            from: original,
            to: copy,
            text: text,
            unsavedRoot: root
        )

        #expect(rewritten == "![](Copy%20%28Final%29.assets/pasted-abc.png)")
        #expect(FileManager.default.fileExists(atPath: image.path))
        let copied = PastedImageWriter.assetsFolder(for: copy).appendingPathComponent("pasted-abc.png")
        #expect(FileManager.default.fileExists(atPath: copied.path))
    }

    @Test func migrationConflictDoesNotOverwriteEitherAsset() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FalconMD-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let original = root.appendingPathComponent("original.md")
        let copy = root.appendingPathComponent("copy.md")
        let sourceAssets = PastedImageWriter.assetsFolder(for: original)
        let destinationAssets = PastedImageWriter.assetsFolder(for: copy)
        try FileManager.default.createDirectory(at: sourceAssets, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationAssets, withIntermediateDirectories: true)
        let source = sourceAssets.appendingPathComponent("same.png")
        let destination = destinationAssets.appendingPathComponent("same.png")
        try Data([1]).write(to: source)
        try Data([2]).write(to: destination)

        #expect(throws: AssetError.self) {
            _ = try DocumentAssets.migrateAssets(
                sessionID: "unused",
                from: original,
                to: copy,
                text: "![](original.assets/same.png)",
                unsavedRoot: root
            )
        }
        #expect(try Data(contentsOf: source) == Data([1]))
        #expect(try Data(contentsOf: destination) == Data([2]))
    }

    @Test func markdownPathsEncodeUnsafeCharacters() {
        let encoded = PastedImageWriter.encodedMarkdownPath("笔记 (final).assets/image #1.png")
        #expect(encoded == "%E7%AC%94%E8%AE%B0%20%28final%29.assets/image%20%231.png")
    }

    @Test func failedMigrationCanPreserveOriginalAssetReferences() {
        let original = URL(fileURLWithPath: "/Notes/Original Note.md")
        let preserved = DocumentAssets.preservingSourceReferences(
            sessionID: "unused",
            oldDocumentURL: original,
            text: "![](Original Note.assets/image.png)"
        )
        #expect(preserved == "![](/Notes/Original%20Note.assets/image.png)")
    }

    @Test func selectedImageIsCopiedIntoTheDocumentAssetsFolder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FalconMD-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.PNG")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)
        let document = root.appendingPathComponent("My Note.md")

        let markdown = try PastedImageWriter.markdown(
            from: source,
            documentURL: document,
            sessionID: "unused"
        )

        #expect(markdown.hasPrefix("![](My%20Note.assets/pasted-"))
        #expect(markdown.hasSuffix(".png)"))
        let copied = try FileManager.default.contentsOfDirectory(
            at: PastedImageWriter.assetsFolder(for: document),
            includingPropertiesForKeys: nil
        )
        #expect(copied.count == 1)
        #expect(try Data(contentsOf: copied[0]) == Data(contentsOf: source))
    }

    @Test func staleUnsavedAssetsAreRemovedButRecentOnesRemain() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FalconMD-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("old", isDirectory: true)
        let recent = root.appendingPathComponent("recent", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recent, withIntermediateDirectories: true)

        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-100)],
            ofItemAtPath: old.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-10)],
            ofItemAtPath: recent.path
        )

        DocumentAssets.cleanupStaleUnsavedAssets(now: now, maximumAge: 60, root: root)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
    }
}

struct FormatActionTests {
    @Test func busNamesAreScopedToTheDocument() {
        let a = FormatAction.bus(for: "doc-a")
        let b = FormatAction.bus(for: "doc-b")
        #expect(a.applyBoldRequest != b.applyBoldRequest)
        #expect(a.findQuery != b.findQuery)
        #expect(a.replaceAll != b.replaceAll)
        #expect(a.applyBoldRequest == FormatAction.name("applyBold", "doc-a"))
    }
}

struct StartPageTests {
    @Test func displayNameKeepsTheExtension() {
        let url = URL(fileURLWithPath: "/Notes/diary.md")
        #expect(StartPage.displayName(for: url) == "diary.md")
    }

    @Test func locationLabelShortensHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent("Notes/diary.md")
        #expect(StartPage.locationLabel(for: url) == "~/Notes")
    }

    @Test func existingRecentsSkipMissingFiles() {
        let kept = URL(fileURLWithPath: "/Notes/alive.md")
        let gone = URL(fileURLWithPath: "/Notes/deleted.md")
        let visible = StartPage.existingRecents(from: [kept, gone]) { $0 == kept.path }
        #expect(visible == [kept])
    }

    @Test func newDocumentStartsEmpty() {
        #expect(MarkdownDocument().text.isEmpty)
    }
}
