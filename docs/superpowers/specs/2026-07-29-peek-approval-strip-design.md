# Peek Approval Strip Design

## Scope and invariants

Phase 3 adds an event-driven approval presentation between Compact and Expanded:

`Compact → Peek → Expanded`

Peek is not another approval system. It is a projection of the existing
`AgentSession.approval` and `queuedApprovals` transactions. It does not install
hooks, start the bridge, encode provider responses, change trust, or infer
session liveness.

The terminal prompt and Peek represent the same correlated transaction at the
same time. The first valid answer wins. Local UI expiry disables NotchDeck's
decision controls and releases the helper to the already-available native flow;
it never emits Allow or Deny and never claims that Terminal has newly appeared.

The five Phase 1–2 commits remain the foundation:

- `d4bb9e0` — socket startup ownership-safe
- `376c83f` — bootstrap independent from diagnostics
- `68af78a` — versioned helper and legacy-path compatibility
- `7bcd3c9` — idempotent hook configuration and trust state
- `3ab1b23` — valid Codex hook document

## Presentation state

The existing dormant `.peeking` case becomes the approval Peek state. Production
hover currently opens Expanded directly, so no shipped hover-only state is being
removed.

`AppState` tracks whether an approval Peek is available, but does not retain a
copied transaction. The presentation coordinator derives a queue snapshot from
the authoritative agent store and retains only the selected session UUID and
transaction ID. Each render and action resolves that identity back against the
store.

The state machine rules are:

- a first presentable transaction changes Compact to Peek;
- a transaction arriving while Expanded leaves Expanded open;
- clicking the strip explicitly opens Expanded Agents;
- resolving, cancelling, or completing the visible transaction selects the
  next valid FIFO item immediately;
- removing the final transaction changes Peek to Compact;
- requesting Compact while a Peek transaction remains returns to Peek, not an
  empty Compact state;
- users cannot synthesize an empty Peek.

Compact Focus and Expanded Agents keep their existing rendering and behavior.

## Queue and correlation

The source queue is still:

`AgentSession.approval + AgentSession.queuedApprovals`

Per-session enqueue and promotion remain append/remove-first FIFO. The Peek
projection flattens the existing queues, removes duplicate helper transaction
IDs, and orders entries by the stored `receivedAt`. Equal timestamps use a
deterministic session UUID and per-session index tie-break; this is stable
ordering, not a claim about unobservable sub-timestamp arrival order.

The sole decision and deduplication key is
`PendingApproval.requestID`, which production ingest populates from the helper's
unique `transactionID`. `providerRequestID`, `toolUseID`, and `turnID` remain
provider correlation metadata. Provider-native fingerprints never own a socket
and never suppress a distinct helper invocation.

Peek actions call a transaction-specific coordinator API:

`session UUID + transaction ID + decision`

That API revalidates the exact current request, state, deadline, and in-flight
set before it changes state to `sending`. The bridge continues to encode and
deliver the existing provider response on the exact transaction socket.
Duplicate, stale, expired, queued, or already-sending clicks are rejected.

## Deadline and terminal-pending lifecycle

Peek reads `PendingApproval.actionDeadline` and `receivedAt`. It creates no
timer model and does not mutate either date. Progress is:

`clamp((deadline - now) / (deadline - receivedAt), 0...1)`

The absolute deadline remains the source of truth even if settings change or a
request waits behind another request.

At the cutoff, the bridge releases the helper without a decision and records
the transaction as terminal-pending. The item remains representable as
non-actionable with truthful `Respond in Terminal` wording. Terminal/provider
progress, cancellation, stop, session end, or authoritative terminal closure
removes the exact item and advances the queue. Expiry itself does not resolve
the request. Orphan cleanup, if needed, is bounded and applies only after the
session is authoritatively gone.

## Truthful action summaries and privacy

Current provider adapters already parse the real PermissionRequest payload, but
the helper currently discards its `tool_input` detail. Phase 3 extends only the
internal display metadata:

- Bash/shell requests use the real command;
- patch/edit/write requests name the operation and target;
- MCP requests name the server/tool and a useful target when present;
- other requests use the most specific safe action/target field available.

The existing sanitizer becomes the shared policy used by both the helper and
app. It strips control sequences, collapses whitespace, rejects raw JSON,
redacts common credential patterns, and caps display text. Peek never reads
prompts, environment variables, transcripts, or raw payload JSON.

A Debug-only payload-shape diagnostic records only sorted field names and value
types, including `tool_input` key names/types. It records no values, commands,
paths, prompts, tokens, or persistent provider identifiers. Real Claude and
Codex requests are used to confirm the current shapes before the final key
report.

## Peek content

The collapsed strip presents one logical request:

- provider mark and provider name;
- project/session display name;
- tool name;
- concise sanitized command or action;
- Deny, Allow, and Focus Terminal;
- `1/N` queue count when more than one item remains;
- a thin deadline progress bar on the lower edge.

Commands use a monospace face. The collapsed line truncates at the tail after
preserving the tool/action prefix. Hover expands only the SwiftUI surface to
show more summary text, working directory, and useful provider/session detail.

Deny and Allow have separated hit targets. Deny precedes Allow so Allow is not
at the natural pointer-entry edge. Controls become unavailable immediately when
the exact transaction enters resolution. No global Allow shortcut is added.

## Panel, focus, and hit testing

There remains one `NotchPanel` and one transparent hosting view. The panel keeps:

- `.nonactivatingPanel`;
- `becomesKeyOnlyIfNeeded = true`;
- `canBecomeMain = false`;
- `.statusBar`;
- `.canJoinAllSpaces`;
- `.fullScreenAuxiliary`;
- `.stationary`;
- `.ignoresCycle`;
- clear, non-opaque, shadowless hosting.

Compact and Peek never permit key focus. Expanded retains key eligibility for
real text input. Allow, Deny, and Focus Terminal order the panel without
activating NotchDeck.

The panel reserves one transparent host frame large enough for Compact, Peek
hover, and Expanded. Presentation changes animate the SwiftUI surface, not the
NSPanel frame. Screen/topology changes may reposition the host without
presentation animation.

The outer host is transparent; the shared `NotchSurface` and current content sit
inside one clipped visible container. Rendering and hit testing consume the
same visible rounded geometry. A defensive hosting-view hit test returns nil
outside it, while window-level `ignoresMouseEvents` is enabled whenever the
pointer is outside the interactive visible path so clicks reach other
applications. Hover activation geometry remains separate and forgiving.

## Display positioning

For approval Peek, the target display is the one with the greatest intersection
with the frontmost application's front window. If no usable window is found,
selection falls back to `NSScreen.main`, then the first available screen.

On a notched display the visible surface aligns to the physical top-center
housing using measured safe-area geometry. On a display without a notch it is a
top-center floating strip anchored below the menu-bar band using
`visibleFrame.maxY`; it never pretends a camera housing exists.

Compact and Expanded retain their existing visible geometry. The current panel
collection behavior keeps Peek available in every Space and as a full-screen
auxiliary window.

## Accessibility and motion

Peek is one accessibility group whose label contains provider, action, project
or session, and queue position. Each control has a consequence-specific label,
including provider and action. Expired state announces that NotchDeck controls
are unavailable and that the same request can still be answered in Terminal.

System Reduce Motion and the existing override disable nonessential appearance,
hover-height, and progress animations. The progress value still updates
truthfully without animated interpolation.

## Verification boundary

Pure tests cover queue projection, deduplication, exact-once actions, deadline
math, expiry, lifecycle removal, geometry, screen selection, hit policy,
accessibility strings, and Reduce Motion policy. Regression tests protect
Compact Focus, Expanded Agents, and bridge/installer state.

Unit tests cannot establish cross-process focus preservation, full-screen
visibility, Spaces behavior, menu-bar click-through, or real provider payload
shape. Those claims require the built application and real Claude/Codex
PermissionRequest flows. Any item that cannot be exercised is reported as
unverified and prevents merge to `main`.
