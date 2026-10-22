# Timetable Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an "Orario" notch workspace that shows a university timetable imported from a `notchdeck-timetable` JSON file, with per-course notes, per-lesson notes, exams and Maps links.

**Architecture:** A built-in workspace module (same pattern as FaceKey) under `NotchDeck/Modules/Timetable/`. Pure value types + pure logic (import/validation, schedule) are unit-tested; a `@MainActor` store persists timetable + user data with `JSONFileStore`; SwiftUI views render the workspace and the Settings section. Spec: `docs/superpowers/specs/2026-10-22-timetable-workspace-design.md`.

**Tech Stack:** Swift 5, SwiftUI, AppKit (NSOpenPanel, NSWorkspace), XCTest, XcodeGen (`project.yml` globs `NotchDeck/` — new files need `xcodegen generate`).

**Commands:**
- Regenerate project: `xcodegen generate`
- Run one test class: `xcodebuild -project NotchDeck.xcodeproj -scheme NotchDeck -destination 'platform=macOS' test -only-testing:NotchDeckTests/<Class> 2>&1 | grep -E "Executed [0-9]+ tests, with.*seconds$|TEST (SUCCEEDED|FAILED)|error:|failed \("`
- Full suite: same without `-only-testing`.

---

### Task 1: Models + import/validation

**Files:**
- Create: `NotchDeck/Modules/Timetable/TimetableModels.swift`
- Create: `NotchDeck/Modules/Timetable/TimetableImport.swift`
- Test: `NotchDeckTests/TimetableImportTests.swift`

Types:
- `Weekday: String, Codable, CaseIterable { mon…sun }` with `isoIndex` (1…7), `init?(date:calendar:)`, `shortLabel`.
- `ClockTime: Codable, Comparable, Hashable` (minutes since midnight), `init?(_ "HH:mm")`, `text`, encodes as "HH:mm".
- Wire: `TimetableFile` (`format`, `version`, `title?`, `term?{start,end}`, `locations?`, `courses`, `lessons`), all Codable with optional fields.
- Validated: `Timetable { title, term: DateInterval?, locations: [Location], courses: [Course], lessons: [Lesson] }`; `Course { id, name, short, professor?, group?, colorHex? }`; `Lesson { id: UUID, courseID, day, start, end, room?, locationID? }`.
- `TimetableImport.parse(_ data: Data) -> Result<Timetable, TimetableImportError>`; `TimetableImportError.messages: [String]`.

Tests (write first, see them fail, then implement):
- valid file → counts, derived `short` when missing, lessons sorted by day/start.
- wrong `format` / `version` → error mentions it.
- malformed JSON → single readable error.
- bad time, start ≥ end, unknown day, unknown course, unknown location, duplicate course id, bad colour, bad term dates / start > end → each produces `lessons[i]: …`/`courses[i]: …` messages; all collected (not first-only).

Commit: `feat(timetable): file format, models and validation`

### Task 2: Schedule logic

**Files:**
- Create: `NotchDeck/Modules/Timetable/TimetableSchedule.swift`
- Test: `NotchDeckTests/TimetableScheduleTests.swift`

API (`enum TimetableSchedule`, pure, takes `Calendar` + `Date`):
- `lessons(on date:, in timetable:, followed: Set<String>, calendar:) -> [Lesson]` — empty outside `term`, filtered by followed, sorted.
- `status(at now:, ...) -> NowStatus { current: Lesson?, minutesLeft: Int?, next: Occurrence? }` where `Occurrence { lesson, date (start Date) }`, `next` searches up to 14 days ahead (respecting term).
- `upcomingOccurrences(of courseID:, from:, count:, ...) -> [Occurrence]`.
- `hourRange(for lessons:) -> ClosedRange<Int>` (floor of earliest start…ceil of latest end; default 8…18 when empty).
- `visibleDays(for lessons:) -> [Weekday]` (mon–fri + sat/sun only if used).
- `acronym(_ name:) -> String` (initials of words > 3 chars or capitalised, max 5).
- `colorIndex(for courseID:, among ids:) -> Int` (stable: sorted index mod palette).
- `mapsURL(room:, location:) -> URL?`.
- `dayKey(_ date:, calendar:) -> String` ("yyyy-MM-dd") for lesson notes.

Tests: boundaries (exactly at start = current; exactly at end = not current; between lessons → next today; Friday evening → next Monday; weekend; empty; outside term → nothing; followed filter), hour range, visible days, acronym, colour stability, maps URL fallbacks, upcoming occurrences count/order.

Commit: `feat(timetable): schedule logic`

### Task 3: Store

**Files:**
- Create: `NotchDeck/Modules/Timetable/TimetableStore.swift`
- Test: `NotchDeckTests/TimetableStoreTests.swift`

`TimetableState: Codable { timetable: Timetable?, userData: [String: CourseUserData] }`;
`CourseUserData: Codable { followed: Bool, note: String, lessonNotes: [String: String], exams: [Exam] }`;
`Exam: Codable, Identifiable { id, date, kind: ExamKind(exam/midterm/deadline), note }`.

`@MainActor final class TimetableStore: ObservableObject` with `init(store: JSONFileStore<TimetableState>)`:
`importFile(_ data:) -> Result<Int, TimetableImportError>` (replace timetable; new ids followed = no groups in file; keep existing user data), `clear()`, `isFollowed`, `setFollowed`, `followedIDs`, `note/setNote`, `lessonNote/setLessonNote(courseID:dayKey:)` (empty string removes), `exams(for:)`, `upsertExam`, `deleteExam`, `upcomingExams(from:)`, `addLesson`, `updateLesson`, `deleteLesson`, `course(id:)`, `location(id:)`. Saves synchronously on each mutation (tiny file).

Tests (temp-dir file): import persists and reloads; re-import keeps notes for surviving ids and keeps dormant data; follow defaults (groups vs no groups); lesson note empty-string removal; exam upsert/delete/sort; lesson CRUD.

Commit: `feat(timetable): persistent store`

### Task 4: Module + workspace wiring

**Files:**
- Create: `NotchDeck/Modules/Timetable/TimetableModule.swift`
- Modify: `NotchDeck/Notch/NotchStateMachine.swift` (add `.timetable`)
- Modify: `NotchDeck/App/AppState.swift` (`timetableWorkspaceEnabled`, sink, `availableFace`, `availableFaces`, `toggleFace` guard)
- Modify: `NotchDeck/Settings/SettingsStore.swift` (`timetableWorkspaceEnabled`)
- Modify: `NotchDeck/Notch/NotchGeometryService.swift` (width)
- Modify: `NotchDeck/Notch/ExpandedNotchView.swift` (segment + content)
- Modify: `NotchDeck/App/AppEnvironment.swift` (own + inject `TimetableStore`)
- Modify: `NotchDeck/Settings/ModulesScreen.swift` (catalog entry + settings section, also FaceKey)
- Test: `NotchDeckTests/TimetableModuleTests.swift`

Descriptor: `built-in.timetable`, "Timetable", `calendar`, `.workspace` + `.settingsSection`, no capabilities, `defaultEnabled: false`, `hasSettings: true`.

Tests: descriptor; `isEnabled` default false / toggled true; catalogue routing (not Home, not More); AppState: enabling shows `.timetable` in `availableFaces`, disabling while on `.timetable` returns to `.utilities`, persisted `.timetable` with module off starts on `.utilities`.

Commit: `feat(timetable): workspace module wiring`

### Task 5: Workspace UI

**Files:**
- Create: `NotchDeck/Modules/Timetable/TimetableWorkspaceView.swift` (Today column, week grid, empty states)
- Create: `NotchDeck/Modules/Timetable/TimetableCourseSheet.swift` (course detail: lessons + Maps, fixed note, next-lesson notes, exams)

`TimelineView(.periodic(from: .now, by: 30))` drives "now". Build + manual run.

Commit: `feat(timetable): notch workspace UI`

### Task 6: Settings UI

**Files:**
- Create: `NotchDeck/Modules/Timetable/TimetableSettingsView.swift` (import via NSOpenPanel, errors list, followed toggles grouped, lesson list with add/edit/delete, clear)

Commit: `feat(timetable): settings section`

### Task 7: FaceKey copy + catalogue fix, docs, data file

- FaceKey: "installed" → "running" in `FaceKeyModuleSettings`, `AppState`, `SettingsStore` comments; `ModuleSurface.workspace` doc. (Catalogue entry done in Task 4.)
- `docs/modules/TIMETABLE.md` documenting the format.
- Generate `~/Desktop/orario-control-engineering-2026-27.json` from the xlsx (scratchpad script), validate it by importing through a test-only parse run.
- Full test suite + Debug build green.

Commit: `fix(facekey): accurate running-state copy` and `docs(timetable): file format`.
