import Foundation

/// Pure greedy row packing for the Home dashboard reflow. Given each card's
/// column span, pack them into rows of at most `columns` columns. Extracted so
/// the reflow behaviour is unit-testable.
enum DashboardPacking {
    /// Returns rows of item indices.
    static func rows(spans: [Int], columns: Int = 4) -> [[Int]] {
        var result: [[Int]] = []
        var current: [Int] = []
        var used = 0
        for (index, rawSpan) in spans.enumerated() {
            let span = max(1, min(rawSpan, columns))
            if used + span > columns, !current.isEmpty {
                result.append(current); current = []; used = 0
            }
            current.append(index); used += span
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

/// Solves which favorite modules fit on Home for the current layout, moving
/// overflow off Home rather than shrinking cards below usable size. Pure and
/// deterministic — preserves the given order.
enum HomeSolver {
    struct Item: Equatable { var id: String; var span: Int; var minWidth: CGFloat }
    struct Result: Equatable { var home: [String]; var overflow: [String] }

    /// - Parameters:
    ///   - items: favorites in user order (span = column span for its size).
    ///   - availableWidth: usable dashboard content width (points).
    ///   - maxModules: hard cap from layout class / user preference.
    ///   - columns: grid columns (default 4).
    static func solve(items: [Item], availableWidth: CGFloat,
                      maxModules: Int, columns: Int = 4) -> Result {
        let unit = max(1, (availableWidth - 10 * CGFloat(columns - 1)) / CGFloat(columns))
        var home: [String] = []
        var overflow: [String] = []
        for item in items {
            let span = max(1, min(item.span, columns))
            let cardWidth = unit * CGFloat(span) + 10 * CGFloat(span - 1)
            // Move off Home if we've hit the cap or the card can't meet its min.
            if home.count >= maxModules || cardWidth < item.minWidth {
                overflow.append(item.id)
            } else {
                home.append(item.id)
            }
        }
        return Result(home: home, overflow: overflow)
    }
}
