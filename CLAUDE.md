# CLAUDE.md — InertiaX Force

Developer reference for the InertiaX Force biomechanical force platform app.
Last updated: 2026-03-24.

---

## PROJECT OVERVIEW

**InertiaX Force** is a Flutter desktop + mobile app for biomechanical testing using
custom ESP32-S3 force platforms. It acquires raw ADC data over serial/USB OTG, applies
DSP filtering and phase detection, computes jump and force metrics, stores results in
SQLite, and optionally syncs to Supabase.

| Dimension | Detail |
|---|---|
| Hardware | ESP32-S3 force platforms (1 or 2), connected via USB OTG (Android) or serial (Windows/macOS/Linux) |
| Flutter SDK | >=3.19.0 |
| Dart SDK | >=3.3.0 <4.0.0 |
| Target platforms | Windows (primary), Android, iOS (BLE), macOS, Linux |
| Package name | `inertiax` |

### Core dependencies

| Package | Purpose |
|---|---|
| `flutter_riverpod` ^2.5.1 | State management |
| `go_router` ^13.2.2 | Navigation |
| `fl_chart` ^0.68.0 | Live and post-test force-time charts |
| `flutter_libserialport` ^0.3.0 | Desktop serial communication |
| `usb_serial` ^0.5.0 | Android USB OTG |
| `flutter_blue_plus` ^1.32.12 | iOS Bluetooth LE |
| `sqflite` + `sqflite_common_ffi` | SQLite (mobile + desktop via FFI) |
| `supabase_flutter` ^2.5.3 | Cloud sync |
| `pdf` + `printing` | PDF report generation |
| `shared_preferences` | Settings persistence |
| `intl` | Locale/date formatting |
| `uuid` | Supabase UUIDs |

---

## ARCHITECTURE

### Layer structure

```
lib/
├── main.dart                         # Entry point — init Supabase, language, route
├── app.dart                          # InertiaXApp (ConsumerStatefulWidget), GoRouter
├── core/
│   ├── constants/
│   │   ├── algorithm_settings.dart   # AlgorithmSettings, method enums
│   │   ├── app_colors.dart           # Design tokens
│   │   └── physics_constants.dart    # g, thresholds, buffer sizes
│   ├── l10n/app_strings.dart         # ES/EN string map (AppStrings.get())
│   ├── services/sound_service.dart   # Haptic/audio feedback
│   └── utils/
│       ├── circular_buffer.dart
│       └── csv_parser.dart           # CsvParser — parses firmware CSV lines
├── data/
│   ├── datasources/
│   │   ├── connection/
│   │   │   ├── connection_datasource.dart   # Abstract ConnectionDataSource
│   │   │   ├── desktop_serial_datasource.dart  # Windows/macOS/Linux (flutter_libserialport)
│   │   │   ├── android_usb_datasource.dart     # Android USB OTG (usb_serial)
│   │   │   ├── ble_connection_datasource.dart  # iOS BLE (flutter_blue_plus)
│   │   │   └── web_stub_datasource.dart        # No-op stub for web builds
│   │   └── local/
│   │       ├── database_helper.dart     # SQLite singleton (DatabaseHelper.instance)
│   │       ├── database_ffi_init.dart   # Desktop: initialises sqflite_common_ffi
│   │       └── database_ffi_init_stub.dart  # Web: no-op stub
│   ├── models/
│   │   ├── raw_sample.dart      # RawSample — parsed CSV row (ADC values)
│   │   └── processed_sample.dart # ProcessedSample — calibrated forces in Newtons
│   └── services/
│       └── supabase_service.dart  # SupabaseService singleton
├── domain/
│   ├── dsp/
│   │   ├── butterworth_filter.dart  # ButterworthFilter (filtfilt) + ButterworthOnline
│   │   ├── calibration_engine.dart  # CalibrationEngine — polyfit, segments, cell gains
│   │   ├── phase_detector.dart      # PhaseDetector state machine
│   │   ├── signal_processor.dart    # SignalProcessor — ADC → Newtons + ButterworthOnline
│   │   └── metrics/
│   │       ├── jump_metrics.dart    # JumpMetrics — height, RFD, power, symmetry
│   │       ├── cop_metrics.dart     # CopMetrics — CoP area, path, velocity
│   │       └── imtp_metrics.dart    # ImtpMetrics helpers
│   ├── entities/
│   │   ├── athlete.dart
│   │   ├── calibration_data.dart   # CalibrationData, CalibrationPoint, CalibrationMode
│   │   └── test_result.dart        # TestResult hierarchy + TestType enum
│   └── services/
│       └── pdf_report_service.dart  # PdfReportService — generates PDF from TestResult
└── presentation/
    ├── providers/          # (see Providers table below)
    ├── screens/
    │   ├── home/           # HomeScreen (dashboard)
    │   ├── tests/          # TestsHubScreen, CmjScreen, SjScreen, DjScreen,
    │   │                   # MultiJumpScreen, CopScreen, ImtpScreen
    │   ├── athletes/       # AthleteListScreen, AthleteProgressScreen
    │   ├── history/        # HistoryScreen
    │   ├── results/        # ResultDetailScreen
    │   ├── comparison/     # ComparisonScreen
    │   ├── calibration/    # CalibrationScreen
    │   ├── connection/     # ConnectionScreen
    │   ├── settings/       # SettingsScreen (also defines settingsProvider)
    │   ├── monitor/        # LiveMonitorScreen
    │   ├── onboarding/     # WelcomeScreen, TestInfoScreen
    │   └── error/          # ErrorScreen
    ├── theme/app_theme.dart   # AppTheme.light / .dark / .outdoor
    └── widgets/
        ├── cards/          # MetricCard, SymmetryGauge
        ├── charts/         # ForceTimeChart
        ├── common/         # PostTestPanel, StatusBadge
        ├── test_illustrations.dart
        └── test_tutorial.dart
```

---

## STATE MANAGEMENT (Riverpod)

All providers use Riverpod 2. There are no code-generated providers (`@riverpod`) —
all are declared manually.

| Provider | Type | File | Description |
|---|---|---|---|
| `connectionDataSourceProvider` | `Provider<ConnectionDataSource>` | `connection_provider.dart` | Platform-aware datasource factory (serial / USB / BLE / stub) |
| `rawSampleStreamProvider` | `StreamProvider<RawSample>` | `connection_provider.dart` | Live stream of parsed CSV rows from the hardware |
| `signalProcessorProvider` | `Provider<SignalProcessor>` | `connection_provider.dart` | Stateful signal processor seeded with active calibration |
| `connectionProvider` | `StateNotifierProvider<ConnectionNotifier, ConnectionState>` | `connection_provider.dart` | Connect / disconnect / list targets |
| `liveDataProvider` | `StateNotifierProvider<LiveDataNotifier, LiveDataState>` | `live_data_provider.dart` | Buffered live force data for the chart (updates every 33 samples) |
| `calibrationProvider` | `StateNotifierProvider<CalibrationNotifier, CalibrationState>` | `calibration_provider.dart` | Active calibration, pending calibration points, tare offsets |
| `testStateProvider` | `StateNotifierProvider<TestStateNotifier, TestState>` | `test_state_provider.dart` | Full test lifecycle — settling, running, metrics, result |
| `athleteListProvider` | `FutureProvider<List<Athlete>>` | `athlete_provider.dart` | Read-only list of athletes from SQLite |
| `selectedAthleteProvider` | `StateNotifierProvider<SelectedAthleteNotifier, Athlete?>` | `athlete_provider.dart` | Currently selected athlete (persisted in SharedPreferences) |
| `athleteNotifierProvider` | `StateNotifierProvider<AthleteNotifier, AsyncValue<List<Athlete>>>` | `athlete_provider.dart` | Full CRUD — create / update / delete athletes |
| `syncProvider` | `StateNotifierProvider<SyncNotifier, SyncState>` | `sync_provider.dart` | Supabase auth (sign in/up/out) and manual sync (`syncPending()`) |
| `languageProvider` | `StateNotifierProvider<LanguageNotifier, String>` | `language_provider.dart` | Active UI language ('es' / 'en'), persisted in SharedPreferences |
| `settingsProvider` | `StateNotifierProvider<SettingsNotifier, AppSettings>` | `settings_screen.dart` | Theme, algorithm flags, sound feedback, all algorithm selections |

### Key state classes

- `ConnectionState` — `{isConnected, connectedName, availableTargets, error}`
- `LiveDataState` — `{timeS, forceTotalN, forceLeftN, forceRightN, currentForceN, currentSmoothedN, currentRawSum, platformCount, leftPct, rightPct, samplesReceived, currentForceALN/ARN/MasterN/SlaveN, currentRawAML/AMR/ASL/ASR}`
- `CalibrationState` — `{activeCalibration, pendingPoints, isCalibrated, isLoading, error}`
- `TestState` — `{testType, status (TestStatus enum), phase (JumpPhase enum), bodyWeightN, elapsedSeconds, statusMessage, result, error}`
- `SyncState` — `{status (SyncStatus enum), pendingCount, lastSyncAt, errorMessage, userEmail, successMessage}`

---

## NAVIGATION (go_router)

The router is created **once** in `_InertiaXAppState.initState()` using a `late final`
field. Never rebuild the router on theme or language changes — that was the root cause
of the welcome screen flash bug.

### Shell (bottom navigation bar — 4 tabs)

| Index | Path | Screen |
|---|---|---|
| 0 | `/` | `HomeScreen` |
| 1 | `/tests` | `TestsHubScreen` |
| 2 | `/history` | `HistoryScreen` |
| 3 | `/settings` | `SettingsScreen` |

### Full-screen routes (push over shell — no bottom nav)

| Path | Screen | Notes |
|---|---|---|
| `/monitor` | `LiveMonitorScreen` | Real-time force chart |
| `/athletes` | `AthleteListScreen` | |
| `/athletes/progress` | `AthleteProgressScreen` | `extra: Athlete` |
| `/connection` | `ConnectionScreen` | |
| `/calibration` | `CalibrationScreen` | |
| `/tests/cmj` | `CmjScreen` | |
| `/tests/sj` | `SjScreen` | |
| `/tests/dj` | `DjScreen` | Drop jump |
| `/tests/multijump` | `MultiJumpScreen` | |
| `/tests/cop` | `CopScreen` | Requires 2 platforms |
| `/tests/imtp` | `ImtpScreen` | |
| `/results/:id` | `ResultDetailScreen` | `extra: TestResult` (from history) |
| `/results/new` | `ResultDetailScreen` | `extra: TestResult` (post-test) |
| `/compare` | `ComparisonScreen` | `extra: {athleteId, testType}` |
| `/welcome` | `WelcomeScreen` | Onboarding (first run) |
| `/test-info` | `TestInfoScreen` | `extra: String testType` |

---

## DATA FLOW

### Live (during test)

```
Hardware (ESP32-S3)
  → USB/Serial line stream
  → CsvParser.parse()         → RawSample
  → SignalProcessor.process() → ProcessedSample   (calibration applied, ButterworthOnline)
  → LiveDataNotifier.onRawSample()  → LiveDataState  (chart, current force display)
  → TestStateNotifier._onRawSample() → PhaseDetector.update() → PhaseEvent
```

### Post-test metric computation

```
Accumulated List<double> _forceData (smoothedTotal, 1000 Hz)
  → ButterworthFilter.filtfilt()    (zero-phase 4th-order 50 Hz LP)
  → Phase index calculation (descentIdx, peakForceIdx, takeoffIdx, minIdx)
  → JumpMetrics (height, RFD, power, impulse, symmetry)
  → TestResult subclass (JumpResult / DropJumpResult / ImtpResult / MultiJumpResult)
  → DatabaseHelper.insertSession()  → SQLite test_sessions (result_json TEXT)
  → SyncNotifier.syncPending()      → Supabase test_sessions (metrics_json JSONB)
```

---

## DATABASE (SQLite)

File location:

- **Windows / macOS / Linux**: `%APPDATA%/InertiaX/inertiax.db`
  (resolved via `getApplicationSupportDirectory()`).
  Legacy databases stored next to the EXE or in `.dart_tool/sqflite_common_ffi/databases/`
  are auto-migrated on first launch.
- **Android / iOS**: standard `getDatabasesPath()`.

DB version: **3** (`_dbVersion = 3`)

### Schema

```sql
CREATE TABLE athletes (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  name           TEXT    NOT NULL,
  sport          TEXT,
  body_weight_kg REAL,
  notes          TEXT,
  created_at     TEXT    NOT NULL DEFAULT (datetime('now')),
  supabase_uuid  TEXT    UNIQUE
);

CREATE TABLE calibrations (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  name                 TEXT    NOT NULL,
  mode                 INTEGER NOT NULL DEFAULT 0,
  coefficients_json    TEXT    NOT NULL DEFAULT '[]',
  cell_offsets_json    TEXT    NOT NULL DEFAULT '{}',
  cell_gains_json      TEXT    NOT NULL DEFAULT '{}',   -- added v2
  cell_polarities_json TEXT    NOT NULL DEFAULT '{}',   -- added v3
  is_active            INTEGER NOT NULL DEFAULT 1,
  created_at           TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE calibration_points (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  calibration_id INTEGER NOT NULL REFERENCES calibrations(id) ON DELETE CASCADE,
  weight_kg      REAL    NOT NULL,
  raw_sum        REAL    NOT NULL,
  raw_aml        REAL    NOT NULL DEFAULT 0,  -- added v2
  raw_amr        REAL    NOT NULL DEFAULT 0,
  raw_asl        REAL    NOT NULL DEFAULT 0,
  raw_asr        REAL    NOT NULL DEFAULT 0
);

CREATE TABLE test_sessions (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  athlete_id     INTEGER NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
  test_type      TEXT    NOT NULL,
  performed_at   TEXT    NOT NULL DEFAULT (datetime('now')),
  body_weight_kg REAL    NOT NULL,
  calibration_id INTEGER REFERENCES calibrations(id),
  platform_count INTEGER NOT NULL DEFAULT 1,
  notes          TEXT,
  raw_data_json  TEXT,
  result_json    TEXT,    -- JSON of TestResult.toMap() — primary source of truth
  sync_status    TEXT    NOT NULL DEFAULT 'pending',  -- 'pending' | 'synced' | 'error'
  supabase_uuid  TEXT    UNIQUE
);

CREATE TABLE jump_results (   -- denormalised mirror of result_json for fast queries
  session_id          INTEGER PRIMARY KEY REFERENCES test_sessions(id) ON DELETE CASCADE,
  jump_height_cm      REAL,
  flight_time_ms      REAL,
  contact_time_ms     REAL,
  peak_force_n        REAL,
  mean_force_n        REAL,
  rsi_mod             REAL,
  asymmetry_index_pct REAL,
  platform_a_pct      REAL,
  peak_power_w        REAL,
  rfd_50ms            REAL,
  rfd_100ms           REAL,
  rfd_200ms           REAL
);

CREATE TABLE cop_results (
  session_id        INTEGER PRIMARY KEY REFERENCES test_sessions(id) ON DELETE CASCADE,
  condition         TEXT,
  stance            TEXT,
  duration_s        REAL,
  area_ellipse_mm2  REAL,
  path_length_mm    REAL,
  velocity_mm_s     REAL,
  range_ml_mm       REAL,
  range_ap_mm       REAL,
  symmetry_pct      REAL,
  romberg_quotient  REAL
);

CREATE INDEX idx_sessions_athlete ON test_sessions(athlete_id);
CREATE INDEX idx_sessions_type    ON test_sessions(test_type);
```

### Migration history

| Version | Change |
|---|---|
| v1 | Initial schema |
| v2 | Added `cell_gains_json` to calibrations; `raw_aml/amr/asl/asr` to calibration_points |
| v3 | Added `cell_polarities_json` to calibrations |

---

## SUPABASE

| Property | Value |
|---|---|
| Project ref | `rldtkomtclolhbmrphgh` |
| URL | `https://rldtkomtclolhbmrphgh.supabase.co` |
| Anon key | Hardcoded as `defaultValue` in `String.fromEnvironment` (see `supabase_service.dart`) |
| Auth | Email + password via `SupabaseService.instance.signIn/signUp/signOut()` |
| Sync mode | Manual — call `syncProvider.notifier.syncPending()` |
| Realtime | Not used |

### Override credentials at build time

```
--dart-define=SUPABASE_URL=https://rldtkomtclolhbmrphgh.supabase.co
--dart-define=SUPABASE_ANON_KEY=eyJhbGci...
```

The anon key is a public client key; Row Level Security on the server enforces access
control. The key is safe to embed in the binary.

### Supabase tables

| Table | Key columns |
|---|---|
| `athletes` | `id UUID PK`, `name`, `sport`, `body_weight_kg`, `notes` |
| `test_sessions` | `id UUID PK`, `athlete_id UUID FK`, `test_type`, `performed_at`, `metrics_json JSONB` |

### Sync logic (`SyncNotifier.syncPending`)

1. Re-queue sessions with `sync_status = 'error'` back to `'pending'`.
2. For each pending session, ensure the linked athlete has a `supabase_uuid`; call
   `upsertAthlete()` to create or look up the remote row (avoids 409 on re-sync).
3. Call `upsertSession()` which writes `metrics_json` from `result_json`.
4. Update local `sync_status` to `'synced'` (or `'error'` on failure).

---

## DSP

### ButterworthFilter (`lib/domain/dsp/butterworth_filter.dart`)

- 4th-order Butterworth low-pass, fc = 50 Hz, fs = 1000 Hz
- Implemented as **two cascaded biquad (SOS) sections** (bilinear transform with
  pre-warping)
- Section 1: b = [0.021884, 0.043768, 0.021884], a = [1.0, -1.700950, 0.788490]
- Section 2: b = [0.019038, 0.038076, 0.019038], a = [1.0, -1.479600, 0.555746]
- **`ButterworthOnline`** — causal, sample-by-sample, used during live acquisition
- **`ButterworthFilter.filtfilt()`** — zero-phase forward+backward pass, used for all
  post-test metric computation (preserves array length)

### PhaseDetector (`lib/domain/dsp/phase_detector.dart`)

State machine that consumes `ProcessedSample` values and emits `PhaseEvent` on
significant transitions.

#### States

```
idle → settling → waiting → descent → flight → landed
```

| State | Description |
|---|---|
| `idle` | Not active |
| `settling` | Measuring body weight — athlete stands still for ~1 s |
| `waiting` | Body weight locked; waiting for athlete to move |
| `descent` | Eccentric phase — force dropped below BW − unweightingDelta |
| `flight` | Airborne — force below flightThreshold for ≥ 10 samples |
| `landed` | Force exceeds landingThreshold for ≥ 12 samples |

#### Thresholds (computed after settling)

| Threshold | Formula | Minimum |
|---|---|---|
| Flight detection | `BW × 0.05` | 20 N |
| Landing detection | `BW × 0.20` | 50 N |
| Unweighting (adaptive) | `max(5 × SD_settling, 20 N)` | 20 N |
| Unweighting (fixed) | 80 N | — |

#### Debounce

- Flight requires **10 consecutive samples** below flight threshold
- Landing requires **12 consecutive samples** above landing threshold

The 10-sample flight debounce means `roughTakeoffIdx` (the index when the phase fires)
is already 10 ms into the flight phase (force ≈ 0–20 N). **Do not use it directly as
the takeoff boundary.**

### SignalProcessor (`lib/domain/dsp/signal_processor.dart`)

Converts `RawSample` → `ProcessedSample`:
1. Applies per-cell tare offsets and polarities from `CalibrationData`
2. Converts ADC counts to Newtons using calibration gains / polynomial
3. Runs `ButterworthOnline` for the smoothed live signal

---

## METRIC COMPUTATION ORDER (CRITICAL)

For CMJ, SJ, and DJ the indices **must** be computed in this exact order to avoid the
19 N peak force bug (caused by searching for the minimum before finding the peak,
landing in the flight-phase near-zero).

```dart
// 1. Propulsive peak — global max in [descentIdx, roughTakeoffIdx]
//    This must come FIRST because roughTakeoffIdx is already inside the flight phase.
int peakForceIdx = descentIdx;
double peakF = forceFiltered[descentIdx];
for (int i = descentIdx + 1; i <= roughTakeoffIdx; i++) {
  if (forceFiltered[i] > peakF) { peakF = forceFiltered[i]; peakForceIdx = i; }
}

// 2. True takeoff — last sample >= flightThreshold after peak
//    Walk forward from peak; takeoffIdx is the last above-threshold sample.
int takeoffIdx = peakForceIdx;
for (int i = peakForceIdx; i <= roughTakeoffIdx; i++) {
  if (forceFiltered[i] >= flightThreshold) takeoffIdx = i;
}

// 3. Squat bottom — minimum in [descentIdx, peakForceIdx] ONLY
//    Never search past peakForceIdx or the flight-phase near-zero gets selected.
int minIdx = descentIdx;
double minF = forceFiltered[descentIdx];
for (int i = descentIdx + 1; i <= peakForceIdx; i++) {
  if (forceFiltered[i] < minF) { minF = forceFiltered[i]; minIdx = i; }
}
```

See `TestStateNotifier._computeAndFinish()` in `test_state_provider.dart` for the
full implementation including RFD, impulse, power, and symmetry.

---

## SERIAL CSV FORMAT

Firmware v2.3 — baud rate **921600**

```
timestamp_us, platform_id, seq_num, adc_master_L, adc_master_R, adc_slave_L, adc_slave_R, flags, seq_jump, packets_lost_total
```

| Field | Description |
|---|---|
| `timestamp_us` | Microsecond timestamp from ESP32 |
| `platform_id` | `0` = Platform A, `1` = Platform B |
| `seq_num` | Sequence number (for packet loss detection) |
| `adc_master_L` | Master board left load cell ADC count |
| `adc_master_R` | Master board right load cell ADC count |
| `adc_slave_L` | Slave board left load cell ADC count (0 if timeout) |
| `adc_slave_R` | Slave board right load cell ADC count (0 if timeout) |
| `flags` | Status flags bitmask |
| `seq_jump` | Per-jump sequence counter |
| `packets_lost_total` | Cumulative lost packet count |

Parsing: `CsvParser` in `lib/core/utils/csv_parser.dart`. ADC values are negated
during calibration (all sensors read negative under load).

---

## TEST TYPES

| Enum value | Display name | Description |
|---|---|---|
| `TestType.cmj` | CMJ — Contramovimiento | Countermovement jump, no arms |
| `TestType.cmjArms` | CMJ + Brazos | Countermovement jump with arm swing |
| `TestType.sj` | SJ — Sentadilla | Squat jump (no pre-stretch) |
| `TestType.dropJump` | DJ — Caída | Drop jump — RSI-mod computed |
| `TestType.multiJump` | Multi-Salto (RSI) | Repeated jumps — fatigue index |
| `TestType.cop` | Equilibrio (CoP) | Centre-of-pressure balance (requires 2 platforms) |
| `TestType.imtp` | IMTP — Tracción | Isometric mid-thigh pull |

`TestType.cop` is the only test that `requiresTwoPlatforms`.

---

## CALIBRATION

### Modes (`CalibrationMode`)

| Mode | Method |
|---|---|
| `linear` | Single-slope polynomial (degree 1) |
| `quadratic` | Polynomial (degree 2) |
| `cubic` | Polynomial (degree 3) |
| `segmented` | Piecewise linear segments between calibration points |

### Per-cell calibration (recommended)

1. **Tare step** — record `rawAML/AMR/ASL/ASR` at zero load → stored as `cellOffsets`
2. **Weight points** — add known weights; record per-cell ADC readings at each
3. `CalibrationEngine.computeCellGains()` fits a single gain per cell
4. Polarity (`+1` or `-1`) per channel stored in `cellPolarities`

### Algorithm settings (`AlgorithmSettings` in `algorithm_settings.dart`)

| Setting | Default | Options |
|---|---|---|
| `jumpHeight` | `impulseMomentum` | `flightTime`, `impulseMomentum` |
| `peakPower` | `sayers` | `sayers`, `harman`, `impulseBased` |
| `symmetry` | `asymmetryIndex` | `asymmetryIndex`, `limbSymmetryIndex` |
| `imtpOnset` | `statisticalSD` | `fixedThreshold` (BW+50N), `statisticalSD` (BW+5×SD) |
| `unweighting` | `adaptive5SD` | `fixed80N`, `adaptive5SD` |
| `copFrequency` | `fft95` | `zeroCrossing`, `fft95` |

---

## BUILD COMMANDS

### Windows (release)

```bat
flutter build windows --release ^
  --dart-define=SUPABASE_URL=https://rldtkomtclolhbmrphgh.supabase.co ^
  "--dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJsZHRrb210Y2xvbGhibXJwaGdoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5NzQ1OTQsImV4cCI6MjA4OTU1MDU5NH0.uB9S--0zxvmO7UccotZRSen6KLRn4aeOuQe0n8MM5rs"
```

Or use the convenience script: `build_windows.bat`

### Android (release APK)

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://rldtkomtclolhbmrphgh.supabase.co \
  "--dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJsZHRrb210Y2xvbGhibXJwaGdoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5NzQ1OTQsImV4cCI6MjA4OTU1MDU5NH0.uB9S--0zxvmO7UccotZRSen6KLRn4aeOuQe0n8MM5rs"
```

### Development run

```bash
flutter run -d windows   # or -d <android-device-id>
```

No `--dart-define` needed for development — production credentials are hardcoded as
`defaultValue` in `SupabaseService`.

### Code generation (Riverpod)

Not currently used (`@riverpod` annotations are absent). If added in future:

```bash
dart run build_runner build --delete-conflicting-outputs
```

---

## KNOWN BUGS & FIXES

### Peak force = 19 N (FIXED)

**Cause**: the squat-bottom search scanned the entire range `[descentIdx, roughTakeoffIdx]`.
Because the phase detector fires after a 10-sample debounce, `roughTakeoffIdx` was
already inside the flight phase where force ≈ 0–20 N. The minimum search returned the
flight-phase near-zero as the "squat bottom", placing `minIdx` after the actual peak.
All subsequent indices were inverted: `concentricDurationMs = 0`, `peakForceN = 19 N`.

**Fix**: find the propulsive peak first, then constrain the squat-bottom search to
`[descentIdx, peakForceIdx]` only. See Metric Computation Order section above.

---

### 409 Conflict on athlete upsert during Supabase sync

**Cause**: the local athlete's `supabase_uuid` was `NULL` (e.g. after a DB wipe or
device change). `upsertAthlete` tried to insert a new row with a freshly generated UUID,
conflicting with an existing row for the same athlete name/email.

**Fix**: in `SupabaseService.upsertAthlete()`, look up any existing remote row by
`name` before inserting. If found, reuse its UUID; if not, insert with the generated UUID.

---

### PDF broken / garbled characters

**Cause**: the `pdf` package's built-in Helvetica does not support Unicode characters
(ñ, á, é, í, ó, ú, ü, ¡, ¿, etc.).

**Fix**: use `PdfGoogleFonts.notoSansRegular()` / `notoSansBold()` instead of
`PdfFonts.helvetica`. These are embedded TrueType fonts with full Latin character
support. See `PdfReportService` in `lib/domain/services/pdf_report_service.dart`.

---

### Welcome screen flashing on theme or language change

**Cause**: `MaterialApp.router` was being rebuilt with a new `GoRouter` instance,
resetting navigation state and triggering the initial route (`/welcome`) again.

**Fix**: create the `GoRouter` exactly once using `late final GoRouter _router` in
`initState()` of `ConsumerStatefulWidget`. The router is never recreated regardless of
theme or language rebuilds. See `_InertiaXAppState` in `lib/app.dart`.

---

### DB path on Windows (legacy migration)

**Cause**: earlier builds stored the database in `.dart_tool/sqflite_common_ffi/databases/`
relative to the executable. This path breaks across Flutter upgrades and is not
user-accessible.

**Fix**: `DatabaseHelper._resolveDbPath()` now always uses
`%APPDATA%/InertiaX/inertiax.db`. On first run it auto-detects and migrates any
legacy database found next to the EXE or in the old `.dart_tool` sub-path.

---

## CONVENTIONS

### Naming

| Element | Convention | Example |
|---|---|---|
| Dart files | `snake_case` | `jump_metrics.dart` |
| Classes | `PascalCase` | `JumpMetrics`, `TestStateNotifier` |
| Providers | `camelCase` + `Provider` suffix | `testStateProvider`, `liveDataProvider` |
| Enums | `PascalCase` type, `camelCase` values | `TestType.dropJump` |
| Private members | `_camelCase` | `_forceData`, `_computeAndFinish` |

### UI strings

- All Spanish strings must use correct Unicode accents: **ñ, á, é, í, ó, ú, ü, ¡, ¿**
- Use `AppStrings.get('key')` for localised strings (ES/EN). See
  `lib/core/l10n/app_strings.dart` for all keys.
- Hardcoded strings in test screens are Spanish (the primary locale).

### Credential handling

- **Always build with `--dart-define`** for Supabase credentials in CI/CD pipelines.
- The anon key in `defaultValue` is a public client key protected by RLS — it is
  intentionally embedded and safe to commit.
- Do not add a `.env` file; the existing `String.fromEnvironment` pattern is the
  project standard.

### Platform-conditional imports

The project uses Dart conditional imports (`if (dart.library.html)`) to swap in
no-op web stubs for `dart:ffi`-dependent code (serial, FFI SQLite). Follow this
pattern when adding new native-only datasources.

### Post-test data access

`TestStateNotifier` exposes `lastForceN`, `lastTimeS`, `lastTimeRelS`, `lastForceAN`,
`lastForceBN` as read-only getters. These are valid from `TestStatus.completed` until
the next `startTest()` call. The PDF service and result detail screen use these.

---

## THEMES

Three themes defined in `lib/presentation/theme/app_theme.dart`:

| Theme | When used |
|---|---|
| `AppTheme.light` | Default light mode |
| `AppTheme.dark` | System dark mode |
| `AppTheme.outdoor` | High-contrast bright theme for outdoor use |

Selected via `settingsProvider` (`AppSettings.themeMode` = `'light'` / `'dark'` /
`'outdoor'`). The `flutterThemeMode` getter converts to `ThemeMode`.

---

## PROJECT FILES OF INTEREST

| File | Purpose |
|---|---|
| `lib/main.dart` | Bootstrap: Supabase init, language restore, initial route decision |
| `lib/app.dart` | Router definition and `InertiaXApp` |
| `lib/domain/dsp/butterworth_filter.dart` | Filter coefficients and filtfilt |
| `lib/domain/dsp/phase_detector.dart` | Jump phase state machine + thresholds |
| `lib/presentation/providers/test_state_provider.dart` | Full test lifecycle and metric computation |
| `lib/data/datasources/local/database_helper.dart` | SQLite schema, migrations, DB path |
| `lib/data/services/supabase_service.dart` | Supabase credentials and upsert logic |
| `lib/domain/services/pdf_report_service.dart` | PDF generation (use Noto Sans fonts) |
| `lib/core/constants/algorithm_settings.dart` | All configurable algorithm enums |
| `build_windows.bat` | Windows release build script |
