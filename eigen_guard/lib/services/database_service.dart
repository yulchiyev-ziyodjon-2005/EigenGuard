import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/measurement_record.dart';

/// DatabaseService — SQLite orqali monitoring sessiyalarini saqlash va o'qish.
/// Singleton pattern bilan ishlatiladi.
class DatabaseService {
  static DatabaseService? _instance;
  static Database? _database;

  DatabaseService._();

  factory DatabaseService() {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  /// Ma'lumotlar bazasini olish (kerak bo'lsa yaratish)
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(appDir.path, 'eigenguard.db');

    return await openDatabase(
      dbPath,
      version: 5,
      onCreate: _createTables,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE measurements ADD COLUMN object_label TEXT');
        }
        if (oldVersion < 3) {
          // Phase 1 + Phase 3 — material + geo + magnetometer
          await db.execute('ALTER TABLE measurements ADD COLUMN material_id TEXT');
          await db.execute('ALTER TABLE measurements ADD COLUMN latitude REAL');
          await db.execute('ALTER TABLE measurements ADD COLUMN longitude REAL');
          await db.execute('ALTER TABLE measurements ADD COLUMN location_accuracy_m REAL');
          await db.execute('ALTER TABLE measurements ADD COLUMN magnetic_field_ut REAL');
          await db.execute('ALTER TABLE measurements ADD COLUMN magnetic_anomaly INTEGER');
        }
        if (oldVersion < 4) {
          // Phase 7 — to'liq tarix: real bufferlar saqlash
          await db.execute('ALTER TABLE measurements ADD COLUMN amplitude_series BLOB');
          await db.execute('ALTER TABLE measurements ADD COLUMN fft_spectrum BLOB');
          await db.execute('ALTER TABLE measurements ADD COLUMN fft_sample_rate REAL');
          await db.execute('ALTER TABLE measurements ADD COLUMN prediction_a REAL');
          await db.execute('ALTER TABLE measurements ADD COLUMN prediction_b REAL');
          await db.execute('ALTER TABLE measurements ADD COLUMN prediction_c REAL');
          await db.execute('ALTER TABLE measurements ADD COLUMN hours_to_critical REAL');
          await db.execute('ALTER TABLE measurements ADD COLUMN hotspots_json TEXT');
          await _createScansTable(db);
        }
        if (oldVersion < 5) {
          // Sprint 15 — B2G ekotizimi: Nexus backend sync uchun tayyor maydonlar
          await db.execute("ALTER TABLE measurements ADD COLUMN device_id TEXT");
          await db.execute("ALTER TABLE measurements ADD COLUMN source TEXT NOT NULL DEFAULT 'mobile'");
          await db.execute("ALTER TABLE measurements ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'pending'");
          await db.execute("ALTER TABLE measurements ADD COLUMN nexus_id TEXT");
          await db.execute("ALTER TABLE measurements ADD COLUMN fusion_confidence REAL");
          await db.execute("ALTER TABLE scans ADD COLUMN device_id TEXT");
          await db.execute("ALTER TABLE scans ADD COLUMN source TEXT NOT NULL DEFAULT 'mobile'");
          await db.execute("ALTER TABLE scans ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'pending'");
          await db.execute("ALTER TABLE scans ADD COLUMN nexus_id TEXT");
          await db.execute(
              "CREATE INDEX IF NOT EXISTS idx_measurements_sync ON measurements(sync_status)");
          await db.execute(
              "CREATE INDEX IF NOT EXISTS idx_measurements_source ON measurements(source)");
        }
      },
    );
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE measurements (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp       TEXT    NOT NULL,
        risk_percent    REAL    NOT NULL,
        frequency       REAL    NOT NULL,
        amplitude       REAL    NOT NULL,
        spline_error    REAL    NOT NULL,
        frame_count     INTEGER NOT NULL,
        duration_seconds INTEGER NOT NULL,
        risk_level      TEXT    NOT NULL,
        object_label    TEXT,
        material_id     TEXT,
        latitude        REAL,
        longitude       REAL,
        location_accuracy_m REAL,
        magnetic_field_ut REAL,
        magnetic_anomaly INTEGER,
        amplitude_series BLOB,
        fft_spectrum    BLOB,
        fft_sample_rate REAL,
        prediction_a    REAL,
        prediction_b    REAL,
        prediction_c    REAL,
        hours_to_critical REAL,
        hotspots_json   TEXT,
        device_id       TEXT,
        source          TEXT    NOT NULL DEFAULT 'mobile',
        sync_status     TEXT    NOT NULL DEFAULT 'pending',
        nexus_id        TEXT,
        fusion_confidence REAL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_measurements_sync ON measurements(sync_status)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_measurements_source ON measurements(source)');
    await _createScansTable(db);
  }

  Future<void> _createScansTable(Database db) async {
    // Point cloud — alohida jadval (BLOB hajmi katta bo'lishi mumkin)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scans (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        measurement_id  INTEGER NOT NULL,
        points_blob     BLOB    NOT NULL,
        point_count     INTEGER NOT NULL,
        device_id       TEXT,
        source          TEXT    NOT NULL DEFAULT 'mobile',
        sync_status     TEXT    NOT NULL DEFAULT 'pending',
        nexus_id        TEXT,
        FOREIGN KEY (measurement_id) REFERENCES measurements(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_scans_measurement ON scans(measurement_id)');
  }

  // ─────────────────────────────────────────────────────────────
  // Sprint 15 — Sync helper'lari (Nexus backend uchun)
  // ─────────────────────────────────────────────────────────────

  /// Sync uchun kutilayotgan yozuvlar (Nexus backend ga yuborilmagan)
  Future<List<MeasurementRecord>> getPendingSyncRecords({int limit = 50}) async {
    final db = await database;
    final maps = await db.query(
      'measurements',
      where: 'sync_status = ?',
      whereArgs: ['pending'],
      orderBy: 'timestamp ASC',
      limit: limit,
    );
    return maps.map(MeasurementRecord.fromMap).toList();
  }

  /// Yozuvni Nexus ga muvaffaqiyatli yuklash natijasini belgilash
  Future<void> markRecordSynced(int id, {String? nexusId}) async {
    final db = await database;
    await db.update(
      'measurements',
      {'sync_status': 'synced', if (nexusId != null) 'nexus_id': nexusId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Sync xatosi (qayta urinib ko'rilishi mumkin)
  Future<void> markRecordSyncFailed(int id) async {
    final db = await database;
    await db.update(
      'measurements',
      {'sync_status': 'failed'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // CRUD Operatsiyalar
  // ─────────────────────────────────────────────────────────────

  /// Yangi o'lchov sessiyasini saqlash
  Future<int> insertMeasurement(MeasurementRecord record) async {
    final db = await database;
    return await db.insert(
      'measurements',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Barcha o'lchovlarni olish (eng yangi birinchi)
  Future<List<MeasurementRecord>> getAllMeasurements({int limit = 50}) async {
    final db = await database;
    final maps = await db.query(
      'measurements',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return maps.map(MeasurementRecord.fromMap).toList();
  }

  /// Oxirgi N ta o'lchovni olish
  Future<List<MeasurementRecord>> getRecentMeasurements(int count) async {
    return getAllMeasurements(limit: count);
  }

  /// O'rtacha xavf darajasini hisoblash (so'nggi 10 sessiya)
  Future<double> getAverageRisk({int lastN = 10}) async {
    final db = await database;
    final result = await db.rawQuery(
      '''SELECT AVG(risk_percent) as avg_risk FROM 
         (SELECT risk_percent FROM measurements 
          ORDER BY timestamp DESC LIMIT ?)''',
      [lastN],
    );
    if (result.isEmpty || result.first['avg_risk'] == null) return 0.0;
    return (result.first['avg_risk'] as num).toDouble();
  }

  /// Jami sessiyalar soni
  Future<int> getTotalCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM measurements',
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// Eng yuqori xavf darajasi
  Future<double> getMaxRisk() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT MAX(risk_percent) as max_risk FROM measurements',
    );
    if (result.isEmpty || result.first['max_risk'] == null) return 0.0;
    return (result.first['max_risk'] as num).toDouble();
  }

  /// Bitta o'lchovni o'chirish (point cloud bilan)
  Future<void> deleteMeasurement(int id) async {
    final db = await database;
    await db.delete('scans', where: 'measurement_id = ?', whereArgs: [id]);
    await db.delete('measurements', where: 'id = ?', whereArgs: [id]);
  }

  /// Barcha o'lchovlarni tozalash
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('scans');
    await db.delete('measurements');
  }

  /// Phase 7 — Bitta o'lchov ID si bo'yicha to'liq yozuvni olish
  Future<MeasurementRecord?> getMeasurementById(int id) async {
    final db = await database;
    final maps = await db.query('measurements',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return MeasurementRecord.fromMap(maps.first);
  }

  /// Bazani yopish
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
