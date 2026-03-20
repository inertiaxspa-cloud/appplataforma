import 'dart:io';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
// Conditional import: desktop uses sqflite_common_ffi (dart:ffi);
// web stub is a no-op so the web build compiles without dart:ffi.
import 'database_ffi_init.dart'
    if (dart.library.html) 'database_ffi_init_stub.dart';

/// SQLite database helper — works on desktop (ffi) and mobile (sqflite).
class DatabaseHelper {
  static const _dbName    = 'inertiax.db';
  static const _dbVersion = 3;

  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    // Switches sqflite to the FFI factory on desktop; no-op on mobile/web.
    initSqfliteForPlatform();

    final dbPath = await _resolveDbPath();
    return openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: _createTables,
      onUpgrade: _migrate,
    );
  }

  /// Retorna siempre la misma ruta en %APPDATA%/InertiaX/ (Windows/Linux/macOS).
  /// En móvil usa getDatabasesPath() como antes.
  /// Si existe un inertiax.db junto al EXE (build anterior), lo migra automáticamente.
  Future<String> _resolveDbPath() async {
    final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;

    if (!isDesktop) {
      return p.join(await getDatabasesPath(), _dbName);
    }

    // Ruta fija: %APPDATA%/InertiaX/inertiax.db
    final appSupport = await getApplicationSupportDirectory();
    final targetDir  = Directory(p.join(appSupport.path, 'InertiaX'));
    if (!targetDir.existsSync()) targetDir.createSync(recursive: true);
    final targetPath = p.join(targetDir.path, _dbName);

    // Migración automática: si hay un .db viejo junto al EXE, copiarlo una vez.
    if (!File(targetPath).existsSync()) {
      final exeDir  = p.dirname(Platform.resolvedExecutable);
      final legacyCwd = p.join(Directory.current.path, _dbName);
      final legacyExe = p.join(exeDir, _dbName);
      for (final legacy in [legacyExe, legacyCwd]) {
        if (File(legacy).existsSync()) {
          File(legacy).copySync(targetPath);
          break;
        }
      }
    }

    return targetPath;
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE athletes (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        name          TEXT    NOT NULL,
        sport         TEXT,
        body_weight_kg REAL,
        notes         TEXT,
        created_at    TEXT    NOT NULL DEFAULT (datetime('now')),
        supabase_uuid TEXT    UNIQUE
      )
    ''');

    await db.execute('''
      CREATE TABLE calibrations (
        id                    INTEGER PRIMARY KEY AUTOINCREMENT,
        name                  TEXT    NOT NULL,
        mode                  INTEGER NOT NULL DEFAULT 0,
        coefficients_json     TEXT    NOT NULL DEFAULT '[]',
        cell_offsets_json     TEXT    NOT NULL DEFAULT '{}',
        cell_gains_json       TEXT    NOT NULL DEFAULT '{}',
        cell_polarities_json  TEXT    NOT NULL DEFAULT '{}',
        is_active             INTEGER NOT NULL DEFAULT 1,
        created_at            TEXT    NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE calibration_points (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        calibration_id   INTEGER NOT NULL REFERENCES calibrations(id) ON DELETE CASCADE,
        weight_kg        REAL    NOT NULL,
        raw_sum          REAL    NOT NULL,
        raw_aml          REAL    NOT NULL DEFAULT 0,
        raw_amr          REAL    NOT NULL DEFAULT 0,
        raw_asl          REAL    NOT NULL DEFAULT 0,
        raw_asr          REAL    NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE test_sessions (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        athlete_id      INTEGER NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
        test_type       TEXT    NOT NULL,
        performed_at    TEXT    NOT NULL DEFAULT (datetime('now')),
        body_weight_kg  REAL    NOT NULL,
        calibration_id  INTEGER REFERENCES calibrations(id),
        platform_count  INTEGER NOT NULL DEFAULT 1,
        notes           TEXT,
        raw_data_json   TEXT,
        result_json     TEXT,
        sync_status     TEXT    NOT NULL DEFAULT 'pending',
        supabase_uuid   TEXT    UNIQUE
      )
    ''');

    await db.execute('''
      CREATE TABLE jump_results (
        session_id            INTEGER PRIMARY KEY REFERENCES test_sessions(id) ON DELETE CASCADE,
        jump_height_cm        REAL,
        flight_time_ms        REAL,
        contact_time_ms       REAL,
        peak_force_n          REAL,
        mean_force_n          REAL,
        rsi_mod               REAL,
        asymmetry_index_pct   REAL,
        platform_a_pct        REAL,
        peak_power_w          REAL,
        rfd_50ms              REAL,
        rfd_100ms             REAL,
        rfd_200ms             REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE cop_results (
        session_id          INTEGER PRIMARY KEY REFERENCES test_sessions(id) ON DELETE CASCADE,
        condition           TEXT,
        stance              TEXT,
        duration_s          REAL,
        area_ellipse_mm2    REAL,
        path_length_mm      REAL,
        velocity_mm_s       REAL,
        range_ml_mm         REAL,
        range_ap_mm         REAL,
        symmetry_pct        REAL,
        romberg_quotient    REAL
      )
    ''');

    await db.execute('CREATE INDEX idx_sessions_athlete ON test_sessions(athlete_id)');
    await db.execute('CREATE INDEX idx_sessions_type ON test_sessions(test_type)');
  }

  Future<void> _migrate(Database db, int oldVersion, int newVersion) async {
    for (int v = oldVersion + 1; v <= newVersion; v++) {
      if (v == 2) {
        // Add per-cell calibration columns (idempotent: ignore if already exist)
        for (final sql in [
          "ALTER TABLE calibrations ADD COLUMN cell_gains_json TEXT NOT NULL DEFAULT '{}'",
          'ALTER TABLE calibration_points ADD COLUMN raw_aml REAL NOT NULL DEFAULT 0',
          'ALTER TABLE calibration_points ADD COLUMN raw_amr REAL NOT NULL DEFAULT 0',
          'ALTER TABLE calibration_points ADD COLUMN raw_asl REAL NOT NULL DEFAULT 0',
          'ALTER TABLE calibration_points ADD COLUMN raw_asr REAL NOT NULL DEFAULT 0',
        ]) {
          try { await db.execute(sql); } catch (_) { /* column already exists */ }
        }
      }
      if (v == 3) {
        // Add per-cell polarity storage (idempotent)
        try {
          await db.execute(
              "ALTER TABLE calibrations ADD COLUMN cell_polarities_json TEXT NOT NULL DEFAULT '{}'");
        } catch (_) { /* column already exists */ }
      }
    }
  }

  // ── Athletes ───────────────────────────────────────────────────────────────

  Future<int> insertAthlete(Map<String, dynamic> athlete) async {
    final db = await database;
    return db.insert('athletes', athlete,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getAthletes() async {
    final db = await database;
    return db.query('athletes', orderBy: 'name ASC');
  }

  Future<Map<String, dynamic>?> getAthlete(int id) async {
    final db = await database;
    final rows = await db.query('athletes', where: 'id = ?', whereArgs: [id]);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<int> updateAthlete(Map<String, dynamic> athlete) async {
    final db = await database;
    return db.update('athletes', athlete,
        where: 'id = ?', whereArgs: [athlete['id']]);
  }

  Future<void> deleteAthlete(int id) async {
    final db = await database;
    await db.delete('athletes', where: 'id = ?', whereArgs: [id]);
  }

  // ── Calibrations ──────────────────────────────────────────────────────────

  Future<int> insertCalibration(Map<String, dynamic> cal) async {
    final db = await database;
    // Deactivate previous active calibrations
    await db.update('calibrations', {'is_active': 0});
    return db.insert('calibrations', cal);
  }

  Future<Map<String, dynamic>?> getActiveCalibration() async {
    final db = await database;
    final rows = await db.query('calibrations',
        where: 'is_active = 1', orderBy: 'created_at DESC', limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<List<Map<String, dynamic>>> getCalibrations() async {
    final db = await database;
    return db.query('calibrations', orderBy: 'created_at DESC');
  }

  Future<int> insertCalibrationPoint(Map<String, dynamic> point) async {
    final db = await database;
    return db.insert('calibration_points', point);
  }

  Future<List<Map<String, dynamic>>> getCalibrationPoints(int calId) async {
    final db = await database;
    return db.query('calibration_points',
        where: 'calibration_id = ?', whereArgs: [calId],
        orderBy: 'weight_kg ASC');
  }

  // ── Test sessions ──────────────────────────────────────────────────────────

  Future<int> insertTestSession(Map<String, dynamic> session) async {
    final db = await database;
    return db.insert('test_sessions', session);
  }

  Future<int> updateTestSession(Map<String, dynamic> session) async {
    final db = await database;
    return db.update('test_sessions', session,
        where: 'id = ?', whereArgs: [session['id']]);
  }

  Future<List<Map<String, dynamic>>> getSessionsForAthlete(int athleteId) async {
    final db = await database;
    return db.query('test_sessions',
        where: 'athlete_id = ?', whereArgs: [athleteId],
        orderBy: 'performed_at DESC');
  }

  Future<List<Map<String, dynamic>>> getAllSessions({int? limit}) async {
    final db = await database;
    return db.query('test_sessions',
        orderBy: 'performed_at DESC', limit: limit);
  }

  /// Returns sessions joined with athlete name for the history list.
  Future<List<Map<String, dynamic>>> getAllSessionsWithAthlete({int? limit}) async {
    final db = await database;
    final limitClause = limit != null ? 'LIMIT $limit' : '';
    return db.rawQuery('''
      SELECT ts.*, a.name AS athlete_name
      FROM test_sessions ts
      LEFT JOIN athletes a ON a.id = ts.athlete_id
      ORDER BY ts.performed_at DESC
      $limitClause
    ''');
  }

  Future<Map<String, dynamic>?> getSession(int id) async {
    final db = await database;
    final rows = await db.query('test_sessions',
        where: 'id = ?', whereArgs: [id]);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<void> deleteSession(int id) async {
    final db = await database;
    await db.delete('test_sessions', where: 'id = ?', whereArgs: [id]);
  }

  /// Returns sessions for one athlete + test type, sorted by date ASC (for trend charts).
  Future<List<Map<String, dynamic>>> getSessionsForAthleteAndType(
      int athleteId, String testType) async {
    final db = await database;
    return db.rawQuery('''
      SELECT ts.*, a.name AS athlete_name
      FROM test_sessions ts
      LEFT JOIN athletes a ON a.id = ts.athlete_id
      WHERE ts.athlete_id = ? AND ts.test_type = ?
      ORDER BY ts.performed_at ASC
    ''', [athleteId, testType]);
  }

  Future<void> close() async => (await database).close();
}
