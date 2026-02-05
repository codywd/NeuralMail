import Foundation
import Network

actor IMAPClient {
    private let config: IMAPConfiguration
    private var socket: AsyncTCPConnection?
    private var tagCounter: Int = 0

    init(config: IMAPConfiguration) {
        self.config = config
    }

    func connect() async throws {
        let socket = try AsyncTCPConnection(
            host: config.host,
            port: config.port,
            mode: config.security
        )
        try await socket.connect()
        self.socket = socket

        _ = try await readLine() // server greeting
    }

    func disconnect() async {
        await socket?.cancel()
        socket = nil
    }

    func login() async throws {
        let user = IMAPClient.quoteIMAPString(config.username)
        let pass = IMAPClient.quoteIMAPString(config.password)
        _ = try await sendCommand("LOGIN \(user) \(pass)")
    }

    func selectMailbox(_ name: String) async throws {
        _ = try await sendCommand("SELECT \(IMAPClient.quoteIMAPString(name))")
    }

    func mailboxStatus(_ name: String) async throws -> IMAPMailboxStatus {
        let response = try await sendCommand("STATUS \(IMAPClient.quoteIMAPString(name)) (UIDNEXT UIDVALIDITY)")
        var status = IMAPMailboxStatus(uidValidity: nil, uidNext: nil)
        for part in response {
            guard case let .line(line) = part else { continue }
            guard line.hasPrefix("* STATUS") else { continue }
            if let uidValidity = IMAPClient.parseStatusValue(line: line, key: "UIDVALIDITY") {
                status.uidValidity = uidValidity
            }
            if let uidNext = IMAPClient.parseStatusValue(line: line, key: "UIDNEXT") {
                status.uidNext = uidNext
            }
        }
        return status
    }

    func uidSearchAll() async throws -> [UInt32] {
        let response = try await sendCommand("UID SEARCH ALL")
        let searchLines = response.compactMap { part -> String? in
            if case let .line(line) = part, line.hasPrefix("* SEARCH") { return line }
            return nil
        }
        guard let line = searchLines.last else { return [] }
        let pieces = line.split(separator: " ").dropFirst(2)
        return pieces.compactMap { UInt32($0) }
    }

    func uidSearchRange(start: UInt32, end: UInt32?) async throws -> [UInt32] {
        let range = end == nil ? "\(start):*" : "\(start):\(end!)"
        let response = try await sendCommand("UID SEARCH \(range)")
        let searchLines = response.compactMap { part -> String? in
            if case let .line(line) = part, line.hasPrefix("* SEARCH") { return line }
            return nil
        }
        guard let line = searchLines.last else { return [] }
        let pieces = line.split(separator: " ").dropFirst(2)
        return pieces.compactMap { UInt32($0) }
    }

    func listMailboxes() async throws -> [String] {
        let response = try await sendCommand("LIST \"\" \"*\"")
        var names: [String] = []
        for part in response {
            guard case let .line(line) = part else { continue }
            guard line.hasPrefix("* LIST") else { continue }
            if let name = IMAPClient.parseMailboxName(from: line) {
                names.append(name)
            }
        }
        return Array(Set(names)).sorted()
    }

    func fetchHeaders(uids: [UInt32]) async throws -> [UInt32: IMAPParsedHeaders] {
        guard !uids.isEmpty else { return [:] }
        let set = uids.map(String.init).joined(separator: ",")
        let response = try await sendCommand("UID FETCH \(set) (UID BODY.PEEK[HEADER.FIELDS (DATE FROM SUBJECT)])")
        return try parseFetchHeaders(responseParts: response)
    }

    func fetchHeadersAndPreview(uids: [UInt32]) async throws -> [UInt32: IMAPFetchResult] {
        guard !uids.isEmpty else { return [:] }
        let set = uids.map(String.init).joined(separator: ",")
        let response = try await sendCommand("UID FETCH \(set) (UID BODY.PEEK[HEADER.FIELDS (DATE FROM SUBJECT)] BODY.PEEK[TEXT]<0.2048>)")
        return try parseFetchHeadersAndPreview(responseParts: response)
    }

    func fetchBodyText(uid: UInt32) async throws -> Data {
        let response = try await sendCommand("UID FETCH \(uid) (UID BODY.PEEK[TEXT])")
        return try parseFetchSingleLiteral(expectedUID: uid, responseParts: response)
    }

    // MARK: - Internals

    private func sendCommand(_ command: String) async throws -> [IMAPResponsePart] {
        guard let socket else { throw IMAPError.notConnected }

        tagCounter += 1
        let tag = "A\(String(format: "%04d", tagCounter))"
        try await socket.write("\(tag) \(command)\r\n")

        var parts: [IMAPResponsePart] = []
        while true {
            let line = try await readLine()
            parts.append(.line(line))

            if let literalCount = IMAPClient.parseLiteralCount(line: line) {
                let literal = try await socket.readExactly(literalCount)
                parts.append(.literal(literal))
            }

            if line.hasPrefix("\(tag) ") {
                if line.contains(" OK") {
                    return parts
                }
                throw IMAPError.commandFailed(line: line)
            }
        }
    }

    private func readLine() async throws -> String {
        guard let socket else { throw IMAPError.notConnected }
        let data = try await socket.readLineCRLF()
        return String(decoding: data, as: UTF8.self)
    }

    private func parseFetchHeaders(responseParts: [IMAPResponsePart]) throws -> [UInt32: IMAPParsedHeaders] {
        var results: [UInt32: IMAPParsedHeaders] = [:]

        var i = 0
        while i < responseParts.count {
            guard case let .line(line) = responseParts[i] else {
                i += 1
                continue
            }
            if !line.hasPrefix("*") || !line.contains("FETCH") {
                i += 1
                continue
            }

            guard let uid = IMAPClient.parseUID(from: line) else {
                i += 1
                continue
            }

            // Expect headers literal immediately after the fetch line that advertises {n}
            if i + 1 < responseParts.count, case let .literal(data) = responseParts[i + 1] {
                let headersText = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
                results[uid] = IMAPHeaderParser.parse(headersText)
                i += 2
                continue
            }

            i += 1
        }

        return results
    }

    private func parseFetchSingleLiteral(expectedUID: UInt32, responseParts: [IMAPResponsePart]) throws -> Data {
        var i = 0
        while i < responseParts.count {
            guard case let .line(line) = responseParts[i] else {
                i += 1
                continue
            }
            if line.contains("FETCH"), IMAPClient.parseUID(from: line) == expectedUID {
                if i + 1 < responseParts.count, case let .literal(data) = responseParts[i + 1] {
                    return data
                }
            }
            i += 1
        }
        throw IMAPError.unexpectedResponse
    }

    private func parseFetchHeadersAndPreview(responseParts: [IMAPResponsePart]) throws -> [UInt32: IMAPFetchResult] {
        struct Partial {
            var headersData: Data?
            var previewData: Data?
        }

        var results: [UInt32: Partial] = [:]
        var currentUID: UInt32?
        var i = 0

        while i < responseParts.count {
            guard case let .line(line) = responseParts[i] else {
                i += 1
                continue
            }

            if let uid = IMAPClient.parseUID(from: line) {
                currentUID = uid
            }

            if let uid = currentUID, i + 1 < responseParts.count, case let .literal(data) = responseParts[i + 1] {
                if line.contains("HEADER.FIELDS") {
                    var entry = results[uid] ?? Partial()
                    entry.headersData = data
                    results[uid] = entry
                    i += 2
                    continue
                }
                if line.contains("BODY[TEXT]") || line.contains("BODY.PEEK[TEXT]") {
                    var entry = results[uid] ?? Partial()
                    entry.previewData = data
                    results[uid] = entry
                    i += 2
                    continue
                }
            }

            i += 1
        }

        var parsed: [UInt32: IMAPFetchResult] = [:]
        for (uid, entry) in results {
            guard let headersData = entry.headersData else { continue }
            let headersText = String(data: headersData, encoding: .utf8) ?? String(data: headersData, encoding: .isoLatin1) ?? ""
            parsed[uid] = IMAPFetchResult(headers: IMAPHeaderParser.parse(headersText), previewData: entry.previewData)
        }
        return parsed
    }

    static func quoteIMAPString(_ value: String) -> String {
        var escaped = value
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func parseUID(from line: String) -> UInt32? {
        guard let range = line.range(of: "UID ") else { return nil }
        let remainder = line[range.upperBound...]
        let digits = remainder.prefix { $0.isNumber }
        return UInt32(digits)
    }

    static func parseLiteralCount(line: String) -> Int? {
        guard line.hasSuffix("}") else { return nil }
        guard let openBrace = line.lastIndex(of: "{") else { return nil }
        let numberStart = line.index(after: openBrace)
        let numberEnd = line.index(before: line.endIndex)
        let number = line[numberStart..<numberEnd]
        return Int(number)
    }

    static func parseStatusValue(line: String, key: String) -> UInt32? {
        guard let range = line.range(of: "\(key) ") else { return nil }
        let remainder = line[range.upperBound...]
        let digits = remainder.prefix { $0.isNumber }
        return UInt32(digits)
    }

    static func parseMailboxName(from line: String) -> String? {
        if let lastQuote = line.lastIndex(of: "\"") {
            let start = line[..<lastQuote]
            if let firstQuote = start.lastIndex(of: "\"") {
                let nameStart = line.index(after: firstQuote)
                let name = line[nameStart..<lastQuote]
                return String(name)
            }
        }
        // Fallback: last token
        let parts = line.split(separator: " ")
        guard let last = parts.last else { return nil }
        return String(last.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
    }
}

enum IMAPResponsePart {
    case line(String)
    case literal(Data)
}

enum IMAPError: LocalizedError {
    case notConnected
    case commandFailed(line: String)
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected."
        case .commandFailed(let line):
            return "IMAP command failed: \(line)"
        case .unexpectedResponse:
            return "IMAP server returned an unexpected response."
        }
    }
}

struct IMAPParsedHeaders: Sendable {
    let subject: String
    let from: String
    let date: Date?
}

struct IMAPMailboxStatus: Sendable {
    var uidValidity: UInt32?
    var uidNext: UInt32?
}

struct IMAPFetchResult: Sendable {
    let headers: IMAPParsedHeaders
    let previewData: Data?
}

enum IMAPHeaderParser {
    private static let rfc2822DateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        return df
    }()

    static func parse(_ raw: String) -> IMAPParsedHeaders {
        let headers = parseHeaderFields(raw)
        let subject = decodeRFC2047(headers["subject"] ?? "")
        let from = decodeRFC2047(headers["from"] ?? "")
        let dateString = headers["date"] ?? ""
        let date = rfc2822DateFormatter.date(from: dateString) ?? DateParser.fallback(dateString: dateString)

        return IMAPParsedHeaders(subject: subject, from: from, date: date)
    }

    private static func parseHeaderFields(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        var currentKey: String?
        var currentValue = ""

        func flush() {
            guard let key = currentKey else { return }
            result[key] = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let lines = raw.split(whereSeparator: \.isNewline)
        for lineSub in lines {
            let line = String(lineSub)
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                currentValue += " " + line.trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            flush()

            guard let colon = line.firstIndex(of: ":") else {
                currentKey = nil
                currentValue = ""
                continue
            }

            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            currentKey = key
            currentValue = value
        }

        flush()
        return result
    }

    private static func decodeRFC2047(_ value: String) -> String {
        // Minimal decoder for common patterns: =?utf-8?B?...?= and =?utf-8?Q?...?=
        var output = value
        let pattern = "=\\?([^?]+)\\?([bBqQ])\\?([^?]+)\\?="
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return value
        }

        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        let matches = regex.matches(in: output, options: [], range: range).reversed()
        for match in matches {
            guard match.numberOfRanges == 4,
                  let charsetRange = Range(match.range(at: 1), in: output),
                  let encodingRange = Range(match.range(at: 2), in: output),
                  let textRange = Range(match.range(at: 3), in: output)
            else { continue }

            let charset = output[charsetRange].lowercased()
            let encoding = output[encodingRange].lowercased()
            let encodedText = String(output[textRange])

            let decoded: String?
            if encoding == "b" {
                decoded = Data(base64Encoded: encodedText)
                    .flatMap { String(data: $0, encoding: charset == "utf-8" ? .utf8 : .isoLatin1) }
            } else {
                decoded = decodeQ(encodedText, charset: charset)
            }

            if let decoded, let wholeRange = Range(match.range(at: 0), in: output) {
                output.replaceSubrange(wholeRange, with: decoded)
            }
        }

        return output
    }

    private static func decodeQ(_ text: String, charset: String) -> String? {
        // RFC 2047 "Q" encoding is like quoted-printable with '_' as space.
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.count)

        let scalars = Array(text.utf8)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if c == 0x5F { // _
                bytes.append(0x20) // space
                i += 1
                continue
            }
            if c == 0x3D, i + 2 < scalars.count { // =
                let h1 = scalars[i + 1]
                let h2 = scalars[i + 2]
                if let v1 = hexValue(h1), let v2 = hexValue(h2) {
                    bytes.append((v1 << 4) | v2)
                    i += 3
                    continue
                }
            }
            bytes.append(c)
            i += 1
        }

        let data = Data(bytes)
        if charset == "utf-8" {
            return String(data: data, encoding: .utf8)
        }
        return String(data: data, encoding: .isoLatin1)
    }

    private static func hexValue(_ c: UInt8) -> UInt8? {
        if (0x30...0x39).contains(c) { // 0-9
            return c - 0x30
        }
        if (0x41...0x46).contains(c) { // A-F
            return c - 0x41 + 10
        }
        if (0x61...0x66).contains(c) { // a-f
            return c - 0x61 + 10
        }
        return nil
    }
}

enum DateParser {
    static func fallback(dateString: String) -> Date? {
        let formats = [
            "EEE, d MMM yyyy HH:mm Z",
            "d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm Z",
        ]

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            df.dateFormat = format
            if let date = df.date(from: dateString) {
                return date
            }
        }
        return nil
    }
}
