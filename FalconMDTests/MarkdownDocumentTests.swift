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
        let rewritten = DocumentAssets.consumeUnsavedAssets(
            sessionID: session,
            into: saved,
            text: text,
            unsavedRoot: root
        )

        #expect(rewritten == "see ![](note.assets/pasted-abc.png)")
        let dest = PastedImageWriter.assetsFolder(for: saved).appendingPathComponent("pasted-abc.png")
        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(!FileManager.default.fileExists(atPath: unsaved.path))
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
