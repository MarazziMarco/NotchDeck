# Bridge Lifecycle and Hook Idempotence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the terminal bridge available on every app launch and make helper
and hook installation idempotent without invalidating Codex trust.

**Architecture:** AppDelegate owns unconditional bridge bootstrap. Existing
bridge and installer files gain small, testable lifecycle and semantic-update
helpers; the Agents workspace keeps only monitoring/configuration ownership.

**Tech Stack:** Swift, Swift Concurrency, Darwin Unix sockets/flock, Foundation
JSONSerialization, SwiftUI/AppKit, XCTest, xcodebuild.

## Global Constraints

- L1 process discovery must not depend on terminal inventory or hooks.
- Do not change Focus Terminal, PermissionRequest response schemas, approval
  deadlines, Utilities, or current compact/expanded visuals.
- Hook silence remains the safe fallback: exit zero with empty stdout.
- Startup, not teardown, is the socket correctness path.
- Do not start Phase 3 Peek.

---

### Task 1: Safe Unix-Socket Startup

**Files:**
- Modify: `NotchDeck/Agents/Terminal/TerminalAgentBridge.swift`
- Modify: `NotchDeck/Agents/Terminal/TerminalBridgeStats.swift`
- Test: `NotchDeckTests/AgentHookLifecycleTests.swift`

**Interfaces:**
- Produces: typed bridge lifecycle failures and a startup primitive that accepts
  an explicit socket path.
- Consumes: Darwin `socket`, `connect`, `poll`, `flock`, `bind`, and `listen`.

- [ ] Add failing tests for a manually created stale file, a live listener,
  concurrent startup, and a path containing at least 104 UTF-8 bytes.
- [ ] Run only `AgentHookLifecycleTests` and verify each new test fails for the
  missing lifecycle behavior.
- [ ] Add path validation before filesystem operations.
- [ ] Add lockfile serialization around probe, stale removal, bind, and listen.
- [ ] Add a nonblocking probe with a 200 ms maximum wait; treat only
  `ECONNREFUSED` and `ENOENT` as stale.
- [ ] Track socket ownership so an unsuccessful second instance cannot unlink the
  first instance's socket during shutdown.
- [ ] Publish the exact lifecycle error in `TerminalBridgeStats`.
- [ ] Re-run focused lifecycle tests and commit the green change.

### Task 2: App-Owned Bootstrap and Read-Only Self-Test

**Files:**
- Modify: `NotchDeck/App/AppDelegate.swift`
- Modify: `NotchDeck/Agents/AgentsWorkspaceController.swift`
- Modify: `NotchDeck/Agents/Terminal/TerminalSelfTest.swift`
- Modify: `NotchDeck/Settings/TerminalIntegrationView.swift`
- Test: `NotchDeckTests/ApplicationTerminationTests.swift`
- Test: `NotchDeckTests/IterationFiveTests.swift`

**Interfaces:**
- Consumes: `TerminalAgentBridge.start()`.
- Produces: a single unconditional bootstrap call and a diagnostic report with
  no repair side effects.

- [ ] Add failing lifecycle/self-test assertions proving diagnostics do not call
  install/start or create a synthetic session.
- [ ] Run the focused tests and record the expected failure.
- [ ] Start the bridge unconditionally at the beginning of
  `applicationDidFinishLaunching`.
- [ ] Remove conditional bridge startup from `AgentsWorkspaceController`.
- [ ] Remove helper installation, bridge startup, and helper invocation from
  `TerminalSelfTest`.
- [ ] Remove the bridge-start side effect from the Install button and show the
  typed lifecycle error in diagnostics.
- [ ] Re-run focused tests and commit.

### Task 3: Versioned Helper with Legacy-Path Compatibility

**Files:**
- Modify: `NotchDeck/Agents/Terminal/HookInstaller.swift`
- Modify: `NotchDeck/App/AppDelegate.swift`
- Test: `NotchDeckTests/AgentHookLifecycleTests.swift`
- Test: `NotchDeckTests/IterationFourTests.swift`

**Interfaces:**
- Produces: `resolvedHelperURL()`, an expected version string, and an idempotent
  helper deployment operation.
- Consumes: existing NotchDeck command strings from both provider configs.

- [ ] Add failing tests for a clean canonical `bin` path, a referenced legacy
  path, equal/different sidecars, a missing helper, and a non-executable helper.
- [ ] Run focused helper tests and verify failure.
- [ ] Resolve an existing supported path from installed managed entries; otherwise
  choose the canonical `bin` path.
- [ ] Write/read the adjacent `.version` sidecar and skip Release replacement
  when version and executable state match.
- [ ] Ensure the helper during app bootstrap without touching either config.
- [ ] Re-run focused tests and commit.

### Task 4: Semantic Install and Source-Preserving Uninstall

**Files:**
- Modify: `NotchDeck/Agents/Terminal/HookInstaller.swift`
- Test: `NotchDeckTests/IterationSeventeenTests.swift`
- Test: `NotchDeckTests/AgentApprovalDeliveryTests.swift`

**Interfaces:**
- Produces: a semantic managed-entry comparator, no-op install plan, deterministic
  merge writer, and source-preserving managed-entry removal.
- Consumes: parsed Claude/Codex JSON and the resolved stable helper path.

- [ ] Add failing tests that assert no-op install leaves bytes and mtime unchanged.
- [ ] Add failing fixtures with third-party entries before and after NotchDeck
  entries and assert they survive install and uninstall.
- [ ] Add a failing test that uninstall leaves all unrelated source bytes
  unchanged while removing every NotchDeck marker.
- [ ] Run focused installer tests and verify failure.
- [ ] Compare exactly one desired managed entry per event before deciding to write.
- [ ] Back up and deterministically merge only when a real difference exists.
- [ ] Implement string-aware JSON range removal for managed array elements so
  uninstall does not reserialize unrelated content.
- [ ] Re-run focused tests and commit.

### Task 5: Missing, Trust-Required, and Working States

**Files:**
- Modify: `NotchDeck/Agents/Terminal/TerminalBridgeStats.swift`
- Modify: `NotchDeck/Agents/Terminal/HookInstaller.swift`
- Modify: `NotchDeck/Settings/TerminalIntegrationView.swift`
- Test: `NotchDeckTests/AgentPermissionAdapterTests.swift`

**Interfaces:**
- Produces: `HookIntegrationState` with `missing`, `approvalRequired`, and
  `working`, plus per-provider observed-event state.
- Consumes: installed config, Codex `[hooks.state]`, and real decoded bridge
  events.

- [ ] Add failing pure-state tests for missing hooks, absent PermissionRequest
  trust, present PermissionRequest trust, and runtime evidence.
- [ ] Run the focused tests and verify failure.
- [ ] Record provider-specific decoded events in bridge stats.
- [ ] Derive and render the three integration states without changing hook
  definitions.
- [ ] Re-run focused tests and commit.

### Task 6: Acceptance Verification

**Files:**
- Modify only if a verification failure exposes a tested defect in Tasks 1–5.

- [ ] Run all focused lifecycle and installer tests.
- [ ] Run the complete Debug test suite.
- [ ] Build the Debug app.
- [ ] Build a universal Release app for `arm64 x86_64`.
- [ ] Run `git diff --check`.
- [ ] Run the built app after Cmd+Q and confirm a listener is created.
- [ ] SIGKILL the app, relaunch, and confirm stale recovery.
- [ ] Stop/rerun from Xcode if the IDE state permits an honest live test.
- [ ] Replace the socket with a regular stale file and confirm recovery.
- [ ] Launch a simultaneous second instance and confirm the first listener
  remains reachable.
- [ ] Exercise a path over Darwin's limit through the lifecycle test harness.
- [ ] Launch ten times and compare Codex/Claude config bytes and mtimes.
- [ ] Verify third-party hook preservation and NotchDeck-only uninstall using
  temporary fixture configs.
- [ ] Verify Codex trust persistence live only if `/hooks` approval can be
  observed; otherwise report structural evidence and the remaining manual step.
