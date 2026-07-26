import Foundation

/// A widget resolved to a concrete grid cell rectangle on a page.
struct GridCell: Identifiable, Equatable {
    var id: String
    var page: Int
    var col: Int
    var row: Int
    var w: Int
    var h: Int
    var maxX: Int { col + w }
    var maxY: Int { row + h }
}

/// Magnetic responsive grid. Places widgets deterministically: honour a
/// widget's preferred cell when free, otherwise scan row-major for the first
/// free rectangle that fits, never overlapping, clamped inside `columns`, and
/// overflowing to the next page after `maxRows`. No absolute pixels — pure cells.
enum GridSolver {
    struct Item: Equatable {
        var id: String
        var w: Int
        var h: Int
        var preferredCol: Int?
        var preferredRow: Int?
    }

    struct Result: Equatable {
        var cells: [GridCell]
        var pageCount: Int
    }

    static func solve(items: [Item], columns: Int, maxRows: Int = DashboardGrid.maxRowsPerPage) -> Result {
        var cells: [GridCell] = []
        // occupancy[page] = set of occupied (col,row) keys
        var occupancy: [Int: Set<Int>] = [:]
        func key(_ c: Int, _ r: Int) -> Int { r * 1000 + c }
        func fits(page: Int, col: Int, row: Int, w: Int, h: Int) -> Bool {
            guard col >= 0, col + w <= columns, row >= 0, row + h <= maxRows else { return false }
            let occ = occupancy[page] ?? []
            for r in row..<(row + h) {
                for c in col..<(col + w) where occ.contains(key(c, r)) { return false }
            }
            return true
        }
        func occupy(page: Int, col: Int, row: Int, w: Int, h: Int) {
            var occ = occupancy[page] ?? []
            for r in row..<(row + h) { for c in col..<(col + w) { occ.insert(key(c, r)) } }
            occupancy[page] = occ
        }
        func firstFree(page: Int, w: Int, h: Int) -> (Int, Int)? {
            for row in 0..<maxRows {
                for col in 0...(max(0, columns - w)) where fits(page: page, col: col, row: row, w: w, h: h) {
                    return (col, row)
                }
            }
            return nil
        }

        for raw in items {
            let w = max(1, min(raw.w, columns))
            let h = max(1, min(raw.h, maxRows))
            var page = 0
            var placed = false
            // Try preferred cell on page 0 first.
            if let pc = raw.preferredCol, let pr = raw.preferredRow,
               fits(page: 0, col: min(pc, columns - w), row: pr, w: w, h: h) {
                let col = min(pc, columns - w)
                occupy(page: 0, col: col, row: pr, w: w, h: h)
                cells.append(GridCell(id: raw.id, page: 0, col: col, row: pr, w: w, h: h))
                placed = true
            }
            // Otherwise first-free, overflowing to later pages.
            while !placed {
                if let (col, row) = firstFree(page: page, w: w, h: h) {
                    occupy(page: page, col: col, row: row, w: w, h: h)
                    cells.append(GridCell(id: raw.id, page: page, col: col, row: row, w: w, h: h))
                    placed = true
                } else {
                    page += 1
                    if page > 8 { break }   // hard safety
                }
            }
        }
        let pageCount = max(1, (cells.map(\.page).max() ?? 0) + 1)
        return Result(cells: cells, pageCount: pageCount)
    }

    /// True if two cells overlap (test helper).
    static func overlaps(_ a: GridCell, _ b: GridCell) -> Bool {
        a.page == b.page && a.col < b.maxX && b.col < a.maxX && a.row < b.maxY && b.row < a.maxY
    }

    /// Which grid cell a drop point maps to (snapping).
    static func cell(forDropAt point: CGPoint, in size: CGSize, columns: Int, rows: Int) -> (col: Int, row: Int) {
        let cw = size.width / CGFloat(columns)
        let ch = rows > 0 ? size.height / CGFloat(rows) : size.height
        let col = Int((point.x / max(1, cw)).rounded(.down)).clampedInt(0, columns - 1)
        let row = Int((point.y / max(1, ch)).rounded(.down)).clampedInt(0, max(0, rows - 1))
        return (col, row)
    }
}

extension Int {
    func clampedInt(_ lo: Int, _ hi: Int) -> Int { Swift.min(Swift.max(self, lo), Swift.max(lo, hi)) }
}
