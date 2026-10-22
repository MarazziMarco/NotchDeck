# Timetable file format (`notchdeck-timetable` v1)

The Timetable workspace shows a weekly lesson timetable imported from a JSON
file (Settings → Timetable → Import Timetable…). The file stays on your Mac.

```json
{
  "format": "notchdeck-timetable",
  "version": 1,
  "title": "Control Engineering · I semestre 2026/27",
  "term": { "start": "2026-09-28", "end": "2027-01-15" },
  "locations": [
    { "id": "diag", "name": "DIAG", "address": "Via Ariosto 25, 00185 Roma" }
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

| Field | Required | Notes |
|---|---|---|
| `format` | yes | Exactly `notchdeck-timetable`. |
| `version` | yes | `1`. |
| `title` | no | Shown in Settings. |
| `term.start`, `term.end` | no | `yyyy-MM-dd`, inclusive. Outside the term, Today shows no lessons. |
| `locations[].id`, `.name` | yes, per location | `address` is optional and used for Apple Maps. |
| `courses[].id`, `.name` | yes, per course | Ids must be unique and stable: notes, exams and the "followed" choice are keyed by id. |
| `courses[].short` | no | Grid label; derived from the name when missing ("Autonomous and Mobile Robotics" → "AMR"). |
| `courses[].professor`, `.group` | no | `group` groups courses in the "Courses you follow" list. |
| `courses[].color` | no | `#RRGGBB`; otherwise a stable palette colour. |
| `lessons[].course` | yes | A course id. |
| `lessons[].day` | yes | `mon` `tue` `wed` `thu` `fri` `sat` `sun`. |
| `lessons[].start`, `.end` | yes | `HH:mm`, start before end. |
| `lessons[].room`, `.location` | no | `location` is a location id. |

Import is all-or-nothing: every problem is listed by path (for example
`lessons[3]: course "xyz" is not defined`) and the current timetable is kept.

Re-importing replaces courses and lessons. Notes, exams and followed courses
are kept per course id; data for a course missing from the new file stays
dormant and returns if the id comes back. When the file uses `group`, new
courses start unfollowed so you can pick yours; otherwise all are followed.
