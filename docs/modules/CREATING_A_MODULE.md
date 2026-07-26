# Creating a Module

A NotchDeck module is a small Swift type compiled into the app. This guide walks
through a minimal module.

## 1. Required files

At minimum:

- one Swift file implementing `NotchDeckModule` under
  `NotchDeck/Modules/Community/YourModule/`;
- a test file under `NotchDeckTests/`.

## 2. Implement the protocol

```swift
import SwiftUI

struct HelloModule: NotchDeckModule {
    static let descriptor = ModuleDescriptor(
        identifier: "com.yourname.hello",         // reverse-DNS, globally unique
        displayName: "Hello",
        summary: "A tiny greeting card.",
        version: "1.0.0",                          // semantic version
        author: "Your Name",
        category: .productivity,
        iconSystemName: "hand.wave",               // prefer SF Symbols
        defaultEnabled: false,                     // community modules ship disabled
        surfaces: [.homeCard],
        capabilities: [],                          // declare ONLY what you need
        hasSettings: false)

    init() {}

    func homeCard(context: ModuleContext) -> AnyView? {
        AnyView(Text("Hello, NotchDeck").font(.headline).padding())
    }
}
```

## 3. Identifier conventions

- Reverse-DNS, lowercase, stable: `com.<you>.<module>`.
- Never reuse a built-in id (`com.notchdeck.*` is reserved for first-party).
- If you must rename, register an alias for the old id in the registry.

## 4. Declare capabilities honestly

Request only what you use. A module that shows text needs **no** capability. If
you read the selected Downloads folder, declare `.downloadsAccess`; the
`ModuleContext` grants access to **only** what you declared. Undeclared access
is not available.

## 5. UI constraints

- Home cards must render in a small card frame; do not assume a fixed pixel size.
- Respect the dark NotchDeck surface; avoid loud gradients and bright borders.
- Support Reduce Motion; keep animations short.

## 6. Compact-notch constraints

- Compact live activities share the single rounded capsule; do **not** draw a
  state-specific rectangular background.
- Keep content out of the physical-notch exclusion zone (the wings only).
- Text in a wing must not truncate into an awkward fragment — use whole
  semantic variants for narrow widths.

## 7. Accessibility & localization

- Provide `accessibilityLabel`s for controls and glyphs.
- Use English as the base language; keep user-facing strings ready to localize.

## 8. Testing

- Put pure logic (formatters, reducers) in `static` functions and test them.
- Register the module in a `CommunityModuleRegistry` in a test and assert its
  descriptor, capabilities, and default-enabled state. See
  `ModuleArchitectureTests.swift`.

## 9. Privacy

- No telemetry, no network calls unless the feature genuinely requires it and it
  is documented and reviewed.
- Never persist secrets, tokens, or full transcripts.

## 10. Prohibited behavior

- No runtime code loading, no shell execution, no arbitrary filesystem access.
- No reading of approval sockets or agent internals unless you declared the
  relevant capability and it passed review.

## 11. Pull-request process

1. Read [MODULE_REVIEW_GUIDELINES.md](MODULE_REVIEW_GUIDELINES.md).
2. Open a **Community module proposal** issue first for anything non-trivial.
3. Submit a PR: Debug + Release build green, tests included, capabilities
   declared, screenshots for UI, and the PR checklist completed.
