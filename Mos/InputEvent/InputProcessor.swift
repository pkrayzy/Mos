//
//  InputProcessor.swift
//  Mos
//  统一事件处理器 - 接收 InputEvent, 匹配 ButtonBinding, 执行动作
//  Created by Mos on 2026/3/16.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

// MARK: - InputResult
/// 事件处理结果
enum InputResult: Equatable {
    case consumed     // 事件已处理,不再传递
    case passthrough  // 事件未匹配,继续传递
}

// MARK: - InputProcessor
/// 统一事件处理器
/// 从 ButtonUtils 获取绑定配置, 匹配 InputEvent, 执行 ShortcutExecutor
/// 使用 activeBindings 表跟踪按下中的绑定, 确保 Up 事件正确配对
class InputProcessor {
    static let shared = InputProcessor()
    init() { NSLog("Module initialized: InputProcessor") }

    // MARK: - Active Bindings Table
    /// 跟踪当前按下中的 stateful 动作, 用于 Up 事件配对
    private var activeBindings: [TriggerKey: ResolvedAction] = [:]

    private struct TriggerKey: Hashable {
        let type: EventType
        let code: UInt16
    }

    /// 清空所有活跃绑定和虚拟修饰键状态 (ButtonCore disable 时调用, 防止状态残留)
    func clearActiveBindings() {
        for action in activeBindings.values where action.executionMode == .stateful {
            ShortcutExecutor.shared.execute(action: action, phase: .up)
        }
        activeBindings.removeAll()
        activeModifierFlags = 0
    }

    // MARK: - Virtual Modifier Flags
    /// 当前激活的虚拟修饰键 flags (从 activeBindings 中所有自定义修饰键绑定动态派生)
    /// ButtonCore 回调读取此值, 注入到 passthrough 的键盘事件中
    private(set) var activeModifierFlags: UInt64 = 0

    /// 从 activeBindings 表重新计算 activeModifierFlags
    private func recomputeActiveModifierFlags() {
        var flags: UInt64 = 0
        for action in activeBindings.values {
            guard case let .customKey(code, modifiers) = action,
                  KeyCode.modifierKeys.contains(code) else { continue }
            flags |= modifiers | KeyCode.getKeyMask(code).rawValue
        }
        activeModifierFlags = flags
    }

    /// 处理输入事件
    /// - Parameter event: 统一输入事件
    /// - Returns: .consumed 表示事件已处理, .passthrough 表示未匹配
    func process(_ event: InputEvent) -> InputResult {
        let key = TriggerKey(type: event.type, code: event.code)

        if event.phase == .up {
            // Up 事件: 按 (type, code) 查表, 忽略 modifiers (用户可能已松开修饰键)
            if let action = activeBindings.removeValue(forKey: key) {
                ShortcutExecutor.shared.execute(action: action, phase: .up)
                recomputeActiveModifierFlags()
                return .consumed
            }
            return .passthrough
        }

        // Down 事件: 完整匹配 (type + code + modifiers + deviceFilter)
        let bindings = ButtonUtils.shared.getButtonBindings()
        for binding in bindings where binding.isEnabled {
            guard binding.triggerEvent.matchesInput(event),
                  let action = ShortcutExecutor.shared.resolveAction(
                    named: binding.systemShortcutName,
                    binding: binding
                  ) else { continue }

            if action.executionMode == .trigger {
                ShortcutExecutor.shared.execute(action: action, phase: .down)
                return .consumed
            }

            if let existing = activeBindings.removeValue(forKey: key) {
                ShortcutExecutor.shared.execute(action: existing, phase: .up)
            }

            activeBindings[key] = action
            ShortcutExecutor.shared.execute(action: action, phase: .down)
            recomputeActiveModifierFlags()
            return .consumed
        }
        return .passthrough
    }
}
