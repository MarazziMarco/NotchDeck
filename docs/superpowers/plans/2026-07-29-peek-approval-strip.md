# Peek Approval Strip Implementation Plan

## 1. Transaction-first test seams

Add failing tests for a pure Peek queue projection over real `AgentSession`
models: transaction-ID deduplication, cross-session deterministic FIFO, one
visible item, total count, current-session actionability, lifecycle removal, and
terminal-pending retention.

Implement a presentation-only `ApprovalPeekCoordinator` that observes
`AgentSessionStore`, resolves identities back to that store, and drives
`AppState` Compact/Peek/Expanded events without copying approval authority.

## 2. Exact-once decisions and expiry

Add failing tests for transaction-specific Allow/Deny, stale/expired/duplicate
click rejection, in-flight disabling, and request-specific acknowledgement
watchdogs.

Implement the exact transaction API in `AgentCoordinator` and route both Peek
and existing Expanded Agents through it. Preserve provider encoders and bridge
socket routing.

Add failing tests proving local expiry emits neither decision, preserves
terminal-pending state, retains original deadlines, and handles queued expiry
without duplicating or auto-deciding. Make the minimal reducer/sweep changes
needed to keep those transactions truthful until authoritative lifecycle
completion.

## 3. Real action summaries

Add failing adapter/helper tests using complete Claude and Codex
PermissionRequest fixtures for shell, patch/file, and MCP inputs. Assert
truthful summaries and credential redaction.

Move the existing display sanitizer to the Foundation-only shared protocol
boundary and have `AgentLatestMessage` delegate to it. Populate the existing
`TerminalAgentEvent.summary`; do not change response schemas.

Add Debug-only safe payload-shape logging and capture real Claude and Codex
field/type shapes during manual verification.

## 4. State and SwiftUI Peek

Add failing state-machine tests for Compact to Peek, no empty manual Peek,
Peek-to-Expanded click, resolution-to-next, final removal-to-Compact, and
Compact requests while a transaction remains.

Implement `ApprovalPeekView` with provider mark, session/project, tool, command
or action, queue counter, Deny, Allow, Focus Terminal, terminal-pending wording,
and absolute-deadline progress. Hover reveals fuller sanitized detail and cwd.
Use monospace command text and safe line limits.

Add semantic presentation tests for provider/action/queue accessibility labels,
button consequences, expired wording, and Reduce Motion animation policy.

## 5. Stable panel host and exact mouse routing

Add failing pure geometry tests for Peek on notched and notchless displays,
frontmost-window display selection, static host sizing, and rounded visible-path
hit testing.

Keep one transparent panel host large enough for all states. Move clipping to a
state-sized visible container and publish its exact frame/path. Set
`becomesKeyOnlyIfNeeded`, keep Compact/Peek non-key, and animate only SwiftUI
content.

Split hover activation from interactive hit geometry. Add defensive host-view
hit testing and dynamically toggle `NSWindow.ignoresMouseEvents` outside the
visible interactive path.

## 6. Regression and build verification

Run focused Peek tests after every red/green slice, then the complete Debug
suite with zero skipped tests. Run a Debug application build and a universal
Release build. Run `git diff --check`, inspect the complete diff, and verify no
hook installer, bootstrap, trust, process-authority, provider response schema,
Utilities, More, Home, Focus, Files, or Expanded Agents changes escaped the
Phase 3 boundary.

## 7. Manual verification and delivery

Run the built Debug app. With Terminal continuously receiving typed input,
exercise real Claude Allow, Deny, and Terminal-side resolution; three queued
requests; hover/cwd; local expiry; Focus Terminal; full-screen; multiple Spaces;
menu-bar and transparent-region click-through; and notchless/external display
positioning. Recheck Compact and Expanded visuals.

Capture the safe real payload-shape diagnostics for Claude and Codex. Record
only checks genuinely completed. Create focused commits, push
`feature/peek-approval-strip`, and do not merge to `main`.
