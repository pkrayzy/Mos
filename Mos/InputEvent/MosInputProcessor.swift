//
//  MosInputProcessor.swift
//  Mos
//  统一事件处理器 - 接收 MosInputEvent, 匹配 ButtonBinding, 执行动作
//  Created by Mos on 2026/3/16.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

// MARK: - MosInputResult
/// 事件处理结果
enum MosInputResult: Equatable {
    case consumed     // 事件已处理,不再传递
    case passthrough  // 事件未匹配,继续传递
}

// MARK: - MosInputProcessor
/// 统一事件处理器
/// 从 ButtonUtils 获取绑定配置, 匹配 MosInputEvent, 执行 ShortcutExecutor
/// 使用 activeBindings 表跟踪按下中的绑定, 确保 Up 事件正确配对
class MosInputProcessor {
    static let shared = MosInputProcessor()
    init() { NSLog("Module initialized: MosInputProcessor") }

    // MARK: - Active Bindings Table
    /// 跟踪当前按下的绑定, 用于 Up 事件配对
    /// Key: (EventType, keyCode)  Value: 匹配到的 ButtonBinding
    private var activeBindings: [TriggerKey: ButtonBinding] = [:]

    private struct TriggerKey: Hashable {
        let type: EventType
        let code: UInt16
    }

    /// 处理输入事件
    /// - Parameter event: 统一输入事件
    /// - Returns: .consumed 表示事件已处理, .passthrough 表示未匹配
    func process(_ event: MosInputEvent) -> MosInputResult {
        let key = TriggerKey(type: event.type, code: event.code)

        if event.phase == .up {
            // Up 事件: 按 (type, code) 查表, 忽略 modifiers (用户可能已松开修饰键)
            if let binding = activeBindings.removeValue(forKey: key) {
                ShortcutExecutor.shared.execute(named: binding.systemShortcutName, phase: .up, binding: binding)
                return .consumed
            }
            return .passthrough
        }

        // Down 事件: 完整匹配 (type + code + modifiers + deviceFilter)
        let bindings = ButtonUtils.shared.getButtonBindings()
        for binding in bindings where binding.isEnabled {
            if binding.triggerEvent.matchesMosInput(event) {
                activeBindings[key] = binding
                ShortcutExecutor.shared.execute(named: binding.systemShortcutName, phase: .down, binding: binding)
                return .consumed
            }
        }
        return .passthrough
    }
}
