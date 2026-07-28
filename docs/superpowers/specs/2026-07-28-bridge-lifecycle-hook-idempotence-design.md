# Bridge Lifecycle and Hook Idempotence Design

## Scope

This change covers NotchDeck's terminal bridge lifecycle and the idempotence of
the Claude Code and Codex CLI hook installer. It does not change process-based
session discovery, terminal focus, permission response schemas, approval
deadlines, Utilities, or notch visuals. Peek remains a separate phase.

## Phase 0 Findings

- A real Cmd+Q terminated NotchDeck but left `terminal-bridge.sock` behind.
- Relaunch created a new application process but did not create a listener.
- Both persisted integration flags were false, so `AgentsWorkspaceController`
  skipped `TerminalAgentBridge.start()`.
- `TerminalAgentBridge.start()` currently unlinks the socket unconditionally.
  This would clear a stale file, but it can steal the path from a live first
  instance.
- `TerminalSelfTest.run()` reinstalls the helper and starts the bridge. The
  diagnostic action is therefore a repair path, not a read-only test.
- A normal application relaunch did not rewrite Codex hooks or reinstall the
  helper. Explicit Install/Reinstall always rewrites the config, and Preview and
  Self-Test always reinstall the helper.
- Installed Claude and Codex entries currently reference the legacy stable path
  `~/Library/Application Support/NotchDeck/notchdeck-agent-hook`.
- Codex's recorded hook state contains a trusted `pre_tool_use` identity but no
  trusted `permission_request` identity.

## Selected Design

Use focused internal helpers in the existing bridge and installer files. This
keeps the architecture intact and avoids adding a new service layer or moving to
XPC.

### Socket Ownership

`TerminalAgentBridge.start()` is invoked unconditionally from
`applicationDidFinishLaunching`, before the panel is created. The Agents
workspace controller continues to configure permission handling and to start or
stop L1/L2 monitoring, but no longer owns socket availability.

The bridge startup sequence is:

1. Reject socket paths whose UTF-8 byte count is at least Darwin's 104-byte
   `sun_path` capacity.
2. Create the private support directory.
3. Open and exclusively lock a stable lockfile.
4. If the socket path exists, probe it with a nonblocking Unix-domain connect
   bounded to 200 ms.
5. A successful probe means another listener is alive: report
   `alreadyRunning` and leave the path untouched.
6. Only `ECONNREFUSED` or `ENOENT` identify a removable stale path.
7. Bind, chmod `0600`, and listen with backlog 16 while still holding the lock.
8. Release the launch lock after the listener is established.

The bridge records whether it owns the listener. `stop()` only closes and
unlinks a socket owned by that instance. Cleanup on graceful exit remains an
optimization; startup is the correctness path.

Lifecycle failures retain errno, operation, and path and are published to the
diagnostic UI.

### Read-Only Diagnostics

The bridge self-test reads config presence, command validity, helper existence
and executability, bridge state, and observed counters. It never installs a
helper, starts a bridge, invokes a synthetic hook, or changes the session store.
Install/Reinstall also stops calling `bridge.start()` because the bridge already
has an app-owned lifecycle.

### Helper Compatibility and Versioning

Clean installations use:

`~/Library/Application Support/NotchDeck/bin/notchdeck-agent-hook`

Existing installations continue to use any supported stable path already
referenced by a NotchDeck-managed hook. In particular, the current legacy path
is not migrated merely to normalize layout, because changing the command string
would invalidate Codex trust.

The selected helper has an adjacent `.version` sidecar. Release builds replace
the helper only when it is missing, not executable, or the sidecar differs from
the expected app/helper protocol version. Debug builds may replace the binary
on every application launch, but never rewrite hook config as a consequence.

Helper deployment and hook-config installation are distinct operations.
Bootstrap may ensure the helper binary but must not create or edit hook entries.

### Semantic Config Updates

For each provider, the installer constructs the desired NotchDeck-managed
entries in memory and compares those parsed structures with the currently
installed managed entries.

- Equivalent entries produce a no-op: no backup, write, replace, or mtime
  change.
- Different, duplicate, or stale managed entries are removed and replaced while
  preserving every unrelated parsed value.
- Real writes use timestamped unique backups and deterministic sorted JSON keys.
- Uninstall removes only managed NotchDeck objects. Its source-preserving path
  edits the original JSON ranges so unrelated bytes remain unchanged.
- Malformed JSON is reported rather than treated as an empty config.

### Integration State

The UI exposes:

- `missing`: no NotchDeck-managed hook entries;
- `approvalRequired`: Codex entries exist but no PermissionRequest trust record
  or successful runtime event has been observed;
- `working`: required entries exist and either the Codex PermissionRequest trust
  record is present or a real hook event for the provider reached the bridge.

Claude has no equivalent Codex trust registry; an installed Claude integration
is shown as working once an event is observed, with installed status remaining
distinct from missing before that observation.

## Safe Degradation

When NotchDeck is absent, the helper continues to exit zero with empty stdout.
No timeout path denies a request. Existing decision encoders and transport
deadlines are unchanged.

## Verification

Automated tests cover path length, stale files, live listeners, launch locking,
ownership, helper version selection, semantic no-op writes, third-party hook
preservation, source-preserving uninstall, and integration state.

Runtime verification covers graceful quit, SIGKILL, Xcode stop/rerun when
controllable, stale socket recovery, a simultaneous second instance, ten
consecutive launches with stable config mtimes, Debug tests/build, universal
Release build, and `git diff --check`. Any manual-only Codex `/hooks` step is
reported as such.
