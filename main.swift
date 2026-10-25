// button-keys — 手柄按键 → 键盘按键
// 绑定表覆盖全部 17 个物理按键；未绑定的写 nil，后续加需求只改表。
// 用法见同目录 README.md

import Foundation
import Cocoa
import GameController
import ApplicationServices

// MARK: - 键名表（键名 → 键码）。需要新键时在这里加一行

let keyCodes: [String: CGKeyCode] = [
    // 主键区
    "enter": 0x24, "return": 0x24, "keypadenter": 0x4C,
    "escape": 0x35, "tab": 0x30, "space": 0x31, "delete": 0x33,
    "up": 0x7E, "down": 0x7D, "left": 0x7B, "right": 0x7C,
    "home": 0x73, "end": 0x77, "pageup": 0x74, "pagedown": 0x79,
    // 修饰键
    "option": 0x3A, "leftoption": 0x3A, "rightoption": 0x3D,
    "command": 0x37, "leftcommand": 0x37, "rightcommand": 0x36,
    "shift": 0x38, "leftshift": 0x38, "rightshift": 0x3C,
    "control": 0x3B, "leftcontrol": 0x3B, "rightcontrol": 0x3E,
    "capslock": 0x39, "fn": 0x3F,
    // 字母
    "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E, "f": 0x03, "g": 0x05,
    "h": 0x04, "i": 0x22, "j": 0x26, "k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D,
    "o": 0x1F, "p": 0x23, "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11, "u": 0x20,
    "v": 0x09, "w": 0x0D, "x": 0x07, "y": 0x10, "z": 0x06,
    // 数字与符号
    "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17,
    "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19,
    "minus": 0x1B, "equal": 0x18, "leftbracket": 0x21, "rightbracket": 0x1E,
    "backslash": 0x2A, "semicolon": 0x29, "quote": 0x27, "comma": 0x2B,
    "period": 0x2F, "slash": 0x2C, "grave": 0x32,
    // 功能键
    "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60, "f6": 0x61,
    "f7": 0x62, "f8": 0x64, "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
]

// 修饰键按下期间要附加到后续事件的 flag
let modifierFlags: [String: CGEventFlags] = [
    "option": .maskAlternate, "leftoption": .maskAlternate, "rightoption": .maskAlternate,
    "command": .maskCommand, "leftcommand": .maskCommand, "rightcommand": .maskCommand,
    "shift": .maskShift, "leftshift": .maskShift, "rightshift": .maskShift,
    "control": .maskControl, "leftcontrol": .maskControl, "rightcontrol": .maskControl,
    "capslock": .maskAlphaShift, "fn": .maskSecondaryFn,
]

// MARK: - 绑定表（全部 17 个物理按键；值为键名，nil = 未绑定）

let defaultBindings: [String: String?] = [
    // ── 面键 ──
    "Button A": "enter",        // 已绑定：Enter
    "Button B": "delete",       // 已绑定：Delete（退格删除，0x33）
    "Button X": "option",       // 已绑定：左 Option
    "Button Y": "escape",       // 已绑定：Esc（0x35）

    // ── 肩键与扳机（扳机是模拟量，过 0.5 视为按下）──
    "Left Shoulder": "mouse:left",    // 左键（按住可拖动）
    "Right Shoulder": "mouse:right",  // 右键
    "Left Trigger": nil,
    "Right Trigger": nil,

    // ── 十字键 ──
    "Direction Pad Up": nil,
    "Direction Pad Down": nil,
    "Direction Pad Left": nil,
    "Direction Pad Right": nil,

    // ── 摇杆按下 ──
    "Left Thumbstick Button": nil,
    "Right Thumbstick Button": nil,

    // ── 功能键 ──
    "Button Menu": nil,
    "Button Options": nil,
    "Button Home": nil,
]
// 注意：摇杆位移派生的 "Left/Right Thumbstick Up/Down/Left/Right" 不属于物理键，
// 阈值低至 0.13，容易误触发，故意不放进绑定表。
//
// 实际生效的绑定来自同目录 bindings.json：改绑定不必重新编译，
// 避免重编译导致「辅助功能」授权失效。文件不存在时会按上表生成。

let defaultConfigJSON = """
{
  "Button A": "enter",
  "Button B": "delete",
  "Button X": "option",
  "Button Y": "escape",
  "Left Shoulder": "mouse:left",
  "Right Shoulder": "mouse:right",
  "Left Trigger": null,
  "Right Trigger": null,
  "Direction Pad Up": null,
  "Direction Pad Down": null,
  "Direction Pad Left": null,
  "Direction Pad Right": null,
  "Left Thumbstick Button": null,
  "Right Thumbstick Button": null,
  "Button Menu": null,
  "Button Options": null,
  "Button Home": null
}
"""

struct ConfigError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

var bindings: [String: String?] = defaultBindings
var configFileURL = URL(fileURLWithPath: "/dev/null")

func loadBindings() {
    configFileURL = URL(fileURLWithPath: CommandLine.arguments[0])
        .resolvingSymlinksInPath()
        .deletingLastPathComponent()
        .appendingPathComponent("bindings.json")

    if !FileManager.default.fileExists(atPath: configFileURL.path) {
        try? defaultConfigJSON.write(to: configFileURL, atomically: true, encoding: .utf8)
        log("已生成默认绑定文件：\(configFileURL.path)")
    }
    do {
        let data = try Data(contentsOf: configFileURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError(message: "顶层不是 JSON 对象")
        }
        var parsed: [String: String?] = [:]
        for (element, value) in object {
            if let keyName = value as? String {
                parsed[element] = keyName
            } else if value is NSNull {
                parsed[element] = nil
            } else {
                log("绑定文件：\(element) 的值既不是字符串也不是 null，已忽略")
            }
        }
        bindings = parsed
        log("绑定文件：\(configFileURL.path)（\(parsed.count) 项）")
    } catch {
        log("绑定文件读取失败（\(error)），改用内置表")
        bindings = defaultBindings
    }
}

// MARK: - 手感配置

var pointerFileURL = URL(fileURLWithPath: "/dev/null")

func loadPointerConfig() {
    pointerFileURL = URL(fileURLWithPath: CommandLine.arguments[0])
        .resolvingSymlinksInPath()
        .deletingLastPathComponent()
        .appendingPathComponent("pointer.json")

    if !FileManager.default.fileExists(atPath: pointerFileURL.path) {
        try? defaultPointerJSON.write(to: pointerFileURL, atomically: true, encoding: .utf8)
        log("已生成默认手感文件：\(pointerFileURL.path)")
    }

    var config = PointerConfig()
    do {
        let data = try Data(contentsOf: pointerFileURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError(message: "顶层不是 JSON 对象")
        }
        func number(_ key: String, _ fallback: Double) -> Double {
            (object[key] as? NSNumber)?.doubleValue ?? fallback
        }
        config.deadzone = min(max(number("deadzone", config.deadzone), 0), 0.9)
        config.exponent = min(max(number("exponent", config.exponent), 0.5), 5)
        config.maxSpeed = min(max(number("maxSpeed", config.maxSpeed), 50), 6000)
        config.scrollDeadzone = min(max(number("scrollDeadzone", config.scrollDeadzone), 0), 0.9)
        config.scrollExponent = min(max(number("scrollExponent", config.scrollExponent), 0.5), 5)
        config.maxScroll = min(max(number("maxScroll", config.maxScroll), 50), 6000)
        config.maxStep = min(max(number("maxStep", config.maxStep), 0.005), 0.2)
        pointer = config
        log("手感文件：\(pointerFileURL.path)")
    } catch {
        log("手感文件读取失败（\(error)），改用默认值")
        pointer = PointerConfig()
    }
}

// MARK: - 事件发送

struct Compiled {
    let code: CGKeyCode
    let flag: CGEventFlags
    let keyName: String
}

var compiled: [String: Compiled] = [:]
var mouseBindings: [String: CGMouseButton] = [:]
var currentFlags: CGEventFlags = []
var verbose = false

// MARK: - 指针与滚动参数（默认值；实际生效值来自同目录 pointer.json）

struct PointerConfig {
    var deadzone = 0.15              // 左摇杆死区，低于此值不动
    var exponent = 1.7               // 指针加速曲线，越大越"慢起步、后段快"
    var maxSpeed = 1400.0            // 摇杆推满时的指针速度（点/秒）
    var scrollDeadzone = 0.18        // 右摇杆死区
    var scrollExponent = 1.5         // 滚动加速曲线
    var maxScroll = 1200.0           // 摇杆推满时的滚动速度（像素/秒）
    var maxStep = 0.05               // 单帧最大步长，防止卡顿后指针瞬移
}

var pointer = PointerConfig()

let defaultPointerJSON = """
{
  "deadzone": 0.15,
  "exponent": 1.7,
  "maxSpeed": 1400,
  "scrollDeadzone": 0.18,
  "scrollExponent": 1.5,
  "maxScroll": 1200,
  "maxStep": 0.05
}
"""

func post(_ code: CGKeyCode, down: Bool) {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { return }
    event.flags = currentFlags
    event.post(tap: .cghidEventTap)
}

// MARK: - 鼠标事件

let eventSource = CGEventSource(stateID: .hidSystemState)
var leftButtonDown = false

/// 绑定表里 "mouse:left" / "mouse:right" / "mouse:middle" 表示鼠标动作而不是键盘键。
func mouseAction(for value: String) -> CGMouseButton? {
    switch value {
    case "mouse:left", "mouse:l": return .left
    case "mouse:right", "mouse:r": return .right
    case "mouse:middle", "mouse:center", "mouse:m": return .center
    default: return nil
    }
}

func currentPointer() -> CGPoint {
    CGEvent(source: nil)?.location ?? .zero
}

/// 所有活动显示器的并集（CG 全局坐标，原点在主屏左上角，y 向下）。
func activeDisplayBounds() -> CGRect {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
        return CGRect(x: 0, y: 0, width: 1920, height: 1080)
    }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
        return CGRect(x: 0, y: 0, width: 1920, height: 1080)
    }
    var rect = CGRect.null
    for id in ids { rect = rect.union(CGDisplayBounds(id)) }
    return rect.isEmpty ? CGRect(x: 0, y: 0, width: 1920, height: 1080) : rect
}

func postMouseButton(_ button: CGMouseButton, down: Bool) {
    let type: CGEventType
    switch button {
    case .left: type = down ? .leftMouseDown : .leftMouseUp
    case .right: type = down ? .rightMouseDown : .rightMouseUp
    default: type = down ? .otherMouseDown : .otherMouseUp
    }
    guard let event = CGEvent(mouseEventSource: eventSource,
                              mouseType: type,
                              mouseCursorPosition: currentPointer(),
                              mouseButton: button) else { return }
    event.setIntegerValueField(.mouseEventClickState, value: 1)
    event.post(tap: .cghidEventTap)
    if button == .left { leftButtonDown = down }
}

func movePointer(dx: Double, dy: Double) {
    let position = currentPointer()
    let bounds = activeDisplayBounds()
    let x = min(max(position.x + dx, bounds.minX), bounds.maxX - 1)
    let y = min(max(position.y + dy, bounds.minY), bounds.maxY - 1)
    // 按住左键时发拖拽事件，否则目标应用不会把移动当作拖动
    let type: CGEventType = leftButtonDown ? .leftMouseDragged : .mouseMoved
    guard let event = CGEvent(mouseEventSource: eventSource,
                              mouseType: type,
                              mouseCursorPosition: CGPoint(x: x, y: y),
                              mouseButton: .left) else { return }
    event.post(tap: .cghidEventTap)
}

func postScroll(pixelsX: Double, pixelsY: Double) {
    guard let event = CGEvent(scrollWheelEvent2Source: eventSource,
                              units: .pixel,
                              wheelCount: 2,
                              wheel1: Int32(pixelsY.rounded(.towardZero)),
                              wheel2: Int32((-pixelsX).rounded(.towardZero)),
                              wheel3: 0) else { return }
    event.post(tap: .cghidEventTap)
}

/// 死区压平后按 [0,1] 线性归一化的单轴取值。
func shapedAxis(_ axis: GCControllerAxisInput, deadzone: Double) -> Double {
    let raw = Double(axis.value)
    let magnitude = abs(raw)
    guard magnitude > deadzone else { return 0 }
    let t = (magnitude - deadzone) / (1 - deadzone)
    return raw < 0 ? -t : t
}

func log(_ message: String) {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    print("[\(f.string(from: Date()))] \(message)")
}

func buildTable() {
    compiled.removeAll()
    mouseBindings.removeAll()
    for (element, keyName) in bindings {
        guard let keyName else { continue }          // nil 保持未绑定
        if let button = mouseAction(for: keyName) {
            mouseBindings[element] = button
            continue
        }
        guard let code = keyCodes[keyName] else {
            log("配置错误：\(element) 的键名 \(keyName) 不存在，按未绑定处理")
            continue
        }
        compiled[element] = Compiled(code: code, flag: modifierFlags[keyName] ?? [], keyName: keyName)
    }
}

/// 当前生效的绑定摘要：元素 → 动作名（键盘键名或 mouse:*）。启动与重载日志共用，避免两处统计口径不一致。
func bindingLabels() -> [String: String] {
    let mouseLabels = mouseBindings.mapValues {
        $0 == .left ? "mouse:left" : ($0 == .right ? "mouse:right" : "mouse:middle")
    }
    return compiled.mapValues(\.keyName).merging(mouseLabels) { key, _ in key }
}

@discardableResult
func apply(_ name: String, pressed: Bool) -> Bool {
    if let button = mouseBindings[name] {
        let label = button == .left ? "左键" : (button == .right ? "右键" : "中键")
        postMouseButton(button, down: pressed)
        log("\(name) → 鼠标\(label)\(pressed ? "按下" : "松开")")
        return true
    }
    guard let action = compiled[name] else {
        if verbose { log("\(name) \(pressed ? "按下" : "松开")（未绑定）") }
        return false
    }
    if pressed {
        currentFlags.formUnion(action.flag)
        post(action.code, down: true)
        log("\(name) → \(action.keyName) 按下")
    } else {
        post(action.code, down: false)
        currentFlags.remove(action.flag)
        log("\(name) → \(action.keyName) 松开")
    }
    return true
}

// MARK: - 主逻辑

final class Bridge: NSObject, NSApplicationDelegate {
    var controller: GCController?
    var previous: [String: Bool] = [:]
    var held: Set<String> = []
    var primed = false
    var signalSources: [DispatchSourceSignal] = []
    var lastTick = CFAbsoluteTimeGetCurrent()
    var scrollRemainderX = 0.0
    var scrollRemainderY = 0.0
    var leftStickActive = false
    var rightStickActive = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setvbuf(stdout, nil, _IOLBF, 0)
        GCController.shouldMonitorBackgroundEvents = true

        if !AXIsProcessTrusted() {
            log("缺少「辅助功能」权限：系统设置 → 隐私与安全性 → 辅助功能，勾选运行本程序的终端")
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }

        loadBindings()
        loadPointerConfig()
        buildTable()
        // 清掉上次异常退出可能残留的按键状态，避免修饰键卡住
        for action in compiled.values { post(action.code, down: false) }

        installSignalHandlers()

        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            self?.attach(note.object as? GCController)
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            guard let self, let controller = note.object as? GCController, controller === self.controller else { return }
            log("手柄断开")
            self.releaseAll()
            self.controller = nil
        }

        attach(GCController.controllers().first)
        if controller == nil { log("等待手柄连接…") }

        Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.tick()
        }

        let labels = bindingLabels()
        let bound = labels.keys.sorted().map { "\($0)→\(labels[$0]!)" }
        log("运行中 \(bindings.count) 个物理键，已绑定 \(labels.count) 个：" + bound.joined(separator: "、"))
        let unbound = bindings.keys.filter { labels[$0] == nil }.sorted()
        log("未绑定：" + unbound.joined(separator: "、"))
        log("摇杆：左=指针移动（死区 \(pointer.deadzone)，峰值 \(Int(pointer.maxSpeed)) pt/s），右=滚动（死区 \(pointer.scrollDeadzone)，峰值 \(Int(pointer.maxScroll)) px/s）")
    }

    func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.releaseAll()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
        // SIGHUP：重新读 bindings.json，不必重启进程
        signal(SIGHUP, SIG_IGN)
        let reload = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main)
        reload.setEventHandler { [weak self] in
            self?.releaseAll()
            loadBindings()
            loadPointerConfig()
            buildTable()
            let labels = bindingLabels()
            log("已按 SIGHUP 重载绑定，当前 \(labels.count) 个："
                + labels.keys.sorted().map { "\($0)→\(labels[$0]!)" }.joined(separator: "、"))
            log("手感：死区 \(pointer.deadzone)/\(pointer.scrollDeadzone)，峰值 \(Int(pointer.maxSpeed)) pt/s / \(Int(pointer.maxScroll)) px/s")
        }
        reload.resume()
        signalSources.append(reload)
    }

    func attach(_ controller: GCController?) {
        guard let controller else { return }
        self.controller = controller
        previous.removeAll()
        primed = false
        log("手柄：\(controller.vendorName ?? "-") | \(controller.productCategory)")
    }

    func tick() {
        guard let controller else { return }
        let now = CFAbsoluteTimeGetCurrent()
        var dt = now - lastTick
        lastTick = now
        if dt <= 0 || dt > pointer.maxStep { dt = pointer.maxStep }
        updateSticks(dt: dt)
        for (name, element) in controller.physicalInputProfile.elements {
            guard let button = element as? GCControllerButtonInput else { continue }
            let pressed = Double(button.value) >= 0.5
            if !primed { previous[name] = pressed; continue }
            guard previous[name] != pressed else { continue }
            previous[name] = pressed
            guard bindings[name] != nil else { continue }
            if pressed { held.insert(name) } else { held.remove(name) }
            apply(name, pressed: pressed)
        }
        primed = true
    }

    /// 左摇杆 → 指针移动；右摇杆 → 滚动。每帧按推杆幅度给速度，不是固定步长。
    func updateSticks(dt: Double) {
        guard let gamepad = controller?.extendedGamepad else { return }

        let lx = shapedAxis(gamepad.leftThumbstick.xAxis, deadzone: pointer.deadzone)
        let ly = shapedAxis(gamepad.leftThumbstick.yAxis, deadzone: pointer.deadzone)
        let leftMagnitude = min(1.0, (lx * lx + ly * ly).squareRoot())
        if leftMagnitude > 0 {
            if !leftStickActive {
                leftStickActive = true
                log("左摇杆推动（指针）")
            }
            let speed = pointer.maxSpeed * pow(leftMagnitude, pointer.exponent)
            // 手柄 y 向上为正，CG 屏幕坐标 y 向下为正
            movePointer(dx: lx / leftMagnitude * speed * dt,
                        dy: -ly / leftMagnitude * speed * dt)
        } else if leftStickActive {
            leftStickActive = false
            log("左摇杆回中（指针）")
        }

        let rx = shapedAxis(gamepad.rightThumbstick.xAxis, deadzone: pointer.scrollDeadzone)
        let ry = shapedAxis(gamepad.rightThumbstick.yAxis, deadzone: pointer.scrollDeadzone)
        let rightMagnitude = min(1.0, (rx * rx + ry * ry).squareRoot())
        if rightMagnitude > 0 {
            if !rightStickActive {
                rightStickActive = true
                log("右摇杆推动（滚动）")
            }
            let speed = pointer.maxScroll * pow(rightMagnitude, pointer.scrollExponent)
            scrollRemainderX += rx / rightMagnitude * speed * dt
            scrollRemainderY += ry / rightMagnitude * speed * dt
            let emitX = scrollRemainderX.rounded(.towardZero)
            let emitY = scrollRemainderY.rounded(.towardZero)
            if emitX != 0 || emitY != 0 {
                scrollRemainderX -= emitX
                scrollRemainderY -= emitY
                postScroll(pixelsX: emitX, pixelsY: emitY)
            }
        } else {
            scrollRemainderX = 0
            scrollRemainderY = 0
            if rightStickActive {
                rightStickActive = false
                log("右摇杆回中（滚动）")
            }
        }
    }

    func releaseAll() {
        if leftButtonDown { postMouseButton(.left, down: false) }
        for name in held { apply(name, pressed: false) }
        held.removeAll()
        currentFlags = []
    }
}

// MARK: - 入口

let arguments = CommandLine.arguments
setvbuf(stdout, nil, _IOLBF, 0)   // 命令行模式下日志也要立刻可见

let buildVersion = "0.2.0"
if arguments.contains("--version") {
    print("button-keys \(buildVersion)")
    exit(0)
}

if arguments.contains("--selftest") {
    // 走与真实按键相同的 apply() 路径：先按住 X(Option)，再敲 A(Enter)，验证修饰键确实生效
    verbose = true
    loadBindings()
    buildTable()
    log("自检：Option 按下 → Enter 按下/松开 → Option 松开")
    apply("Button X", pressed: true)
    usleep(150_000)
    apply("Button A", pressed: true)
    usleep(60_000)
    apply("Button A", pressed: false)
    usleep(150_000)
    apply("Button X", pressed: false)
    log("自检结束")
    exit(0)
}

if let index = arguments.firstIndex(of: "--tap"), index + 1 < arguments.count {
    // 只触发一个绑定：--tap "Button B"，用于验证权限与键码
    verbose = true
    loadBindings()
    buildTable()
    let name = arguments[index + 1]
    if apply(name, pressed: true) {
        usleep(60_000)
        apply(name, pressed: false)
    } else {
        log("\(name) 未绑定或元素名不存在；已绑定：\(compiled.keys.sorted().joined(separator: "、"))")
    }
    exit(0)
}

verbose = arguments.contains("--verbose")
let app = NSApplication.shared
let bridge = Bridge()
app.delegate = bridge
app.setActivationPolicy(.accessory)
app.run()
