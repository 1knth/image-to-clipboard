import AppKit
import ScreenCaptureKit
import Vision
import Carbon

private func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
}

final class SelectionView: NSView {
    var start: CGPoint?
    var end: CGPoint?
    var finish: ((CGRect) -> Void)?
    var cancel: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        start = convert(event.locationInWindow, from: nil)
        end = start
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        end = CGPoint(x: max(0, min(bounds.width, point.x)), y: max(0, min(bounds.height, point.y)))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        guard let start, let end else { return }
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        if rect.width < 2 || rect.height < 2 { cancel?() } else { finish?(rect) }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancel?() }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.22).setFill()
        bounds.fill()
        if let start, let end {
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            rect.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 1
            path.stroke()
        }
        let message = "Drag around text. Release to copy. Esc cancels."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let padding = CGSize(width: 14, height: 9)
        let measured = (message as NSString).size(withAttributes: attributes)
        let bubble = CGRect(x: 20, y: 20, width: measured.width + padding.width * 2, height: measured.height + padding.height * 2)
        NSColor.black.withAlphaComponent(0.48).setFill()
        NSBezierPath(roundedRect: bubble, xRadius: 11, yRadius: 11).fill()
        message.draw(at: CGPoint(x: bubble.minX + padding.width, y: bubble.minY + padding.height), withAttributes: attributes)
    }
}

final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppController: NSObject, NSApplicationDelegate {
    private var status: NSStatusItem!
    private var captureItem: NSMenuItem!
    private var cancelItem: NSMenuItem!
    private var windows: [NSWindow] = []
    private var job: UUID?
    private var workerActive = false
    private var previousApp: NSRunningApplication?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var toast: NSPanel?
    private var toastTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var started = false
    private var shortcutStatus = "Shortcut not registered"
    private let ocrQueue = DispatchQueue(label: "app.scanner.ocr", qos: .userInitiated)
    private var literalMode: Bool { UserDefaults.standard.bool(forKey: "literalMode") }
    private var shortcut: KeyboardShortcut { KeyboardShortcut.load() }
    private var registeredShortcut: KeyboardShortcut?
    private var settingsController: ClippySettingsController?
    private var literalItem: NSMenuItem?
    private var recognitionLanguages: [String] { UserDefaults.standard.stringArray(forKey: "recognitionLanguages") ?? [] }

    func applicationDidFinishLaunching(_ notification: Notification) {
        start()
    }

    func start() {
        guard !started else { return }
        started = true
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.isVisible = true
        if let icon = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Clippy") {
            icon.size = NSSize(width: 18, height: 18)
            icon.isTemplate = true
            status.button?.image = icon
        } else {
            status.button?.title = "Clip"
        }
        status.button?.toolTip = "Clippy — capture text from your screen"
        let menu = NSMenu()
        captureItem = NSMenuItem(title: "Capture Text    \(shortcut.display)", action: #selector(beginCapture), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        cancelItem = NSMenuItem(title: "Cancel Capture", action: #selector(cancelCapture), keyEquivalent: "")
        cancelItem.target = self
        cancelItem.isHidden = true
        menu.addItem(cancelItem)
        menu.addItem(.separator())
        let literal = NSMenuItem(title: "Literal Text (Disable Spelling Correction)", action: #selector(toggleLiteral(_:)), keyEquivalent: "")
        literalItem = literal
        literal.target = self
        literal.state = literalMode ? .on : .off
        menu.addItem(literal)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let permission = NSMenuItem(title: "Screen Capture Permission…", action: #selector(openPermission), keyEquivalent: "")
        permission.target = self
        menu.addItem(permission)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Clippy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        status.menu = menu
        registerShortcut()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.windows.isEmpty else { return }
                self.cancelCapture()
                self.showFeedback("Displays changed. Try again.")
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening the app again keeps it in the menu bar without creating a window.
        return false
    }

    @discardableResult
    private func registerShortcut(_ candidate: KeyboardShortcut? = nil) -> Bool {
        let value = candidate ?? shortcut
        if registeredShortcut == value, hotKey != nil { return true }
        if eventHandler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let context = Unmanaged.passUnretained(self).toOpaque()
            let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, pointer in
                guard let pointer else { return OSStatus(eventNotHandledErr) }
                let app = Unmanaged<AppController>.fromOpaque(pointer).takeUnretainedValue()
                DispatchQueue.main.async {
                    // Keep an existing global shortcut from interrupting its recorder.
                    guard app.settingsController == nil else { return }
                    app.beginCapture()
                }
                return noErr
            }, 1, &event, context, &eventHandler)
            guard installed == noErr else { shortcutStatus = "Shortcut handler unavailable. Use Capture Text."; return false }
        }
        var replacement: EventHotKeyRef?
        let result = RegisterEventHotKey(value.keyCode, value.modifiers, EventHotKeyID(signature: 0x53434E52, id: 1), GetApplicationEventTarget(), 0, &replacement)
        guard result == noErr else {
            fputs("Clippy: shortcut registration failed (\(result))\n", stderr)
            if hotKey == nil { shortcutStatus = "Shortcut unavailable. Use Capture Text." }
            return false
        }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        registeredShortcut = value
        shortcutStatus = "Shortcut ready: \(value.display)"
        fputs("Clippy: shortcut registered \(value.display)\n", stderr)
        return true
    }

    @objc private func openSettings() {
        guard job == nil, !workerActive else { showFeedback("Finish or cancel the capture first."); return }
        if let settingsController {
            NSApp.activate(ignoringOtherApps: true)
            settingsController.showWindow(nil)
            settingsController.window?.makeKeyAndOrderFront(nil)
            return
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let settings = ClippySettingsController(shortcut: shortcut, languages: recognitionLanguages, supported: supported, correctSpelling: !literalMode)
        settings.save = { [weak self] candidate, languages, correction in
            guard let self else { return "Clippy is closing." }
            guard self.registerShortcut(candidate) else {
                return "That shortcut is unavailable. Choose another combination; your previous shortcut is still active."
            }
            candidate.persist()
            UserDefaults.standard.set(languages, forKey: "recognitionLanguages")
            UserDefaults.standard.set(!correction, forKey: "literalMode")
            self.literalItem?.state = correction ? .off : .on
            self.captureItem.title = "Capture Text    \(candidate.display)"
            return nil
        }
        settings.openPermissions = { [weak self] in self?.openPermission() }
        settings.didClose = { [weak self] in self?.settingsController = nil }
        settingsController = settings
        NSApp.activate(ignoringOtherApps: true)
        settings.showWindow(nil)
        settings.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLiteral(_ sender: NSMenuItem) {
        UserDefaults.standard.set(!literalMode, forKey: "literalMode")
        sender.state = literalMode ? .on : .off
    }

    @objc private func openPermission() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }

    @objc func beginCapture() {
        fputs("Clippy: capture requested\n", stderr)
        guard job == nil, !workerActive else { showFeedback("Capture already in progress."); return }
        dismissFeedback()
        previousApp = NSWorkspace.shared.frontmostApplication
        // Preflight is advisory: let ScreenCaptureKit report whether this process
        // can actually capture rather than blocking on a stale preflight result.
        let preflight = CGPreflightScreenCaptureAccess()
        fputs("Clippy: screen permission preflight=\(preflight)\n", stderr)
        if !preflight { _ = CGRequestScreenCaptureAccess() }
        let id = UUID()
        job = id
        updateBusy()
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard self.job == id else { return }
                let screens = NSScreen.screens.filter { screen in content.displays.contains { $0.displayID == displayID(screen) } }
                guard !screens.isEmpty else { throw ClippyError.message("No available display.") }
                self.presentSelection(screens: screens, id: id)
            } catch { self.fail(error, id: id, stage: "Preparing screen capture") }
        }
    }

    private func presentSelection(screens: [NSScreen], id: UUID) {
        for screen in screens {
            let window = SelectionWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.cancel = { [weak self] in self?.cancelCapture() }
            view.finish = { [weak self] rect in
                let global = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
                self?.capture(rect: global, screen: screen, id: id)
            }
            window.contentView = view
            windows.append(window)
            window.orderFrontRegardless()
            window.makeFirstResponder(view)
        }
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        (windows.first { $0.frame.contains(mouse) } ?? windows.first)?.makeKey()
    }

    private func capture(rect: CGRect, screen: NSScreen, id: UUID) {
        guard job == id, !workerActive else { return }
        workerActive = true
        let overlayIDs = Set(windows.map { CGWindowID($0.windowNumber) })
        closeSelection()
        let correction = !literalMode
        let languages = recognitionLanguages
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard self.job == id else { self.drain(); return }
                guard let display = content.displays.first(where: { $0.displayID == displayID(screen) }) else { throw ClippyError.message("Display changed. Try again.") }
                let excluded = content.windows.filter { overlayIDs.contains($0.windowID) }
                // The selection windows are ordered out before capture, then excluded defensively
                // if ScreenCaptureKit still reports them during its content refresh.
                let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                let effectiveFilter = ownApps.isEmpty ? SCContentFilter(display: display, excludingWindows: excluded) : filter
                guard let plan = CaptureGeometry.plan(selection: rect, screen: screen.frame, scale: CGFloat(effectiveFilter.pointPixelScale)) else { throw ClippyError.message("Select a larger region.") }
                guard plan.width <= 12000, plan.height <= 12000, plan.width * plan.height <= 32_000_000 else { throw ClippyError.message("Select a smaller region (maximum 32 megapixels).") }
                let configuration = SCStreamConfiguration()
                configuration.sourceRect = plan.rect
                configuration.width = plan.width
                configuration.height = plan.height
                configuration.showsCursor = false
                configuration.capturesAudio = false
                configuration.pixelFormat = kCVPixelFormatType_32BGRA
                let image = try await SCScreenshotManager.captureImage(contentFilter: effectiveFilter, configuration: configuration)
                guard self.job == id else { self.drain(); return }
                guard image.width == plan.width, image.height == plan.height else { throw ClippyError.message("Unexpected screenshot size. Try again.") }
                self.recognize(image, correction: correction, languages: languages, id: id)
            } catch { self.drain(); self.fail(error, id: id, stage: "Capturing selected region") }
        }
    }

    private func recognize(_ image: CGImage, correction: Bool, languages: [String], id: UUID) {
        ocrQueue.async {
            let result: Result<String, Error> = Result {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = correction
                request.automaticallyDetectsLanguage = languages.isEmpty
                if !languages.isEmpty { request.recognitionLanguages = languages }
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                let lines = (request.results ?? []).compactMap { observation -> OCRLine? in
                    guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
                    return OCRLine(text: text, bounds: observation.boundingBox)
                }
                return TextAssembler.assemble(lines)
            }
            DispatchQueue.main.async {
                self.drain()
                guard self.job == id else { return }
                switch result {
                case .success(let text):
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        self.complete(id: id, message: "No text found."); return
                    }
                    NSPasteboard.general.clearContents()
                    let copied = NSPasteboard.general.setString(text, forType: .string)
                    self.complete(id: id, message: copied ? "Text copied" : "Couldn’t copy text.")
                case .failure(let error): self.fail(error, id: id, stage: "Recognizing text")
                }
            }
        }
    }

    @objc func cancelCapture() {
        job = nil
        closeSelection()
        updateBusy()
    }
    private func drain() { workerActive = false; updateBusy() }
    private func complete(id: UUID, message: String) {
        guard job == id else { return }
        job = nil
        closeSelection()
        updateBusy()
        showFeedback(message)
    }
    private func fail(_ error: Error, id: UUID, stage: String) {
        guard job == id else { return }
        let nsError = error as NSError
        fputs("Clippy: \(stage) failed [\(nsError.domain):\(nsError.code)]\n", stderr)
        job = nil
        closeSelection()
        updateBusy()
        let alert = NSAlert()
        alert.messageText = "\(stage) failed"
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let appPath = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path
        alert.informativeText = "\(error.localizedDescription)\n\nError: \(nsError.domain) (\(nsError.code))\n\nIf access is already enabled, quit Clippy completely, remove its old entry from Screen & System Audio Recording, add this exact app again, and reopen it. Rebuilding an ad-hoc signed app can invalidate its saved permission.\n\nRunning app: \(appPath)"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Permission Settings")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { openPermission() }
    }
    private func updateBusy() {
        captureItem.isEnabled = job == nil && !workerActive
        cancelItem.isHidden = job == nil
        status.button?.appearsDisabled = workerActive
    }
    private func closeSelection() {
        let hadSelection = !windows.isEmpty
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows.removeAll()
        if hadSelection, NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            previousApp?.activate(options: [])
        }
        previousApp = nil
    }
    private func dismissFeedback() {
        toastTimer?.invalidate()
        guard let panel = toast as? FeedbackPanel else {
            toast?.orderOut(nil)
            toast = nil
            return
        }
        toast = nil
        panel.fadeOut { panel.orderOut(nil) }
    }
    private func showFeedback(_ message: String) {
        dismissFeedback()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let panel = FeedbackPanel(message: message, visibleFrame: screen.visibleFrame)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.fadeIn()
        }
        toast = panel
        toastTimer = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: false) { [weak self] _ in self?.dismissFeedback() }
    }
    func applicationWillTerminate(_ notification: Notification) {
        cancelCapture()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }
}

enum ClippyError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

let application = NSApplication.shared
let controller = AppController()
application.delegate = controller
// Keep the delegate alive for the entire event loop, including optimized builds.
DispatchQueue.main.async { controller.start() }
withExtendedLifetime(controller) {
    application.run()
}
