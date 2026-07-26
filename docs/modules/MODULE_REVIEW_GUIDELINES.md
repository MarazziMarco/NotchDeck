# Module Review Guidelines

Reviewers use this checklist before merging a community module. The goal is a
safe, coherent, privacy-respecting app.

## Identity & metadata

- [ ] Unique reverse-DNS `identifier`; does not collide with an existing module.
- [ ] `displayName`, `summary`, semantic `version`, and `author` are present and
      accurate.
- [ ] `category`, `iconSystemName`, `surfaces`, and `hasSettings` match what the
      module actually does.
- [ ] `defaultEnabled` is `false` for community/example modules.

## Capabilities (most important)

- [ ] The module declares **only** the capabilities it uses.
- [ ] No attempt to reach services outside the declared capabilities.
- [ ] Sensitive capabilities (`camera`, `screenRecording`, `downloadsAccess`,
      `selectedFolderAccess`, `terminalSessionEvents`, `agentApprovalEvents`,
      `mediaControl`, `notifications`, `backgroundExecution`) are individually
      justified in the PR description.
- [ ] `agentApprovalEvents` / `terminalSessionEvents` receive extra scrutiny —
      these touch the approval pipeline.

## Security

- [ ] No runtime code loading, no shell execution, no arbitrary filesystem
      access.
- [ ] No network calls unless documented and necessary.
- [ ] No secrets, tokens, or transcripts persisted or logged.
- [ ] No use of private APIs.

## UI & UX

- [ ] Fits the dark NotchDeck surface; no bright borders / loud gradients.
- [ ] Compact content shares the single rounded capsule; no rectangular
      state-specific background; content clears the physical-notch zone.
- [ ] Respects Reduce Motion; animations are short.

## Accessibility & localization

- [ ] Accessibility labels for controls and glyphs.
- [ ] English base strings; ready to localize; no mixed-language UI.

## Quality

- [ ] Debug **and** Release build green.
- [ ] Tests included for pure logic and registry registration.
- [ ] Deterministic behavior; no reliance on `Date.now`/randomness in tests.

## Documentation

- [ ] README/metadata explain what it does and which permissions it needs.
- [ ] Screenshots for any UI change (privacy-scrubbed).

A module that cannot pass the capability and security sections will not be
merged, regardless of how useful it is.
