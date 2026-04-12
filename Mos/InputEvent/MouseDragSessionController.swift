//
//  MouseDragSessionController.swift
//  Mos
//  管理 synthetic 鼠标拖拽会话, 提供目标优先级与生命周期控制
//

import Cocoa

enum SyntheticMouseTarget: Equatable {
    case left
    case right
    case other(buttonNumber: Int64)
}

enum PhysicalMouseTarget: Equatable {
    case none
    case left
    case right
    case other(buttonNumber: Int64)
}

final class MouseDragSessionController {
    static let shared = MouseDragSessionController()

    private static let motionEventMask: CGEventMask =
        (CGEventMask(1 << CGEventType.mouseMoved.rawValue)) |
        (CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)) |
        (CGEventMask(1 << CGEventType.rightMouseDragged.rawValue)) |
        (CGEventMask(1 << CGEventType.otherMouseDragged.rawValue))

    private static let motionEventCallback: CGEventTapCallBack = { _, type, event, _ in
        MouseDragSessionController.shared.handleMotionTapEvent(type: type, event: event)
    }

    private let startMotionTapOverride: (() -> Void)?
    private let stopMotionTapOverride: (() -> Void)?
    private(set) var isMotionTapRunning = false
    private var activeSessions: [UUID: SyntheticMouseTarget] = [:]
    private var dominantTarget: SyntheticMouseTarget?
    private var motionInterceptor: Interceptor?
    private var testStartMotionTap: (() -> Void)?
    private var testStopMotionTap: (() -> Void)?
    var activeSessionCount: Int { activeSessions.count }

    init(
        startMotionTap: (() -> Void)? = nil,
        stopMotionTap: (() -> Void)? = nil
    ) {
        self.startMotionTapOverride = startMotionTap
        self.stopMotionTapOverride = stopMotionTap
    }

    static func dominantSyntheticTarget(from targets: [SyntheticMouseTarget]) -> SyntheticMouseTarget? {
        guard !targets.isEmpty else { return nil }
        return targets.min(by: { lhs, rhs in
            syntheticPriority(of: lhs) < syntheticPriority(of: rhs)
        })
    }

    static func effectiveTarget(
        physical: PhysicalMouseTarget,
        synthetic: SyntheticMouseTarget?
    ) -> SyntheticMouseTarget? {
        guard let synthetic else {
            switch physical {
            case .none:
                return nil
            case .left:
                return .left
            case .right:
                return .right
            case .other(let buttonNumber):
                return .other(buttonNumber: buttonNumber)
            }
        }

        let physicalAsSynthetic: SyntheticMouseTarget? = {
            switch physical {
            case .none:
                return nil
            case .left:
                return .left
            case .right:
                return .right
            case .other(let buttonNumber):
                return .other(buttonNumber: buttonNumber)
            }
        }()

        guard let physicalAsSynthetic else { return synthetic }
        return syntheticPriority(of: physicalAsSynthetic) <= syntheticPriority(of: synthetic) ? physicalAsSynthetic : synthetic
    }

    @discardableResult
    func beginSession(target: SyntheticMouseTarget) -> UUID {
        let sessionID = UUID()
        activeSessions[sessionID] = target
        recomputeDominantTarget()
        if !isMotionTapRunning {
            startMotionTap()
        }
        return sessionID
    }

    func endSession(id: UUID) {
        guard activeSessions.removeValue(forKey: id) != nil else { return }
        recomputeDominantTarget()
        guard activeSessions.isEmpty else { return }
        stopMotionTap()
    }

    func clearAllSessions() {
        guard !activeSessions.isEmpty || isMotionTapRunning else { return }
        activeSessions.removeAll()
        dominantTarget = nil
        stopMotionTap()
    }

    func rewriteMouseInteractionEvent(_ event: CGEvent) {
        guard let synthetic = dominantTarget else { return }
        let physical = Self.physicalTarget(from: event)
        guard let effective = Self.effectiveTarget(physical: physical, synthetic: synthetic) else { return }
        rewrite(event, as: effective)
    }

    func setTestingMotionTapHooks(start: (() -> Void)? = {}, stop: (() -> Void)? = {}) {
        testStartMotionTap = start
        testStopMotionTap = stop
    }

    func clearTestingMotionTapHooks() {
        testStartMotionTap = nil
        testStopMotionTap = nil
    }

    private static func syntheticPriority(of target: SyntheticMouseTarget) -> (Int, Int64) {
        switch target {
        case .left:
            return (0, 0)
        case .right:
            return (1, 0)
        case .other(let buttonNumber):
            return (2, buttonNumber)
        }
    }

    private static func physicalTarget(from event: CGEvent) -> PhysicalMouseTarget {
        switch event.type {
        case .leftMouseDragged:
            return .left
        case .rightMouseDragged:
            return .right
        case .otherMouseDragged:
            return .other(buttonNumber: event.getIntegerValueField(.mouseEventButtonNumber))
        case .mouseMoved:
            return .none
        default:
            return .none
        }
    }

    private func recomputeDominantTarget() {
        dominantTarget = Self.dominantSyntheticTarget(from: Array(activeSessions.values))
    }

    private func rewrite(_ event: CGEvent, as target: SyntheticMouseTarget) {
        switch target {
        case .left:
            event.type = .leftMouseDragged
            event.setIntegerValueField(.mouseEventButtonNumber, value: 0)
        case .right:
            event.type = .rightMouseDragged
            event.setIntegerValueField(.mouseEventButtonNumber, value: 1)
        case .other(let buttonNumber):
            event.type = .otherMouseDragged
            event.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
        }
    }

    private func startMotionTap() {
        if let startMotionTapOverride {
            startMotionTapOverride()
            isMotionTapRunning = true
            return
        }

        if let testStartMotionTap {
            testStartMotionTap()
            isMotionTapRunning = true
            return
        }

        if let motionInterceptor {
            do {
                try motionInterceptor.start()
                isMotionTapRunning = true
            } catch {
                NSLog("MouseDragSessionController: Failed to start motion interceptor: \(error)")
                isMotionTapRunning = false
            }
            return
        }

        do {
            let interceptor = try Interceptor(
                event: Self.motionEventMask,
                handleBy: Self.motionEventCallback,
                listenOn: .cgAnnotatedSessionEventTap,
                placeAt: .tailAppendEventTap,
                for: .defaultTap
            )
            interceptor.onRestart = {
                InputProcessor.shared.clearActiveBindings()
            }
            interceptor.shouldRestart = { [weak self] in
                guard let self else { return false }
                return self.activeSessionCount > 0
            }
            motionInterceptor = interceptor
            isMotionTapRunning = true
        } catch {
            NSLog("MouseDragSessionController: Failed to create motion interceptor: \(error)")
            isMotionTapRunning = false
        }
    }

    private func stopMotionTap() {
        if let stopMotionTapOverride {
            stopMotionTapOverride()
            isMotionTapRunning = false
            return
        }

        if let testStopMotionTap {
            testStopMotionTap()
            isMotionTapRunning = false
            return
        }

        motionInterceptor?.pause()
        isMotionTapRunning = false
    }

    private func handleMotionTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            InputProcessor.shared.clearActiveBindings()
            return Unmanaged.passUnretained(event)
        }

        rewriteMouseInteractionEvent(event)
        return Unmanaged.passUnretained(event)
    }
}
