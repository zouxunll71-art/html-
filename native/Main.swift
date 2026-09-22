import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    var window: NSWindow!
    var web: WKWebView!
    var process: Process?
    var didStart = false
    var nativeOnly = false
    let base = URL(string: "http://127.0.0.1:18777")!
    var config: [String:String] = [:]
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "client", withExtension: "json"), let data = try? Data(contentsOf: url), let value = try? JSONSerialization.jsonObject(with: data) as? [String:String] { config = value }
        nativeOnly = FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/HTMLCodexNative.app").path)
        if nativeOnly { connect(attempt: 0); return }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1500, height: 950)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: min(1500, screen.width - 40), height: min(920, screen.height - 40)), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "HTML Native Studio"
        window.minSize = NSSize(width: 1000, height: 700)
        window.setFrameAutosaveName("HTMLCodexWorkbench")
        window.isReleasedWhenClosed = false
        window.backgroundColor = .white
        window.center()
        let webConfig = WKWebViewConfiguration()
        webConfig.websiteDataStore = .default()
        webConfig.userContentController.add(self, name: "native")
        web = WKWebView(frame: .zero, configuration: webConfig)
        web.navigationDelegate = self; web.uiDelegate = self
        web.autoresizingMask = [.width, .height]
        window.contentView = web
        web.loadHTMLString("<html><body style='font:15px -apple-system;color:#658095;display:grid;place-items:center;height:90vh'><div>正在打开原生工作台…<p style='font-size:12px;color:#9aa7b2'>连接 Codex 与本机预览服务</p></div></body></html>", baseURL: nil)
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); mainMenu.addItem(appItem); let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于原生工作台", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator()); appMenu.addItem(withTitle: "隐藏原生工作台", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出原生工作台", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); editItem.title = "编辑"; mainMenu.addItem(editItem); let editMenu = NSMenu(title: "编辑"); editItem.submenu = editMenu
        for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] { editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key) }
        let viewItem = NSMenuItem(); viewItem.title = "显示"; mainMenu.addItem(viewItem); let viewMenu = NSMenu(title: "显示"); viewItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "重新加载", action: #selector(reload), keyEquivalent: "r")
        NSApp.mainMenu = mainMenu
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        connect(attempt: 0)
    }
    @objc func about() { let a = NSAlert(); a.messageText = "HTML Native Studio"; a.informativeText = "版本 1.0.0\n你的原生工作台与 Codex App Server 的独立客户端。"; a.runModal() }
    @objc func reload() { web.load(URLRequest(url: base)) }
    func connect(attempt: Int) {
        var request = URLRequest(url: base.appendingPathComponent("health")); request.timeoutInterval = 2
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String:Any], json["app"] as? String == "html-native-codex-client" {
                    self.didStart = true
                    if json["ready"] as? Bool == true {
                        if self.nativeOnly {
                            let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/HTMLCodexNative.app")
                            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, error in DispatchQueue.main.async { if error == nil { NSApp.terminate(nil) } } }
                        } else { self.web.load(URLRequest(url: self.base)) }
                        return
                    }
                }
                if !self.didStart { self.didStart = true; self.startServer() }
                if attempt < 180 { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.connect(attempt: attempt + 1) } }
                else { let alert = NSAlert(); alert.messageText = "工作台连接失败"; alert.informativeText = "请查看 ~/Library/Application Support/HTMLNativeStudio-CodexClient/client.log，然后重新打开应用。"; alert.runModal() }
            }
        }.resume()
    }
    func startServer() {
        guard let node = config["node"] else { return }
        let source = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Client").path
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/HTMLNativeStudio-CodexClient")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let log = directory.appendingPathComponent("client.log")
        if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
        let file = try? FileHandle(forWritingTo: log); try? file?.seekToEnd()
        let child = Process(); child.executableURL = URL(fileURLWithPath: node); child.arguments = [source + "/server.mjs"]
        child.currentDirectoryURL = URL(fileURLWithPath: source)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (node as NSString).deletingLastPathComponent + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let codex = config["codex"], !codex.isEmpty { env["CODEX_BINARY"] = codex }
        child.environment = env; child.standardOutput = file; child.standardError = file
        do { try child.run(); process = child } catch { NSLog("Client start error: %@", error.localizedDescription) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if nativeOnly { connect(attempt:0) } else { window?.makeKeyAndOrderFront(nil) }; return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String:Any], body["action"] as? String == "openURL", let raw = body["url"] as? String, let url = URL(string: raw), ["http", "https"].contains(url.scheme ?? "") else { return }
        NSWorkspace.shared.open(url)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "about" || url.scheme == "blob" || (url.host == "127.0.0.1" && url.port == 18777) { decisionHandler(.allow); return }
        if navigationAction.navigationType == .linkActivated, ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        decisionHandler(.cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }; return nil
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = parameters.allowsMultipleSelection; panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.beginSheetModal(for: window) { response in completionHandler(response == .OK ? panel.urls : nil) }
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
