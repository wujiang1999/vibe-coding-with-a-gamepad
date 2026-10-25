// flags-probe — 复现「同一修饰键连按第二次无效」的合成事件实验
// 用法：
//   flags-probe listen <日志路径> <秒数>   打开窗口收键，记录 flagsChanged/keyDown/keyUp
//   flags-probe post buggy|fixed          按 button-keys 的 post() 逻辑发 option 按下/松开两轮
// 只发 Option，不注入字符，风险最低。

import Cocoa
import ApplicationServices

let args = CommandLine.arguments

func stamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f.string(from: Date())
}

// MARK: - 收键端

final class ProbeView: NSView {
    let logURL: URL
    init(frame: NSRect, logURL: URL) {
        self.logURL = logURL
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    var acceptsFirstResponderKey = true
    override var acceptsFirstResponder: Bool { true }

    func record(_ text: String) {
        let line = "[\(stamp())] \(text)\n"
        print(line, terminator: "")
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        }
    }

    override func flagsChanged(with event: NSEvent) {
        record("flagsChanged key=\(event.keyCode) option=\(event.modifierFlags.contains(.option)) raw=\(event.modifierFlags.rawValue)")
    }
    override func keyDown(with event: NSEvent) {
        record("keyDown key=\(event.keyCode) option=\(event.modifierFlags.contains(.option))")
    }
    override func keyUp(with event: NSEvent) {
        record("keyUp key=\(event.keyCode) option=\(event.modifierFlags.contains(.option))")
    }
}

final class ListenerDelegate: NSObject, NSApplicationDelegate {
    let logURL: URL
    let seconds: Double
    let selftestMode: String?
    let tapBinary: String?
    var window: NSWindow?
    var view: ProbeView?

    init(logURL: URL, seconds: Double, selftestMode: String? = nil, tapBinary: String? = nil) {
        self.logURL = logURL
        self.seconds = seconds
        self.selftestMode = selftestMode
        self.tapBinary = tapBinary
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 520, height: 260),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "flags-probe"
        let v = ProbeView(frame: w.contentLayoutRect, logURL: logURL)
        w.contentView = v
        window = w
        view = v
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(v)
        // 无 bundle 的 CLI 进程首次 activate 常常不生效：多试几次并记录状态
        for delay in [0.0, 0.3, 0.8, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NSApp.activate(ignoringOtherApps: true)
                NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
                w.makeKeyAndOrderFront(nil)
                w.makeFirstResponder(v)
                v.record("activate+\(delay)s window=key:\(w.isKeyWindow) app=active:\(NSApp.isActive)")
                if delay == 1.5, let mode = self.selftestMode, w.isKeyWindow, NSApp.isActive {
                    v.record("selftest begin mode=\(mode)")
                    DispatchQueue.global().async {
                        runPoster(mode)
                        DispatchQueue.main.async { v.record("selftest posted") }
                    }
                }
                if delay == 1.5, let bin = self.tapBinary, w.isKeyWindow, NSApp.isActive {
                    v.record("tap begin bin=\(bin)")
                    DispatchQueue.global().async {
                        // 走真实二进制的 apply() 路径：X、X、A、X
                        let childLog = "/tmp/fp-tap-child.log"
                        FileManager.default.createFile(atPath: childLog, contents: nil)
                        for name in ["Button X", "Button X", "Button A", "Button X"] {
                            let p = Process()
                            p.executableURL = URL(fileURLWithPath: bin)
                            p.arguments = ["--tap", name]
                            if let h = FileHandle(forWritingAtPath: childLog) {
                                h.seekToEndOfFile()
                                p.standardOutput = h
                                p.standardError = h
                            }
                            try? p.run()
                            p.waitUntilExit()
                            usleep(300_000)
                        }
                        DispatchQueue.main.async { v.record("tap done") }
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            v.record("done")
            NSApp.terminate(nil)
        }
    }
}

// MARK: - 发键端（与 main.swift 的 post() 完全同构）

var currentFlags: CGEventFlags = []

func post(_ code: CGKeyCode, down: Bool) {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { return }
    event.flags = currentFlags
    event.post(tap: .cghidEventTap)
}

let optionCode: CGKeyCode = 0x3A

func roundBuggy() {
    // 现状：按下时登记 flag，松开时先把事件发出去（flag 还在）再清 flag
    currentFlags.formUnion(.maskAlternate)
    post(optionCode, down: true)
    usleep(120_000)
    post(optionCode, down: false)
    currentFlags.remove(.maskAlternate)
    usleep(250_000)
}

func roundFixed() {
    // 候选修复：松开前先摘掉 flag，keyUp 的 flags 不再包含自身
    currentFlags.formUnion(.maskAlternate)
    post(optionCode, down: true)
    usleep(120_000)
    currentFlags.remove(.maskAlternate)
    post(optionCode, down: false)
    usleep(250_000)
}

func roundEnter() {
    // 非修饰键：flags 为当前修饰键集合（此处为空）
    post(0x24, down: true)
    usleep(80_000)
    post(0x24, down: false)
    usleep(250_000)
}

func roundCompose() {
    // 「按住 X 再按 A」：Enter 事件必须带 Option 修饰，X 松开后修饰消失
    currentFlags.formUnion(.maskAlternate)
    post(optionCode, down: true)
    usleep(150_000)
    post(0x24, down: true)
    usleep(80_000)
    post(0x24, down: false)
    usleep(150_000)
    currentFlags.remove(.maskAlternate)
    post(optionCode, down: false)
    usleep(250_000)
}

func runPoster(_ mode: String) {
    print("[\(stamp())] post mode=\(mode)")
    if mode == "compose" {
        roundCompose()
        print("[\(stamp())] post done")
        return
    }
    let round = mode == "fixed" ? roundFixed : roundBuggy
    round()
    round()
    roundEnter()     // 中间按一个普通键，模拟用户「按别的键」
    round()
    print("[\(stamp())] post done")
}

// MARK: - 入口

if args.count >= 4, args[1] == "listen" {
    let logURL = URL(fileURLWithPath: args[2])
    let seconds = Double(args[3]) ?? 12
    let app = NSApplication.shared
    let delegate = ListenerDelegate(logURL: logURL, seconds: seconds)
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
} else if args.count >= 4, args[1] == "selftest" {
    // 同一进程既收键又发键：窗口拿到焦点后按指定模式注入，避免后台子进程被回收
    let mode = args[2]
    let logURL = URL(fileURLWithPath: args[3])
    let app = NSApplication.shared
    let delegate = ListenerDelegate(logURL: logURL, seconds: 9, selftestMode: mode)
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
} else if args.count >= 4, args[1] == "tap" {
    // 用真实 button-keys 二进制的 --tap 发键，验证它自己的 post() 路径
    let bin = args[2]
    let logURL = URL(fileURLWithPath: args[3])
    let app = NSApplication.shared
    let delegate = ListenerDelegate(logURL: logURL, seconds: 12, tapBinary: bin)
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
} else if args.count >= 3, args[1] == "post" {
    runPoster(args[2])
} else {
    FileHandle.standardError.write("usage: flags-probe listen <log> <seconds> | post buggy|fixed\n".data(using: .utf8)!)
    exit(2)
}
