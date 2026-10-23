# SharedWidgets

Local data and reusable timetable views for LaunchPad and NotchDeck, on macOS 14+.
The canonical package is maintained in LaunchMe/SharedWidgets. NotchDeck vendors
an identical snapshot under Packages/SharedWidgets so each checkout builds on its
own. Run `scripts/sync-shared-widgets.sh` from LaunchMe after editing this package.
No source checkout or second app is required by the installed applications.

## Shared data

Records are stored under `~/Library/Application Support/MarazziWidgets/`:

- `quick-note.json`: title, text, paper color and one-time migration markers.
- `timetable.json`: courses, lessons, locations, semester, followed courses,
  course notes, lesson notes, exams and optionally a PDF document.

Each update acquires a filesystem lock, reloads the latest document, applies only
its mutation and commits atomically, with a readable backup. Live channels notice
changes from the other app. The archive survives app quit, widget removal and
uninstallation. App layouts and widget placements remain independent.

Existing NotchDeck timetable data is migrated once. Pre-existing quick notes from
both apps are retained: differing texts are combined with labeled separators.
Tests and previews accept an isolated directory and never use production records.

## Timetable imports

JSON accepts the `notchdeck-timetable` v1 format, a saved timetable state, or a
simple object with `title` and `events`. CSV accepts comma, semicolon or tab
separators, quoted cells, Italian/English column names and weekday names.
Required CSV columns: `giorno,inizio,fine,titolo` (or `day,start,end,title`).
Optional: `sigla,colore,aula,sede`. Times use `HH:mm`; overnight lessons must be
split into separate days. Colors use `#RRGGBB`.

JSON/CSV imports are validated and previewed before replacing the shared schedule.
PDFs are copied into the archive and displayed faithfully as paginated documents,
including scanned PDFs. PDF contents are not inferred as structured lessons.
Maximum input: 20 MB; PDF limit: 100 pages, no password.

Use `TimetableImporter.exampleJSON` and `exampleCSV` or download templates from
the timetable editor. Course filters and notes are shared; imported courses with
groups start unfollowed until the user selects the desired group/courses.

Run tests with `cd SharedWidgets && swift test`.

## Timetable presentations

LaunchPad uses four fixed layouts: day-only (2×2), compact week grid (3×2),
week grid (4×3) and overview with today's sidebar (6×4). The compact and regular
week modes never show the sidebar, regardless of the screen resolution.
These layouts all read the same schedule. NotchDeck can choose the presentation
that fits its own surfaces; no NotchDeck installation is required by LaunchPad.
