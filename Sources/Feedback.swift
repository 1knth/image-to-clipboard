import AppKit

final class FeedbackPanel: NSPanel {
    init(message: String, visibleFrame: CGRect) {
        let displayMessage = message == "Text copied" ? "Copied to clipboard" : message
        let isSuccess = message == "Text copied"
        let font = NSFont.systemFont(ofSize: 17, weight: .regular)
        let textSize = (displayMessage as NSString).size(withAttributes: [.font: font])
        let horizontalPadding: CGFloat = 24
        let iconSize: CGFloat = 20
        let gap: CGFloat = 13
        let naturalWidth = ceil(textSize.width) + horizontalPadding * 2 + iconSize + gap
        let width = min(max(240, naturalWidth), max(240, visibleFrame.width - 32))
        let height: CGFloat = 62
        let frame = CGRect(
            x: round(visibleFrame.midX - width / 2),
            y: round(visibleFrame.maxY - height - 24),
            width: width,
            height: height
        )
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        alphaValue = 0
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let glass = NSVisualEffectView(frame: CGRect(origin: .zero, size: frame.size))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.backgroundColor = NSColor.clear.cgColor
        glass.layer?.cornerRadius = height / 2
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 0
        glass.layer?.shadowOpacity = 0

        let label = NSTextField(labelWithString: displayMessage)
        label.font = font
        label.textColor = .labelColor
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let symbol = isSuccess ? "checkmark.circle.fill" : "info.circle.fill"
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = isSuccess ? NSColor.systemGreen : NSColor.secondaryLabelColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [icon, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = gap
        row.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(row)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: iconSize),
            icon.heightAnchor.constraint(equalToConstant: iconSize),
            row.centerXAnchor.constraint(equalTo: glass.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: glass.centerYAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: glass.leadingAnchor, constant: horizontalPadding),
            row.trailingAnchor.constraint(lessThanOrEqualTo: glass.trailingAnchor, constant: -horizontalPadding)
        ])
        contentView = glass
    }

    func fadeIn() {
        animator().alphaValue = 1
    }

    func fadeOut(completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = 0
        } completionHandler: {
            completion()
        }
    }
}
