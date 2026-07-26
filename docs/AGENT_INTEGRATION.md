# Agent Integration (Claude Code & Codex)

NotchDeck can monitor coding-agent sessions and surface real permission
requests. This does **not** happen automatically — it requires installing small
lifecycle **hooks** into the agent's own configuration.

## How it works (plain language)

- NotchDeck **does not** scan, read, or scrape arbitrary terminal contents.
- Claude Code and Codex emit **lifecycle events** through command hooks you
  install. NotchDeck uses those events to show session status, recent activity,
  and genuine permission requests.
- **Activity hooks and permission hooks are different.** Activity hooks update a
  session's status; only a real `PermissionRequest` creates an approval.
- **Focus Terminal** locates and raises the *existing* Terminal tab where the
  agent runs — it never creates a new session or runs a command.

## Hook events used

The installer registers exactly these events (no others):

| Event             | Effect in NotchDeck                                   |
| ----------------- | ---------------------------------------------------- |
| `SessionStart`    | Session becomes visible / running.                   |
| `PreToolUse`      | **Activity only** — updates tool name + summary. Never an approval. |
| `PermissionRequest` | Creates **one** approval (Allow / Deny).           |
| `PostToolUse`     | Tool completed — updates/clears activity.            |
| `Stop`            | Assistant turn finished — session goes idle/finished.|
| `SessionEnd`      | Session finished.                                    |

Active vs Recent is determined by **terminal presence** (is the tab still open),
not by these events. A finished session whose tab is still open stays **Active**.

## Installing hooks

Use the app-driven installer (no manual file editing needed):

1. Open **NotchDeck**.
2. Open **Settings**.
3. Open the **Agents** section → **Terminal integration**.
4. Choose **Install Hooks** (or **Reinstall Hooks**) for **Claude Code** or
   **Codex**.
5. Start a **new** agent session in your terminal.
6. Run the built-in **integration self-test** to confirm the socket and hooks.

> Sessions started **before** the hooks were installed will not appear until
> they emit a later hook (e.g. a tool use) or you restart them.

The installer marks its own entries, replaces stale NotchDeck-managed entries,
**preserves unrelated user/plugin hooks**, and writes a timestamped backup of
the config before changing it.

## Updating hooks

Use **Reinstall Hooks** after upgrading NotchDeck when:

- the app reports a **hook-version / schema mismatch**;
- clicking **Allow** does not continue the provider;
- the installer **timeout or schema** changed between versions;
- sessions appear but their actions don't update.

## Permission handling modes

Set in **Settings → Agents → Approvals**:

- **Terminal only** — NotchDeck shows the request for context and a **Focus
  Terminal** button, but no functional Allow/Deny; you answer in the terminal.
- **NotchDeck only** — NotchDeck owns the decision; no native prompt is
  expected. A timeout fails safe and **never auto-approves**.
- **NotchDeck, then Terminal fallback** (default, hybrid).

### Hybrid flow (sequential, not simultaneous)

1. The synchronous `PermissionRequest` helper **waits** for NotchDeck's decision.
2. NotchDeck shows the approval with a **countdown** ("Terminal prompt in Ns").
3. If you click **Allow/Deny** before the deadline, the decision is delivered to
   the **live helper**, which prints the provider's exact response and exits.
4. Only after a real delivery acknowledgement does the card show **Approved**.
5. If no decision is made before the fallback timeout, the helper **exits with
   no decision**.
6. The provider then shows its **native terminal prompt**.

> Terminal-native approval and NotchDeck approval are **sequential** options, not
> two independent approval surfaces active at once. Returning a decision answers
> the request on your behalf; returning nothing hands it back to the terminal.

NotchDeck never simulates keystrokes, pastes commands, or injects TTY input to
fake dual control.

## Hook privacy & security

- **Collected metadata:** provider, session id, working directory, tool name, a
  sanitized command *summary*, TTY / terminal app, PIDs, and a request id.
- **Not collected:** full prompts, tool input, tokens, environment variables.
  Summaries are sanitized (ANSI/JSON/secret-stripped) and length-capped.
- **Stored:** locally under `~/Library/Application Support/NotchDeck`; a short
  helper log at `~/Library/Logs/NotchDeck/agent-hook.log` (metadata only).
- Approval responses are correlated to the **exact live request** over the same
  socket connection.
- **Modules** cannot receive agent/approval capabilities unless a module
  explicitly declares `agentApprovalEvents` / `terminalSessionEvents` and passes
  review.

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for: session not appearing, session
shown in Recent while the terminal is open, approval appearing twice, Allow not
continuing the provider, outdated hooks, socket not listening, Focus Terminal
not locating the tab, missing Automation permission, and duplicate managed
hooks.
