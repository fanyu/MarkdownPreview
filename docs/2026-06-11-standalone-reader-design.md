# MarkdownPreview v2 Design — Standalone Reader + Xcode Extension

**Date:** 2026-06-11
**Status:** Approved (user delegated design decisions)

## Goal

A beautiful, easy-to-use macOS Markdown reader that renders all common diagram
types (Mermaid: flowchart, sequence, gantt, class, state, ER, pie, mindmap,
timeline, git graph), with the existing Xcode Source Editor Extension retained
as a secondary entry point.

This supersedes the v1 design where the app was a faceless background agent
(`LSUIElement=YES`) serving only Xcode.

## Product Shape

One regular macOS app (Dock icon), two modes:

1. **Standalone reader (primary).** The app registers as a viewer for
   Markdown files (`net.daringfireball.markdown`). Open via Finder
   double-click ("Open With"), drag onto Dock, or File > Open (⌘O).
   Each file opens in a document window:
   - Left sidebar: outline / table of contents extracted from headings,
     click to scroll to a section. Collapsible.
   - Content: WKWebView rendering with GitHub-style typography.
   - Toolbar: theme picker (Auto / Light / Dark).
   - View menu: zoom in / out / reset (⌘+ / ⌘- / ⌘0).
   - Live reload: FSEvents watches the open file; on save the content
     re-renders in place, preserving scroll position.
2. **Xcode follow mode (secondary).** A floating non-activating `NSPanel`
   that auto-shows the `.md` file currently open in Xcode (AppleScript
   polling at 1s while Xcode is frontmost). Toggleable via the
   "Follow Xcode" menu and via the Source Editor Extension command
   "Toggle Markdown Preview" (distributed notification
   `com.fanyu.markdownpreview.toggle`). Default: enabled.

## Rendering Pipeline (offline, bundled in app Resources)

- `marked.js` 9.x — GFM Markdown parsing (tables, task lists, strikethrough)
- `mermaid.js` 10.x — all diagram types; theme follows light/dark
- `highlight.js` 11.x — code block syntax highlighting, GitHub light/dark CSS
- `preview.html` — single template with CSS variables for light/dark,
  loaded once per webview; content injected via
  `renderMarkdown(content, baseDir)` through `evaluateJavaScript`
  (JSON-encoded string for safety)

Template responsibilities:

- Assign stable ids to headings after render; post the heading list to Swift
  via `webkit.messageHandlers.toc` (drives the sidebar)
- `scrollToHeading(id)` for sidebar clicks
- Rewrite relative `img src` against `baseDir` so local images resolve
  (template loads with `allowingReadAccessTo: /` — the app is unsandboxed)
- Preserve `scrollY` across re-renders
- Mermaid failures render an inline error block instead of breaking the page

## Architecture (Swift, macOS 13+, Swift 5.9)

SwiftUI app lifecycle with `DocumentGroup(viewing:)` — gives Finder opens,
Recents, ⌘O, window titles for free. AppKit only where required
(WKWebView wrapper, floating panel).

| File | Responsibility |
|---|---|
| `App.swift` | `@main` SwiftUI App: DocumentGroup, commands (theme, zoom, Follow Xcode toggle), delegate adaptor |
| `MarkdownDocument.swift` | Read-only `FileDocument` for the markdown UTI |
| `ReaderView.swift` | NavigationSplitView: TOC sidebar + MarkdownWebView, toolbar |
| `MarkdownWebView.swift` | NSViewRepresentable: owns WKWebView + Renderer + FileMonitor per window |
| `Renderer.swift` | Template load, JSON-safe render call, theme, TOC message handling |
| `FileMonitor.swift` | FSEventStream wrapper (0.3s latency) |
| `XcodeWatcher.swift` | AppleScript poll for Xcode's active `.md` |
| `PreviewPanel.swift` | Floating NSPanel for Xcode follow mode (webview, no sidebar) |
| `AppDelegate.swift` | Xcode-follow wiring: watcher → monitor → panel; distributed notification listener |
| `Resources/preview.html` + vendor js/css | Rendering template |

Extension target unchanged: `SourceEditorCommand` posts the toggle
notification and launches the app if needed.

## Settings (UserDefaults / @AppStorage)

- `theme`: `auto` (default) | `light` | `dark` — applies to webview content
  and mermaid theme
- `zoom`: Double, default 1.0, applied to `webView.pageZoom`
- `followXcode`: Bool, default true

## Info.plist / entitlements changes from v1

- `LSUIElement` removed (regular app)
- `CFBundleDocumentTypes` (Viewer role for markdown UTI) +
  `UTImportedTypeDeclarations` for `.md` / `.markdown` / `.mdown`
- Entitlements unchanged: app unsandboxed (AppleScript + arbitrary file
  reads), extension sandboxed with shared App Group

## Error Handling

- File unreadable / deleted → show placeholder message in content area
- AppleScript errors (automation permission denied) → follow mode silently
  idle; reader mode unaffected
- Mermaid parse errors → inline error block, rest of document renders

## Testing

- `xcodebuild` build green for both targets
- Demo document exercising headings, code, tables, task lists, and multiple
  mermaid diagram types; visual verification by launching the built app
- Manual: live-reload on save, theme switching, TOC navigation, Xcode follow
