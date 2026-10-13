import CoreGraphics

struct OCRLine {
    let text: String
    let bounds: CGRect
}

enum TextAssembler {
    static func assemble(_ lines: [OCRLine]) -> String {
        let sorted = lines.sorted { lhs, rhs in
            if lhs.bounds.midY != rhs.bounds.midY { return lhs.bounds.midY > rhs.bounds.midY }
            return lhs.bounds.minX < rhs.bounds.minX
        }
        var rows: [[OCRLine]] = []
        for line in sorted {
            if let last = rows.last, let anchor = last.first,
               abs(anchor.bounds.midY - line.bounds.midY) <= min(anchor.bounds.height, line.bounds.height) * 0.4 {
                rows[rows.count - 1].append(line)
            } else { rows.append([line]) }
        }
        return rows.map { row in row.sorted { $0.bounds.minX < $1.bounds.minX }.map(\.text).joined(separator: " ") }.joined(separator: "\n")
    }
}
