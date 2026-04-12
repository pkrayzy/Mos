import XCTest
@testable import Mos_Debug

final class MouseDragSessionControllerTests: XCTestCase {

    func testSyntheticTargetPriority_leftBeatsRightAndOther() {
        XCTAssertEqual(
            MouseDragSessionController.dominantSyntheticTarget(from: [
                .other(buttonNumber: 4),
                .right,
                .left,
            ]),
            .left
        )
        XCTAssertEqual(
            MouseDragSessionController.dominantSyntheticTarget(from: [
                .other(buttonNumber: 4),
                .other(buttonNumber: 3),
            ]),
            .other(buttonNumber: 3)
        )
    }

    func testEffectiveTarget_prefersPhysicalLeftOverSyntheticRight() {
        XCTAssertEqual(
            MouseDragSessionController.effectiveTarget(
                physical: .left,
                synthetic: .right
            ),
            .left
        )
    }

    func testEffectiveTarget_upgradesMouseMovedToSyntheticLeftDragged() {
        XCTAssertEqual(
            MouseDragSessionController.effectiveTarget(
                physical: .none,
                synthetic: .left
            ),
            .left
        )
    }

    func testSessionLifecycle_startsOnFirstMouseSession_andStopsOnLast() {
        var startCount = 0
        var stopCount = 0
        let controller = MouseDragSessionController(
            startMotionTap: { startCount += 1 },
            stopMotionTap: { stopCount += 1 }
        )

        XCTAssertFalse(controller.isMotionTapRunning)

        let leftSessionID = controller.beginSession(target: .left)
        XCTAssertTrue(controller.isMotionTapRunning)
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(stopCount, 0)

        let rightSessionID = controller.beginSession(target: .right)
        XCTAssertTrue(controller.isMotionTapRunning)
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(stopCount, 0)

        controller.endSession(id: leftSessionID)
        XCTAssertTrue(controller.isMotionTapRunning)
        XCTAssertEqual(stopCount, 0)

        controller.endSession(id: rightSessionID)
        XCTAssertFalse(controller.isMotionTapRunning)
        XCTAssertEqual(stopCount, 1)
    }

    func testRewriteMouseInteractionEvent_withSyntheticLeftConvertsMouseMovedToLeftDragged() {
        let controller = MouseDragSessionController(startMotionTap: {}, stopMotionTap: {})
        _ = controller.beginSession(target: .left)

        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: 120, y: 60),
            mouseButton: .left
        )!

        controller.rewriteMouseInteractionEvent(event)

        XCTAssertEqual(event.type, .leftMouseDragged)
        XCTAssertEqual(event.getIntegerValueField(.mouseEventButtonNumber), 0)
    }

    func testRewriteMouseInteractionEvent_withSyntheticOtherSetsOtherDraggedAndButtonNumber() {
        let controller = MouseDragSessionController(startMotionTap: {}, stopMotionTap: {})
        _ = controller.beginSession(target: .other(buttonNumber: 4))

        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: 20, y: 10),
            mouseButton: .left
        )!

        controller.rewriteMouseInteractionEvent(event)

        XCTAssertEqual(event.type, .otherMouseDragged)
        XCTAssertEqual(event.getIntegerValueField(.mouseEventButtonNumber), 4)
    }

    func testRewriteMouseInteractionEvent_prefersHigherPrioritySyntheticLeftOverPhysicalRight() {
        let controller = MouseDragSessionController(startMotionTap: {}, stopMotionTap: {})
        _ = controller.beginSession(target: .left)

        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseDragged,
            mouseCursorPosition: CGPoint(x: 55, y: 42),
            mouseButton: .right
        )!
        event.setIntegerValueField(.mouseEventButtonNumber, value: 1)

        controller.rewriteMouseInteractionEvent(event)

        XCTAssertEqual(event.type, .leftMouseDragged)
        XCTAssertEqual(event.getIntegerValueField(.mouseEventButtonNumber), 0)
    }
}
