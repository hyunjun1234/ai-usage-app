import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let store = UsageStore()
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = nil
            (button.cell as? NSButtonCell)?.usesSingleLineMode = false
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateStatusTitle()

        popover.behavior = .transient
        popover.animates = true
        let hosting = NSHostingController(rootView: ContentView(store: store))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusTitle() }
            .store(in: &cancellables)

        store.refresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.store.refresh()
        }
    }

    // MARK: - Clicks

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isContext = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isContext { showContextMenu() } else { togglePopover() }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        store.refresh()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showContextMenu() {
        if popover.isShown { popover.performClose(nil) }
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(withTitle: "사용량 보기", action: #selector(openPopover), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "지금 새로고침", action: #selector(refreshNow), keyEquivalent: "r")
            .target = self

        menu.addItem(.separator())

        let windowItem = NSMenuItem(title: "메뉴 막대 표시", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu()
        for kind in [WindowKind.fiveHour, .weekly] {
            let item = NSMenuItem(title: "\(kind.label) 사용률",
                                  action: #selector(selectMenuWindow(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            item.state = (store.menuWindow == kind) ? .on : .off
            windowMenu.addItem(item)
        }
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)

        let planItem = NSMenuItem(title: "Claude 요금제", action: nil, keyEquivalent: "")
        let planMenu = NSMenu()
        for plan in ClaudePlan.allCases {
            let item = NSMenuItem(title: plan.label,
                                  action: #selector(selectPlan(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = plan.rawValue
            item.state = (store.claudePlan == plan) ? .on : .off
            planMenu.addItem(item)
        }
        planItem.submenu = planMenu
        menu.addItem(planItem)

        let launch = NSMenuItem(title: "로그인 시 자동 실행",
                                action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = store.launchAtLogin ? .on : .off
        menu.addItem(launch)

        menu.addItem(.separator())

        menu.addItem(withTitle: "AI Usage 정보", action: #selector(showAbout), keyEquivalent: "")
            .target = self
        let quit = NSMenuItem(title: "종료", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    // MARK: - Menu actions

    @objc private func openPopover() { if !popover.isShown { togglePopover() } }
    @objc private func refreshNow() { store.refresh(force: true) }
    @objc private func toggleLaunchAtLogin() { store.launchAtLogin.toggle() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    @objc private func selectPlan(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let plan = ClaudePlan(rawValue: raw) {
            store.claudePlan = plan
            store.refresh()
        }
    }

    @objc private func selectMenuWindow(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let kind = WindowKind(rawValue: raw) {
            store.menuWindow = kind
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "AI Usage"
        alert.informativeText = """
        Claude Code · Codex 사용량을 메뉴 막대에 표시합니다.
        Codex 한도는 실시간, Claude는 요금제 기반 추정입니다.

        버전 2.0
        """
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }

    // MARK: - Menu-bar title (two stacked lines: C / X)

    private func updateStatusTitle() {
        guard let button = statusItem.button else { return }
        let snap = store.snapshot

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.lineSpacing = 0
        paragraph.maximumLineHeight = 10
        paragraph.minimumLineHeight = 10
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)

        let kind = store.menuWindow
        let title = NSMutableAttributedString()
        title.append(line("C", snap.percent(.claude, kind), font, paragraph))
        title.append(NSAttributedString(string: "\n"))
        title.append(line("X", snap.percent(.codex, kind), font, paragraph))
        button.attributedTitle = title
    }

    private func line(_ tag: String, _ percent: Double?,
                      _ font: NSFont, _ paragraph: NSParagraphStyle) -> NSAttributedString {
        let text = percent.map { "\(tag) \(Int($0.rounded()))%" } ?? "\(tag)  —"
        var color = NSColor.labelColor
        if let p = percent {
            if p >= 100 { color = .systemRed }
            else if p >= 80 { color = .systemOrange }
        }
        return NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
        ])
    }
}
