import Foundation
import CoreGraphics

/// Resolved Files-tab editorial frames for the current page.
struct FilesLayout: Equatable {
    var frames: [String: CGRect]     // moduleID → frame
    var pageCount: Int
    func frame(_ id: String) -> CGRect? { frames[id] }
}

/// Pure editorial layout for the Files tab: Clipboard as the main left column,
/// a right column stacking Downloads (top) over Screen (bottom). Deterministic;
/// compact falls back to two pages (Clipboard, then Downloads+Screen).
enum FilesEditorialLayout {
    static let clipboardID = "clipboard"
    static let downloadsID = "downloads"
    static let screenID = "screenshot"

    /// Left column width as a fraction of the row (within the 56–62% target).
    static let leftRatio: CGFloat = 0.58

    static func layout(contentSize: CGSize,
                       layoutClass: NotchLayoutClass,
                       split: FilesRightSplit,
                       page: Int = 0,
                       dividerWidth: CGFloat = 1,
                       spacing: CGFloat = 12) -> FilesLayout {
        let W = contentSize.width, H = contentSize.height

        if layoutClass == .compact {
            // Page 0: Clipboard full. Page 1: Downloads over Screen.
            let pageCount = 2
            let idx = max(0, min(page, pageCount - 1))
            if idx == 0 {
                return FilesLayout(frames: [clipboardID: CGRect(x: 0, y: 0, width: W, height: H)],
                                   pageCount: pageCount)
            }
            let topH = (H - spacing) * split.downloadsFraction
            let botH = H - spacing - topH
            return FilesLayout(frames: [
                downloadsID: CGRect(x: 0, y: 0, width: W, height: topH),
                screenID: CGRect(x: 0, y: topH + spacing, width: W, height: botH),
            ], pageCount: pageCount)
        }

        // Regular / spacious: one row, left column + right stacked column.
        let available = max(0, W - spacing - dividerWidth)
        let leftW = (available * leftRatio).rounded()
        let rightW = available - leftW
        let rightX = leftW + spacing + dividerWidth

        let topH = ((H - spacing) * split.downloadsFraction).rounded()
        let botH = H - spacing - topH

        return FilesLayout(frames: [
            clipboardID: CGRect(x: 0, y: 0, width: leftW, height: H),
            downloadsID: CGRect(x: rightX, y: 0, width: rightW, height: topH),
            screenID: CGRect(x: rightX, y: topH + spacing, width: rightW, height: botH),
        ], pageCount: 1)
    }
}
