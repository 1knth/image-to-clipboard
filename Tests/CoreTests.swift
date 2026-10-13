import Foundation
import Vision
import AppKit

@main
struct CoreTests {
    static func main() throws {
        let shortcutEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .shift], timestamp: 0, windowNumber: 0, context: nil, characters: "T", charactersIgnoringModifiers: "t", isARepeat: false, keyCode: 17)!
        precondition(KeyboardShortcut.from(shortcutEvent) == .defaultValue)
        let customEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option], timestamp: 0, windowNumber: 0, context: nil, characters: "s", charactersIgnoringModifiers: "s", isARepeat: false, keyCode: 1)!
        precondition(KeyboardShortcut.from(customEvent)?.display == "⌥⌘S")
        let bareEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "t", charactersIgnoringModifiers: "t", isARepeat: false, keyCode: 17)!
        precondition(KeyboardShortcut.from(bareEvent) == nil)
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        precondition(KeyboardShortcut.from(escape) == nil)
        let screen = CGRect(x: -1200, y: 300, width: 1200, height: 800)
        let plan = CaptureGeometry.plan(selection: CGRect(x: -1100, y: 700, width: 400, height: 200), screen: screen, scale: 2)!
        precondition(plan.rect == CGRect(x: 100, y: 200, width: 400, height: 200))
        precondition(plan.width == 800 && plan.height == 400)
        let clipped = CaptureGeometry.plan(selection: CGRect(x: -1250, y: 1050, width: 100, height: 100), screen: screen, scale: 1)!
        precondition(clipped.rect == CGRect(x: 0, y: 0, width: 50, height: 50))
        precondition(CaptureGeometry.plan(selection: .zero, screen: screen, scale: 2) == nil)
        precondition(CaptureGeometry.plan(selection: screen, screen: screen, scale: 0) == nil)
        let fractional = CaptureGeometry.plan(selection: CGRect(x: -1199.8, y: 300.2, width: 10.1, height: 10.1), screen: screen, scale: 2)!
        precondition(fractional.width == 21 && fractional.height == 21)
        let lines = [OCRLine(text: "second", bounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1)), OCRLine(text: "right", bounds: CGRect(x: 0.6, y: 0.805, width: 0.3, height: 0.1)), OCRLine(text: "left", bounds: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.1))]
        precondition(TextAssembler.assemble(lines) == "left right\nsecond")
        precondition(TextAssembler.assemble([]) == "")
        // Exercise the actual Vision engine on a generated image, without screen permission.
        let image = NSImage(size: NSSize(width: 900, height: 180))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 900, height: 180).fill()
        "Clippy OCR test 12345".draw(at: NSPoint(x: 40, y: 60), withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
        image.unlockFocus()
        var rect = NSRect(origin: .zero, size: image.size)
        let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        guard text.contains("Clippy OCR test 12345") else { fatalError("Unexpected OCR: \(text)") }
        _ = NSApplication.shared
        let settings = ClippySettingsController(shortcut: .defaultValue, languages: [], supported: ["en-US", "fr-FR"], correctSpelling: true)
        settings.window?.appearance = NSAppearance(named: .aqua)
        settings.showWindow(nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        let content = settings.window!.contentView!
        content.layoutSubtreeIfNeeded()
        let stack = content.subviews.first as! NSStackView
        precondition(!stack.hasAmbiguousLayout)
        for view in stack.arrangedSubviews {
            precondition(view.frame.minY >= 0 && view.frame.maxY <= stack.bounds.height + 1, "Settings row outside layout")
        }
        if let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/settings-preview.png"))
        }
        settings.close()
        for width: CGFloat in [390, 1200] {
            for message in ["Text copied", "Capture already in progress.", "Shortcut unavailable. Use Capture Text in the menu."] {
                let screen = CGRect(x: -500, y: 100, width: width, height: 700)
                let panel = FeedbackPanel(message: message, visibleFrame: screen)
                panel.contentView!.layoutSubtreeIfNeeded()
                precondition(screen.contains(panel.frame), "Feedback must remain inside the visible screen")
                func textFields(in view: NSView) -> [NSTextField] {
                    view.subviews.flatMap { subview in ([subview as? NSTextField].compactMap { $0 }) + textFields(in: subview) }
                }
                let label = textFields(in: panel.contentView!).first!
                let labelFrame = label.convert(label.bounds, to: panel.contentView!)
                precondition(abs(labelFrame.midY - panel.contentView!.bounds.midY) < 1, "Feedback text must be vertically centered")
                precondition(labelFrame.width > 0 && panel.contentView!.bounds.contains(labelFrame), "Feedback text must fit")
            }
        }
        print("Passed shortcut parsing, geometry, text ordering, and real Vision OCR checks.")
    }
}
