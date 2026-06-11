import SwiftUI

@main
struct MarkdownPreviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppDelegate.followXcodeKey) private var followXcode = true
    @AppStorage("zoom") private var zoom = 1.0

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { configuration in
            ReaderView(
                document: configuration.$document,
                fileURL: configuration.fileURL
            )
        }
        // The welcome window (AppDelegate.showWelcome) replaces the automatic
        // untitled document at launch; documents reopen via the recents list
        // instead of scene restoration so launch is deterministic.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: 1280, height: 860)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("欢迎使用 MarkdownPreview") {
                    AppDelegate.shared?.showWelcome()
                }
                .keyboardShortcut("1", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Actual Size") { zoom = 1.0 }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Zoom In") { zoom = min(3.0, zoom + 0.1) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") { zoom = max(0.5, zoom - 0.1) }
                    .keyboardShortcut("-", modifiers: .command)
                Divider()
            }
            CommandMenu("Xcode") {
                Toggle("Follow Xcode Automatically", isOn: $followXcode)
            }
        }
    }
}
