# Timetable workspace — design

## Goal

A dedicated, interactive notch workspace ("Orario") for a university weekly
timetable: today's lessons with live current/next status, a colour-block week
grid, and a per-course sheet with a fixed note, per-lesson notes, exams/deadlines
and an "open room in Maps" action. The timetable is imported from a JSON file in
NotchDeck's own format; light lesson editing happens in Settings.

## Scope

In: workspace face, own JSON format + import, course selection ("followed"),
course sheet (fixed note, per-lesson notes, exams, Maps), lesson add/edit/delete
in Settings, local persistence, tests, a one-off JSON generated from the user's
xlsx timetable, and fixing stale FaceKey copy ("installed" → "running").

Out (YAGNI): compact-notch lesson alerts, native xlsx import, sync with any other
app, network access of any kind.

## Data format — `notchdeck-timetable` v1

```json
{
  "format": "notchdeck-timetable",
  "version": 1,
  "title": "Control Engineering · I semestre 2026/27",
  "term": { "start": "2026-09-28", "end": "2027-01-15" },
  "locations": [
    { "id": "diag", "name": "DIAG", "address": "Via Ariosto 25, Roma" }
  ],
  "courses": [
    { "id": "amr", "name": "Autonomous and Mobile Robotics", "short": "AMR",
      "professor": "Oriolo", "group": "2° anno", "color": "#20C997" }
  ],
  "lessons": [
    { "course": "amr", "day": "mon", "start": "10:00", "end": "12:00",
      "room": "B2", "location": "diag" }
  ]
}
```

- Required: `format` (exactly `notchdeck-timetable`), `version` (1),
  `courses[].id`, `courses[].name`, `lessons[].course/day/start/end`.
- Optional: `title`, `term` (both dates `yyyy-MM-dd`; outside the term "Today"
  shows no lessons), `locations` (`id`, `name`, optional `address`),
  `courses[].short` (else derived acronym), `professor`, `group` (groups courses
  in the "followed" picker), `color` (`#RRGGBB`, else stable palette colour),
  `lessons[].room`, `lessons[].location` (location id).
- `day` ∈ `mon…sun`; times `HH:mm`, `start < end`.
- Validation is all-or-nothing with readable messages, e.g.
  `lessons[3]: course "xyz" is not defined`. Duplicate course/location ids,
  unknown location ids, bad colours and bad dates are errors.

## Architecture

New built-in workspace module, same pattern as FaceKey, under
`NotchDeck/Modules/Timetable/`:

| File | Responsibility |
|---|---|
| `TimetableModels.swift` | Codable value types: `TimetableFile` (wire format), `Weekday`, `ClockTime`, `Timetable` (validated), `Course`, `Lesson`, `Location`, user data (`CourseUserData`: followed, note, lesson notes by date, exams) |
| `TimetableImport.swift` | Decode + validate a file into a `Timetable` or a list of errors. Pure. |
| `TimetableSchedule.swift` | Pure logic: lessons on a date (respecting term + followed), current/next lesson and minutes remaining, grid hour range, acronym, stable colour, Maps URL |
| `TimetableStore.swift` | `@MainActor ObservableObject`; persists `timetable.json` via `JSONFileStore`; import (replace timetable, keep user data by course id), lesson CRUD, followed toggle, notes, exams |
| `TimetableModule.swift` | Descriptor (`built-in.timetable`, `.workspace` + `.settingsSection`, no capabilities, default disabled) and enablement |
| `TimetableWorkspaceView.swift` | Notch UI: Today column + week grid + course sheet |
| `TimetableSettingsView.swift` | Import button (NSOpenPanel), followed-course toggles grouped by `group`, lesson list with add/edit/delete |

Wiring: `NotchFace.timetable`; `AppState.timetableWorkspaceEnabled` with the same
normalisation rule as FaceKey (disabling while selected → Utilities);
`FaceSwitcher` segment "Orario" (`calendar`); `ExpandedNotchView` content case;
`NotchGeometryService.expandedWidth` (760); Settings → Modules entry;
`AppEnvironment` owns the `TimetableStore`.

User data is keyed by course id. Re-import replaces courses + lessons; user data
for ids no longer present is retained (dormant) and reappears if the id returns.
A newly seen course is followed by default only when the timetable has no
`group`s; otherwise courses start unfollowed so the user picks theirs. (An empty
followed set shows a "choose your courses in Settings" hint.)

## Notch UI (~760 × 280 pt)

- **Today (left, ~250 pt):** date header; current lesson highlighted with "ends
  in N min" + progress; next lesson "in 1 h 10"; rest of today. No lessons →
  "No lessons today · next Thu 08:00 AMR". Rows tap → course sheet.
- **Week (right):** Mon–Fri columns (Sat/Sun only if used), hour rows spanning
  the earliest start to the latest end of followed lessons, colour blocks with
  acronym + start time, today's column tinted, a "now" line, a dot on blocks
  whose next occurrence has a lesson note. Block tap → course sheet.
- **Course sheet:** replaces content with a "‹ Orario" back button: name,
  professor, weekly lessons (room, location, Maps button), fixed note (multi-line
  field), next 4 lesson dates each with an inline note field, exams list with
  "in N days" countdown and add/edit/delete (date, kind: Exam / Midterm /
  Deadline, note).
- Text fields use the existing editing flag so the panel stays open and becomes
  key while typing.

Maps: `address` of the lesson's location if present, else `<location name> Roma`,
else `<room> Sapienza Roma`; opened with `https://maps.apple.com/?q=…` via
`NSWorkspace` (no network call by NotchDeck itself).

Strings are user-facing English base like the rest of the app.

## Persistence & privacy

`~/Library/Application Support/NotchDeck/timetable.json` (timetable + user data).
Nothing leaves the Mac; no capability required.

## Testing

XCTest: import happy path + every validation error; acronym/colour stability;
lessons on a date across term bounds and followed filter; current/next at exact
boundaries (start, end, between lessons, weekend, empty); grid hour range;
store re-import retains user data; lesson CRUD; Maps URL building; AppState
face normalisation when the module is disabled; catalogue routing (workspace →
neither Home nor More).

## Deliverable outside the repo

`~/Desktop/orario-control-engineering-2026-27.json`, generated from the xlsx:
both years (`group` "1° anno" / "2° anno"), consecutive hours of the same course
on the same day/room merged into one lesson, `term` omitted.
