import Foundation
import UniformTypeIdentifiers
import SwiftUI

extension UTType {
    /// Markdown as declared in `Info.plist` (`net.daringfireball.markdown`).
    static var markdownDocument: UTType {
        UTType(importedAs: "net.daringfireball.markdown")
    }
}

/// UTF-8 Markdown file opened and saved by FalconMD.
struct MarkdownDocument: FileDocument, Equatable {
    static var readableContentTypes: [UTType] { [.markdownDocument, .plainText] }
    static var writableContentTypes: [UTType] { [.markdownDocument] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = try Self.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }

    /// Decode a Markdown file as UTF-8, stripping a leading BOM if present.
    static func decode(_ data: Data) throws -> String {
        if data.isEmpty { return "" }
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return stripBOM(string)
    }

    static func stripBOM(_ string: String) -> String {
        string.hasPrefix("\u{FEFF}") ? String(string.dropFirst()) : string
    }
}
