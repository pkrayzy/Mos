import XCTest
@testable import Mos_Debug

final class ButtonUtilsCacheTests: XCTestCase {

    func testInvalidateCache_causesFreshLoad() {
        ButtonUtils.shared.invalidateCache()
        let bindings = ButtonUtils.shared.getButtonBindings()
        XCTAssertNotNil(bindings)
    }

    func testGetButtonBindings_preparesCustomCache() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let loaded = ButtonUtils.shared.getButtonBindings()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].cachedCustomCode, 56)
        XCTAssertEqual(loaded[0].cachedCustomModifiers, 0)

        // Cleanup
        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
    }
}
