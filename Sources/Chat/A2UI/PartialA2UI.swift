import Foundation

nonisolated func healedA2UIPrefix(_ partial: String) -> String? {
    var open: [UInt8] = []
    var inString = false
    var escaped = false
    var cut: (end: Int, open: [UInt8])?
    for (index, byte) in partial.utf8.enumerated() {
        if inString {
            if escaped {
                escaped = false
            } else if byte == UInt8(ascii: "\\") {
                escaped = true
            } else if byte == UInt8(ascii: "\"") {
                inString = false
            }
            continue
        }
        if byte == UInt8(ascii: "\"") {
            inString = true
        } else if byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[") {
            open.append(byte)
        } else if byte == UInt8(ascii: "}") || byte == UInt8(ascii: "]") {
            guard open.popLast() != nil else { return nil }
            if byte == UInt8(ascii: "}"), open.last == UInt8(ascii: "[") { cut = (index + 1, open) }
        }
    }
    guard let cut else { return nil }
    let closers = cut.open.reversed().map { $0 == UInt8(ascii: "{") ? "}" : "]" }.joined()
    return String(decoding: partial.utf8.prefix(cut.end), as: UTF8.self) + closers
}

nonisolated func previewStep(forLength length: Int) -> Int {
    Int(log2(Double(length + 1024)) * 24)
}
