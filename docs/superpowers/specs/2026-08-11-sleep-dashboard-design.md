# Sleep Dashboard — Mac App Design (v1)

## Purpose

Native macOS app to import personal sleep data (AutoSleep CSV export) and
view it on an interactive local dashboard. All processing is local-only —
no network transmission of health data.

## Non-goals (v1)

- Apple Health export.zip import — deferred to v2. It is not "one more
  importer": it requires interval union across overlapping `InBed`/stage
  records, stage precedence rules, multi-source arbitration, and per-metric
  availability handling. Doing it alongside CSV risks two half-finished
  importers instead of one solid one.
- AI/LLM narrative or insights of any kind — not a stated requirement.
- Cloud sync / multi-device sync
- Multi-user support
- Writing data back to Apple Health
- Non-sleep health metrics (steps, weight, workouts, etc.)

## Architecture

SwiftUI app, SwiftData for persistence, Swift Charts for visualization.
No backend, no network calls, no outbound network entitlement in the sandbox.

```
SleepDashboard/
  Models/
    ImportedSleepRecord.swift   (SwiftData @Model — raw imported rows)
    SleepNight.swift            (SwiftData @Model — normalized nightly aggregate)
  Import/
    ParsedSleepRecord.swift     (Sendable DTO, parser output)
    AutoSleepCSVImporter.swift
    ImportCoordinator.swift     (ModelActor — transactional upsert)
  Analytics/
    SleepAnalyticsEngine.swift  (pure functions: averages, trends, moving windows)
  Views/
    DashboardView.swift         (core metrics, default screen)
    DetailMetricsView.swift     (remaining metrics)
    ImportView.swift            (file picker + progress + cancel)
  App.swift
```

## Data Model

Two-layer model, to avoid collapsing "what was imported" and "what a night
looked like" into one lossy row (naps, multi-session nights, and re-imports
from the same source must not silently overwrite each other):

**`ImportedSleepRecord`** (SwiftData `@Model`) — one row per row in the
source file, kept as close to raw as possible:
- `sourceFile: String`, `sourceRowFingerprint: String` (hash of raw row —
  identity for de-dup of exact re-imports)
- `startDate: Date`, `endDate: Date`, `timeZoneIdentifier: String`
- `bedtime: Date`, `wakeTime: Date`
- `inBedDuration: TimeInterval`, `awakeDuration: TimeInterval`,
  `asleepDuration: TimeInterval`, `deepDuration: TimeInterval`
- `efficiency: Double` (stored 0–100)
- `sleepBPM: Double?`, `hrv: Double?`
- `spo2Avg/Min/Max: Double?`, `respAvg/Min/Max: Double?`
- `apneaHypopneaIndex: Double?` (AutoSleep's `apnea` field is events/hour —
  i.e. AHI — not an event count; named and displayed accordingly)
- `sessionsInNight: Int`

**`SleepNight`** (SwiftData `@Model`) — one row per calendar night, derived
from one or more `ImportedSleepRecord`s sharing that night. This is what the
dashboard queries. Aggregation rule for v1 (single-source CSV): a night's
`ImportedSleepRecord`s are summed/merged in `ImportCoordinator`; since v1 has
only one source, "merge" reduces to "one record per night" but the two-layer
model means adding a second source in v2 doesn't require a data migration —
only a new arbitration rule in the coordinator.

Import is a transactional upsert on `ImportedSleepRecord.sourceRowFingerprint`
(exact duplicate rows are no-ops), and `SleepNight` rows are recomputed for
any night touched by the import — never a blind overwrite keyed on date alone.

## Import

```swift
struct ParsedSleepRecord: Sendable { /* mirrors ImportedSleepRecord fields */ }

protocol SleepDataSource {
    func parse(fileURL: URL) -> AsyncThrowingStream<ParsedSleepRecord, Error>
}
```

**AutoSleepCSVImporter** — parses the AutoSleep CSV export. Explicit
contract (must hold before implementation starts):
- Delimiter: detect `,` vs `;` (AutoSleep can export either); honor a
  leading `sep=;` line if present.
- Encoding: UTF-8, strip BOM if present.
- Quoted fields: RFC 4180 quoting (commas/newlines inside `notes` must not
  break column alignment) — use a real CSV parser, not
  `components(separatedBy:)`.
- Dates: `yyyy-MM-dd HH:mm:ss`, parsed in the timezone the file was
  exported in (falls back to device timezone if unavailable — v1 does not
  attempt per-row timezone detection since AutoSleep exports don't carry
  per-row timezone).
- Durations (`inBed`, `awake`, `asleep`, `deep`): `HH:mm:ss` format, parsed
  to `TimeInterval`.
- `efficiency`: stored as 0–100 (matches source format).
- Column matching: case-insensitive header match against the known AutoSleep
  column names, so future minor header changes don't hard-fail.
- Row-level failure policy: a malformed row is skipped and recorded in an
  import summary (`N rows imported, M rows skipped`); a malformed *file*
  (missing required columns entirely) fails the whole import with a clear
  error before writing anything.

Import flow: `fileImporter` (accepts `.csv`) — security-scoped resource
`startAccessingSecurityScopedResource()`/`stopAccessingSecurityScopedResource()`
paired around the read — → `AutoSleepCSVImporter` streams `ParsedSleepRecord`s
→ `ImportCoordinator` (a `ModelActor`) batches them into one transaction →
commit or full rollback on error/cancel. Progress is reported via the async
stream's element count; cancellation stops the stream and rolls back the
in-progress transaction, leaving previously-committed data untouched.

## Dashboard

**Home (core metrics)** — time range picker (7d / 30d / 90d / All / custom,
range boundaries inclusive of both start and end dates) applies to all
charts. Six Swift Charts, backed by `SleepAnalyticsEngine`:
1. Sleep duration (asleep) trend, with 7-day moving average line
2. Bedtime scatter/timeline (shows consistency; bedtimes after midnight are
   plotted on a continuous 24h+ axis rather than wrapping to 00:00, so a
   01:00 bedtime sorts after 23:00, not before it)
3. Deep sleep % of total asleep time (renders as a gap, not 0%, on nights
   with zero recorded `asleepDuration`)
4. Efficiency trend
5. Sleep BPM trend (gaps where `nil`)
6. HRV trend (gaps where `nil`)

Each chart supports point selection (tap/hover) to show that night's exact
values. A summary card row above the charts shows current-range averages.

**`SleepAnalyticsEngine`** semantics (pure functions, unit-tested
independently of any view):
- "7-day moving average" = average over the trailing 7 *calendar* days
  ending on that night, counting only nights with data (missing nights are
  excluded from the denominator, not treated as zero).
- Averages over `Double?` metrics (HRV, SpO2, etc.) ignore `nil` values
  rather than treating them as zero.

**Detail Metrics (secondary screen)** — same time range picker, covers the
remaining columns: SpO2 (avg/min/max), respiration rate (avg/min/max),
apnea-hypopnea index, awake duration, sessions count, in-bed duration.
Reached via a tab/sidebar item from the dashboard, not shown by default.

## Error Handling

- Import errors (bad format, unreadable file, missing required columns)
  show a dismissable alert with the specific failure reason; nothing is
  written to SwiftData until the whole transaction succeeds.
- Missing optional fields (e.g. HRV) render as gaps in charts, not zeros.
- A "Delete all imported data" action exists for the user to reset local
  state.

## Testing

- `AutoSleepCSVImporter` unit tests: happy-path fixture, comma vs semicolon
  delimiter, `sep=;` header, UTF-8 BOM, quoted `notes` field containing a
  comma/newline, missing optional columns, malformed row (skip + report),
  missing required column (whole-file failure), re-import of the same file
  (no duplicate `SleepNight`s produced).
- `SleepAnalyticsEngine` unit tests: 7-day average with gaps, all-nil metric
  column, zero-asleep-duration deep%, custom range boundary inclusivity,
  cross-midnight bedtime ordering.
- One integration test: fixture CSV → `ImportCoordinator` → SwiftData →
  assert `SleepNight` rows and dashboard-facing query results match
  expected values.
- No UI/snapshot testing in scope for v1.
