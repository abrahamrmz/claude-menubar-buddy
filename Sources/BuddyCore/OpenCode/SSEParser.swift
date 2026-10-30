import Foundation

/// Turns the byte stream of a Server-Sent Events response into the `data`
/// payload of each event the bridge understands.
///
/// Bytes are kept, not text: a multi-byte character can arrive split across
/// two network chunks, and decoding each chunk on its own would corrupt it.
/// A line is only decoded once its terminating `\n` is here, so the character
/// is always whole by then.
public struct SSEParser {
    public init() {}

    private var buffer: [UInt8] = []
    private var dataLines: [String] = []

    /// Feeds bytes as they arrive; returns the `data` payload of every event this chunk completed.
    public mutating func feed(_ chunk: Data) -> [String] {
        buffer.append(contentsOf: chunk)
        var events: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = Array(buffer[..<newline])
            buffer.removeFirst(newline + 1)
            if line.last == 0x0D { line.removeLast() }
            if let event = consume(line: String(decoding: line, as: UTF8.self)) {
                events.append(event)
            }
        }
        return events
    }

    private mutating func consume(line: String) -> String? {
        if line.isEmpty {
            guard !dataLines.isEmpty else { return nil }
            let event = dataLines.joined(separator: "\n")
            dataLines.removeAll()
            return event
        }
        if line.hasPrefix(":") { return nil }
        if line.hasPrefix("data:") {
            var value = String(line.dropFirst("data:".count))
            if value.hasPrefix(" ") { value.removeFirst() }
            dataLines.append(value)
        }
        return nil
    }
}
