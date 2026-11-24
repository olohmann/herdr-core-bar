import Foundation

/// Splits a byte stream into `\n`-terminated lines, rejecting lines longer than `maxLineLength` bytes.
struct LineBuffer: Sendable {
    let maxLineLength: Int
    private var partial = Data()

    init(maxLineLength: Int) {
        self.maxLineLength = maxLineLength
    }

    /// Appends bytes and returns the complete, non-empty lines (without terminator) they finish.
    mutating func append(_ bytes: some Collection<UInt8>) throws(CoreError) -> [Data] {
        var lines: [Data] = []
        var rest = bytes[...]
        while let newline = rest.firstIndex(of: 0x0A) {
            let segment = rest[..<newline]
            guard partial.count + segment.count <= maxLineLength + 1 else { throw .lineTooLong }
            var line = partial
            line.append(contentsOf: segment)
            partial = Data()
            if line.last == 0x0D { line.removeLast() }
            guard line.count <= maxLineLength else { throw .lineTooLong }
            if !line.isEmpty { lines.append(line) }
            rest = rest[rest.index(after: newline)...]
        }
        guard partial.count + rest.count <= maxLineLength else { throw .lineTooLong }
        partial.append(contentsOf: rest)
        return lines
    }
}
