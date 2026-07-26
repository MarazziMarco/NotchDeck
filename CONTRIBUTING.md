# Contributing to NotchDeck

Thanks for your interest! NotchDeck is an early-stage, open-source macOS app.
Contributions are welcome via pull requests.

## Prerequisites

- macOS 14+ and Xcode 15+.
- [XcodeGen](https://github.com/yonabc/XcodeGen): `brew install xcodegen`
  (`project.yml` is authoritative; the `.xcodeproj` is generated and git-ignored).

## Generate, build, test

```bash
xcodegen generate

# Debug
xcodebuild -project NotchDeck.xcodeproj -scheme NotchDeck \
  -configuration Debug -destination 'platform=macOS' build

# Tests
xcodebuild -project NotchDeck.xcodeproj -scheme NotchDeck \
  -destination 'platform=macOS' test

# Release (unsigned, local)
xcodebuild -project NotchDeck.xcodeproj -scheme NotchDeck \
  -configuration Release -destination 'platform=macOS' build
```

Both Debug **and** Release must build, and the full test suite must pass, before
a PR is ready.

## Conventions

- Match the surrounding code's style, naming, and comment density.
- Keep pure logic (formatters, reducers, filters, geometry) in
  `nonisolated`/`static` functions so it is unit-testable without the panel.
- Tests must be deterministic — do not rely on `Date.now`/randomness.
- English is the base language for user-facing strings; do not mix languages in
  one screen.
- Never commit secrets, tokens, certificates, provisioning profiles, absolute
  personal paths, build output, `.DS_Store`, logs, sockets, or user data.

## Two contribution paths

### Feature / fix contribution

Changes to the app itself (a widget, the agent bridge, geometry, etc.). Open an
issue for anything non-trivial, then a PR with tests and screenshots for UI
changes.

### Module contribution

A new community module. Read the module guides first:

- [docs/modules/CREATING_A_MODULE.md](docs/modules/CREATING_A_MODULE.md)
- [docs/modules/MODULE_REVIEW_GUIDELINES.md](docs/modules/MODULE_REVIEW_GUIDELINES.md)

Modules must **declare the capabilities they use**; reviewers verify that a
module cannot reach services beyond what it declared.

## Pull-request expectations

Complete the PR template checklist:

- [ ] Debug build passes.
- [ ] Release build passes.
- [ ] Tests pass (and new tests added where relevant).
- [ ] Screenshots for UI changes (privacy-scrubbed).
- [ ] Permissions impact described.
- [ ] Privacy impact described.
- [ ] Module capabilities declared (if a module).
- [ ] Localization considered.
- [ ] Accessibility considered.

## Screenshot policy

Use real app screenshots. Remove personal terminal commands, usernames, local
paths, and sensitive file names. Do not enable DEBUG overlays. Do not invent
screenshots.

## Privacy & no-secrets requirement

By opening a PR you confirm it contains no secrets and adds no telemetry or
network calls without explicit discussion. Sensitive metadata handling must stay
sanitized.

## Code of Conduct

Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md). Report
security issues privately (see [SECURITY.md](SECURITY.md)).
