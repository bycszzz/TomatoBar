import Cocoa

// MARK: - Key-capable window (borderless windows refuse key status by default)

private class MaskWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Mask helper

class MaskHelper {
    var windowControllers = [NSWindowController]()
    var dismissBlock: (() -> Void)?

    static let shared = MaskHelper()

    private init() {}

    func showMaskWindow(desc: String, sessionId: UUID? = nil, dismissBlock: (() -> Void)? = nil) {
        self.dismissBlock = dismissBlock

        // Fallback: if caller didn't pass a sessionId (e.g. manual rest start),
        // try the most recent completed work session.
        let effectiveSessionId = sessionId ?? TrackingStore.shared.sessions
            .filter { $0.type == .work && $0.completed }
            .max(by: { $0.startedAt < $1.startedAt })?
            .id

        let screens = NSScreen.screens
        for (idx, screen) in screens.enumerated() {
            let window = MaskWindow(contentRect: screen.frame,
                                    styleMask: .borderless, backing: .buffered, defer: true)
            window.level = .screenSaver
            window.collectionBehavior = .canJoinAllSpaces
            window.backgroundColor = NSColor.black.withAlphaComponent(0.2)
            window.isReleasedWhenClosed = false
            window.acceptsMouseMovedEvents = true

            // Only show the note input on the primary screen to avoid duplicates
            let viewSessionId: UUID? = (idx == 0) ? effectiveSessionId : nil
            let maskView = MaskView(desc: desc,
                                    sessionId: viewSessionId,
                                    frame: NSRect(origin: .zero, size: screen.frame.size)) { [weak self] in
                guard let self, !self.windowControllers.isEmpty else { return }
                for wc in self.windowControllers { wc.close() }
                self.windowControllers.removeAll()
            }
            window.contentView = maskView
            let wc = NSWindowController(window: window)
            wc.loadWindow()
            wc.showWindow(nil)
            windowControllers.append(wc)
            maskView.show()
        }

        // Activate app and make the primary mask window key so the text field can take focus
        NSApp.activate(ignoringOtherApps: true)
        if let primary = windowControllers.first?.window {
            primary.makeKeyAndOrderFront(nil)
            if let mv = primary.contentView as? MaskView {
                DispatchQueue.main.async { mv.focusNoteField() }
            }
        }
    }

    func hideMaskWindow(skip: Bool = false) {
        for wc in windowControllers {
            if let mv = wc.window?.contentView as? MaskView {
                mv.savePendingNote()
                mv.hide()
            }
        }
        if skip { dismissBlock?() }
    }
}

// MARK: - Mask view

class MaskView: NSView {
    var dismissBlock: (() -> Void)?
    private var clickTimer: Timer?
    private let sessionId: UUID?
    private var noteContainer: NSView?
    private var noteField: NSTextField?

    lazy var titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.textColor = .white.withAlphaComponent(0.95)
        label.font = NSFont.systemFont(ofSize: 36, weight: .semibold)
        label.alignment = .center
        return label
    }()

    lazy var tipLabel: NSTextField = {
        let label = NSTextField(labelWithString: NSLocalizedString("TBMask.skip.label", comment: "Skip label"))
        label.textColor = .white.withAlphaComponent(0.45)
        label.font = NSFont.systemFont(ofSize: 13)
        label.alignment = .center
        return label
    }()

    lazy var blurEffect: NSVisualEffectView = {
        let v = NSVisualEffectView(frame: bounds)
        v.autoresizingMask = [.width, .height]
        v.alphaValue = 0.9
        v.appearance = NSAppearance(named: .vibrantDark)
        v.blendingMode = .behindWindow
        v.state = .inactive
        return v
    }()

    init(desc: String, sessionId: UUID? = nil, frame: NSRect, dismissBlock: (() -> Void)? = nil) {
        self.dismissBlock = dismissBlock
        self.sessionId = sessionId
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        titleLabel.stringValue = desc

        addSubview(blurEffect)

        let mid = bounds.midY
        let w = bounds.width

        if sessionId != nil {
            titleLabel.frame = CGRect(x: 0, y: mid + 110, width: w, height: 56)
            tipLabel.frame = CGRect(x: 0, y: mid - 140, width: w, height: 24)
            setupNoteInput(centerY: mid, viewWidth: w)
        } else {
            titleLabel.frame = CGRect(x: 0, y: mid - 30, width: w, height: 50)
            tipLabel.frame = CGRect(x: 0, y: mid - 80, width: w, height: 30)
        }

        addSubview(titleLabel)
        addSubview(tipLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Note input setup

    private func setupNoteInput(centerY: CGFloat, viewWidth: CGFloat) {
        let containerW: CGFloat = min(viewWidth * 0.5, 720)
        let containerH: CGFloat = 128
        let containerX = (viewWidth - containerW) / 2
        let containerY = centerY - containerH / 2

        let container = NSView(frame: NSRect(x: containerX, y: containerY,
                                             width: containerW, height: containerH))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        container.layer?.cornerRadius = 18
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        let placeholder = NSLocalizedString("TBMask.notePlaceholder", comment: "Note placeholder")
        let tf = NoteTextField(frame: NSRect(x: 36, y: 56, width: containerW - 72, height: 40))
        tf.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.4),
                .font: NSFont.systemFont(ofSize: 22, weight: .regular)
            ]
        )
        tf.font = NSFont.systemFont(ofSize: 22, weight: .regular)
        tf.textColor = .white
        tf.alignment = .center
        tf.isBordered = false
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.delegate = self
        tf.target = self
        tf.action = #selector(noteFieldDidSubmit)

        // Divider line
        let divider = NSView(frame: NSRect(x: 36, y: 50, width: containerW - 72, height: 1))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor

        // Hint label
        let hint = NSTextField(labelWithString: NSLocalizedString("TBMask.noteSaveHint", comment: "Save hint"))
        hint.textColor = .white.withAlphaComponent(0.4)
        hint.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        hint.alignment = .center
        hint.frame = NSRect(x: 0, y: 22, width: containerW, height: 16)
        hint.isBezeled = false
        hint.drawsBackground = false
        hint.isEditable = false

        container.addSubview(divider)
        container.addSubview(tf)
        container.addSubview(hint)
        addSubview(container)

        noteField = tf
        noteContainer = container
    }

    // MARK: - Note save

    @objc private func noteFieldDidSubmit() {
        commitNote(showSaved: true)
    }

    func savePendingNote() {
        commitNote(showSaved: false)
    }

    private func commitNote(showSaved: Bool) {
        guard let sid = sessionId, let field = noteField else { return }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        TrackingStore.shared.updateSessionNotes(id: sid, notes: trimmed)
        if showSaved {
            showSavedFeedback()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                MaskHelper.shared.hideMaskWindow()
            }
        }
    }

    private func showSavedFeedback() {
        guard let container = noteContainer else { return }
        for sv in container.subviews { sv.removeFromSuperview() }
        let saved = NSTextField(labelWithString: NSLocalizedString("TBMask.savedFeedback", comment: "Saved feedback"))
        saved.textColor = NSColor.systemGreen
        saved.font = NSFont.systemFont(ofSize: 22, weight: .medium)
        saved.alignment = .center
        saved.isBezeled = false
        saved.drawsBackground = false
        saved.isEditable = false
        saved.frame = NSRect(x: 0, y: (container.bounds.height - 30) / 2,
                             width: container.bounds.width, height: 30)
        container.addSubview(saved)
    }

    // MARK: - Focus

    func focusNoteField() {
        guard let tf = noteField, let window = window else { return }
        window.makeFirstResponder(tf)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if noteField != nil {
            DispatchQueue.main.async { [weak self] in
                self?.focusNoteField()
            }
        }
    }

    // MARK: - Click to dismiss (ignore clicks inside the note container)

    override func mouseDown(with event: NSEvent) {
        if let container = noteContainer {
            let pt = convert(event.locationInWindow, from: nil)
            if container.frame.contains(pt) {
                super.mouseDown(with: event)
                return
            }
        }
        super.mouseDown(with: event)
        if event.clickCount == 1 {
            clickTimer?.invalidate()
            clickTimer = Timer.scheduledTimer(withTimeInterval: 0.18,
                                              repeats: false) { _ in
                MaskHelper.shared.hideMaskWindow()
            }
        } else if event.clickCount == 2 {
            clickTimer?.invalidate()
            MaskHelper.shared.hideMaskWindow(skip: true)
        }
    }

    // MARK: - Animations

    func show() {
        layer?.removeAllAnimations()
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 0; anim.toValue = 1; anim.duration = 1.0
        layer?.add(anim, forKey: "opacity")
    }

    func hide() {
        layer?.removeAllAnimations()
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1; anim.toValue = 0; anim.duration = 0.25
        anim.isRemovedOnCompletion = false; anim.fillMode = .forwards
        anim.delegate = self
        layer?.add(anim, forKey: "opacity")
    }
}

extension MaskView: NSTextFieldDelegate {
    func control(_ control: NSControl,
                 textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitNote(showSaved: true)
            return true
        }
        return false
    }
}

extension MaskView: CAAnimationDelegate {
    func animationDidStop(_ anim: CAAnimation, finished _: Bool) {
        dismissBlock?()
    }
}

// MARK: - Editable text field that overrides the default first-responder behavior

private class NoteTextField: NSTextField {
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok, let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = .white
        }
        return ok
    }
}
