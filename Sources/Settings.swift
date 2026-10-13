import AppKit
import Carbon

struct KeyboardShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let defaultValue = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | shiftKey), keyLabel: "T")
    var display: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + keyLabel
    }
    static func from(_ event: NSEvent) -> KeyboardShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.control) || flags.contains(.option) || flags.contains(.command),
              ![53, 48, 36, 76, 51, 117].contains(Int(event.keyCode)),
              let characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return nil }
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        let special: [UInt16: String] = [123: "←", 124: "→", 125: "↓", 126: "↑", 49: "Space", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        return KeyboardShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: special[event.keyCode] ?? characters.uppercased())
    }
    func persist() {
        UserDefaults.standard.set(Int(keyCode), forKey: "shortcutCode")
        UserDefaults.standard.set(Int(modifiers), forKey: "shortcutModifiers")
        UserDefaults.standard.set(keyLabel, forKey: "shortcutLabel")
    }
    static func load() -> KeyboardShortcut {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "shortcutCode") != nil {
            return KeyboardShortcut(keyCode: UInt32(defaults.integer(forKey: "shortcutCode")), modifiers: UInt32(defaults.integer(forKey: "shortcutModifiers")), keyLabel: defaults.string(forKey: "shortcutLabel") ?? "T")
        }
        // Preserve any letter customized in the earlier settings dialog.
        let letters: [String: Int] = ["A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D, "E": kVK_ANSI_E, "F": kVK_ANSI_F, "G": kVK_ANSI_G, "H": kVK_ANSI_H, "I": kVK_ANSI_I, "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L, "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O, "P": kVK_ANSI_P, "Q": kVK_ANSI_Q, "R": kVK_ANSI_R, "S": kVK_ANSI_S, "T": kVK_ANSI_T, "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X, "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z]
        let letter = defaults.string(forKey: "shortcutKey") ?? "T"
        return KeyboardShortcut(keyCode: UInt32(letters[letter] ?? kVK_ANSI_T), modifiers: defaultValue.modifiers, keyLabel: letters[letter] == nil ? "T" : letter)
    }
}

final class ShortcutRecorder: NSButton {
    var shortcut = KeyboardShortcut.defaultValue { didSet { if !recording { title = shortcut.display } } }
    var recording = false
    var onHint: ((String) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    init() {
        super.init(frame: .zero)
        title = shortcut.display
        bezelStyle = .rounded
        font = .systemFont(ofSize: NSFont.systemFontSize)
        target = self
        action = #selector(startRecording)
        setAccessibilityLabel("Capture text keyboard shortcut")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func startRecording() {
        recording = true
        title = "Press shortcut…"
        window?.makeFirstResponder(self)
        onHint?("Press a combination with Control, Option, or Command. Esc cancels.")
    }
    func stopRecording() { recording = false; title = shortcut.display }
    override func resignFirstResponder() -> Bool { stopRecording(); return super.resignFirstResponder() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { stopRecording(); onHint?("Shortcut unchanged."); return }
        guard let value = KeyboardShortcut.from(event) else { onHint?("Include Control, Option, or Command with a key."); NSSound.beep(); return }
        shortcut = value
        stopRecording()
        onHint?("Press Save Changes to use \(shortcut.display).")
    }
}

final class ClippySettingsController: NSWindowController, NSWindowDelegate {
    private let recorder = ShortcutRecorder()
    private let hint = NSTextField(wrappingLabelWithString: "Click the shortcut to record a new combination.")
    private let language = NSPopUpButton()
    private let correction = NSButton(checkboxWithTitle: "Correct spelling when recognizing text", target: nil, action: nil)
    private let message = NSTextField(wrappingLabelWithString: "")
    private var languageCodes: [String?] = [nil]
    var save: ((KeyboardShortcut, [String], Bool) -> String?)?
    var didClose: (() -> Void)?
    var openPermissions: (() -> Void)?

    init(shortcut: KeyboardShortcut, languages: [String], supported: [String], correctSpelling: Bool) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 465), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Clippy Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
        recorder.shortcut = shortcut
        recorder.onHint = { [weak self] text in self?.hint.stringValue = text; self?.message.stringValue = "" }
        correction.state = correctSpelling ? .on : .off
        language.addItem(withTitle: "Detect automatically")
        languageCodes += supported.map { Optional($0) }
        for code in supported {
            let name = Locale.current.localizedString(forIdentifier: code) ?? code
            language.addItem(withTitle: "\(name) (\(code))")
        }
        if languages.count > 1 {
            language.addItem(withTitle: "Keep current languages (\(languages.joined(separator: ", ")))")
            languageCodes.append("__existing__")
            language.selectItem(at: languageCodes.count - 1)
        } else if let first = languages.first, let index = languageCodes.firstIndex(where: { $0 == first }) { language.selectItem(at: index) }
        existingLanguages = languages
        buildContent()
    }
    private var existingLanguages: [String] = []
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = weight == .regular ? .systemFont(ofSize: size) : .systemFont(ofSize: size, weight: weight)
        if secondary { field.textColor = .secondaryLabelColor }
        return field
    }
    private func buildContent() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28), stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24), stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)])
        stack.addArrangedSubview(label("Keyboard Shortcut", weight: .semibold))
        let shortcutRow = NSStackView(views: [label("Capture text:"), NSView(), recorder])
        shortcutRow.orientation = .horizontal
        recorder.widthAnchor.constraint(equalToConstant: 190).isActive = true
        recorder.heightAnchor.constraint(equalToConstant: 32).isActive = true
        stack.addArrangedSubview(shortcutRow)
        shortcutRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 12)
        stack.addArrangedSubview(hint)
        hint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let reset = NSButton(title: "Restore Control–Shift–T", target: self, action: #selector(resetShortcut))
        reset.bezelStyle = .rounded
        stack.addArrangedSubview(reset)
        let divider = NSBox()
        divider.boxType = .separator
        stack.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: divider)
        stack.addArrangedSubview(label("Text Recognition", weight: .semibold))
        let languageRow = NSStackView(views: [label("Language:"), NSView(), language])
        languageRow.orientation = .horizontal
        language.widthAnchor.constraint(equalToConstant: 280).isActive = true
        stack.addArrangedSubview(languageRow)
        languageRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.addArrangedSubview(correction)
        stack.addArrangedSubview(label("Turn correction off for code, identifiers, and literal text.", size: 12, secondary: true))
        let privacyRow = NSStackView(views: [label("Recognition stays on your Mac.", size: 12, secondary: true), NSView(), NSButton(title: "Permissions…", target: self, action: #selector(permissions))])
        stack.addArrangedSubview(privacyRow)
        privacyRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        message.font = .systemFont(ofSize: 12)
        message.textColor = .systemRed
        stack.addArrangedSubview(message)
        message.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        message.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelChanges))
        cancel.bezelStyle = .rounded
        let apply = NSButton(title: "Save Changes", target: self, action: #selector(saveChanges))
        apply.bezelStyle = .rounded
        apply.keyEquivalent = "\r"
        let footer = NSStackView(views: [NSView(), cancel, apply])
        stack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    @objc private func resetShortcut() {
        recorder.stopRecording()
        recorder.shortcut = .defaultValue
        hint.stringValue = "Default restored. Press Save Changes to apply."
        message.stringValue = ""
    }
    @objc private func permissions() { openPermissions?() }
    @objc private func cancelChanges() { close() }
    @objc private func saveChanges() {
        recorder.stopRecording()
        let choice = languageCodes[language.indexOfSelectedItem]
        let languages = choice == "__existing__" ? existingLanguages : choice.map { [$0] } ?? []
        if let error = save?(recorder.shortcut, languages, correction.state == .on) {
            message.stringValue = error
        } else { close() }
    }
    func windowWillClose(_ notification: Notification) { recorder.stopRecording(); didClose?() }
}
