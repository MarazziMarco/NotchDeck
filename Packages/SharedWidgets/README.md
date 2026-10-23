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

## Productivity cards

Five additional widgets work standalone and share state locally when both apps are
installed. Use the gear to flip a card, edit its draft and press **Save** at the
bottom to apply it and return to the front. Cancel and × discard the draft.
Placement and widget size remain specific to each app.

- **File shelf** (`file-shelf.json`, `FileShelf/`): drop files or folders, add via
  the + button, open, reveal in Finder or drag out. Settings choose references
  or persistent copies, ordering and file sizes. Originals stay in place when
  added through the shared card; removing a reference leaves its original alone.
  Explicit removal of a stored copy sends it to Trash. Committed orphan copies
  are recovered on next opening. The existing NotchDeck expanded shelf retains
  its explicit move/restore workflow; legacy staged paths remain valid.
- **Pomodoro / Focus** (`focus.json`): shared session timestamps, pause/resume,
  reset, skip and completion count. Settings choose title, focus and break
  lengths, long-break cycle, automatic advance, completion sound and color.
  Both apps can control the same session; only one advances it at completion.
- **Music** (`music.json`): Music.app or Spotify metadata and transport controls.
  Explicitly connect once; macOS may request Automation access. Settings choose
  player, connection and artwork. A short shared lease ensures only one app polls
  the player and executes a command. Other players are not supported. Spotify
  supplies artwork; Music falls back to the music-note artwork.
- **Countdown** (`countdown.json`): title, exact date/time, symbol, color and
  seconds display. Dates use the Mac's local timezone; expired values stop at zero.
- **Habits** (`habits.json`): up to 12 routines with name, symbol, color, daily
  target and selected weekdays. Check-ins and streaks survive relaunch, use local
  calendar days and are retained when card settings change. Deleting a routine
  and saving removes its history.

Native NotchDeck Focus, music live activities and file-shelf actions use these
same records. Countdown and Habits appear in NotchDeck's module catalog under
More; enable/add them to the desired surface. Existing shelf and timer records
are imported once without moving the user's files.

`swift test` covers storage races, timer coordination, shelf copy/recovery,
calendar-day habits, music command ownership and offscreen card rendering.
Rendering tests write front/back PNG previews to `/private/tmp/productivity-*.png`.
