# Quick Note Colours Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Quick Note a brighter classic-yellow default, six accessible preset swatches, and a persistent native custom colour.

**Architecture:** Keep the existing `NoteColor` preset as the backward-compatible stored choice and add an optional Codable sRGB value as the active custom override. Resolve paper and contrast-aware ink through one shared model consumed by both Quick Note renderers. Settings mutates the same `AppSettings` authority used throughout the app.

**Tech Stack:** Swift 5, SwiftUI, AppKit `NSColor`, Codable settings, XCTest, macOS 14.

## Global Constraints

- Do not change Home layout, eligibility, ordering, sizing, or routing.
- Do not add dependencies or a second settings store.
- Classic Yellow is the default and is close to `#FFE56B`.
- Presets are Classic Yellow, Pink, Green, Blue, Orange, and Purple.
- Existing persisted Yellow/Pink/Green/Blue choices remain valid.
- Custom paper colours must select readable dark or light ink automatically.

---

### Task 1: Paper colour model and persistence

**Files:**
- Modify: `NotchDeck/Shared/Appearance.swift`
- Modify: `NotchDeck/Settings/AppSettings.swift`
- Test: `NotchDeckTests/IterationNineTests.swift`

**Interfaces:**
- Produces: `NotePaperColor`, `NoteColor.paperComponents`, `AppSettings.resolvedNotePaperColor`, `AppSettings.selectNotePreset(_:)`, and `AppSettings.selectCustomNoteColor(_:)`.
- Consumes: existing `NoteColor` and `AppSettings` Codable persistence.

- [ ] **Step 1: Write failing model tests**

```swift
func testClassicYellowIsBrightPostItYellow() {
    XCTAssertEqual(NoteColor.yellow.paperComponents,
                   NotePaperColor(red: 1.0, green: 0.898, blue: 0.42))
}

func testCustomColourOverridesPresetAndRoundTrips() throws {
    var settings = AppSettings()
    let custom = NotePaperColor(red: 0.1, green: 0.2, blue: 0.3)
    settings.selectCustomNoteColor(custom)
    let decoded = try JSONDecoder().decode(
        AppSettings.self,
        from: JSONEncoder().encode(settings)
    )
    XCTAssertEqual(decoded.resolvedNotePaperColor, custom)
}

func testSelectingPresetClearsCustomOverride() {
    var settings = AppSettings()
    settings.selectCustomNoteColor(.init(red: 0.1, green: 0.2, blue: 0.3))
    settings.selectNotePreset(.pink)
    XCTAssertNil(settings.noteCustomColor)
    XCTAssertEqual(settings.resolvedNotePaperColor, NoteColor.pink.paperComponents)
}

func testDarkCustomPaperUsesLightInk() {
    XCTAssertTrue(NotePaperColor(red: 0.05, green: 0.05, blue: 0.05).usesLightInk)
    XCTAssertFalse(NotePaperColor(red: 1.0, green: 0.9, blue: 0.4).usesLightInk)
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
xcodebuild test -project NotchDeck.xcodeproj -scheme NotchDeck \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:NotchDeckTests/QuickNoteTests
```

Expected: compilation fails because `NotePaperColor` and the selection methods do not exist.

- [ ] **Step 3: Implement the minimal colour model**

Add a clamped Codable `NotePaperColor` containing `red`, `green`, `blue`, and
`opacity`; expose SwiftUI paper/ink colours and WCAG-style relative luminance.
Extend `NoteColor` with Orange and Purple and replace the muted yellow with
`(1.0, 0.898, 0.42)`.

Add:

```swift
var noteCustomColor: NotePaperColor? = nil

var resolvedNotePaperColor: NotePaperColor {
    noteCustomColor ?? noteColor.paperComponents
}

mutating func selectNotePreset(_ preset: NoteColor) {
    noteColor = preset
    noteCustomColor = nil
}

mutating func selectCustomNoteColor(_ colour: NotePaperColor) {
    noteCustomColor = colour.clamped
}
```

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the Task 1 command. Expected: all Quick Note tests pass.

- [ ] **Step 5: Commit**

```bash
git add NotchDeck/Shared/Appearance.swift NotchDeck/Settings/AppSettings.swift \
  NotchDeckTests/IterationNineTests.swift
git commit -m "feat: add persistent Quick Note paper colours"
```

---

### Task 2: Preset swatches and custom ColorPicker

**Files:**
- Modify: `NotchDeck/Settings/SettingsSectionsA.swift`
- Modify: `NotchDeck/Modules/Dashboard/EditorialWidgets.swift`
- Modify: `NotchDeck/Modules/Dashboard/WidgetVisuals.swift`
- Test: `NotchDeckTests/IterationNineTests.swift`

**Interfaces:**
- Consumes: `AppSettings.resolvedNotePaperColor`, `selectNotePreset(_:)`, and `selectCustomNoteColor(_:)`.
- Produces: one shared resolved paper/ink appearance in all Quick Note views and an accessible settings palette.

- [ ] **Step 1: Write failing selection and palette tests**

```swift
func testQuickNotePaletteHasSixNamedPresets() {
    XCTAssertEqual(NoteColor.allCases.map(\.label),
                   ["Classic Yellow", "Pink", "Green", "Blue", "Orange", "Purple"])
}

func testLegacyPresetRemainsActiveWithoutCustomOverride() {
    var settings = AppSettings()
    settings.noteColor = .blue
    settings.noteCustomColor = nil
    XCTAssertEqual(settings.resolvedNotePaperColor, NoteColor.blue.paperComponents)
}
```

- [ ] **Step 2: Run tests and verify RED**

Run the Task 1 test command. Expected: palette-name assertion fails until the
new labels and cases are present.

- [ ] **Step 3: Implement settings controls and shared rendering**

Replace the text-only colour Picker with six compact buttons containing real
paper-colour swatches, a checkmark/stroke for the active preset, and
module-specific accessibility labels. Add a native `ColorPicker("Custom
colour", selection:)` whose setter converts the selected `Color` to normalized
sRGB and calls `selectCustomNoteColor`.

Update `EditorialNote` and `QuickNoteWidget` to use:

```swift
private var paperColour: NotePaperColor {
    settings.settings.resolvedNotePaperColor
}
```

Use `paperColour.color` for paper and `paperColour.inkColor` for text, tint,
placeholder, fold, and decoration.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the Task 1 command. Expected: all focused tests pass.

- [ ] **Step 5: Commit**

```bash
git add NotchDeck/Settings/SettingsSectionsA.swift \
  NotchDeck/Modules/Dashboard/EditorialWidgets.swift \
  NotchDeck/Modules/Dashboard/WidgetVisuals.swift \
  NotchDeckTests/IterationNineTests.swift
git commit -m "feat: add Quick Note colour palette and picker"
```

---

### Task 3: Regression and visual verification

**Files:**
- Modify only if a test exposes a scoped defect.

**Interfaces:**
- Consumes: completed Tasks 1 and 2.
- Produces: verified Debug/Release application and clean Git state.

- [ ] **Step 1: Run focused tests**

```bash
xcodebuild test -project NotchDeck.xcodeproj -scheme NotchDeck \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:NotchDeckTests/QuickNoteTests
```

- [ ] **Step 2: Run complete Debug suite**

```bash
xcodebuild test -project NotchDeck.xcodeproj -scheme NotchDeck \
  -configuration Debug -destination 'platform=macOS'
```

- [ ] **Step 3: Run Debug and universal Release builds**

```bash
xcodebuild build -project NotchDeck.xcodeproj -scheme NotchDeck \
  -configuration Debug -destination 'platform=macOS'
xcodebuild build -project NotchDeck.xcodeproj -scheme NotchDeck \
  -configuration Release -destination 'generic/platform=macOS' \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO
```

- [ ] **Step 4: Inspect the running app**

Verify Classic Yellow, every preset, a light custom colour, a dark custom
colour, immediate Home updates, persistence after relaunch, and readable ink.
Confirm Home layout and the compact/expanded notch geometry are unchanged.

- [ ] **Step 5: Inspect and publish**

```bash
git diff --check
git status --short
git push origin main
```

