# Security Policy

NotchDeck is an early-stage, open-source macOS app. It runs locally, stores data
only under `~/Library/Application Support/NotchDeck`, and makes no network calls
of its own. This document describes how to report vulnerabilities and the
project's security model.

## Reporting a vulnerability

Please **do not** open a public issue for a security vulnerability.

Use **GitHub Private Vulnerability Reporting**:

1. Go to the repository's **Security** tab.
2. Click **Report a vulnerability**.
3. Describe the issue, affected version/commit, and reproduction steps.

If private reporting is unavailable, open a minimal public issue asking a
maintainer to enable it — without any exploit details.

### Do not include in a public issue

- API keys, tokens, certificates, or provisioning profiles.
- Full terminal transcripts or agent conversation content.
- Security-scoped bookmarks or absolute personal paths.
- Screenshots containing private file names or commands.

## Supported versions

NotchDeck is pre-1.0 and under active development. Security fixes target the
`main` branch. There is no long-term-support branch yet.

| Version | Supported |
| ------- | --------- |
| `main`  | ✅        |
| tagged pre-releases | best-effort |

## Security model

### Local-only

- No telemetry, no analytics, no cloud sync.
- The agent bridge is a **Unix-domain socket** under the user's Application
  Support directory (0700 dir, 0600 socket). No TCP/IP port is opened.
- Only sanitized event metadata crosses the socket — never full prompts, tokens,
  or environment variables. Command summaries are redacted where implemented.

### Agent hooks — threat considerations

- NotchDeck installs **command hooks** into the Claude Code / Codex config. The
  installer marks its own entries, replaces stale NotchDeck-managed entries,
  preserves unrelated user/plugin hooks, and writes a timestamped backup.
- Approvals are correlated to the **exact live request** over the same open
  socket connection; a decision cannot be routed to the wrong request.
- NotchDeck **never** simulates keystrokes, pastes commands, or injects TTY
  input. "Focus Terminal" only raises an existing tab — it never runs a command
  or creates a session.

### Module capability model

Community modules are **compiled into** NotchDeck through reviewed pull requests.
There is **no runtime loading of arbitrary unsigned bundles, dylibs, or
downloaded code** in the current model.

- Every module declares the sensitive capabilities it needs
  (`ModuleCapability`), and receives access to **only** those through its
  `ModuleContext`.
- Modules cannot obtain raw approval sockets, unrestricted shell execution, or
  arbitrary filesystem access.
- Capability declarations are part of PR review (see
  `docs/modules/MODULE_REVIEW_GUIDELINES.md`).

### No arbitrary command execution

NotchDeck does not execute user- or module-supplied shell commands. The bundled
`notchdeck-agent-hook` helper only forwards sanitized hook events and relays an
Allow/Deny decision back to the CLI in the provider's documented schema.

## Roadmap (not yet implemented)

Signed and/or sandboxed external extensions are a **future** goal. They are not
implemented today. Do not assume runtime plugin isolation exists yet.
