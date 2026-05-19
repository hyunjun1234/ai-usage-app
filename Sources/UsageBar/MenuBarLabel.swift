import AppKit

/// A status-bar view that draws up to two right-aligned lines, vertically
/// centered. NSStatusItem's own multi-line title renders too high, so the
/// menu-bar text is drawn manually here instead.
final class MenuBarLabel: NSView {
    struct Line {
        let text: String
        let color: NSColor
    }

    var lines: [Line] = [] {
        didSet { needsDisplay = true }
    }

    private let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
    private let lineGap: CGFloat = 0
    private let sidePadding: CGFloat = 5

    /// Width the status item should reserve for the current text.
    var contentWidth: CGFloat {
        let widest = lines
            .map { ($0.text as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        return ceil(widest) + sidePadding * 2
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !lines.isEmpty else { return }
        let lineHeight = ("0" as NSString).size(withAttributes: [.font: font]).height
        let total = lineHeight * CGFloat(lines.count) + lineGap * CGFloat(lines.count - 1)
        let topY = (bounds.height + total) / 2     // AppKit y-up

        for (i, line) in lines.enumerated() {
            let str = NSAttributedString(string: line.text,
                                         attributes: [.font: font, .foregroundColor: line.color])
            let size = str.size()
            let y = topY - lineHeight * CGFloat(i + 1) - lineGap * CGFloat(i)
            str.draw(at: NSPoint(x: bounds.width - size.width - sidePadding, y: y))
        }
    }

    /// Let clicks fall through to the underlying status-item button.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        needsDisplay = true
    }
}
