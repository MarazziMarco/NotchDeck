# Architecture

This document describes how NotchDeck is put together. It distinguishes what is
**implemented today**, what is **experimental**, and what is **roadmap**.

## Overview

NotchDeck is a menu-bar-only (`LSUIElement`) macOS app. A single borderless,
non-activating `NSPanel` hosts a SwiftUI hierarchy positioned around the
physical notch. It is compact/near-invisible at rest and expands on hover,
click, or file drag.

```
┌────────────────────────────────────────────────────────────┐
│ AppDelegate                                                 │
│   ├─ AppEnvironment (owns all long-lived services)          │
│   ├─ NotchPanelController ── NSPanel + NSHostingView        │
│   │     └─ NotchRootView (SwiftUI)                          │
│   │           ├─ CompactNotchView   (closed / live activity)│
│   │           └─ ExpandedNotchView  (Utilities / Agents)    │
│   ├─ NotchInteractionCoordinator (hover / pointer tracking) │
│   └─ TerminalAgentBridge (Unix-domain socket)               │
└────────────────────────────────────────────────────────────┘
```

## AppKit shell + SwiftUI content

- **`NotchPanel`** — borderless `.nonactivatingPanel` at `.statusBar` level,
  all-Spaces, `hasShadow = false`, clear background, excluded from the Dock and
  window cycle. Becomes key only when a text field needs input.
- **`NotchPanelController`** — owns the panel and `NSHostingView`, repositions on
  state/screen changes, and computes hot zones for hover/activation.
- **`NotchRootView`** — the single SwiftUI root. One authoritative rounded shape
  (`BottomRoundedShape`) clips both the background fill and the content.

## Notch geometry service

`NotchGeometryService` is pure geometry math over a `DisplayMetrics` value
(decoupled from `NSScreen`, so it is unit-testable). It computes:

- **physical-idle** — matches the hardware notch exactly when there is no
  compact activity, so NotchDeck disappears into the notch;
- **compact-activity** — a rounded capsule with side wings when a live activity
  is shown (timer, agent, approval, media, file);
- **expanded** — the wide letterbox panel; its geometry is driven by
  `NotchResponsiveLayoutService` from actual logical screen width, never a
  hard-coded model.

## Compact vs expanded presentation

- **Compact** renders whatever `LiveActivityCoordinator` resolves — only active
  or attention-requiring information, never idle module icons. Content is placed
  in the two wings beside the physical camera housing.
- **Expanded** shows two faces: **Utilities** (Home / Focus / Files / More tabs)
  and **Agents**.

## Utility modules

The shipped widgets implement the built-in `NotchModule` protocol and are wired
through `ModuleRegistry` + `DashboardModel`. Each module owns its service
(Clipboard, FileShelf, Mirror, Pomodoro, QuickNote, NowPlaying, Downloads,
Screenshot, Battery). Pure logic (formatters, reducers, filters, layout) is kept
in `nonisolated`/testable functions.

## Module registry (community architecture)

A separate, community-extensible layer lives in `NotchDeck/Modules/Core`:

- `NotchDeckModule` — the protocol contributors implement.
- `ModuleDescriptor` — stable metadata (id, name, version, author, category,
  icon, default-enabled, surfaces, **declared capabilities**, settings).
- `ModuleCapability` / `ModuleSurface` — what a module may access and where it
  may present.
- `AnyNotchDeckModule` — type erasure so heterogeneous SwiftUI views live in the
  registry without unsafe casts.
- `ModuleContext` — capability-gated access; a module sees only what it declared.
- `CommunityModuleRegistry` — one authoritative registry (rejects duplicate ids,
  deterministic ordering, enabled/disabled state, alias-based id migration).

> **Status:** the registry, descriptors, capability gating, and an example
> module are implemented and tested. Wiring every shipped widget onto this new
> layer is intentionally incremental — existing features keep using the built-in
> path until migrated.

## Agent bridge + helper

- **`notchdeck-agent-hook`** (a tiny CLI target) is invoked by Claude Code /
  Codex command hooks. It reads the hook JSON from stdin, forwards a sanitized
  event over the socket, and — only for a `PermissionRequest` — **blocks
  synchronously** for an Allow/Deny decision, prints the provider's exact
  response schema to stdout, flushes, sends a delivery acknowledgement, and
  exits.
- **`TerminalAgentBridge`** (an `actor`) accepts connections on background
  threads (blocking `accept()`/`read()` never touch the actor executor), decodes
  events, reduces them onto sessions on the main actor, and answers approvals on
  the same live connection.

### Unix-socket request/response

The socket lives at
`~/Library/Application Support/NotchDeck/terminal-bridge.sock` (0700 directory,
0600 socket, no network port). The wire format is a small versioned JSONL
protocol (`TerminalAgentProtocol`). Only sanitized metadata is accepted.

### Timeout hierarchy (approvals)

`UI fallback (8s) < helper hard deadline (15s) < Claude hook timeout (30s)`.
At the UI fallback the app sends a **release** to the still-blocked helper so it
returns immediately with empty stdout and the provider shows its native prompt.

## Terminal presence tracking

Active vs Recent is driven by **terminal presence**, not hook activity or
approvals. `TerminalController` enumerates open Terminal.app tab TTYs; a session
stays **Active** while its tab exists (even idle/completed) and moves to
**Recent** only after **three confirmed** absences (query/permission errors do
not count) or when Terminal quits.

## Permissions coordinator

- `PermissionCoordinator` reports live camera / accessibility / notification
  status.
- `PermissionsSetupModel` + `PermissionsSetupWindow` drive a first-launch,
  sequential onboarding window (Camera → Screen Recording → Downloads → Terminal
  Automation). The notch collapses before the window appears so system dialogs
  are never hidden.

## Persistence

Settings are one `AppSettings` JSON blob in `UserDefaults`. Module state uses
small `JSONFileStore` files under Application Support (Pomodoro engine, File
Shelf manifest, agent sessions). Nothing is synced to the cloud.

## Privacy boundaries

- No telemetry, no network calls of NotchDeck's own.
- Hook events carry sanitized metadata only (ANSI/JSON/secret-stripped, capped
  summaries); full prompts, tokens, and environment never cross the socket.
- Modules receive services only for declared capabilities.
- Focus Terminal raises an existing tab; it never types or runs commands.
