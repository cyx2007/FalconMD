import AppKit
import SwiftUI

@main
struct FalconMDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            MarkdownEditorView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: 900, height: 740)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            MarkdownFormatCommands()
            StartPageCommands()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    private var startWindow: NSWindow?
    private var documentFocusObserver: NSObjectProtocol?

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        showStartPage()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task.detached(priority: .utility) {
            DocumentAssets.cleanupStaleUnsavedAssets()
        }
        closeOpenPanels()
        showStartPage()

        documentFocusObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow,
                  window.windowController?.document is NSDocument else { return }
            Task { @MainActor in
                guard let self, window !== self.startWindow else { return }
                self.hideStartPage()
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.closeOpenPanels()
            self?.showStartPage()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showStartPage()
            return false
        }
        return true
    }

    func showStartPage() {
        closeOpenPanels()
        if startWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 740, height: 460),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.identifier = NSUserInterfaceItemIdentifier(StartPage.windowID)
            window.title = StartPage.windowTitle
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.contentView = NSHostingView(rootView: StartPageView())
            window.center()
            startWindow = window
        }
        startWindow?.makeKeyAndOrderFront(nil)
    }

    func hideStartPage() {
        startWindow?.orderOut(nil)
    }

    func closeOpenPanels() {
        for window in NSApp.windows {
            if let panel = window as? NSOpenPanel {
                panel.cancel(nil)
            }
        }
    }
}

struct StartPageCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button(StartPage.windowTitle) {
                AppDelegate.shared?.showStartPage()
            }
        }
    }
}
