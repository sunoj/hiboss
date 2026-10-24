// Safe on-disk filenames for downloaded Box originals, from title, MIME type or sniffed bytes.
// Exports BoxDownloadName for BoxMediaStore.
// Dependencies: Foundation, HibossKit and UniformTypeIdentifiers.

import Foundation
import HibossKit
import UniformTypeIdentifiers

enum BoxDownloadName {
    static func filename(_ item: BoxItem, bytesAt url: URL) throws -> String {
        let raw = item.text.flatMap { $0.isEmpty ? nil : $0 } ?? item.boxTitle
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
        let safe = raw.unicodeScalars.map { forbidden.contains($0) ? "-" : String($0) }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let ownExtension = realExtension((safe as NSString).pathExtension)
        let mimeExtension = item.mediaType.flatMap { UTType(mimeType: $0)?.preferredFilenameExtension }
        let typedExtension = mimeExtension.flatMap { $0 == "bin" ? nil : $0 }
        let ext = try typedExtension ?? (ownExtension.isEmpty ? nil : bounded(ownExtension, bytes: 32))
            ?? sniff(url) ?? "bin"
        let stem = ownExtension.isEmpty ? safe : (safe as NSString).deletingPathExtension
        let name = bounded(stem, bytes: 200)
        return "\(name.isEmpty ? "attachment" : name).\(ext)"
    }

    /// A trailing ".12" or ".2 notes" is part of the title, not a file extension.
    private static func realExtension(_ candidate: String) -> String {
        guard !candidate.isEmpty, candidate.utf8.count <= 32,
              candidate.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.contains($0) })
        else { return "" }
        let lettersOnly = candidate.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
        return lettersOnly || UTType(filenameExtension: candidate)?.isDeclared == true ? candidate : ""
    }

    private static func bounded(_ value: String, bytes: Int) -> String {
        var result = ""
        for character in value {
            guard result.utf8.count + String(character).utf8.count <= bytes else { break }
            result.append(character)
        }
        return result
    }

    private static func sniff(_ url: URL) throws -> String? {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let bytes = Array(try file.read(upToCount: 16) ?? Data())
        if bytes.starts(with: Array("%PDF-".utf8)) { return "pdf" }
        if bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) { return "png" }
        if bytes.starts(with: [255, 216, 255]) { return "jpg" }
        if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) {
            return "gif"
        }
        if [[80, 75, 3, 4], [80, 75, 5, 6], [80, 75, 7, 8]].contains(where: { bytes.starts(with: $0) }) {
            return "zip"
        }
        if bytes.count >= 12, String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp" {
            return String(bytes: bytes[8..<12], encoding: .ascii) == "qt  " ? "mov" : "mp4"
        }
        return nil
    }
}
