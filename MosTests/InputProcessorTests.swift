import XCTest
@testable import Mos_Debug

final class InputProcessorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
        MouseDragSessionController.shared.setTestingMotionTapHooks()
        MouseDragSessionController.shared.clearAllSessions()
        ShortcutExecutor.shared.setTestingMouseEventObserver()
        InputProcessor.shared.clearActiveBindings()
    }

    override func tearDown() {
        InputProcessor.shared.clearActiveBindings()
        MouseDragSessionController.shared.clearAllSessions()
        MouseDragSessionController.shared.clearTestingMotionTapHooks()
        ShortcutExecutor.shared.clearTestingMouseEventObserver()
        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
        super.tearDown()
    }

    func testProcess_downEvent_consumedWhenBindingMatches() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let event = InputEvent(type: .mouse, code: 3, modifiers: CGEventFlags(rawValue: 0),
                               phase: .down, source: .hidPP, device: nil)
        let result = InputProcessor.shared.process(event)
        XCTAssertEqual(result, .consumed)
    }

    func testProcess_upEvent_consumedViaActiveBindings() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: CGEventFlags(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        _ = InputProcessor.shared.process(downEvent)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: CGEventFlags(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        let result = InputProcessor.shared.process(upEvent)
        XCTAssertEqual(result, .consumed)
    }

    func testProcess_upEvent_passthroughWithoutPriorDown() {
        let event = InputEvent(type: .mouse, code: 99, modifiers: CGEventFlags(rawValue: 0),
                               phase: .up, source: .hidPP, device: nil)
        let result = InputProcessor.shared.process(event)
        XCTAssertEqual(result, .passthrough)
    }

    func testProcess_upEvent_matchesDespiteModifierChange() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: UInt(CGEventFlags.maskCommand.rawValue),
                                    displayComponents: ["⌘", "🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskCommand,
                                   phase: .down, source: .hidPP, device: nil)
        _ = InputProcessor.shared.process(downEvent)

        // Up with ⌘ already released (modifiers = 0)
        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: CGEventFlags(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        let result = InputProcessor.shared.process(upEvent)
        XCTAssertEqual(result, .consumed)
    }

    func testSystemShortcutExecutionModes_mouseActionsStateful_nonMouseTrigger() {
        XCTAssertEqual(SystemShortcut.mouseLeftClick.executionMode, .stateful)
        XCTAssertEqual(SystemShortcut.logiSmartShiftToggle.executionMode, .trigger)
    }

    func testProcess_upEvent_passthroughForTriggerShortcut() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "logiSmartShiftToggle", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .passthrough)
    }

    func testProcess_upEvent_consumedForStatefulMouseShortcut() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)
    }

    func testProcess_statefulMouseShortcut_doesNotSetVirtualModifierFlags() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
    }

    func testProcess_statefulMouseShortcut_startsAndStopsMouseDragSession() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertTrue(MouseDragSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseDragSessionController.shared.activeSessionCount, 1)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)
        XCTAssertFalse(MouseDragSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseDragSessionController.shared.activeSessionCount, 0)
    }

    func testProcess_statefulMouseShortcut_preservesPhysicalModifierFlagsOnSyntheticMouseEvents() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: UInt(CGEventFlags.maskShift.rawValue), displayComponents: ["⇧", "🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [(type: CGEventType, flags: CGEventFlags)] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append((event.type, event.flags))
        }

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)

        XCTAssertEqual(observedEvents.map(\.type), [.leftMouseDown, .leftMouseUp])
        XCTAssertTrue(observedEvents.allSatisfy { $0.flags.contains(.maskShift) })
    }

    func testProcess_mouseTriggerWithoutModifiers_matchesWhenAdditionalModifiersHeld() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedTypes: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedTypes.append(event.type)
        }

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)

        XCTAssertEqual(observedTypes, [.leftMouseDown, .leftMouseUp])
    }

    func testProcess_mouseTriggerPrefersExactModifierBindingOverBaseBinding() {
        let baseTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let exactTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: UInt(CGEventFlags.maskShift.rawValue), displayComponents: ["⇧", "🖱4"], deviceFilter: nil)
        let baseBinding = ButtonBinding(triggerEvent: baseTrigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        let exactBinding = ButtonBinding(triggerEvent: exactTrigger, systemShortcutName: "mouseRightClick", isEnabled: true)
        Options.shared.buttons.binding = [baseBinding, exactBinding]
        ButtonUtils.shared.invalidateCache()

        var observedTypes: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedTypes.append(event.type)
        }

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)

        XCTAssertEqual(observedTypes, [.rightMouseDown, .rightMouseUp])
    }

    func testProcess_repeatedDownForSameTrigger_replacesPreviousMouseDragSession() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertEqual(MouseDragSessionController.shared.activeSessionCount, 1)

        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertEqual(MouseDragSessionController.shared.activeSessionCount, 1)
    }

    func testClearActiveBindings_clearsVirtualModifierFlags() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, KeyCode.getKeyMask(56).rawValue)

        InputProcessor.shared.clearActiveBindings()
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
    }

    func testClearActiveBindings_clearsActiveMouseDragSessions() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertEqual(MouseDragSessionController.shared.activeSessionCount, 1)

        InputProcessor.shared.clearActiveBindings()
        XCTAssertFalse(MouseDragSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseDragSessionController.shared.activeSessionCount, 0)
    }

    func testButtonCore_passthroughMouseEvent_appliesVirtualModifierFlags() {
        let modifierTrigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱7"], deviceFilter: nil)
        let modifierBinding = ButtonBinding(triggerEvent: modifierTrigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [modifierBinding]
        ButtonUtils.shared.invalidateCache()

        let modifierDown = InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0),
                                      phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(modifierDown), .consumed)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskShift.rawValue)

        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: CGPoint(x: 16, y: 24),
            mouseButton: .left
        )!

        let proxy = CGEventTapProxy(bitPattern: 1)!
        let output = ButtonCore.shared.buttonEventCallBack(proxy, .leftMouseDown, event, nil)

        XCTAssertNotNil(output)
        XCTAssertTrue(event.flags.contains(.maskShift))
    }

    func testCGEventExtensions_otherMouseDraggedIsRecognizedForDiagnostics() {
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDragged,
            mouseCursorPosition: CGPoint(x: 120, y: 80),
            mouseButton: .center
        )!
        event.setIntegerValueField(.mouseEventButtonNumber, value: 3)

        XCTAssertFalse(event.isMouseEvent)
        XCTAssertTrue(event.isMouseDragEvent)
        XCTAssertTrue(event.isMouseInteractionEvent)
        XCTAssertEqual(event.mouseCode, 3)
        XCTAssertEqual(event.eventTypeName, "otherMouseDragged")
    }

    func testCGEventExtensions_mouseMovedIsRecognizedForDiagnostics() {
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: 12, y: 34),
            mouseButton: .left
        )!

        XCTAssertFalse(event.isMouseEvent)
        XCTAssertFalse(event.isMouseDragEvent)
        XCTAssertTrue(event.isMouseMoveEvent)
        XCTAssertTrue(event.isMouseInteractionEvent)
        XCTAssertEqual(event.eventTypeName, "mouseMoved")
    }

    func testInputEventFromCGEvent_otherMouseDraggedPreservesMouseCode() {
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDragged,
            mouseCursorPosition: CGPoint(x: 90, y: 45),
            mouseButton: .center
        )!
        event.setIntegerValueField(.mouseEventButtonNumber, value: 3)

        let inputEvent = InputEvent(fromCGEvent: event)
        XCTAssertEqual(inputEvent.type, .mouse)
        XCTAssertEqual(inputEvent.code, 3)
    }

    func testMonitorLogStore_previewShowsNewestLinesWithoutDroppingExportHistory() {
        let store = MonitorLogStore(previewLineLimit: 2)

        store.append("first", to: .buttonEvent)
        store.append("second", to: .buttonEvent)
        store.append("third", to: .buttonEvent)

        XCTAssertEqual(store.previewText(for: .buttonEvent), "third\nsecond")
        XCTAssertEqual(store.exportText(for: .buttonEvent), "first\nsecond\nthird")
    }

    func testMonitorLogStore_clearChannelRemovesPreviewAndHistory() {
        let store = MonitorLogStore(previewLineLimit: 3)

        store.append("one", to: .buttonEvent)
        store.append("two", to: .buttonEvent)
        store.clear(.buttonEvent)

        XCTAssertEqual(store.previewText(for: .buttonEvent), "")
        XCTAssertEqual(store.exportText(for: .buttonEvent), "")
    }

    func testButtonUtilsIndex_returnsOnlyMatchingTypeAndCodeCandidates() {
        let matchingTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let matchingWithDifferentModifiers = RecordedEvent(type: .mouse, code: 3, modifiers: UInt(CGEventFlags.maskCommand.rawValue), displayComponents: ["⌘", "🖱4"], deviceFilter: nil)
        let wrongTypeTrigger = RecordedEvent(type: .keyboard, code: 3, modifiers: 0, displayComponents: ["F"], deviceFilter: nil)
        let wrongCodeTrigger = RecordedEvent(type: .mouse, code: 4, modifiers: 0, displayComponents: ["🖱5"], deviceFilter: nil)

        let matchingBinding = ButtonBinding(triggerEvent: matchingTrigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        let matchingWithDifferentModifiersBinding = ButtonBinding(triggerEvent: matchingWithDifferentModifiers, systemShortcutName: "custom::56:0", isEnabled: true)
        let wrongTypeBinding = ButtonBinding(triggerEvent: wrongTypeTrigger, systemShortcutName: "mouseRightClick", isEnabled: true)
        let wrongCodeBinding = ButtonBinding(triggerEvent: wrongCodeTrigger, systemShortcutName: "mouseMiddleClick", isEnabled: true)

        Options.shared.buttons.binding = [
            matchingBinding,
            matchingWithDifferentModifiersBinding,
            wrongTypeBinding,
            wrongCodeBinding,
        ]
        ButtonUtils.shared.invalidateCache()

        let candidates = ButtonUtils.shared.getButtonBindings(for: .mouse, code: 3)

        XCTAssertEqual(
            Set(candidates.map(\.id)),
            Set([matchingBinding.id, matchingWithDifferentModifiersBinding.id])
        )
    }

    func testButtonCoreEventMask_includesFullMouseDownAndUpCoverage() {
        let core = ButtonCore.shared

        func contains(_ type: CGEventType) -> Bool {
            let typeMask = CGEventMask(1 << type.rawValue)
            return core.eventMask & typeMask != 0
        }

        XCTAssertTrue(contains(.leftMouseDown))
        XCTAssertTrue(contains(.leftMouseUp))
        XCTAssertTrue(contains(.rightMouseDown))
        XCTAssertTrue(contains(.rightMouseUp))
        XCTAssertTrue(contains(.otherMouseDown))
        XCTAssertTrue(contains(.otherMouseUp))
    }
}
