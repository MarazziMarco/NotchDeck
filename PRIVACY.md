# Privacy

NotchDeck is designed to keep everything on your Mac.

## What NotchDeck does NOT do

- No telemetry or analytics
- No accounts or sign-in to NotchDeck
- No backend or servers of its own
- No third-party crash reporting
- No clipboard upload
- No camera upload, and no recording
- No collection of agent prompts or output
- No cloud sync

## Local data

Stored under `~/Library/Application Support/NotchDeck/`:

- **Settings** (`UserDefaults`, one JSON blob) — preferences and toggles.
- **Clipboard history** (`clipboard-history.json`) — local only. Images are
  downscaled before storage. Items marked *transient* / *concealed* by their
  source (e.g. password managers) are never captured. You can pause monitoring,
  enable a temporary private mode, delete single items, or clear everything.
- **File Shelf** (`file-shelf.json`) — only security-scoped bookmarks/paths.
  Originals are never moved or copied.
- **Pomodoro** (`pomodoro.json`) — timer state (absolute timestamps).
- **Agent sessions** (`agent-sessions.json`) — metadata for managed sessions
  (title, project path, status). No credentials.
- **Agent logs** (`Logs/agent-<id>.log`) — optional, size-bounded rotating logs.
  Disabled from Settings if you prefer. Every line is passed through a secret
  sanitizer before it is written.

## Camera

The Mirror module uses AVFoundation. The capture session starts only while the
module is visible and stops the instant it closes. There is no audio, no
recording, no frames written to disk, and no network. The macOS camera privacy
indicator is never hidden or bypassed.

## Coding agents

NotchDeck never stores API keys. Managed sessions reuse the authentication of
your installed `codex` / `claude` CLIs. Subprocesses are launched with argument
arrays (never a shell string), and NotchDeck only terminates processes it
started — never external ones.

## Secret sanitization

Before any command line, environment or output is written to a diagnostic log or
exported, `SecretSanitizer` redacts API keys, bearer tokens, `key=value`
secrets, cookies and common provider token shapes, and collapses your home
directory to `~`. This is best-effort defense-in-depth, not a guarantee.

## Accessibility

The optional external-window control uses the Accessibility API only to
enumerate accessible windows (title, PID, bundle id, frame, minimized state) and
to raise/activate them. It never reads screen pixels, never uses OCR, and never
injects synthetic keystrokes to drive agents.
