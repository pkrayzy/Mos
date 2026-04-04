//
//  ButtonCore.swift
//  Mos
//  鼠标按钮事件截取与处理核心类
//  Created by Claude on 2025/8/10.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class ButtonCore {
    
    // 单例
    static let shared = ButtonCore()
    init() { NSLog("Module initialized: ButtonCore") }
    
    // 执行状态
    var isActive = false
    
    // 拦截层
    var eventInterceptor: Interceptor?

    // 组合的按钮事件掩码
    let leftDown = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
    let rightDown = CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
    let otherDown = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
    let keyDown = CGEventMask(1 << CGEventType.keyDown.rawValue)
    let flagsChanged = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
    let otherUp = CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
    let keyUp = CGEventMask(1 << CGEventType.keyUp.rawValue)
    var eventMask: CGEventMask {
        return leftDown | rightDown | otherDown | otherUp | keyDown | keyUp
    }

    // MARK: - 按钮事件处理
    let buttonEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        // 跳过 Mos 合成事件, 避免 executeCustom 发出的事件被重复处理
        if event.getIntegerValueField(.eventSourceUserData) == MosEventMarker.syntheticCustom {
            return Unmanaged.passUnretained(event)
        }

        // 使用原始 flags 匹配绑定 (不注入虚拟修饰键, 保证匹配准确)
        let mosEvent = MosInputEvent(fromCGEvent: event)
        let result = MosInputProcessor.shared.process(mosEvent)
        switch result {
        case .consumed:
            return nil
        case .passthrough:
            // 注入虚拟修饰键 flags 到 passthrough 的键盘事件
            // 使长按鼠标侧键(绑定到修饰键) + 键盘按键 = 修饰键+按键
            let activeFlags = MosInputProcessor.shared.activeModifierFlags
            if activeFlags != 0 && (type == .keyDown || type == .keyUp) {
                event.flags = CGEventFlags(rawValue: event.flags.rawValue | activeFlags)
            }
            return Unmanaged.passUnretained(event)
        }
    }
    
    // MARK: - 启用和禁用
    
    // 启用按钮监控
    func enable() {
        if !isActive {
            NSLog("ButtonCore enabled")
            do {
                eventInterceptor = try Interceptor(
                    event: eventMask,
                    handleBy: buttonEventCallBack,
                    listenOn: .cgAnnotatedSessionEventTap,
                    placeAt: .tailAppendEventTap,
                    for: .defaultTap
                )
                isActive = true
            } catch {
                NSLog("ButtonCore: Failed to create interceptor: \(error)")
            }
        }
    }
    
    // 禁用按钮监控
    func disable() {
        if isActive {
            NSLog("ButtonCore disabled")
            eventInterceptor?.stop()
            eventInterceptor = nil
            MosInputProcessor.shared.clearActiveBindings()
            isActive = false
        }
    }
    
    // 切换状态
    func toggle() {
        isActive ? disable() : enable()
    }
}
