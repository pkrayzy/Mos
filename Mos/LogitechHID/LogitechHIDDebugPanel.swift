//
//  LogitechHIDDebugPanel.swift
//  Mos
//  Logitech HID++ 综合调试面板
//  Created by Mos on 2026/3/16.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa
import IOKit
import IOKit.hid

// MARK: - Log Entry

enum LogEntryType: String, CaseIterable {
    case info = "Info"
    case tx = "TX"
    case rx = "RX"
    case error = "Error"
    case buttonEvent = "Button"
    case warning = "Warning"
}

struct LogEntry {
    let timestamp: String
    let deviceName: String
    let type: LogEntryType
    let message: String
    let decoded: String?
    let rawBytes: [UInt8]?
    var isExpanded: Bool = false
}

// MARK: - HID++ Protocol Dictionaries

struct HIDPPInfo {
    static let featureNames: [UInt16: (String, String)] = [
        0x0000: ("IRoot", "Feature discovery root"),
        0x0001: ("IFeatureSet", "Enumerate all features"),
        0x0003: ("DeviceFWVersion", "Firmware version info"),
        0x0005: ("DeviceNameType", "Device name and type"),
        0x0020: ("ConfigChange", "Config change notification"),
        0x1000: ("BatteryStatus", "Battery level and status"),
        0x1001: ("BatteryVoltage", "Battery voltage reading"),
        0x1004: ("UnifiedBattery", "Unified battery reporting"),
        0x1814: ("ChangeHost", "Multi-host switching"),
        0x1815: ("HostsInfo", "Connected host info"),
        0x1B04: ("ReprogControlsV4", "Button reprog and divert"),
        0x1D4B: ("WirelessStatus", "Wireless connection status"),
        0x2110: ("SmartShift", "Scroll wheel mode"),
        0x2111: ("SmartShiftV2", "SmartShift v2"),
        0x2121: ("HiResWheel", "Hi-res scroll wheel"),
        0x2150: ("ThumbWheel", "Thumb wheel control"),
        0x2200: ("MouseButtonSpy", "Mouse button spy"),
        0x2201: ("AdjustableDPI", "DPI adjustment"),
        0x2205: ("PointerSpeed", "Pointer speed control"),
        0x4521: ("HiResWheel", "Hi-res scroll wheel"),
    ]

    static let controlFlagBits: [(bit: Int, short: String, desc: String)] = [
        (0, "Mouse", "Mouse button group"),
        (1, "FKey", "F-key group"),
        (2, "HotKey", "Hotkey"),
        (3, "FnToggle", "Fn toggle affected"),
        (4, "Reprog", "Reprogrammable"),
        (5, "Divert", "Divertable to SW"),
        (6, "Persist", "Persistent divert"),
        (7, "Virtual", "Virtual button"),
        (8, "RawXY", "Raw XY capable"),
        (9, "ForceXY", "Force raw XY"),
    ]

    static func flagsDescription(_ flags: UInt16) -> String {
        return controlFlagBits
            .filter { (flags >> $0.bit) & 1 != 0 }
            .map { $0.short }
            .joined(separator: ",")
    }

    static let errorNames: [UInt8: String] = [
        0x00: "NoError", 0x01: "Unknown", 0x02: "InvalidArgument",
        0x03: "OutOfRange", 0x04: "HWError", 0x05: "LogitechInternal",
        0x06: "InvalidFeatureIndex", 0x07: "InvalidFunctionID",
        0x08: "Busy", 0x09: "Unsupported",
    ]
}

// MARK: - Feature Action Definitions

struct HIDPPFeatureAction {
    let name: String
    let functionId: UInt8
    enum ParamType { case none, index, hex }
    let paramType: ParamType
    let defaultParams: [UInt8]
}

struct HIDPPFeatureActions {
    static let knownActions: [UInt16: [HIDPPFeatureAction]] = [
        0x0000: [
            HIDPPFeatureAction(name: "Ping", functionId: 0x01, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "GetFeature", functionId: 0x00, paramType: .hex, defaultParams: [0x00, 0x01]),
        ],
        0x0001: [
            HIDPPFeatureAction(name: "GetCount", functionId: 0x00, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "GetFeatureID", functionId: 0x01, paramType: .index, defaultParams: []),
        ],
        0x0003: [
            HIDPPFeatureAction(name: "GetEntityCount", functionId: 0x00, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "GetFWVersion", functionId: 0x01, paramType: .index, defaultParams: []),
        ],
        0x0005: [
            HIDPPFeatureAction(name: "GetCount", functionId: 0x00, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "GetName", functionId: 0x01, paramType: .index, defaultParams: []),
            HIDPPFeatureAction(name: "GetType", functionId: 0x02, paramType: .none, defaultParams: []),
        ],
        0x1000: [
            HIDPPFeatureAction(name: "GetLevel", functionId: 0x00, paramType: .none, defaultParams: []),
        ],
        0x1004: [
            HIDPPFeatureAction(name: "GetStatus", functionId: 0x00, paramType: .none, defaultParams: []),
        ],
        0x1B04: [
            HIDPPFeatureAction(name: "GetCount", functionId: 0x00, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "GetInfo", functionId: 0x01, paramType: .index, defaultParams: []),
            HIDPPFeatureAction(name: "GetReporting", functionId: 0x02, paramType: .hex, defaultParams: [0x00, 0x50]),
            HIDPPFeatureAction(name: "SetReporting", functionId: 0x03, paramType: .hex, defaultParams: [0x00, 0x50, 0x03]),
        ],
        0x2110: [
            HIDPPFeatureAction(name: "GetStatus", functionId: 0x00, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "SetStatus", functionId: 0x01, paramType: .hex, defaultParams: [0x02]),
        ],
        0x2121: [
            HIDPPFeatureAction(name: "GetCapability", functionId: 0x00, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "GetMode", functionId: 0x01, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "SetMode", functionId: 0x02, paramType: .hex, defaultParams: [0x00]),
        ],
        0x2201: [
            HIDPPFeatureAction(name: "GetSensorCount", functionId: 0x00, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "GetDPI", functionId: 0x01, paramType: .index, defaultParams: []),
            HIDPPFeatureAction(name: "SetDPI", functionId: 0x02, paramType: .hex, defaultParams: [0x00, 0x00, 0x03, 0x20]),
            HIDPPFeatureAction(name: "GetDPIList", functionId: 0x03, paramType: .index, defaultParams: []),
        ],
    ]

    static func actions(for featureId: UInt16) -> [HIDPPFeatureAction] {
        if let known = knownActions[featureId] { return known }
        return (0...15).map { funcId in
            HIDPPFeatureAction(name: "Func \(funcId)", functionId: UInt8(funcId), paramType: .hex, defaultParams: [])
        }
    }
}

// MARK: - Debug Panel

class LogitechHIDDebugPanel: NSObject {

    static let shared = LogitechHIDDebugPanel()
    static let logNotification = NSNotification.Name("LogitechHIDDebugLog")

    // MARK: - Layout Constants

    private struct L {
        static let defaultWidth: CGFloat = 1100
        static let defaultHeight: CGFloat = 750
        static let minWidth: CGFloat = 1100
        static let minHeight: CGFloat = 600
        static let sidebarWidth: CGFloat = 180
        static let actionsWidth: CGFloat = 160
        static let gap: CGFloat = 2
        static let pad: CGFloat = 8
        static let btnH: CGFloat = 24
        static let btnGap: CGFloat = 4
        static let topRatio: CGFloat = 0.4
        static let devInfoH: CGFloat = 140
        static let logToolbarH: CGFloat = 28
        static let rawInputH: CGFloat = 30
        static let sectionHdrH: CGFloat = 20
    }

    // MARK: - Window

    private var window: NSPanel?

    // MARK: - Sidebar

    private var outlineView: NSOutlineView!
    private var deviceInfoLabels: [(key: NSTextField, value: NSTextField)] = []
    private var moreInfoLabels: [(key: NSTextField, value: NSTextField)] = []

    // MARK: - Tables

    private var featureTableView: NSTableView!
    private var controlsTableView: NSTableView!

    // MARK: - Actions Panel

    private var contextActionsContainer: NSView!
    private var paramInputField: NSTextField?
    private var indexStepper: NSStepper?
    private var indexStepperLabel: NSTextField?

    // MARK: - Log

    private var logTableView: NSTableView!
    private var filterButtons: [LogEntryType: NSButton] = [:]
    private var rawInputField: NSTextField!
    private var reportTypeControl: NSSegmentedControl!

    // MARK: - State

    private var currentSession: LogitechDeviceSession?
    private var logTypeFilter: Set<LogEntryType> = Set(LogEntryType.allCases)
    static var logBuffer: [LogEntry] = []
    static let maxLogLines = 500
    private var logObserver: NSObjectProtocol?
    private var sessionObserver: NSObjectProtocol?

    // MARK: - Sidebar Data

    private class DeviceNode {
        let session: LogitechDeviceSession
        var isReceiver: Bool { session.debugConnectionMode == "receiver" }
        init(session: LogitechDeviceSession) { self.session = session }
    }

    private class SlotNode {
        let session: LogitechDeviceSession
        let slot: UInt8
        init(session: LogitechDeviceSession, slot: UInt8) { self.session = session; self.slot = slot }
    }

    private var deviceNodes: [DeviceNode] = []

    // MARK: - Feature/Control Data

    private var featureRows: [(index: String, featureId: UInt16, featureIdHex: String, name: String)] = []
    private var controlRows: [LogitechDeviceSession.ControlInfo] = []
    private var selectedFeatureId: UInt16?
    private var selectedControlCID: UInt16?

    // MARK: - Logging API

    class func log(_ message: String) {
        let entry = LogEntry(timestamp: timestamp(), deviceName: "", type: .info, message: message, decoded: nil, rawBytes: nil)
        appendToBuffer(entry)
    }

    class func log(device: String, type: LogEntryType, message: String, decoded: String? = nil, rawBytes: [UInt8]? = nil) {
        let entry = LogEntry(timestamp: timestamp(), deviceName: device, type: type, message: message, decoded: decoded, rawBytes: rawBytes)
        appendToBuffer(entry)
    }

    // Note: existing callers that pass (device:type:message:decoded:) without rawBytes
    // will use the default rawBytes: nil from the method above.

    private class func appendToBuffer(_ entry: LogEntry) {
        logBuffer.append(entry)
        if logBuffer.count > maxLogLines { logBuffer.removeFirst(logBuffer.count - maxLogLines) }
        NotificationCenter.default.post(name: logNotification, object: entry)
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }

    // MARK: - Show / Hide

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            refreshAll()
            startObserving()
            return
        }
        let w = buildWindow()
        window = w
        refreshAll()
        startObserving()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Build Window

    private func buildWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: L.defaultWidth, height: L.defaultHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Logitech HID++ Debug"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.minSize = NSSize(width: L.minWidth, height: L.minHeight)
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: panel.frame.size))
        effectView.autoresizingMask = [.width, .height]
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        panel.appearance = NSAppearance(named: .vibrantDark)
        if #available(macOS 10.14, *) {
            effectView.material = .hudWindow
        } else {
            effectView.material = .dark
        }
        panel.contentView = effectView

        let topInset = resolvedTopInset(for: panel)
        buildContent(in: effectView, topInset: topInset)

        return panel
    }

    private func resolvedTopInset(for panel: NSPanel) -> CGFloat {
        let titlebarH = panel.frame.height - panel.contentLayoutRect.height
        return max(L.pad, titlebarH + 4)
    }

    private func buildContent(in container: NSView, topInset: CGFloat) {
        let contentView = FlippedView(frame: container.bounds)
        contentView.autoresizingMask = [.width, .height]
        container.addSubview(contentView)

        let mainX = L.sidebarWidth + L.gap
        let mainW = container.bounds.width - mainX
        let bodyH = container.bounds.height - topInset

        buildSidebar(in: contentView, x: 0, y: topInset, width: L.sidebarWidth, height: bodyH)

        // Use NSSplitView for top/log to properly handle resize
        let splitView = NSSplitView(frame: NSRect(x: mainX, y: topInset, width: mainW, height: bodyH))
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]
        contentView.addSubview(splitView)

        let topH = bodyH * L.topRatio
        let logH = bodyH - topH - 1 // 1px for divider

        let topContainer = FlippedView(frame: NSRect(x: 0, y: 0, width: mainW, height: topH))
        topContainer.autoresizingMask = [.width, .height]
        buildTopArea(in: topContainer, x: 0, y: 0, width: mainW, height: topH)
        splitView.addSubview(topContainer)

        let logContainer = FlippedView(frame: NSRect(x: 0, y: 0, width: mainW, height: logH))
        logContainer.autoresizingMask = [.width, .height]
        buildLogArea(in: logContainer, x: 0, y: 0, width: mainW, height: logH)
        splitView.addSubview(logContainer)

        splitView.adjustSubviews()
    }

    // Flipped coordinate view: y=0 at top, increases downward
    private final class FlippedView: NSView {
        override var isFlipped: Bool { return true }
    }

    // MARK: - Build Sidebar

    private func buildSidebar(in parent: NSView, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        let container = FlippedView(frame: NSRect(x: x, y: y, width: width, height: height))
        container.autoresizingMask = [.height]
        parent.addSubview(container)

        let bg = makeSectionBg()
        bg.frame = container.bounds
        bg.autoresizingMask = [.width, .height]
        container.addSubview(bg)

        var cy: CGFloat = L.pad

        let header = makeSectionHeader("DEVICES")
        header.frame = NSRect(x: L.pad, y: cy, width: width - L.pad * 2, height: L.sectionHdrH)
        container.addSubview(header)
        cy += L.sectionHdrH

        // Device tree takes available space between header and device info
        let treeH = height - cy - L.devInfoH - 1
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: cy, width: width, height: max(treeH, 40)))
        scrollView.autoresizingMask = [.height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let outline = NSOutlineView()
        outline.headerView = nil
        outline.backgroundColor = .clear
        outline.selectionHighlightStyle = .sourceList
        outline.indentationPerLevel = 14
        outline.rowHeight = 22
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("device"))
        col.resizingMask = .autoresizingMask
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.delegate = self
        outline.dataSource = self
        outline.target = self
        outline.action = #selector(outlineViewClicked(_:))
        scrollView.documentView = outline
        container.addSubview(scrollView)
        self.outlineView = outline

        // Device info at the bottom — use a scrollable area
        let infoY = height - L.devInfoH
        let sep = makeSep()
        sep.frame = NSRect(x: L.pad, y: infoY - 1, width: width - L.pad * 2, height: 1)
        sep.autoresizingMask = [.minYMargin]
        container.addSubview(sep)

        buildDeviceInfoArea(in: container, y: infoY, width: width, height: L.devInfoH)
    }

    private func buildDeviceInfoArea(in parent: NSView, y: CGFloat, width: CGFloat, height: CGFloat) {
        // Scrollable device info area to handle overflow
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: y, width: width, height: height))
        scrollView.autoresizingMask = [.minYMargin]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let allKeys = ["VID", "PID", "Protocol", "Transport", "Dev Index", "Conn Mode", "Opened",
                        "UsagePage", "Usage", "HID++ Cand", "Init Done", "Dvrt CIDs"]
        let contentH: CGFloat = CGFloat(allKeys.count) * 16 + L.pad
        let infoContent = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: contentH))

        var iy: CGFloat = L.pad
        let keyW: CGFloat = 65
        let valX: CGFloat = keyW + 4

        deviceInfoLabels.removeAll()
        moreInfoLabels.removeAll()

        for (i, keyText) in allKeys.enumerated() {
            let kl = makeLabel(text: keyText, fontSize: 9, weight: .medium, color: .tertiaryLabelColor)
            kl.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
            kl.frame = NSRect(x: L.pad, y: iy, width: keyW, height: 14)
            infoContent.addSubview(kl)
            let vl = makeLabel(text: "--", fontSize: 9, color: .secondaryLabelColor)
            vl.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
            vl.frame = NSRect(x: valX, y: iy, width: width - valX - L.pad, height: 14)
            infoContent.addSubview(vl)
            if i < 7 {
                deviceInfoLabels.append((key: kl, value: vl))
            } else {
                moreInfoLabels.append((key: kl, value: vl))
            }
            iy += 16
        }

        scrollView.documentView = infoContent
        parent.addSubview(scrollView)
    }

    @objc private func outlineViewClicked(_ sender: Any?) {
        let row = outlineView.selectedRow
        guard row >= 0 else { return }
        let item = outlineView.item(atRow: row)

        if let node = item as? DeviceNode {
            currentSession = node.session
            selectedFeatureId = nil
            selectedControlCID = nil
            refreshRightPanels()
        } else if let slot = item as? SlotNode {
            // Validate slot is online
            let paired = slot.session.debugReceiverPairedDevices
            let idx = Int(slot.slot) - 1
            guard idx >= 0, idx < paired.count, paired[idx].isConnected else { return }
            currentSession = slot.session
            slot.session.setTargetSlot(slot: slot.slot)
            refreshRightPanelsLoading()
            slot.session.rediscoverFeatures()
        }
    }

    // MARK: - Build Top Area

    private func buildTopArea(in parent: NSView, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        let container = FlippedView(frame: NSRect(x: x, y: y, width: width, height: height))
        container.autoresizingMask = [.width, .height]
        parent.addSubview(container)

        let actionsX = width - L.actionsWidth
        let tableW = actionsX - L.gap
        let halfW = (tableW - L.gap) / 2

        buildFeatureTable(in: container, x: 0, y: 0, width: halfW, height: height)
        buildControlsTable(in: container, x: halfW + L.gap, y: 0, width: halfW, height: height)
        buildActionsPanel(in: container, x: actionsX, y: 0, width: L.actionsWidth, height: height)
    }

    private func buildFeatureTable(in parent: NSView, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        let bg = makeSectionBg()
        bg.frame = NSRect(x: x, y: y, width: width, height: height)
        bg.autoresizingMask = [.width, .height]
        parent.addSubview(bg)

        let header = makeSectionHeader("FEATURES (0)")
        header.frame = NSRect(x: x + L.pad, y: y + 4, width: width - L.pad * 2, height: 16)
        header.tag = 100
        parent.addSubview(header)

        let tableY = y + L.sectionHdrH
        let sv = NSScrollView(frame: NSRect(x: x, y: tableY, width: width, height: height - L.sectionHdrH))
        sv.autoresizingMask = [.width, .height]
        sv.hasVerticalScroller = true
        sv.borderType = .noBorder
        sv.drawsBackground = false

        let table = NSTableView()
        table.backgroundColor = .clear
        table.headerView = nil
        table.selectionHighlightStyle = .regular
        table.rowHeight = 20
        table.tag = 200
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.action = #selector(featureTableClicked(_:))

        for (id, w) in [("fIdx", CGFloat(36)), ("fId", CGFloat(50)), ("fName", CGFloat(0))] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.width = w > 0 ? w : 100
            if w == 0 { col.resizingMask = .autoresizingMask }
            table.addTableColumn(col)
        }

        sv.documentView = table
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.sizeLastColumnToFit()
        parent.addSubview(sv)
        self.featureTableView = table
    }

    private func buildControlsTable(in parent: NSView, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        let bg = makeSectionBg()
        bg.frame = NSRect(x: x, y: y, width: width, height: height)
        bg.autoresizingMask = [.width, .height]
        parent.addSubview(bg)

        let header = makeSectionHeader("CONTROLS (0)")
        header.frame = NSRect(x: x + L.pad, y: y + 4, width: width - L.pad * 2, height: 16)
        header.tag = 101
        parent.addSubview(header)

        let tableY = y + L.sectionHdrH
        let sv = NSScrollView(frame: NSRect(x: x, y: tableY, width: width, height: height - L.sectionHdrH))
        sv.autoresizingMask = [.width, .height]
        sv.hasVerticalScroller = true
        sv.borderType = .noBorder
        sv.drawsBackground = false

        let table = NSTableView()
        table.backgroundColor = .clear
        table.headerView = nil
        table.selectionHighlightStyle = .regular
        table.rowHeight = 20
        table.tag = 201
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.action = #selector(controlsTableClicked(_:))

        for (id, w) in [("cCid", CGFloat(50)), ("cName", CGFloat(0)), ("cFlags", CGFloat(40)), ("cStatus", CGFloat(50))] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            if w > 0 {
                col.width = w
                col.resizingMask = [] // fixed width
            } else {
                col.width = 100
                col.resizingMask = .autoresizingMask
            }
            table.addTableColumn(col)
        }

        sv.documentView = table
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.sizeLastColumnToFit()
        parent.addSubview(sv)
        self.controlsTableView = table
    }

    private func buildActionsPanel(in parent: NSView, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        let bg = makeSectionBg()
        bg.frame = NSRect(x: x, y: y, width: width, height: height)
        bg.autoresizingMask = [.width, .height]
        parent.addSubview(bg)

        let header = makeSectionHeader("ACTIONS")
        header.frame = NSRect(x: x + L.pad, y: y + 4, width: width - L.pad * 2, height: 16)
        parent.addSubview(header)

        let ctxY = y + L.sectionHdrH
        let globalH: CGFloat = CGFloat(5) * (L.btnH + L.btnGap) + L.pad * 2
        let ctxH = height - L.sectionHdrH - globalH - 1
        let ctxC = FlippedView(frame: NSRect(x: x, y: ctxY, width: width, height: max(ctxH, 60)))
        parent.addSubview(ctxC)
        self.contextActionsContainer = ctxC

        let placeholder = makeLabel(text: "Select a feature\nor control", fontSize: 10, color: .tertiaryLabelColor)
        placeholder.frame = NSRect(x: L.pad, y: L.pad, width: width - L.pad * 2, height: 40)
        placeholder.alignment = .center
        placeholder.maximumNumberOfLines = 2
        ctxC.addSubview(placeholder)

        let sep = makeSep()
        let sepY = ctxY + ctxH
        sep.frame = NSRect(x: x + L.pad, y: sepY, width: width - L.pad * 2, height: 1)
        parent.addSubview(sep)

        let globalY = sepY + L.pad
        let globalC = FlippedView(frame: NSRect(x: x, y: globalY, width: width, height: globalH))
        parent.addSubview(globalC)

        let btnW = width - L.pad * 2
        var by: CGFloat = 0
        let globalActions: [(String, Selector)] = [
            ("Re-Discover", #selector(rediscoverClicked)),
            ("Re-Divert", #selector(redivertClicked)),
            ("Undivert All", #selector(undivertClicked)),
            ("Enumerate", #selector(enumerateClicked)),
            ("Clear Log", #selector(clearLogClicked)),
        ]
        for (title, action) in globalActions {
            let btn = makeActionBtn(title: title, action: action)
            btn.frame = NSRect(x: L.pad, y: by, width: btnW, height: L.btnH)
            globalC.addSubview(btn)
            by += L.btnH + L.btnGap
        }
    }

    // MARK: - Build Log Area

    private func buildLogArea(in parent: NSView, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        let bg = makeLogBg()
        bg.frame = NSRect(x: x, y: y, width: width, height: height)
        bg.autoresizingMask = [.width, .height]
        parent.addSubview(bg)

        var cy = y + 4

        // Toolbar
        let toolbar = NSView(frame: NSRect(x: x, y: cy, width: width, height: L.logToolbarH))
        toolbar.autoresizingMask = [.width]
        parent.addSubview(toolbar)

        let logLabel = makeSectionHeader("PROTOCOL LOG")
        logLabel.frame = NSRect(x: L.pad, y: 6, width: 100, height: 16)
        toolbar.addSubview(logLabel)

        let chipColors: [(LogEntryType, String, NSColor)] = [
            (.tx, "TX", NSColor(calibratedRed: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)),
            (.rx, "RX", NSColor(calibratedRed: 0.3, green: 0.8, blue: 0.4, alpha: 1.0)),
            (.error, "ERR", NSColor(calibratedRed: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)),
            (.buttonEvent, "BTN", NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.2, alpha: 1.0)),
            (.warning, "WARN", NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)),
            (.info, "INFO", NSColor(calibratedWhite: 0.75, alpha: 1.0)),
        ]
        var fx: CGFloat = 110
        for (i, (entryType, label, color)) in chipColors.enumerated() {
            let btn = NSButton(title: label, target: self, action: #selector(filterChipClicked(_:)))
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.backgroundColor = color.withAlphaComponent(0.3).cgColor
            btn.layer?.cornerRadius = 3
            btn.font = NSFont.systemFont(ofSize: 9, weight: .medium)
            if #available(macOS 10.14, *) { btn.contentTintColor = color }
            btn.tag = i
            btn.frame = NSRect(x: fx, y: 4, width: 38, height: 20)
            toolbar.addSubview(btn)
            filterButtons[entryType] = btn
            fx += 42
        }

        let clearBtn = makeActionBtn(title: "Clear", action: #selector(clearLogClicked))
        clearBtn.frame = NSRect(x: width - 50, y: 4, width: 42, height: 20)
        clearBtn.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        toolbar.addSubview(clearBtn)

        let exportBtn = makeActionBtn(title: "Export", action: #selector(exportLogClicked))
        exportBtn.frame = NSRect(x: width - 100, y: 4, width: 46, height: 20)
        exportBtn.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        toolbar.addSubview(exportBtn)

        cy += L.logToolbarH

        // Log table
        let tableH = height - L.logToolbarH - L.rawInputH - 8
        let sv = NSScrollView(frame: NSRect(x: x, y: cy, width: width, height: tableH))
        sv.autoresizingMask = [.width, .height]
        sv.hasVerticalScroller = true
        sv.borderType = .noBorder
        sv.drawsBackground = false

        let table = NSTableView()
        table.backgroundColor = .clear
        table.headerView = nil
        table.selectionHighlightStyle = .none
        table.rowHeight = 18
        table.tag = 300
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.action = #selector(logRowClicked(_:))
        let logCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("log"))
        logCol.resizingMask = .autoresizingMask
        table.addTableColumn(logCol)
        sv.documentView = table
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.sizeLastColumnToFit()
        parent.addSubview(sv)
        self.logTableView = table

        cy += tableH + 4

        // Raw input bar
        buildRawInputBar(in: parent, x: x, y: cy, width: width)
    }

    private func buildRawInputBar(in parent: NSView, x: CGFloat, y: CGFloat, width: CGFloat) {
        let container = FlippedView(frame: NSRect(x: x, y: y, width: width, height: L.rawInputH))
        container.autoresizingMask = [.width, .minYMargin]
        parent.addSubview(container)

        let sep = makeSep()
        sep.frame = NSRect(x: L.pad, y: 0, width: width - L.pad * 2, height: 1)
        sep.autoresizingMask = [.width]
        container.addSubview(sep)

        let rawLabel = makeLabel(text: "RAW:", fontSize: 10, weight: .medium, color: .tertiaryLabelColor)
        rawLabel.frame = NSRect(x: L.pad, y: 6, width: 35, height: 18)
        container.addSubview(rawLabel)

        let segCtrl = NSSegmentedControl(labels: ["Short 7B", "Long 20B"], trackingMode: .selectOne, target: nil, action: nil)
        segCtrl.selectedSegment = 1
        segCtrl.frame = NSRect(x: 48, y: 5, width: 120, height: 20)
        segCtrl.font = NSFont.systemFont(ofSize: 9)
        container.addSubview(segCtrl)
        self.reportTypeControl = segCtrl

        let inputField = NSTextField()
        inputField.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        inputField.placeholderString = "11 FF 00 01 1B 04 00 ..."
        inputField.frame = NSRect(x: 174, y: 5, width: width - 174 - 56, height: 20)
        inputField.wantsLayer = true
        inputField.layer?.cornerRadius = 3
        inputField.textColor = .labelColor
        inputField.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.06)
        inputField.isBezeled = false
        inputField.autoresizingMask = [.width]
        container.addSubview(inputField)
        self.rawInputField = inputField

        let sendBtn = makeActionBtn(title: "Send", action: #selector(sendRawClicked),
                                    color: NSColor(calibratedRed: 0.3, green: 0.8, blue: 0.4, alpha: 1.0))
        sendBtn.frame = NSRect(x: width - 50, y: 5, width: 42, height: 20)
        sendBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        sendBtn.autoresizingMask = [.minXMargin]
        container.addSubview(sendBtn)
    }

    // MARK: - Table Click Handlers

    @objc private func featureTableClicked(_ sender: Any?) {
        let row = featureTableView.selectedRow
        controlsTableView?.deselectAll(nil)
        selectedControlCID = nil
        guard row >= 0, row < featureRows.count else { selectedFeatureId = nil; updateContextActions(); return }
        selectedFeatureId = featureRows[row].featureId
        updateContextActions()
    }

    @objc private func controlsTableClicked(_ sender: Any?) {
        let row = controlsTableView.selectedRow
        featureTableView?.deselectAll(nil)
        selectedFeatureId = nil
        guard row >= 0, row < controlRows.count else { selectedControlCID = nil; updateContextActions(); return }
        selectedControlCID = controlRows[row].cid
        updateContextActions()
    }

    private func updateContextActions() {
        guard let container = contextActionsContainer else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        let w = container.bounds.width - L.pad * 2
        var by: CGFloat = 0

        if let featureId = selectedFeatureId {
            let actions = HIDPPFeatureActions.actions(for: featureId)
            for action in actions {
                let btn = makeActionBtn(title: action.name, action: #selector(featureActionClicked(_:)))
                btn.tag = Int(action.functionId)
                btn.frame = NSRect(x: L.pad, y: by, width: w, height: L.btnH)
                container.addSubview(btn)
                by += L.btnH + L.btnGap
            }
            by += 4
            let pf = NSTextField()
            pf.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            pf.placeholderString = "params (hex)"
            pf.frame = NSRect(x: L.pad, y: by, width: w, height: 22)
            pf.wantsLayer = true
            pf.layer?.cornerRadius = 3
            pf.textColor = .labelColor
            pf.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.08)
            pf.isBezeled = false
            container.addSubview(pf)
            self.paramInputField = pf
            by += 26

            let sl = makeLabel(text: "Index: 0", fontSize: 10, color: .secondaryLabelColor)
            sl.frame = NSRect(x: L.pad, y: by, width: 60, height: 18)
            container.addSubview(sl)
            self.indexStepperLabel = sl

            let stepper = NSStepper()
            stepper.minValue = 0
            stepper.maxValue = 255
            stepper.integerValue = 0
            stepper.target = self
            stepper.action = #selector(indexStepperChanged(_:))
            stepper.frame = NSRect(x: L.pad + 62, y: by, width: 19, height: 18)
            container.addSubview(stepper)
            self.indexStepper = stepper

        } else if let cid = selectedControlCID {
            let isDiverted = currentSession?.debugDivertedCIDs.contains(cid) ?? false
            let divertBtn = makeActionBtn(title: isDiverted ? "Undivert" : "Divert", action: #selector(toggleDivertClicked))
            divertBtn.frame = NSRect(x: L.pad, y: by, width: w, height: L.btnH)
            container.addSubview(divertBtn)
            by += L.btnH + L.btnGap

            let queryBtn = makeActionBtn(title: "Query Reporting", action: #selector(queryReportingClicked))
            queryBtn.frame = NSRect(x: L.pad, y: by, width: w, height: L.btnH)
            container.addSubview(queryBtn)
            by += L.btnH + L.btnGap + 4

            // Show current flags and target CID
            if let ctrl = controlRows.first(where: { $0.cid == cid }) {
                let flagsText = "Flags: \(HIDPPInfo.flagsDescription(ctrl.flags))"
                let fl = makeLabel(text: flagsText, fontSize: 9, color: .secondaryLabelColor)
                fl.frame = NSRect(x: L.pad, y: by, width: w, height: 14)
                container.addSubview(fl)
                by += 16

                if ctrl.targetCID != 0 && ctrl.targetCID != ctrl.cid {
                    let targetText = "Target: \(String(format: "0x%04X", ctrl.targetCID))"
                    let tl = makeLabel(text: targetText, fontSize: 9, color: .secondaryLabelColor)
                    tl.frame = NSRect(x: L.pad, y: by, width: w, height: 14)
                    container.addSubview(tl)
                }
            }
        } else {
            let ph = makeLabel(text: "Select a feature\nor control", fontSize: 10, color: .tertiaryLabelColor)
            ph.frame = NSRect(x: L.pad, y: L.pad, width: w, height: 40)
            ph.alignment = .center
            ph.maximumNumberOfLines = 2
            container.addSubview(ph)
        }
    }

    @objc private func indexStepperChanged(_ sender: NSStepper) {
        indexStepperLabel?.stringValue = "Index: \(sender.integerValue)"
    }

    // MARK: - Global Actions

    @objc private func rediscoverClicked() {
        currentSession?.rediscoverFeatures()
        refreshRightPanelsLoading()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.refreshRightPanels() }
    }

    @objc private func redivertClicked() {
        currentSession?.redivertAllControls()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refreshControls() }
    }

    @objc private func undivertClicked() {
        currentSession?.undivertAllControls()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refreshControls() }
    }

    @objc private func enumerateClicked() {
        currentSession?.enumerateReceiverDevices()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            self?.refreshSidebar()
            self?.refreshRightPanels()
        }
    }

    @objc private func clearLogClicked() {
        LogitechHIDDebugPanel.logBuffer.removeAll()
        logTableView?.reloadData()
    }

    // MARK: - Feature Actions

    @objc private func featureActionClicked(_ sender: NSButton) {
        guard let session = currentSession, let featureId = selectedFeatureId else { return }
        guard let featureIdx = session.debugFeatureIndex[featureId] else {
            LogitechHIDDebugPanel.log(device: session.deviceInfo.name, type: .warning,
                                      message: "Feature 0x\(String(format: "%04X", featureId)) not indexed")
            return
        }
        let functionId = UInt8(sender.tag)
        var params = [UInt8](repeating: 0, count: 16)

        let actions = HIDPPFeatureActions.actions(for: featureId)
        if let action = actions.first(where: { $0.functionId == functionId }) {
            switch action.paramType {
            case .none: break
            case .index:
                params[0] = UInt8(indexStepper?.integerValue ?? 0)
            case .hex:
                if let hexStr = paramInputField?.stringValue, !hexStr.isEmpty {
                    let bytes = hexStr.split(separator: " ").compactMap { UInt8($0, radix: 16) }
                    for (i, b) in bytes.prefix(16).enumerated() { params[i] = b }
                } else {
                    for (i, b) in action.defaultParams.prefix(16).enumerated() { params[i] = b }
                }
            }
        }
        sendDebugPacket(session: session, featureIndex: featureIdx, functionId: functionId, params: params)
    }

    @objc private func toggleDivertClicked() {
        guard let session = currentSession, let cid = selectedControlCID else { return }
        session.toggleDivert(cid: cid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshControls()
            self?.updateContextActions()
        }
    }

    @objc private func queryReportingClicked() {
        guard let session = currentSession, let cid = selectedControlCID else { return }
        guard let reprogIdx = session.debugFeatureIndex[0x1B04] else { return }
        let params: [UInt8] = [UInt8(cid >> 8), UInt8(cid & 0xFF)] + [UInt8](repeating: 0, count: 14)
        sendDebugPacket(session: session, featureIndex: reprogIdx, functionId: 2, params: params)
    }

    private func sendDebugPacket(session: LogitechDeviceSession, featureIndex: UInt8, functionId: UInt8, params: [UInt8]) {
        var report = [UInt8](repeating: 0, count: 20)
        report[0] = 0x11
        report[1] = session.debugDeviceIndex
        report[2] = featureIndex
        report[3] = (functionId << 4) | 0x01
        for (i, p) in params.prefix(16).enumerated() { report[4 + i] = p }

        let hex = report.map { String(format: "%02X", $0) }.joined(separator: " ")
        LogitechHIDDebugPanel.log(device: session.deviceInfo.name, type: .tx, message: "TX: \(hex)", rawBytes: report)

        let result = IOHIDDeviceSetReport(session.hidDevice, kIOHIDReportTypeOutput, CFIndex(report[0]), report, report.count)
        if result != kIOReturnSuccess {
            LogitechHIDDebugPanel.log(device: session.deviceInfo.name, type: .error,
                                      message: "IOHIDDeviceSetReport failed: \(String(format: "0x%08X", result))")
        }
    }

    // MARK: - Log Actions

    @objc private func filterChipClicked(_ sender: NSButton) {
        let chipOrder: [LogEntryType] = [.tx, .rx, .error, .buttonEvent, .warning, .info]
        guard sender.tag >= 0, sender.tag < chipOrder.count else { return }
        let type = chipOrder[sender.tag]
        if logTypeFilter.contains(type) {
            logTypeFilter.remove(type)
            sender.layer?.opacity = 0.3
        } else {
            logTypeFilter.insert(type)
            sender.layer?.opacity = 1.0
        }
        logTableView?.reloadData()
    }

    @objc private func logRowClicked(_ sender: Any?) {
        let row = logTableView.clickedRow
        let filtered = filteredLogEntries()
        guard row >= 0, row < filtered.count else { return }
        let bufferIdx = filtered[row].0
        LogitechHIDDebugPanel.logBuffer[bufferIdx].isExpanded.toggle()
        logTableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
        logTableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
    }

    @objc private func exportLogClicked() {
        guard let win = window else { return }
        let panel = NSSavePanel()
        let dateStr: String = {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd-HHmmss"
            return fmt.string(from: Date())
        }()
        panel.nameFieldStringValue = "hidpp-debug-\(dateStr).log"
        panel.beginSheetModal(for: win) { response in
            guard response == .OK, let url = panel.url else { return }
            var output = ""
            for entry in LogitechHIDDebugPanel.logBuffer {
                let dev = entry.deviceName.isEmpty ? "" : "[\(entry.deviceName)] "
                output += "[\(entry.timestamp)] \(dev)[\(entry.type.rawValue)] \(entry.message)\n"
                if let decoded = entry.decoded { output += "  > \(decoded)\n" }
                if let raw = entry.rawBytes {
                    output += "  HEX: \(raw.map { String(format: "%02X", $0) }.joined(separator: " "))\n"
                }
            }
            try? output.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    @objc private func sendRawClicked() {
        guard let session = currentSession else { return }
        guard session.debugDeviceOpened else {
            LogitechHIDDebugPanel.log(device: session.deviceInfo.name, type: .warning, message: "Device not opened")
            return
        }
        let hexStr = rawInputField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !hexStr.isEmpty else { return }
        let bytes = hexStr.split(separator: " ").compactMap { UInt8($0, radix: 16) }
        guard !bytes.isEmpty else {
            LogitechHIDDebugPanel.log(device: session.deviceInfo.name, type: .warning, message: "Invalid hex input")
            return
        }

        let isLong = reportTypeControl.selectedSegment == 1
        let reportLen = isLong ? 20 : 7
        var report = [UInt8](repeating: 0, count: reportLen)
        report[0] = isLong ? 0x11 : 0x10
        let srcBytes: [UInt8] = (bytes.first == 0x10 || bytes.first == 0x11) ? Array(bytes.dropFirst()) : bytes
        for (i, b) in srcBytes.prefix(reportLen - 1).enumerated() { report[1 + i] = b }

        let hex = report.map { String(format: "%02X", $0) }.joined(separator: " ")
        LogitechHIDDebugPanel.log(device: session.deviceInfo.name, type: .tx, message: "TX: \(hex)", rawBytes: report)

        let result = IOHIDDeviceSetReport(session.hidDevice, kIOHIDReportTypeOutput, CFIndex(report[0]), report, report.count)
        if result != kIOReturnSuccess {
            LogitechHIDDebugPanel.log(device: session.deviceInfo.name, type: .error,
                                      message: "IOHIDDeviceSetReport failed: \(String(format: "0x%08X", result))")
        }
    }

    private func filteredLogEntries() -> [(Int, LogEntry)] {
        return LogitechHIDDebugPanel.logBuffer.enumerated().filter { logTypeFilter.contains($0.element.type) }
    }

    // MARK: - Refresh

    private func refreshAll() {
        refreshSidebar()
        refreshDeviceInfo()
        refreshFeatureTable()
        refreshControls()
        updateContextActions()
        logTableView?.reloadData()
    }

    private func refreshRightPanels() {
        refreshDeviceInfo()
        refreshFeatureTable()
        refreshControls()
        updateContextActions()
    }

    private func refreshRightPanelsLoading() {
        featureRows.removeAll()
        controlRows.removeAll()
        featureTableView?.reloadData()
        controlsTableView?.reloadData()
        updateHeaderLabel(tag: 100, text: "FEATURES (...)")
        updateHeaderLabel(tag: 101, text: "CONTROLS (...)")
        updateContextActions()
    }

    private func refreshSidebar() {
        let sessions = LogitechHIDManager.shared.activeSessions
        deviceNodes = sessions
            .filter { $0.debugConnectionMode != "unsupported" }
            .map { DeviceNode(session: $0) }
        outlineView?.reloadData()
        for node in deviceNodes where node.isReceiver { outlineView?.expandItem(node) }
        // If current session disconnected, select first remaining device and clear selection state
        if let cs = currentSession, !sessions.contains(where: { $0 === cs }) {
            currentSession = deviceNodes.first?.session
            selectedFeatureId = nil
            selectedControlCID = nil
        }
        if currentSession == nil {
            currentSession = deviceNodes.first?.session
            selectedFeatureId = nil
            selectedControlCID = nil
        }
    }

    private func refreshDeviceInfo() {
        guard let s = currentSession else {
            for pair in deviceInfoLabels { pair.value.stringValue = "--" }
            for pair in moreInfoLabels { pair.value.stringValue = "--" }
            return
        }
        let vals: [String] = [
            String(format: "0x%04X", s.deviceInfo.vendorId),
            String(format: "0x%04X", s.deviceInfo.productId),
            s.debugFeatureIndex.isEmpty ? "--" : "4.x",
            s.transport,
            String(format: "0x%02X", s.debugDeviceIndex),
            s.debugConnectionMode,
            s.debugDeviceOpened ? "\u{2713}" : "\u{2717}",
        ]
        for (i, val) in vals.enumerated() where i < deviceInfoLabels.count {
            deviceInfoLabels[i].value.stringValue = val
        }
        let moreVals: [String] = [
            String(format: "0x%04X", s.usagePage),
            String(format: "0x%04X", s.usage),
            s.isHIDPPCandidate ? "Yes" : "No",
            s.debugReprogInitComplete ? "Yes" : "No",
            "\(s.debugDivertedCIDs.count)",
        ]
        for (i, val) in moreVals.enumerated() where i < moreInfoLabels.count {
            moreInfoLabels[i].value.stringValue = val
        }
    }

    private func refreshFeatureTable() {
        guard let s = currentSession else {
            featureRows.removeAll()
            featureTableView?.reloadData()
            return
        }
        featureRows = s.debugFeatureIndex.sorted(by: { $0.value < $1.value }).map { (featureId, index) in
            let name = HIDPPInfo.featureNames[featureId]?.0 ?? "Unknown"
            return (index: String(format: "0x%02X", index), featureId: featureId,
                    featureIdHex: String(format: "0x%04X", featureId), name: name)
        }
        featureTableView?.reloadData()
        updateHeaderLabel(tag: 100, text: "FEATURES (\(featureRows.count))")
    }

    private func refreshControls() {
        guard let s = currentSession else {
            controlRows.removeAll()
            controlsTableView?.reloadData()
            return
        }
        controlRows = s.debugDiscoveredControls
        controlsTableView?.reloadData()
        updateHeaderLabel(tag: 101, text: "CONTROLS (\(controlRows.count))")
    }

    private func updateHeaderLabel(tag: Int, text: String) {
        func find(in view: NSView) -> NSTextField? {
            if let tf = view as? NSTextField, tf.tag == tag { return tf }
            for sub in view.subviews { if let f = find(in: sub) { return f } }
            return nil
        }
        if let cv = window?.contentView, let lbl = find(in: cv) { lbl.stringValue = text }
    }

    // MARK: - Observers

    private func startObserving() {
        stopObserving()
        logObserver = NotificationCenter.default.addObserver(
            forName: LogitechHIDDebugPanel.logNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            self.logTableView?.reloadData()
            // Auto-scroll only if user is near the bottom
            if let sv = self.logTableView?.enclosingScrollView {
                let visibleH = sv.contentView.bounds.height
                let contentH = self.logTableView?.frame.height ?? 0
                let scrollY = sv.contentView.bounds.origin.y
                let isNearBottom = (contentH - scrollY - visibleH) < 40
                if isNearBottom {
                    let count = self.filteredLogEntries().count
                    if count > 0 { self.logTableView?.scrollRowToVisible(count - 1) }
                }
            }
            if let entry = notification.object as? LogEntry,
               entry.type == .buttonEvent || entry.message.contains("divert") {
                self.refreshControls()
            }
        }
        sessionObserver = NotificationCenter.default.addObserver(
            forName: LogitechHIDManager.sessionChangedNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshAll() }
    }

    private func stopObserving() {
        if let o = logObserver { NotificationCenter.default.removeObserver(o); logObserver = nil }
        if let o = sessionObserver { NotificationCenter.default.removeObserver(o); sessionObserver = nil }
    }

    // MARK: - Helpers

    private func makeLabel(text: String, fontSize: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        l.textColor = color
        l.backgroundColor = .clear
        l.isBezeled = false
        l.isEditable = false
        l.isSelectable = false
        return l
    }

    private func makeSectionHeader(_ title: String) -> NSTextField {
        return makeLabel(text: title, fontSize: 10, weight: .medium, color: .tertiaryLabelColor)
    }

    private func makeActionBtn(title: String, action: Selector,
                               color: NSColor = NSColor(calibratedRed: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.backgroundColor = color.withAlphaComponent(0.15).cgColor
        btn.layer?.borderColor = color.withAlphaComponent(0.3).cgColor
        btn.layer?.borderWidth = 1
        btn.layer?.cornerRadius = 4
        btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        if #available(macOS 10.14, *) { btn.contentTintColor = .labelColor }
        return btn
    }

    private func makeSep() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.1).cgColor
        return v
    }

    private func makeSectionBg() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.05).cgColor
        v.layer?.cornerRadius = 6
        return v
    }

    private func makeLogBg() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.4).cgColor
        v.layer?.cornerRadius = 6
        return v
    }

    private func logColor(for type: LogEntryType) -> NSColor {
        switch type {
        case .tx: return NSColor(calibratedRed: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)
        case .rx: return NSColor(calibratedRed: 0.3, green: 0.8, blue: 0.4, alpha: 1.0)
        case .error: return NSColor(calibratedRed: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        case .buttonEvent: return NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.2, alpha: 1.0)
        case .warning: return NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)
        case .info: return NSColor(calibratedWhite: 0.75, alpha: 1.0)
        }
    }
}

// MARK: - NSOutlineViewDataSource & Delegate

extension LogitechHIDDebugPanel: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return deviceNodes.count }
        if let node = item as? DeviceNode, node.isReceiver {
            return node.session.debugReceiverPairedDevices.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return deviceNodes[index] }
        if let node = item as? DeviceNode, node.isReceiver {
            let paired = node.session.debugReceiverPairedDevices[index]
            return SlotNode(session: node.session, slot: paired.slot)
        }
        return NSNull()
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return (item as? DeviceNode)?.isReceiver ?? false
    }
}

extension LogitechHIDDebugPanel: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let cellId = NSUserInterfaceItemIdentifier("DeviceCell")
        let cell = outlineView.makeView(withIdentifier: cellId, owner: nil) as? NSTextField
            ?? NSTextField(labelWithString: "")
        cell.identifier = cellId
        cell.font = NSFont.systemFont(ofSize: 11)
        cell.backgroundColor = .clear
        cell.isBezeled = false
        cell.isEditable = false

        if let node = item as? DeviceNode {
            let prefix = node.isReceiver ? "[R]" : "[M]"
            let attr = NSMutableAttributedString(string: "\(prefix) \(node.session.deviceInfo.name) ",
                                                  attributes: [.foregroundColor: NSColor.labelColor,
                                                               .font: NSFont.systemFont(ofSize: 11)])
            let dot = NSAttributedString(string: "\u{25CF}",
                                          attributes: [.foregroundColor: NSColor(calibratedRed: 0.3, green: 0.8, blue: 0.4, alpha: 1.0),
                                                       .font: NSFont.systemFont(ofSize: 8)])
            attr.append(dot)
            cell.attributedStringValue = attr
        } else if let slot = item as? SlotNode {
            let paired = slot.session.debugReceiverPairedDevices
            let idx = Int(slot.slot) - 1
            guard idx >= 0, idx < paired.count else {
                cell.stringValue = "Slot \(slot.slot): --"
                cell.textColor = .tertiaryLabelColor
                return cell
            }
            let dev = paired[idx]
            if dev.isConnected {
                cell.stringValue = dev.name.isEmpty ? "Slot \(dev.slot)" : dev.name
                cell.textColor = .labelColor
            } else {
                cell.stringValue = "Slot \(dev.slot): empty"
                cell.textColor = .tertiaryLabelColor
            }
        }
        return cell
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension LogitechHIDDebugPanel: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        switch tableView.tag {
        case 200: return featureRows.count
        case 201: return controlRows.count
        case 300: return filteredLogEntries().count
        default: return 0
        }
    }
}

extension LogitechHIDDebugPanel: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch tableView.tag {
        case 200: return featureCell(tableColumn: tableColumn, row: row)
        case 201: return controlCell(tableColumn: tableColumn, row: row)
        case 300: return logCell(row: row)
        default: return nil
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if tableView.tag == 300 {
            let filtered = filteredLogEntries()
            guard row < filtered.count else { return 18 }
            let entry = filtered[row].1
            if entry.isExpanded {
                var lines = 1
                if entry.rawBytes != nil { lines += 1 }
                if entry.decoded != nil { lines += 1 }
                return CGFloat(lines) * 16 + 4
            }
        }
        return tableView.tag == 300 ? 18 : 20
    }

    private func featureCell(tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < featureRows.count else { return nil }
        let item = featureRows[row]
        let cellId = NSUserInterfaceItemIdentifier("fCell")
        let cell = featureTableView.makeView(withIdentifier: cellId, owner: nil) as? NSTextField
            ?? NSTextField(labelWithString: "")
        cell.identifier = cellId
        cell.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        cell.backgroundColor = .clear
        cell.isBezeled = false
        cell.isEditable = false
        cell.textColor = .labelColor

        switch tableColumn?.identifier.rawValue {
        case "fIdx": cell.stringValue = item.index
        case "fId": cell.stringValue = item.featureIdHex
        case "fName":
            cell.stringValue = item.name
            cell.textColor = NSColor(calibratedRed: 0.5, green: 0.7, blue: 1.0, alpha: 1.0)
        default: break
        }
        return cell
    }

    private func controlCell(tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < controlRows.count else { return nil }
        let ctrl = controlRows[row]
        let cellId = NSUserInterfaceItemIdentifier("cCell")
        let cell = controlsTableView.makeView(withIdentifier: cellId, owner: nil) as? NSTextField
            ?? NSTextField(labelWithString: "")
        cell.identifier = cellId
        cell.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        cell.backgroundColor = .clear
        cell.isBezeled = false
        cell.isEditable = false
        cell.textColor = .labelColor

        let isDiverted = ctrl.reportingFlags & 0x01 != 0
        let isRemapped = ctrl.targetCID != 0

        switch tableColumn?.identifier.rawValue {
        case "cCid": cell.stringValue = String(format: "0x%04X", ctrl.cid)
        case "cName": cell.stringValue = LogitechCIDRegistry.name(forCID: ctrl.cid)
        case "cFlags":
            cell.stringValue = HIDPPInfo.flagsDescription(ctrl.flags)
            cell.textColor = .secondaryLabelColor
            cell.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        case "cStatus":
            if isDiverted {
                cell.stringValue = "DVRT"
                cell.textColor = NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.0, alpha: 0.8)
            } else if isRemapped {
                cell.stringValue = "REMAP"
                cell.textColor = NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.2, alpha: 0.8)
            } else {
                cell.stringValue = "\u{25CF}"
                cell.textColor = NSColor(calibratedRed: 0.3, green: 0.8, blue: 0.4, alpha: 1.0)
            }
        default: break
        }
        return cell
    }

    private func logCell(row: Int) -> NSView? {
        let filtered = filteredLogEntries()
        guard row < filtered.count else { return nil }
        let entry = filtered[row].1

        let cellId = NSUserInterfaceItemIdentifier("logCell")
        let cell = logTableView.makeView(withIdentifier: cellId, owner: nil) as? NSTextField
            ?? NSTextField(labelWithString: "")
        cell.identifier = cellId
        cell.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        cell.backgroundColor = .clear
        cell.isBezeled = false
        cell.isEditable = false
        cell.isSelectable = true
        cell.maximumNumberOfLines = 0
        cell.cell?.wraps = true

        let color = logColor(for: entry.type)
        let arrow = entry.isExpanded ? "\u{25BE}" : "\u{25B8}"
        var text = "\(arrow) [\(entry.timestamp)] \(entry.message)"
        if entry.isExpanded {
            if let raw = entry.rawBytes {
                text += "\n  HEX: \(raw.map { String(format: "%02X", $0) }.joined(separator: " "))"
            }
            if let decoded = entry.decoded { text += "\n  \(decoded)" }
        }
        cell.attributedStringValue = NSAttributedString(string: text, attributes: [
            .foregroundColor: color,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
        ])
        return cell
    }
}
