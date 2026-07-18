# TypeLock Architecture

## Overview

TypeLock is a macOS menu bar utility that applies the correct input method for the active app. It keeps a global default, optional per-app input method assignments, and no-action exclusions, then restores the expected source when macOS or another app changes it.

## Component Diagram

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          TypeLockApp (@main)                             │
│                     SwiftUI App (empty Settings scene)                   │
│                                 │                                        │
│                  @NSApplicationDelegateAdaptor                           │
│                                 ▼                                        │
│  ┌───────────────────────────────────────────────────────────────────┐   │
│  │                       AppDelegate                                 │   │
│  │                                                                   │   │
│  │  ┌─────────────┐   ┌──────────────┐   ┌─────────────────┐        │   │
│  │  │ NSStatusItem │   │   NSMenu     │   │ ExcludedApps    │        │   │
│  │  │  lock icon   │   │              │   │ NSWindow        │        │   │
│  │  │ (menu bar)  │   │ • Status     │   │    │            │        │   │
│  │  └──────┬──────┘   │ • Sources    │   │    ▼            │        │   │
│  │         │          │ • Unlock     │   │ ExcludedApps    │        │   │
│  │         └─────────►│ • Excluded…  │   │ View (SwiftUI)  │        │   │
│  │                    │ • Login      │   │  • App list     │        │   │
│  │                    │ • About      │   │  • IM picker    │        │   │
│  │                    │ • Quit       │   └─────────────────┘        │   │
│  │                    └──────────────┘                               │   │
│  │         │                                                         │   │
│  │         │ Combine (objectWillChange)                              │   │
│  │         ▼                                                         │   │
│  │  ┌────────────────────────────────────────────────────────────┐   │   │
│  │  │              InputSourceManager                            │   │   │
│  │  │                                                            │   │   │
│  │  │  @Published availableSources: [(id, name)]                 │   │   │
│  │  │  @Published lockedSourceID: String?                        │   │   │
│  │  │  @Published excludedApps: [ExcludedApp]                    │   │   │
│  │  │                                                            │   │   │
│  │  │  Caches:                                                   │   │   │
│  │  │    excludedBundleIDs: Set<String>                          │   │   │
│  │  │    excludedAppInputSources: [String: String]               │   │   │
│  │  │                                                            │   │   │
│  │  │  ┌──────────────────┐ ┌──────────────────┐ ┌────────────────┐  │   │
│  │  │  │  Listener 1      │ │  Listener 2      │ │  Listener 3    │  │   │
│  │  │  │  DistributedNotif│ │  NSWorkspace      │ │  AX Focus Poll │  │   │
│  │  │  │  Center          │ │  .didActivateApp  │ │  (200ms timer) │  │   │
│  │  │  │                  │ │                   │ │                │  │   │
│  │  │  │  "input source   │ │  "frontmost app   │ │  AX focus attrs│  │   │
│  │  │  │   changed"       │ │   changed"        │ │  + fallback    │  │   │
│  │  │  └────────┬─────────┘ └─────────┬─────────┘ └───────┬────────┘  │   │
│  │  │           │                     │                    │          │   │
│  │  │           ▼                     ▼                    ▼          │   │
│  │  │  ┌─────────────────────────────────────────────────────────┐   │   │
│  │  │  │           Enforcement Pipeline                          │   │   │
│  │  │  │                                                         │   │   │
│  │  │  │  1. isHandlingChange? ──── yes ──► ignore               │   │   │
│  │  │  │  2. isLocked?  ────────── no ───► ignore                │   │   │
│  │  │  │  3. app excluded?                                       │   │   │
│  │  │  │     ├── yes + assigned IM ──► enforce IM                │   │   │
│  │  │  │     ├── yes + no assignment ► ignore                    │   │   │
│  │  │  │     └── no ─────────────────► enforce lock              │   │   │
│  │  │  │  4. input changes debounce 50ms                         │   │   │
│  │  │  │     (activation/focus polling enforce immediately)       │   │   │
│  │  │  │          │                                              │   │   │
│  │  │  │          ▼                                              │   │   │
│  │  │  │  selectSource()                                         │   │   │
│  │  │  │     set isHandlingChange = true                         │   │   │
│  │  │  │     TISSelectInputSource(target)                        │   │   │
│  │  │  │          │                                              │   │   │
│  │  │  │          ▼  (after 150ms, cancels previous)             │   │   │
│  │  │  │     isHandlingChange = false                            │   │   │
│  │  │  │     re-check & enforce again if needed                  │   │   │
│  │  │  └─────────────────────────────────────────────────────────┘   │   │
│  │  └────────────────────────────────────────────────────────────────┘   │
│  └───────────────────────────────────────────────────────────────────────┘
│                                                                          │
│  Persistence                                                             │
│  ┌───────────────────────────────────────────────────────────────────┐   │
│  │  UserDefaults                                                     │   │
│  │  • lockedSourceID (String)                                        │   │
│  │  • excludedApps   (JSON: [{bundleID, name, inputSourceID?}])      │   │
│  └───────────────────────────────────────────────────────────────────┘   │
│  ┌───────────────────────────────────────────────────────────────────┐   │
│  │  SMAppService.mainApp                                             │   │
│  │  (launch at login; migrates the legacy LaunchAgent)               │   │
│  └───────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  macOS APIs                                                              │
│  ┌───────────────────────────────────────────────────────────────────┐   │
│  │  Carbon TIS*  ──► TISInputSource+Extensions (Swift wrapper)       │   │
│  │  Accessibility ─► AXIsProcessTrusted (prompted on launch)         │   │
│  │                ─► AXUIElementCreateSystemWide (focus polling)      │   │
│  └───────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────┘
```

## Key Design: Triple-Listener Pattern

Three listeners run simultaneously, all feeding into the enforcement pipeline:

1. **Input source change** (`DistributedNotificationCenter`) — catches switches made by any process
2. **App activation** (`NSWorkspace`) — catches app-focus-driven switches, since many apps force an input source on activation
3. **AX focus polling** (200ms `DispatchSourceTimer`) — catches non-activating panels (Spotlight, Alfred, Raycast, 1Password mini) that steal keyboard focus without firing `didActivateApplicationNotification`. It resolves the focused owner from `kAXFocusedWindowAttribute`, then `kAXFocusedApplicationAttribute`, then `kAXFocusedUIElementAttribute`, then falls back to `NSWorkspace.shared.frontmostApplication`. Only active when locked AND excluded apps exist. An `NSProcessInfo` activity prevents App Nap from throttling the timer.

## Three App Types

| Type | On activation | On external IM change |
|------|---------------|----------------------|
| Normal app | Enforce global default | Fight back to global default |
| App with assigned IM | Switch to assigned IM | Fight back to assigned IM |
| Excluded app with no assignment | No action | No action |

## Enforcement Guards

Checks prevent unnecessary or recursive enforcement:

- **`isHandlingChange`** — prevents re-entrant loops (our own `TISSelectInputSource` fires the same notification)
- **`isLocked`** — all enforcement requires a global default to be active
- **Frontmost app context** — debounced work re-checks the frontmost app before acting, preventing enforcement in the wrong app during rapid switching
- **Resolved bundle ID required** — the focus poller only updates `currentFrontmostBundleID` after resolving a bundle identifier from AX ownership or the `NSWorkspace` fallback

A 50ms debounce collapses input-source-change notification storms. App activation and focus polling enforce immediately. A tracked 150ms re-check timer after each switch (cancelling any previous timer) catches races without overlapping.

## Startup

At launch, `currentFrontmostBundleID` is initialized before any enforcement. The `startupSource()` helper determines the correct source — per-app assignment when configured, global default otherwise. A 3-second retry handles third-party input methods that aren't loaded immediately after reboot.

TypeLock starts enforcement only after Accessibility permission is granted. Until then, the menu exposes only setup, About, and Quit. A setup window links directly to System Settings and updates automatically when permission changes. Revoking permission pauses enforcement without deleting the saved default or app rules.
