# Troubleshooting

Common issues with NotchDeck's agent integration and how to resolve them. Prefer
the in-app installer and self-test over editing config files by hand.

## Session does not appear

- The session likely **started before hooks were installed**. Install/reinstall
  hooks (Settings → Agents → Terminal integration) and start a **new** session,
  or trigger any tool use in the existing one.
- Confirm the bridge is listening: run the **integration self-test** in Settings.
  The socket is `~/Library/Application Support/NotchDeck/terminal-bridge.sock`.
- Check the helper log: `~/Library/Logs/NotchDeck/agent-hook.log` (metadata only).

## Session shows in Recent while the terminal is open

- Active/Recent follows **terminal presence**. NotchDeck confirms a tab is gone
  only after **three consecutive** successful enumerations that don't find the
  TTY. Query/permission errors do **not** count, so a session should not flip to
  Recent from a transient error.
- If it flipped anyway, ensure **Automation** permission is granted (below) so
  the tab enumeration can succeed.

## Approval appears twice

- Only a `PermissionRequest` creates an approval; `PreToolUse` never does.
  Duplicate approvals usually mean **stale/duplicate managed hooks** — use
  **Reinstall Hooks**, which removes NotchDeck-managed duplicates and keeps
  exactly one `PermissionRequest` entry.

## Clicking Allow does not continue the provider

- The card shows **Approved** only after the helper acknowledges delivering the
  decision. If it stays on **Sending…** or shows **Approval could not be
  delivered**, the helper likely exited (timeout) — answer in the terminal.
- Ensure hooks are current with **Reinstall Hooks** (a schema/timeout change
  between versions can break delivery).

## Hook configuration is outdated

- NotchDeck detects a mismatch (wrong timeout, missing marker, or an `async`
  `PermissionRequest`). Use **Reinstall Hooks**. Managed entries are replaced;
  unrelated user/plugin hooks are preserved; a backup is written first.

## Helper socket is not listening

- The bridge starts when terminal integration is enabled. Toggle it off/on in
  Settings, or restart NotchDeck, then re-run the self-test.

## Focus Terminal cannot locate the original tab

- NotchDeck matches the **TTY** of the agent's tab in Terminal.app. If it can't
  find it, it shows a precise message (e.g. *"NotchDeck does not have permission
  to control Terminal"*, *"Unable to verify the Terminal session"*, or *"The
  original terminal session is no longer available"*) — it never opens a
  replacement window.
- Grant **Automation** permission (below). Exact matching for non-Apple-Terminal
  emulators is limited.

## Automation permission is missing

- Focus Terminal and tab enumeration use AppleEvents. Grant it under **System
  Settings → Privacy & Security → Automation → NotchDeck → Terminal**. You can
  also run the Permissions Setup again from Settings.

## Duplicate managed hooks

- Use **Reinstall Hooks**. The installer keeps a single NotchDeck-managed
  `PermissionRequest` entry (marked with a stable identifier) and preserves your
  other hooks.

## Nuclear option

If the automated installer cannot resolve a problem, uninstall the NotchDeck
hooks from Settings, restart the agent CLI, and reinstall. Manual editing of the
provider's config is a last resort.
