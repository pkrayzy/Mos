//
//  ToastPanel.swift
//  Mos
//  产品级 Toast Debug 面板 - 配置、自定义发送、场景测试
//

import Cocoa

/// Toast Debug 面板
///
/// 面向用户的产品功能, 提供 Toast 配置、自定义发送和一键场景测试。
/// 作为 NSObject 子类可直接作为 NSMenuItem 的 target。
class ToastPanel: NSObject {

    private struct LayoutMetrics {
        static let panelWidth: CGFloat = 420
        static let horizontalMargin: CGFloat = 20
        static let topPadding: CGFloat = 12
        static let bottomPadding: CGFloat = 20
        static let titleHeight: CGFloat = 22
        static let subtitleHeight: CGFloat = 16
        static let sectionSpacing: CGFloat = 16
        static let rowHeight: CGFloat = 18
        static let fieldHeight: CGFloat = 22
        static let buttonHeight: CGFloat = 24
        static let resetButtonHeight: CGFloat = 22
        static let gridCellHeight: CGFloat = 36
        static let gridCellSpacing: CGFloat = 6
        static let gridColumnSpacing: CGFloat = 8
        static let labelColumnWidth: CGFloat = 140
        static let valueColumnX: CGFloat = horizontalMargin + 180
    }

    static let shared = ToastPanel()

    private var window: NSPanel?

    // MARK: - UI Controls (Configuration)
    private var maxCountSlider: NSSlider!
    private var maxCountLabel: NSTextField!
    private var positionStatusLabel: NSTextField!

    // MARK: - UI Controls (Send Toast)
    private var messageField: NSTextField!
    private var styleButtons: [NSButton] = []
    private var selectedStyle: Toast.Style = .info
    private var durationSlider: NSSlider!
    private var durationLabel: NSTextField!
    private var showsIconCheckbox: NSButton!
    private var useCustomIconCheckbox: NSButton!
    private var showsAccentRibbonCheckbox: NSButton!

    private let positionStatusActiveColor = NSColor(calibratedRed: 0.30, green: 0.78, blue: 0.40, alpha: 1.0)

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(anchorDidChange),
            name: .toastAnchorDidChange,
            object: nil
        )
    }

    // MARK: - Menu Item

    /// 创建可直接加入菜单的 MenuItem
    func createMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: NSLocalizedString("Toast Debug", comment: "Toast debug panel menu item"),
            action: #selector(menuItemClicked),
            keyEquivalent: ""
        )
        item.target = self
        if #available(macOS 11.0, *) {
            if let img = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil) {
                img.isTemplate = true
                item.image = img
            }
        } else {
            item.image = #imageLiteral(resourceName: "SF.bubble.left.fill")
        }
        return item
    }

    @objc private func menuItemClicked() {
        show()
    }

    // MARK: - Show

    func show() {
        if let w = window {
            refreshPositionStatus()
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            applyAccentRibbonPreference()
            applyIconPreference()
            return
        }
        let w = buildWindow()
        window = w
        refreshPositionStatus()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        applyAccentRibbonPreference()
        applyIconPreference()
    }

    // MARK: - Build Window

    private func buildWindow() -> NSPanel {
        let contentWidth = LayoutMetrics.panelWidth
        let baseContentHeight = calculatedContentHeight(topInset: LayoutMetrics.topPadding)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: baseContentHeight),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = NSLocalizedString("Toast Debug", comment: "Toast debug panel window title")
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        let topInset = resolvedTopInset(for: panel)
        let contentHeight = calculatedContentHeight(topInset: topInset)
        panel.setContentSize(NSSize(width: contentWidth, height: contentHeight))

        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: NSSize(width: contentWidth, height: contentHeight)))
        effectView.autoresizingMask = [.width, .height]
        effectView.state = .active
        effectView.blendingMode = .behindWindow

        if #available(macOS 10.14, *) {
            effectView.material = .hudWindow
            panel.appearance = NSAppearance(named: .vibrantDark)
        } else {
            effectView.material = .dark
        }
        panel.contentView = effectView

        buildContent(in: effectView, width: contentWidth, height: contentHeight, topInset: topInset)
        panel.center()

        return panel
    }

    private func buildContent(in container: NSView, width: CGFloat, height: CGFloat, topInset: CGFloat) {
        let contentWidth = width - LayoutMetrics.horizontalMargin * 2
        let contentView = ToastPanelContentView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        contentView.autoresizingMask = [.width, .height]
        container.addSubview(contentView)

        var y = topInset

        let titleLabel = makeLabel(text: NSLocalizedString("Toast Debug", comment: "Toast debug panel title"), fontSize: 18, weight: .semibold, color: .white)
        titleLabel.frame = NSRect(x: LayoutMetrics.horizontalMargin, y: y, width: contentWidth, height: LayoutMetrics.titleHeight)
        contentView.addSubview(titleLabel)
        y += LayoutMetrics.titleHeight + 2

        let subtitleLabel = makeLabel(text: NSLocalizedString("Component testing & configuration", comment: "Toast debug panel subtitle"), fontSize: 12, weight: .regular, color: .secondaryLabelColor)
        subtitleLabel.frame = NSRect(x: LayoutMetrics.horizontalMargin, y: y, width: contentWidth, height: LayoutMetrics.subtitleHeight)
        contentView.addSubview(subtitleLabel)
        y += LayoutMetrics.subtitleHeight + LayoutMetrics.sectionSpacing

        y = placeSectionHeader(in: contentView, title: NSLocalizedString("CONFIGURATION", comment: "Toast debug section header"), y: y, width: contentWidth)

        let maxCountRow = makeLabel(text: NSLocalizedString("Max Simultaneous", comment: "Toast debug max count label"), fontSize: 12, weight: .regular, color: .labelColor)
        maxCountRow.frame = NSRect(x: LayoutMetrics.horizontalMargin, y: y, width: LayoutMetrics.labelColumnWidth, height: LayoutMetrics.rowHeight)
        contentView.addSubview(maxCountRow)

        maxCountSlider = NSSlider(frame: NSRect(x: LayoutMetrics.valueColumnX, y: y, width: 150, height: LayoutMetrics.rowHeight))
        maxCountSlider.minValue = 1
        maxCountSlider.maxValue = 8
        maxCountSlider.integerValue = ToastStorage.shared.maxCount
        maxCountSlider.target = self
        maxCountSlider.action = #selector(maxCountChanged)
        contentView.addSubview(maxCountSlider)

        maxCountLabel = makeLabel(text: "\(ToastStorage.shared.maxCount)", fontSize: 12, weight: .medium, color: .secondaryLabelColor)
        maxCountLabel.frame = NSRect(x: width - LayoutMetrics.horizontalMargin - 30, y: y, width: 30, height: LayoutMetrics.rowHeight)
        maxCountLabel.alignment = .right
        contentView.addSubview(maxCountLabel)
        y += LayoutMetrics.rowHeight + 10

        let posLabel = makeLabel(text: NSLocalizedString("Position", comment: "Toast debug position label"), fontSize: 12, weight: .regular, color: .labelColor)
        posLabel.frame = NSRect(x: LayoutMetrics.horizontalMargin, y: y, width: LayoutMetrics.labelColumnWidth, height: LayoutMetrics.rowHeight)
        contentView.addSubview(posLabel)

        positionStatusLabel = makeLabel(
            text: "",
            fontSize: 11,
            weight: .medium,
            color: .secondaryLabelColor
        )
        positionStatusLabel.frame = NSRect(x: LayoutMetrics.valueColumnX, y: y, width: 120, height: LayoutMetrics.rowHeight)
        contentView.addSubview(positionStatusLabel)
        refreshPositionStatus()
        y += LayoutMetrics.rowHeight + 6

        let resetBtn = NSButton(frame: NSRect(x: LayoutMetrics.valueColumnX, y: y, width: 86, height: LayoutMetrics.resetButtonHeight))
        resetBtn.title = NSLocalizedString("Reset", comment: "Toast debug reset position button")
        resetBtn.bezelStyle = .rounded
        resetBtn.font = NSFont.systemFont(ofSize: 11)
        resetBtn.target = self
        resetBtn.action = #selector(resetPosition)
        contentView.addSubview(resetBtn)
        y += LayoutMetrics.resetButtonHeight + LayoutMetrics.sectionSpacing

        y = placeSectionHeader(in: contentView, title: NSLocalizedString("SEND TOAST", comment: "Toast debug section header"), y: y, width: contentWidth)

        let durLabel = makeLabel(text: NSLocalizedString("Duration", comment: "Toast debug duration label"), fontSize: 12, weight: .regular, color: .labelColor)
        durLabel.frame = NSRect(x: LayoutMetrics.horizontalMargin, y: y, width: 60, height: LayoutMetrics.rowHeight)
        contentView.addSubview(durLabel)

        durationSlider = NSSlider(frame: NSRect(x: LayoutMetrics.horizontalMargin + 80, y: y, width: 240, height: LayoutMetrics.rowHeight))
        durationSlider.minValue = 0.5
        durationSlider.maxValue = 10.0
        durationSlider.doubleValue = 2.5
        durationSlider.target = self
        durationSlider.action = #selector(durationChanged)
        contentView.addSubview(durationSlider)

        durationLabel = makeLabel(text: "2.5s", fontSize: 12, weight: .medium, color: .secondaryLabelColor)
        durationLabel.frame = NSRect(x: width - LayoutMetrics.horizontalMargin - 50, y: y, width: 50, height: LayoutMetrics.rowHeight)
        durationLabel.alignment = .right
        contentView.addSubview(durationLabel)
        y += LayoutMetrics.rowHeight + 8

        showsIconCheckbox = NSButton(
            checkboxWithTitle: NSLocalizedString("Show Icon", comment: "Toast debug show icon checkbox"),
            target: self,
            action: #selector(showsIconChanged(_:))
        )
        showsIconCheckbox.frame = NSRect(x: LayoutMetrics.horizontalMargin, y: y, width: contentWidth, height: LayoutMetrics.rowHeight)
        showsIconCheckbox.font = NSFont.systemFont(ofSize: 12)
        showsIconCheckbox.state = ToastStorage.shared.showsIcon ? .on : .off
        contentView.addSubview(showsIconCheckbox)
        y += LayoutMetrics.rowHeight + 8

        useCustomIconCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Custom Icon (app icon)", comment: "Toast debug custom icon checkbox"), target: nil, action: nil)
        useCustomIconCheckbox.frame = NSRect(x: LayoutMetrics.horizontalMargin, y: y, width: contentWidth, height: LayoutMetrics.rowHeight)
        useCustomIconCheckbox.font = NSFont.systemFont(ofSize: 12)
        contentView.addSubview(useCustomIconCheckbox)
        y += LayoutMetrics.rowHeight + 10

        showsAccentRibbonCheckbox = NSButton(
            checkboxWithTitle: NSLocalizedString("Ribbon", comment: "Toast debug accent indicator checkbox"),
            target: self,
            action: #selector(showsAccentRibbonChanged(_:))
        )
        showsAccentRibbonCheckbox.frame = NSRect(x: LayoutMetrics.horizontalMargin, y: y, width: contentWidth, height: LayoutMetrics.rowHeight)
        showsAccentRibbonCheckbox.font = NSFont.systemFont(ofSize: 12)
        showsAccentRibbonCheckbox.state = ToastStorage.shared.showsAccentIndicator ? .on : .off
        contentView.addSubview(showsAccentRibbonCheckbox)
        y += LayoutMetrics.rowHeight + 14

        messageField = NSTextField(frame: NSRect(x: LayoutMetrics.horizontalMargin, y: y, width: contentWidth, height: LayoutMetrics.fieldHeight))
        messageField.stringValue = NSLocalizedString("Hello, this is a toast message", comment: "Toast debug default message")
        messageField.placeholderString = NSLocalizedString("Enter toast message...", comment: "Toast debug message placeholder")
        contentView.addSubview(messageField)
        y += LayoutMetrics.fieldHeight + 10

        let styles: [(String, Toast.Style)] = [
            (NSLocalizedString("ℹ️ Info", comment: "Toast debug style button"), .info),
            (NSLocalizedString("✅ Success", comment: "Toast debug style button"), .success),
            (NSLocalizedString("⚠️ Warning", comment: "Toast debug style button"), .warning),
            (NSLocalizedString("❌ Error", comment: "Toast debug style button"), .error),
        ]
        let buttonWidth = (contentWidth - CGFloat(styles.count - 1) * 6) / CGFloat(styles.count)
        styleButtons = []
        for (index, (title, _)) in styles.enumerated() {
            let button = NSButton(
                frame: NSRect(
                    x: LayoutMetrics.horizontalMargin + CGFloat(index) * (buttonWidth + 6),
                    y: y,
                    width: buttonWidth,
                    height: LayoutMetrics.buttonHeight
                )
            )
            button.title = title
            button.bezelStyle = .rounded
            button.font = NSFont.systemFont(ofSize: 11)
            button.tag = index
            button.target = self
            button.action = #selector(styleSelected(_:))
            if index == 0 { button.state = .on }
            contentView.addSubview(button)
            styleButtons.append(button)
        }
        y += LayoutMetrics.buttonHeight + LayoutMetrics.sectionSpacing

        y = placeSectionHeader(in: contentView, title: NSLocalizedString("SCENARIO TESTS", comment: "Toast debug section header"), y: y, width: contentWidth)

        let tests: [(String, String, Selector)] = [
            (NSLocalizedString("🎨 All Styles", comment: "Toast debug quick test title"),
             NSLocalizedString("Show each style", comment: "Toast debug quick test subtitle"),
             #selector(testAllStyles)),
            (NSLocalizedString("📚 Stack Test", comment: "Toast debug quick test title"),
             NSLocalizedString("Fill to max count", comment: "Toast debug quick test subtitle"),
             #selector(testStackFill)),
            (NSLocalizedString("🔁 Overflow", comment: "Toast debug quick test title"),
             NSLocalizedString("Exceed max, test eviction", comment: "Toast debug quick test subtitle"),
             #selector(testOverflow)),
            (NSLocalizedString("🔇 Dedup", comment: "Toast debug quick test title"),
             NSLocalizedString("Rapid same message", comment: "Toast debug quick test subtitle"),
             #selector(testDedup)),
            (NSLocalizedString("📏 Long Text", comment: "Toast debug quick test title"),
             NSLocalizedString("Truncation test", comment: "Toast debug quick test subtitle"),
             #selector(testLongText)),
            (NSLocalizedString("🧹 Dismiss All", comment: "Toast debug quick test title"),
             NSLocalizedString("Clear all toasts", comment: "Toast debug quick test subtitle"),
             #selector(testDismissAll)),
        ]
        let gridCols = 2
        let cellWidth = (contentWidth - LayoutMetrics.gridColumnSpacing) / CGFloat(gridCols)
        for (index, (title, subtitle, action)) in tests.enumerated() {
            let column = index % gridCols
            let row = index / gridCols
            let cellY = y + CGFloat(row) * (LayoutMetrics.gridCellHeight + LayoutMetrics.gridCellSpacing)
            let button = NSButton(
                frame: NSRect(
                    x: LayoutMetrics.horizontalMargin + CGFloat(column) * (cellWidth + LayoutMetrics.gridColumnSpacing),
                    y: cellY,
                    width: cellWidth,
                    height: LayoutMetrics.gridCellHeight
                )
            )
            button.title = "\(title)\n\(subtitle)"
            button.bezelStyle = .rounded
            button.font = NSFont.systemFont(ofSize: 11)
            button.target = self
            button.action = action
            contentView.addSubview(button)
        }

        let rowCount = Int(ceil(Double(tests.count) / Double(gridCols)))
        y += CGFloat(rowCount) * LayoutMetrics.gridCellHeight
        y += CGFloat(max(0, rowCount - 1)) * LayoutMetrics.gridCellSpacing
        y += LayoutMetrics.bottomPadding
    }

    private func calculatedContentHeight(topInset: CGFloat) -> CGFloat {
        let sectionHeaderHeight: CGFloat = 14 + 8
        let headerHeight = topInset
            + LayoutMetrics.titleHeight + 2
            + LayoutMetrics.subtitleHeight + LayoutMetrics.sectionSpacing
        let configurationHeight = sectionHeaderHeight
            + LayoutMetrics.rowHeight + 10
            + LayoutMetrics.rowHeight + 6
            + LayoutMetrics.resetButtonHeight + LayoutMetrics.sectionSpacing
        let sendToastHeight = sectionHeaderHeight
            + LayoutMetrics.rowHeight + 8
            + LayoutMetrics.rowHeight + 8
            + LayoutMetrics.rowHeight + 10
            + LayoutMetrics.rowHeight + 14
            + LayoutMetrics.fieldHeight + 10
            + LayoutMetrics.buttonHeight + LayoutMetrics.sectionSpacing
        let quickTestsRowCount: CGFloat = 3
        let quickTestsHeight = sectionHeaderHeight
            + quickTestsRowCount * LayoutMetrics.gridCellHeight
            + (quickTestsRowCount - 1) * LayoutMetrics.gridCellSpacing
        return headerHeight
            + configurationHeight
            + sendToastHeight
            + quickTestsHeight
            + LayoutMetrics.bottomPadding
    }

    private func resolvedTopInset(for panel: NSPanel) -> CGFloat {
        let titlebarHeight = panel.frame.height - panel.contentLayoutRect.height
        return max(LayoutMetrics.topPadding, titlebarHeight + 10)
    }

    // MARK: - Layout Helpers

    private func placeSectionHeader(in parent: NSView, title: String, y: CGFloat, width: CGFloat) -> CGFloat {
        let headerH: CGFloat = 14
        let label = makeLabel(text: title, fontSize: 10, weight: .medium, color: .tertiaryLabelColor)
        label.frame = NSRect(x: LayoutMetrics.horizontalMargin, y: y, width: width, height: headerH)
        parent.addSubview(label)
        return y + headerH + 8
    }

    private func makeLabel(text: String, fontSize: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        label.textColor = color
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        return label
    }

    // MARK: - Actions (Configuration)

    @objc private func maxCountChanged() {
        let value = maxCountSlider.integerValue
        maxCountLabel.stringValue = "\(value)"
        ToastStorage.shared.maxCount = value
        ToastManager.shared.applyMaxCountChange()
    }

    @objc private func resetPosition() {
        ToastManager.shared.resetToDefaultAnchor()
        refreshPositionStatus()
    }

    // MARK: - Actions (Send Toast)

    @objc private func styleSelected(_ sender: NSButton) {
        let allStyles = Array(Toast.Style.allCases)
        guard sender.tag < allStyles.count else { return }
        selectedStyle = allStyles[sender.tag]
        for (i, btn) in styleButtons.enumerated() {
            btn.state = (i == sender.tag) ? .on : .off
        }
        emitToast(allowDuplicateVisibleMessage: true)
    }

    @objc private func durationChanged() {
        durationLabel.stringValue = String(format: "%.1fs", durationSlider.doubleValue)
    }

    @objc private func fireToast() {
        emitToast(allowDuplicateVisibleMessage: false)
    }

    @objc private func showsAccentRibbonChanged(_ sender: NSButton) {
        ToastStorage.shared.showsAccentIndicator = (sender.state == .on)
        applyAccentRibbonPreference()
    }

    @objc private func showsIconChanged(_ sender: NSButton) {
        ToastStorage.shared.showsIcon = (sender.state == .on)
        applyIconPreference()
    }

    @objc private func anchorDidChange() {
        refreshPositionStatus()
    }

    private func emitToast(allowDuplicateVisibleMessage: Bool) {
        let message = messageField.stringValue.isEmpty
            ? NSLocalizedString("Test Toast", comment: "Toast debug fallback message")
            : messageField.stringValue
        let duration = durationSlider.doubleValue
        let showsIcon = ToastStorage.shared.showsIcon
        let icon: NSImage? = useCustomIconCheckbox.state == .on ? NSApp.applicationIconImage : nil
        Toast.show(
            message,
            style: selectedStyle,
            duration: duration,
            icon: icon,
            showsIcon: showsIcon,
            allowDuplicateVisibleMessage: allowDuplicateVisibleMessage
        )
        DispatchQueue.main.async { [weak self] in
            self?.applyAccentRibbonPreference()
            self?.applyIconPreference()
        }
    }

    // MARK: - Actions (Quick Tests)

    @objc private func testAllStyles() {
        let styles: [(String, Toast.Style)] = [
            (NSLocalizedString("Info style", comment: "Toast debug quick test message"), .info),
            (NSLocalizedString("Success style", comment: "Toast debug quick test message"), .success),
            (NSLocalizedString("Warning style", comment: "Toast debug quick test message"), .warning),
            (NSLocalizedString("Error style", comment: "Toast debug quick test message"), .error),
        ]
        for (i, (name, style)) in styles.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                self.showToast(
                    String(format: NSLocalizedString("Style: %@", comment: "Toast debug quick test format"), name),
                    style: style,
                    duration: 3.0
                )
            }
        }
    }

    @objc private func testStackFill() {
        let max = ToastStorage.shared.maxCount
        for i in 0..<max {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                self.showToast(
                    String(format: NSLocalizedString("Toast %d of %d", comment: "Toast debug stack fill format"), i + 1, max),
                    style: .info,
                    duration: 5.0
                )
            }
        }
    }

    @objc private func testOverflow() {
        let max = ToastStorage.shared.maxCount
        let total = max + 2
        for i in 0..<total {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                self.showToast(
                    String(format: NSLocalizedString("Overflow %d of %d", comment: "Toast debug overflow format"), i + 1, total),
                    style: .warning,
                    duration: 8.0
                )
            }
        }
    }

    @objc private func testDedup() {
        for _ in 0..<5 {
            showToast(
                NSLocalizedString("Dedup test - same message", comment: "Toast debug dedup test message"),
                style: .info,
                duration: 2.0
            )
        }
    }

    @objc private func testLongText() {
        showToast(
            NSLocalizedString(
                "This is a very long toast message that should be truncated after two lines because nobody wants to read a novel in a toast notification, right? Let's see how this handles.",
                comment: "Toast debug long text test message"
            ),
            style: .warning,
            duration: 4.0
        )
    }

    @objc private func testDismissAll() {
        Toast.dismissAll()
    }

    // MARK: - Toast Helpers

    private func showToast(_ message: String, style: Toast.Style, duration: TimeInterval, icon: NSImage? = nil, allowDuplicateVisibleMessage: Bool = false) {
        Toast.show(
            message,
            style: style,
            duration: duration,
            icon: icon,
            showsIcon: ToastStorage.shared.showsIcon,
            allowDuplicateVisibleMessage: allowDuplicateVisibleMessage
        )
        DispatchQueue.main.async { [weak self] in
            self?.applyAccentRibbonPreference()
            self?.applyIconPreference()
        }
    }

    private func applyAccentRibbonPreference() {
        showsAccentRibbonCheckbox?.state = ToastStorage.shared.showsAccentIndicator ? .on : .off
        ToastManager.shared.applyAccentIndicatorVisibilityChange()
    }

    private func applyIconPreference() {
        let showsIcon = ToastStorage.shared.showsIcon
        showsIconCheckbox?.state = showsIcon ? .on : .off
        useCustomIconCheckbox?.isEnabled = showsIcon
        useCustomIconCheckbox?.alphaValue = showsIcon ? 1.0 : 0.5
    }

    private func refreshPositionStatus() {
        guard let positionStatusLabel = positionStatusLabel else { return }

        let hasCustomPosition = ToastStorage.shared.hasCustomPosition
        positionStatusLabel.stringValue = hasCustomPosition
            ? NSLocalizedString("Saved", comment: "Toast position saved status")
            : NSLocalizedString("Default", comment: "Toast position default status")
        positionStatusLabel.textColor = hasCustomPosition ? positionStatusActiveColor : .secondaryLabelColor
    }
}

private final class ToastPanelContentView: NSView {
    override var isFlipped: Bool {
        return true
    }
}
