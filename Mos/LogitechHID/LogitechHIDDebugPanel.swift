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

// MARK: - Debug Panel

class LogitechHIDDebugPanel: NSObject {
    static let shared = LogitechHIDDebugPanel()
    static let logNotification = NSNotification.Name("LogitechHIDDebugLog")

    private var window: NSWindow?

    // Tables
    private var deviceInfoTable: NSTableView?
    private var receiverDevicesTable: NSTableView?
    private var featureTable: NSTableView?
    private var controlsTable: NSTableView?
    private var logTextView: NSTextView?
    private var deviceSelector: NSPopUpButton?

    // Layout: Device Info + Receiver side-by-side
    private var topSplit: NSSplitView?          // 水平 split (左: DeviceInfo, 右: Receiver)
    private var receiverSection: NSView?        // 右侧 receiver 容器, 非 receiver 设备时隐藏

    // Data
    private var deviceInfoRows: [(String, String, String)] = []   // (property, value, annotation)
    private var receiverDeviceRows: [(UInt8, String, String, String, String, String, String)] = []
    // (slot, status, name, type, wirelessPID, protocol, error)
    private var featureRows: [(String, String, String, String)] = [] // (index, featID, name, purpose)
    private var controlRows: [(Int, String, String, String, String, String, String)] = []
    // (idx, cid, name, taskId, flagsDesc, reportingState, targetCID)

    private var currentSession: LogitechDeviceSession?

    // Log
    private static var logBuffer: [LogEntry] = []
    private static let maxLogLines = 500
    private var logTypeFilter: Set<LogEntryType> = Set(LogEntryType.allCases)

    // Observers
    private var logObserver: NSObjectProtocol?
    private var sessionObserver: NSObjectProtocol?

    // MARK: - Logging API

    class func log(_ message: String) {
        let entry = LogEntry(
            timestamp: timestamp(),
            deviceName: "",
            type: .info,
            message: message,
            decoded: nil
        )
        appendToBuffer(entry)
    }

    class func log(device: String, type: LogEntryType, message: String, decoded: String? = nil) {
        let entry = LogEntry(
            timestamp: timestamp(),
            deviceName: device,
            type: type,
            message: message,
            decoded: decoded
        )
        appendToBuffer(entry)
    }

    private class func appendToBuffer(_ entry: LogEntry) {
        // 仅输出到 HID++ debug 面板, 不污染系统 console
        logBuffer.append(entry)
        if logBuffer.count > maxLogLines { logBuffer.removeFirst(logBuffer.count - maxLogLines) }
        NotificationCenter.default.post(name: logNotification, object: nil, userInfo: ["entry": entry])
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }

    // MARK: - Show / Hide

    func show() {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        createWindow()
        refreshAll()
        for entry in LogitechHIDDebugPanel.logBuffer { appendLogEntry(entry) }
        startObserving()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Window Creation

    private func createWindow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        w.title = "Logitech HID++ Debug"
        w.center()
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 700, height: 400)

        let content = w.contentView!
        let cw = content.bounds.width
        let ch = content.bounds.height

        // Toolbar (top 36px)
        let toolbar = NSView(frame: NSRect(x: 0, y: ch - 36, width: cw, height: 36))
        toolbar.autoresizingMask = [.width, .minYMargin]

        var bx: CGFloat = 8
        let buttonDefs: [(String, Selector)] = [
            ("Refresh", #selector(refreshClicked)),
            ("Enumerate", #selector(enumerateClicked)),
            ("Re-Discover", #selector(rediscoverClicked)),
            ("Re-Divert", #selector(redivertClicked)),
            ("Undivert", #selector(undivertClicked)),
            ("Clear Log", #selector(clearLogClicked)),
        ]
        for (title, action) in buttonDefs {
            let btn = NSButton(title: title, target: self, action: action)
            btn.bezelStyle = .rounded
            btn.frame = NSRect(x: bx, y: 6, width: CGFloat(title.count * 9 + 20), height: 24)
            toolbar.addSubview(btn)
            bx += btn.frame.width + 4
        }
        // 分隔线
        bx += 8
        let sep = NSBox(frame: NSRect(x: bx, y: 8, width: 1, height: 20))
        sep.boxType = .separator
        toolbar.addSubview(sep)
        bx += 8
        // Logi 动作测试按钮
        let testDefs: [(String, Selector)] = [
            ("SmartShift", #selector(testSmartShiftClicked)),
            ("DPI+", #selector(testDPIUpClicked)),
            ("DPI-", #selector(testDPIDownClicked)),
        ]
        for (title, action) in testDefs {
            let btn = NSButton(title: title, target: self, action: action)
            btn.bezelStyle = .rounded
            btn.frame = NSRect(x: bx, y: 6, width: CGFloat(title.count * 9 + 20), height: 24)
            toolbar.addSubview(btn)
            bx += btn.frame.width + 4
        }
        // Device selector
        let selector = NSPopUpButton(frame: NSRect(x: bx + 20, y: 6, width: 200, height: 24), pullsDown: false)
        selector.target = self
        selector.action = #selector(deviceSelectorChanged)
        toolbar.addSubview(selector)
        self.deviceSelector = selector

        content.addSubview(toolbar)

        // NSSplitView: 可拖动分隔条
        let bodyH = ch - 36
        let split = NSSplitView(frame: NSRect(x: 0, y: 0, width: cw, height: bodyH))
        split.isVertical = false
        split.dividerStyle = .thin
        split.autoresizingMask = [.width, .height]

        // Top row: Device Info (左) + Receiver Devices (右, 仅 receiver 设备时显示)
        let topH: CGFloat = 140
        let hSplit = NSSplitView(frame: NSRect(x: 0, y: 0, width: cw, height: topH))
        hSplit.isVertical = true
        hSplit.dividerStyle = .thin
        hSplit.autoresizingMask = [.width, .height]
        self.topSplit = hSplit

        let s1 = makeTableSection(
            columns: [("Property", 120), ("Value", 200), ("Annotation", 300)],
            tag: 1
        )
        s1.frame = NSRect(x: 0, y: 0, width: cw / 2, height: topH)
        hSplit.addSubview(s1)

        let s4 = makeTableSection(
            columns: [("Slot", 35), ("Status", 50), ("Name", 120), ("Type", 60), ("PID", 60), ("Proto", 50), ("Note", 120)],
            tag: 4
        )
        s4.frame = NSRect(x: 0, y: 0, width: cw / 2, height: topH)
        hSplit.addSubview(s4)
        self.receiverSection = s4

        hSplit.adjustSubviews()
        split.addSubview(hSplit)

        // Section 2: Feature Table
        let s2 = makeTableSection(
            columns: [("Index", 60), ("Feature ID", 90), ("Name", 180), ("Purpose", 400)],
            tag: 2
        )
        s2.frame = NSRect(x: 0, y: 0, width: cw, height: 50)
        split.addSubview(s2)

        // Section 3: Controls
        let s3 = makeTableSection(
            columns: [("Idx", 35), ("CID", 65), ("Name", 120), ("TaskID", 65), ("Flags", 160), ("Reporting", 120), ("Target", 100)],
            tag: 3
        )
        s3.frame = NSRect(x: 0, y: 0, width: cw, height: 120)
        split.addSubview(s3)

        // Section 5: Protocol Log
        let logScroll = NSScrollView()
        logScroll.hasVerticalScroller = true
        logScroll.frame = NSRect(x: 0, y: 0, width: cw, height: bodyH - 310)
        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = NSFont.userFixedPitchFont(ofSize: 11)!
        tv.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1.0)
        tv.textColor = NSColor.white
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        logScroll.documentView = tv
        self.logTextView = tv
        split.addSubview(logScroll)

        content.addSubview(split)
        split.adjustSubviews()

        self.window = w
    }

    private static let sectionTitles: [Int: String] = [
        1: "Device Info",
        2: "Feature Table (HID++ Features)",
        3: "Controls (REPROG_CONTROLS_V4 Buttons)",
        4: "Receiver Devices (Unifying/Bolt)",
    ]

    private func makeTableSection(columns: [(String, CGFloat)], tag: Int) -> NSView {
        let container = NSView()
        container.autoresizingMask = [.width, .height]

        // Section 标题
        let titleLabel = NSTextField(labelWithString: LogitechHIDDebugPanel.sectionTitles[tag] ?? "")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 11)
        titleLabel.textColor = NSColor.secondaryLabelColor
        titleLabel.frame = NSRect(x: 6, y: 0, width: 400, height: 16)
        titleLabel.autoresizingMask = [.width, .maxYMargin]

        // 表格
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]

        let table = NSTableView()
        table.headerView = NSTableHeaderView()
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 18
        table.tag = tag
        table.delegate = self
        table.dataSource = self

        for (title, width) in columns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("\(tag)_\(title)"))
            col.title = title
            col.width = width
            table.addTableColumn(col)
        }

        scroll.documentView = table

        switch tag {
        case 1: deviceInfoTable = table
        case 2: featureTable = table
        case 3: controlsTable = table
        case 4: receiverDevicesTable = table
        default: break
        }

        container.addSubview(scroll)
        container.addSubview(titleLabel)

        // macOS 坐标系: y=0 在底部. 标题在顶部, 表格在下方
        // 使用 autoresizingMask 回调来动态布局
        container.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: container, queue: .main) { _ in
            let h = container.bounds.height
            titleLabel.frame = NSRect(x: 6, y: h - 16, width: container.bounds.width - 12, height: 16)
            scroll.frame = NSRect(x: 0, y: 0, width: container.bounds.width, height: h - 16)
        }
        // 初始布局
        let h = container.bounds.height > 0 ? container.bounds.height : 100
        titleLabel.frame = NSRect(x: 6, y: h - 16, width: 900, height: 16)
        scroll.frame = NSRect(x: 0, y: 0, width: 900, height: h - 16)

        return container
    }

    // MARK: - Data Refresh

    @objc private func refreshClicked() { refreshAll() }

    @objc private func enumerateClicked() {
        guard let session = currentSession, session.debugConnectionMode.contains("Receiver") else {
            LogitechHIDDebugPanel.log("[DebugPanel] Enumerate: not a receiver session")
            return
        }
        session.enumerateReceiverDevices()
        // 延迟刷新以等待枚举完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.refreshReceiverDevices() }
    }

    @objc private func rediscoverClicked() {
        currentSession?.rediscoverFeatures()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.refreshAll() }
    }

    @objc private func redivertClicked() {
        currentSession?.redivertAllControls()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refreshAll() }
    }

    @objc private func undivertClicked() {
        currentSession?.undivertAllControls()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refreshAll() }
    }

    @objc private func clearLogClicked() {
        logTextView?.string = ""
    }

    // MARK: - Logi Action Tests

    @objc private func testSmartShiftClicked() {
        guard let session = currentSession else { return }
        LogitechHIDDebugPanel.log(device: session.deviceInfo.name, type: .info, message: ">>> TEST: SmartShift Toggle")
        session.executeSmartShiftToggle()
    }

    @objc private func testDPIUpClicked() {
        guard let session = currentSession else { return }
        LogitechHIDDebugPanel.log(device: session.deviceInfo.name, type: .info, message: ">>> TEST: DPI Cycle Up")
        session.executeDPICycle(direction: .up)
    }

    @objc private func testDPIDownClicked() {
        guard let session = currentSession else { return }
        LogitechHIDDebugPanel.log(device: session.deviceInfo.name, type: .info, message: ">>> TEST: DPI Cycle Down")
        session.executeDPICycle(direction: .down)
    }

    @objc private func deviceSelectorChanged() {
        let sessions = LogitechHIDManager.shared.activeSessions
        let idx = deviceSelector?.indexOfSelectedItem ?? 0
        if idx < sessions.count {
            currentSession = sessions[idx]
        }
        refreshDeviceInfo()
        refreshReceiverDevices()
        refreshFeatureTable()
        refreshControls()
    }

    private func refreshAll() {
        let sessions = LogitechHIDManager.shared.activeSessions

        // 更新设备选择器
        deviceSelector?.removeAllItems()
        for s in sessions {
            let label = "\(s.deviceInfo.name) (\(s.transport) \(String(format: "0x%04X/0x%04X", s.usagePage, s.usage)))"
            deviceSelector?.addItem(withTitle: label)
        }

        // 选择第一个 HID++ candidate, 或保持当前选择
        if currentSession == nil || !sessions.contains(where: { $0 === currentSession }) {
            currentSession = sessions.first(where: { $0.isHIDPPCandidate }) ?? sessions.first
            if let cs = currentSession, let idx = sessions.firstIndex(where: { $0 === cs }) {
                deviceSelector?.selectItem(at: idx)
            }
        }

        refreshDeviceInfo()
        refreshReceiverDevices()
        refreshFeatureTable()
        refreshControls()
    }

    private func refreshDeviceInfo() {
        deviceInfoRows.removeAll()
        guard let s = currentSession else {
            deviceInfoRows.append(("Status", "No HID++ device found", "Connect a Logitech BLE mouse"))
            deviceInfoTable?.reloadData()
            return
        }

        let usagePageName: String
        switch s.usagePage {
        case 0x0001: usagePageName = "Generic Desktop"
        case 0xFF00: usagePageName = "Vendor-Specific (Logitech)"
        case 0xFF43: usagePageName = "Vendor-Specific (Logitech Alt)"
        default: usagePageName = "Unknown"
        }

        let usageName: String
        switch s.usage {
        case 0x0001: usageName = "Pointer"
        case 0x0002: usageName = "Mouse"
        case 0x0006: usageName = "Keyboard"
        default: usageName = "0x\(String(format: "%04X", s.usage))"
        }

        deviceInfoRows = [
            ("Product", s.deviceInfo.name, "IOKit kIOHIDProductKey"),
            ("Vendor ID", String(format: "0x%04X (%d)", s.deviceInfo.vendorId, s.deviceInfo.vendorId), "Logitech = 0x046D"),
            ("Product ID", String(format: "0x%04X (%d)", s.deviceInfo.productId, s.deviceInfo.productId), "Device model identifier"),
            ("Usage Page", String(format: "0x%04X", s.usagePage), usagePageName),
            ("Usage", String(format: "0x%04X", s.usage), usageName),
            ("Transport", s.transport, s.debugIsBLE ? "Bluetooth Low Energy" : "USB"),
            ("Connection Mode", s.debugConnectionMode, "BLE Direct / Receiver (Unifying-Bolt) / Unsupported"),
            ("Device Index", String(format: "0x%02X", s.debugDeviceIndex), s.debugIsBLE ? "0xFF = BLE direct" : "Target slot (click row below to switch)"),
            ("Device Opened", s.debugDeviceOpened ? "YES" : "NO", "IOHIDDeviceOpen result"),
            ("HID++ Candidate", s.isHIDPPCandidate ? "YES" : "NO", "Eligible for HID++ protocol"),
            ("Init Complete", s.debugReprogInitComplete ? "YES" : "NO", "Feature discovery + divert done"),
            ("Diverted CIDs", s.debugDivertedCIDs.map { String(format: "0x%04X", $0) }.joined(separator: ", "),
             s.debugDivertedCIDs.isEmpty ? "No buttons diverted" : "\(s.debugDivertedCIDs.count) buttons diverted"),
        ]
        deviceInfoTable?.reloadData()
    }

    private func refreshReceiverDevices() {
        receiverDeviceRows.removeAll()
        let isReceiver = currentSession?.debugConnectionMode.contains("Receiver") ?? false

        // 非 receiver: 隐藏右侧面板
        if !isReceiver {
            receiverSection?.isHidden = true
            topSplit?.adjustSubviews()
            receiverDevicesTable?.reloadData()
            return
        }

        // Receiver: 显示右侧面板
        receiverSection?.isHidden = false
        topSplit?.adjustSubviews()

        guard let s = currentSession else { receiverDevicesTable?.reloadData(); return }
        let devices = s.debugReceiverPairedDevices
        let targetSlot = s.debugDeviceIndex
        if devices.isEmpty {
            receiverDeviceRows.append((0, "--", "Enumerating...", "--", "--", "--", ""))
        } else {
            for dev in devices {
                let isTarget = dev.slot == targetSlot
                let status = dev.isConnected ? "Online" : "Offline"
                let name = dev.name.isEmpty ? "--" : dev.name
                let typeName = dev.deviceTypeName
                let pid = dev.wirelessPID == 0 ? "--" : String(format: "0x%04X", dev.wirelessPID)
                let proto = dev.protocolVersion
                var note = dev.lastError ?? ""
                if isTarget { note = note.isEmpty ? "TARGETED" : "TARGETED | \(note)" }
                receiverDeviceRows.append((dev.slot, status, name, typeName, pid, proto, note))
            }
        }
        receiverDevicesTable?.reloadData()
    }

    private func refreshFeatureTable() {
        featureRows.removeAll()
        guard let s = currentSession else { featureTable?.reloadData(); return }

        for (featId, idx) in s.debugFeatureIndex.sorted(by: { $0.value < $1.value }) {
            let (name, purpose) = HIDPPInfo.featureNames[featId] ?? ("Unknown", "Feature ID \(String(format: "0x%04X", featId))")
            featureRows.append((
                String(format: "0x%02X", idx),
                String(format: "0x%04X", featId),
                name,
                purpose
            ))
        }
        if featureRows.isEmpty {
            featureRows.append(("--", "--", "No features discovered", "Feature discovery may have failed"))
        }
        featureTable?.reloadData()
    }

    private func refreshControls() {
        controlRows.removeAll()
        guard let s = currentSession else { controlsTable?.reloadData(); return }

        for (i, c) in s.debugDiscoveredControls.enumerated() {
            let name = LogitechCIDRegistry.name(forCID: c.cid)

            // Reporting 状态 (从 GetControlReporting function 2 查询)
            let reporting: String
            if c.reportingQueried {
                var parts: [String] = []
                if c.reportingFlags & 0x01 != 0 { parts.append("tmpDvrt") }
                if c.reportingFlags & 0x02 != 0 { parts.append("pstDvrt") }
                if c.reportingFlags & 0x04 != 0 { parts.append("tmpRemap") }
                if c.reportingFlags & 0x08 != 0 { parts.append("pstRemap") }
                reporting = parts.isEmpty ? "none" : parts.joined(separator: ",")
            } else {
                reporting = "..."
            }

            // Target CID (remap 目标)
            let target: String
            if c.reportingQueried && c.targetCID != 0 && c.targetCID != c.cid {
                target = "\(String(format: "0x%04X", c.targetCID)) \(LogitechCIDRegistry.name(forCID: c.targetCID))"
            } else {
                target = "--"
            }

            controlRows.append((
                i,
                String(format: "0x%04X", c.cid),
                name,
                String(format: "0x%04X", c.taskId),
                HIDPPInfo.flagsDescription(c.flags),
                reporting,
                target
            ))
        }
        if controlRows.isEmpty {
            controlRows.append((0, "--", "No controls discovered", "--", "--", "--", "--"))
        }
        controlsTable?.reloadData()
    }

    // MARK: - Log

    private func appendLogEntry(_ entry: LogEntry) {
        guard logTypeFilter.contains(entry.type) else { return }
        guard let tv = logTextView else { return }

        let color: NSColor
        switch entry.type {
        case .tx:          color = NSColor(calibratedRed: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)
        case .rx:          color = NSColor(calibratedRed: 0.3, green: 0.8, blue: 0.4, alpha: 1.0)
        case .error:       color = NSColor(calibratedRed: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        case .buttonEvent: color = NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.2, alpha: 1.0)
        case .warning:     color = NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)
        case .info:        color = NSColor(calibratedWhite: 0.75, alpha: 1.0)
        }

        let font = NSFont.userFixedPitchFont(ofSize: 11)!
        let line = "[\(entry.timestamp)] \(entry.message)\n"
        tv.textStorage?.append(NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: color]))

        if let decoded = entry.decoded {
            let decodedColor = color.withAlphaComponent(0.7)
            tv.textStorage?.append(NSAttributedString(string: "  -> \(decoded)\n", attributes: [.font: font, .foregroundColor: decodedColor]))
        }

        tv.scrollToEndOfDocument(nil)
    }

    // MARK: - Observers

    private func startObserving() {
        logObserver = NotificationCenter.default.addObserver(
            forName: LogitechHIDDebugPanel.logNotification, object: nil, queue: .main
        ) { [weak self] n in
            if let entry = n.userInfo?["entry"] as? LogEntry { self?.appendLogEntry(entry) }
            // Auto-refresh controls when button events or divert changes happen
            if let entry = n.userInfo?["entry"] as? LogEntry,
               entry.type == .buttonEvent || entry.message.contains("divert=") {
                self?.refreshControls()
            }
        }
        sessionObserver = NotificationCenter.default.addObserver(
            forName: LogitechHIDManager.sessionChangedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshAll()
        }
    }

    private func stopObserving() {
        if let o = logObserver { NotificationCenter.default.removeObserver(o) }
        if let o = sessionObserver { NotificationCenter.default.removeObserver(o) }
        logObserver = nil; sessionObserver = nil
    }
}

// MARK: - NSTableViewDelegate & DataSource

extension LogitechHIDDebugPanel: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        switch tableView.tag {
        case 1: return deviceInfoRows.count
        case 2: return featureRows.count
        case 3: return controlRows.count
        case 4: return receiverDeviceRows.count
        default: return 0
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let colId = tableColumn?.identifier.rawValue else { return nil }
        let cellId = NSUserInterfaceItemIdentifier("Cell_\(colId)")

        let cell: NSTextField
        if let existing = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTextField {
            cell = existing
        } else {
            cell = NSTextField(labelWithString: "")
            cell.identifier = cellId
            cell.font = NSFont.userFixedPitchFont(ofSize: 11)!
            cell.lineBreakMode = .byTruncatingTail
        }

        switch tableView.tag {
        case 1: // Device Info
            let r = deviceInfoRows[row]
            switch colId {
            case "1_Property": cell.stringValue = r.0
            case "1_Value": cell.stringValue = r.1
            case "1_Annotation":
                cell.stringValue = r.2
                cell.textColor = NSColor.secondaryLabelColor
            default: break
            }
        case 2: // Feature Table
            let r = featureRows[row]
            switch colId {
            case "2_Index": cell.stringValue = r.0
            case "2_Feature ID": cell.stringValue = r.1
            case "2_Name": cell.stringValue = r.2
            case "2_Purpose":
                cell.stringValue = r.3
                cell.textColor = NSColor.secondaryLabelColor
            default: break
            }
        case 3: // Controls
            let r = controlRows[row]
            switch colId {
            case "3_Idx": cell.stringValue = "\(r.0)"
            case "3_CID": cell.stringValue = r.1
            case "3_Name": cell.stringValue = r.2
            case "3_TaskID": cell.stringValue = r.3
            case "3_Flags": cell.stringValue = r.4
            case "3_Reporting":
                cell.stringValue = r.5
                if r.5.contains("Dvrt") || r.5.contains("Remap") {
                    cell.textColor = NSColor(calibratedRed: 0.3, green: 0.8, blue: 0.4, alpha: 1.0)
                } else if r.5 == "none" {
                    cell.textColor = NSColor.secondaryLabelColor
                }
            case "3_Target":
                cell.stringValue = r.6
                cell.textColor = r.6 == "--" ? NSColor.secondaryLabelColor : NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.2, alpha: 1.0)
            default: break
            }
        case 4: // Receiver Devices
            let r = receiverDeviceRows[row]
            let isTargeted = r.6.contains("TARGETED")
            switch colId {
            case "4_Slot":
                cell.stringValue = r.0 == 0 ? "--" : "\(r.0)"
                if isTargeted { cell.textColor = NSColor(calibratedRed: 0.4, green: 0.6, blue: 1.0, alpha: 1.0) }
            case "4_Status":
                cell.stringValue = r.1
                if r.1 == "Online" {
                    cell.textColor = isTargeted
                        ? NSColor(calibratedRed: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)
                        : NSColor(calibratedRed: 0.3, green: 0.8, blue: 0.4, alpha: 1.0)
                } else {
                    cell.textColor = NSColor.secondaryLabelColor
                }
            case "4_Name":
                cell.stringValue = r.2
                if isTargeted { cell.textColor = NSColor(calibratedRed: 0.4, green: 0.6, blue: 1.0, alpha: 1.0) }
            case "4_Type": cell.stringValue = r.3
            case "4_PID": cell.stringValue = r.4
            case "4_Proto": cell.stringValue = r.5
            case "4_Note":
                cell.stringValue = r.6
                cell.textColor = isTargeted
                    ? NSColor(calibratedRed: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)
                    : NSColor.secondaryLabelColor
            default: break
            }
        default: break
        }

        if !colId.contains("Annotation") && !colId.contains("Purpose") && !colId.contains("Reporting") && !colId.contains("Target") && !colId.contains("Status") && !colId.contains("Note") {
            cell.textColor = NSColor.labelColor
        }
        cell.font = NSFont.userFixedPitchFont(ofSize: 11)!
        return cell
    }

    // MARK: - Receiver Slot Selection

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView, table.tag == 4 else { return }
        let row = table.selectedRow
        guard row >= 0, row < receiverDeviceRows.count else { return }
        let slot = receiverDeviceRows[row].0
        guard slot >= 1, slot <= 6 else { return }

        currentSession?.setTargetSlot(slot: slot)
        LogitechHIDDebugPanel.log("[DebugPanel] Targeted slot \(slot)")
        refreshDeviceInfo()
        refreshReceiverDevices()
        refreshFeatureTable()
        refreshControls()
    }
}
