import Foundation

enum IMAPBodyPreviewParser {
    static func previewText(from data: Data?) -> String? {
        guard let data else { return nil }
        var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        text = text.replacingOccurrences(of: "\0", with: "")

        if text.contains("<html") || text.contains("<body") || text.contains("<div") || text.contains("<p") {
            text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            text = text.replacingOccurrences(of: "&nbsp;", with: " ")
            text = text.replacingOccurrences(of: "&amp;", with: "&")
            text = text.replacingOccurrences(of: "&lt;", with: "<")
            text = text.replacingOccurrences(of: "&gt;", with: ">")
        }

        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var output = ""
        for line in lines {
            if line.hasPrefix(">") { continue }
            if line.hasPrefix("--") { continue }
            let lower = line.lowercased()
            if lower.hasPrefix("on "), lower.contains(" wrote:") { continue }

            if !output.isEmpty { output += " " }
            output += line
            if output.count >= 280 { break }
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

