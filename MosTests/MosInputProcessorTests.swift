import XCTest
@testable import Mos_Debug

final class MosInputProcessorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
    }

    override func tearDown() {
        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
        super.tearDown()
    }

    func testProcess_downEvent_consumedWhenBindingMatches() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let event = MosInputEvent(type: .mouse, code: 3, modifiers: CGEventFlags(rawValue: 0),
                                   phase: .down, source: .hidPlusPlus, device: nil)
        let result = MosInputProcessor.shared.process(event)
        XCTAssertEqual(result, .consumed)
    }

    func testProcess_upEvent_consumedViaActiveBindings() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = MosInputEvent(type: .mouse, code: 3, modifiers: CGEventFlags(rawValue: 0),
                                       phase: .down, source: .hidPlusPlus, device: nil)
        _ = MosInputProcessor.shared.process(downEvent)

        let upEvent = MosInputEvent(type: .mouse, code: 3, modifiers: CGEventFlags(rawValue: 0),
                                     phase: .up, source: .hidPlusPlus, device: nil)
        let result = MosInputProcessor.shared.process(upEvent)
        XCTAssertEqual(result, .consumed)
    }

    func testProcess_upEvent_passthroughWithoutPriorDown() {
        let event = MosInputEvent(type: .mouse, code: 99, modifiers: CGEventFlags(rawValue: 0),
                                   phase: .up, source: .hidPlusPlus, device: nil)
        let result = MosInputProcessor.shared.process(event)
        XCTAssertEqual(result, .passthrough)
    }

    func testProcess_upEvent_matchesDespiteModifierChange() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: UInt(CGEventFlags.maskCommand.rawValue),
                                     displayComponents: ["⌘", "🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = MosInputEvent(type: .mouse, code: 3, modifiers: .maskCommand,
                                       phase: .down, source: .hidPlusPlus, device: nil)
        _ = MosInputProcessor.shared.process(downEvent)

        // Up with ⌘ already released (modifiers = 0)
        let upEvent = MosInputEvent(type: .mouse, code: 3, modifiers: CGEventFlags(rawValue: 0),
                                     phase: .up, source: .hidPlusPlus, device: nil)
        let result = MosInputProcessor.shared.process(upEvent)
        XCTAssertEqual(result, .consumed)
    }
}
