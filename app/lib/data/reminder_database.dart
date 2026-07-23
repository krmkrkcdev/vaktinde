import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/reminder.dart';

/// Cihaz üzerindeki SQLite deposu. Backend gerektirmez.
class ReminderDatabase {
  ReminderDatabase._();

  static final ReminderDatabase instance = ReminderDatabase._();

  static const _dbName = 'vaktinde.db';

  /// v2: belge fotoğrafları için `photo_paths` sütunu eklendi.
  /// v3: bulut senkronizasyonu için `uuid`, `updated_at`, `is_deleted`,
  ///     `is_dirty` sütunları eklendi.
  /// v4: tamamlanmayan hatırlatmanın tekrarı için `nag_interval_hours`.
  static const _dbVersion = 4;
  static const _table = 'reminders';

  Database? _db;

  Future<Database> get database async {
    return _db ??= await _open();
  }

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid TEXT NOT NULL UNIQUE,
            updated_at INTEGER NOT NULL DEFAULT 0,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            is_dirty INTEGER NOT NULL DEFAULT 1,
            category_id TEXT NOT NULL,
            title TEXT NOT NULL,
            note TEXT,
            due_date INTEGER NOT NULL,
            lead_days TEXT NOT NULL,
            notify_hour INTEGER NOT NULL DEFAULT 9,
            notify_minute INTEGER NOT NULL DEFAULT 0,
            nag_interval_hours INTEGER,
            repeat_interval TEXT NOT NULL DEFAULT 'none',
            is_archived INTEGER NOT NULL DEFAULT 0,
            amount REAL,
            photo_paths TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_reminders_due_date ON $_table (due_date)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE $_table ADD COLUMN photo_paths TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 3) {
          // SQLite'ta UNIQUE kısıtlı sütun ALTER ile eklenemez; sütun önce
          // sade olarak eklenir, doldurulur, sonra benzersiz indeks kurulur.
          await db.execute(
            "ALTER TABLE $_table ADD COLUMN uuid TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
          );
          // Mevcut kayıtlar hiç gönderilmediği için kirli işaretlenir; ilk
          // girişte tamamı sunucuya yüklenir.
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN is_dirty INTEGER NOT NULL DEFAULT 1',
          );

          final now = DateTime.now().millisecondsSinceEpoch;
          const uuidGenerator = Uuid();
          final rows = await db.query(_table, columns: ['id']);
          for (final row in rows) {
            await db.update(
              _table,
              {'uuid': uuidGenerator.v4(), 'updated_at': now},
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          }

          await db.execute(
            'CREATE UNIQUE INDEX idx_reminders_uuid ON $_table (uuid)',
          );
        }
        if (oldVersion < 4) {
          // Nullable: null = tekrar hatırlatma kapalı. Mevcut kayıtların
          // davranışı değişmez.
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN nag_interval_hours INTEGER',
          );
        }
      },
    );
  }

  /// Kullanıcıya gösterilecek kayıtlar. Silinmiş olanlar (mezar taşları)
  /// senkronize edilene kadar tabloda durur ama listelerde görünmez.
  Future<List<Reminder>> fetchAll() async {
    final db = await database;
    final rows = await db.query(
      _table,
      where: 'is_deleted = 0',
      orderBy: 'due_date ASC',
    );
    return rows.map(Reminder.fromMap).toList();
  }

  /// Sunucuya gönderilmeyi bekleyen kayıtlar (silinmişler dahil).
  Future<List<Reminder>> fetchDirty() async {
    final db = await database;
    final rows = await db.query(_table, where: 'is_dirty = 1');
    return rows.map(Reminder.fromMap).toList();
  }

  Future<Reminder?> findByUuid(String uuid) async {
    final db = await database;
    final rows = await db.query(
      _table,
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    return rows.isEmpty ? null : Reminder.fromMap(rows.first);
  }

  /// Başarıyla gönderilen kayıtları temiz olarak işaretler.
  Future<void> markSynced(Iterable<String> uuids) async {
    if (uuids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(uuids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE $_table SET is_dirty = 0 WHERE uuid IN ($placeholders)',
      uuids.toList(),
    );
  }

  /// Sunucuya bildirilmiş mezar taşlarını kalıcı olarak siler.
  Future<void> purgeSyncedTombstones() async {
    final db = await database;
    await db.delete(_table, where: 'is_deleted = 1 AND is_dirty = 0');
  }

  Future<int> countActive() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $_table WHERE is_archived = 0 AND is_deleted = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<Reminder> insert(Reminder reminder) async {
    final db = await database;
    final id = await db.insert(_table, reminder.toMap());
    return reminder.copyWith(id: id);
  }

  Future<void> update(Reminder reminder) async {
    assert(reminder.id != null, 'Kaydedilmemiş hatırlatma güncellenemez');
    final db = await database;
    await db.update(
      _table,
      reminder.toMap(),
      where: 'id = ?',
      whereArgs: [reminder.id],
    );
  }

  /// Sunucudan gelen kaydı yerele yazar.
  ///
  /// Yereldeki kayıt kirliyse ve daha yeniyse dokunulmaz: kullanıcının henüz
  /// gönderilmemiş düzenlemesi sunucu sürümü tarafından ezilmemelidir.
  Future<void> upsertFromServer(Reminder incoming) async {
    final db = await database;
    final existing = await findByUuid(incoming.uuid);

    if (existing == null) {
      await db.insert(_table, incoming.toMap());
      return;
    }

    if (existing.isDirty && existing.updatedAt.isAfter(incoming.updatedAt)) {
      return;
    }

    // copyWith kullanılmaz: her çağrıda `updatedAt` değerini şimdiye çeker ve
    // sunucudan gelen zaman damgasını bozar.
    await db.update(
      _table,
      incoming.toMap()..['id'] = existing.id,
      where: 'id = ?',
      whereArgs: [existing.id],
    );
  }

  Future<void> delete(int id) async {
    final db = await database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAll() async {
    final db = await database;
    await db.delete(_table);
  }
}
