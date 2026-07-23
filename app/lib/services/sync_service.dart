import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/reminder_database.dart';
import '../models/reminder.dart';
import 'api_client.dart';
import 'photo_store.dart';

enum SyncState { idle, running, offline, failed }

/// Yerel SQLite ile sunucu arasında iki yönlü senkronizasyon.
///
/// Uygulama çevrimdışı önceliklidir: telefondaki veritabanı ana kaynaktır ve
/// bildirimler internet olmadan da çalışır. Bu servis yalnızca yedekleme ve
/// cihazlar arası aktarım sağlar; başarısız olması uygulamanın çalışmasını
/// engellemez.
class SyncService {
  SyncService({
    required this.api,
    ReminderDatabase? database,
    PhotoStore? photos,
  }) : _db = database ?? ReminderDatabase.instance,
       _photos = photos ?? PhotoStore.instance;

  static const _keyCursor = 'sync_cursor';

  final ApiClient api;
  final ReminderDatabase _db;
  final PhotoStore _photos;

  bool _running = false;

  /// Fotoğraf dosya adı ile sunucudaki kimliği arasındaki bağ.
  ///
  /// Dosya adları `belge_<uuid>.<uzantı>` biçiminde üretilir; uzantı ve önek
  /// çıkarıldığında sunucunun beklediği kimlik elde edilir. Ayrı bir eşleme
  /// tablosu tutmaya gerek kalmaz.
  static String? photoIdFromFileName(String fileName) {
    final match = RegExp(r'^belge_([0-9a-fA-F-]{36})\.').firstMatch(fileName);
    return match?.group(1);
  }

  /// Tam bir senkronizasyon turu: önce gönder, sonra çek, sonra fotoğraflar.
  ///
  /// Aynı anda birden fazla tur çalışmaz; ağ yoksa sessizce vazgeçer.
  Future<SyncState> run() async {
    if (_running) return SyncState.running;
    if (!api.hasSession) return SyncState.idle;

    _running = true;
    try {
      await _push();
      await _pull();
      await _syncPhotos();
      await _db.purgeSyncedTombstones();
      return SyncState.idle;
    } on NetworkUnavailableException {
      return SyncState.offline;
    } on ApiException catch (e) {
      // 401 zaten ApiClient tarafından ele alınıp oturum düşürüldü.
      debugPrint('Senkronizasyon başarısız: $e');
      return SyncState.failed;
    } catch (e) {
      debugPrint('Senkronizasyon başarısız: $e');
      return SyncState.failed;
    } finally {
      _running = false;
    }
  }

  // ---------------------------------------------------------------- gönder

  Future<void> _push() async {
    final dirty = await _db.fetchDirty();
    if (dirty.isEmpty) return;

    // Sunucu tek istekte 500 kayıt kabul ediyor.
    for (var i = 0; i < dirty.length; i += 200) {
      final batch = dirty.skip(i).take(200).toList();
      final response = await api.push([for (final r in batch) r.toApi()]);

      final rejected = ((response['rejected_ids'] as List?) ?? const [])
          .cast<String>()
          .toSet();

      // Reddedilenler kirli kalır; bir sonraki çekimde sunucu sürümü gelir ve
      // yerel kopyanın üzerine yazılır.
      await _db.markSynced(
        batch.map((r) => r.uuid).where((uuid) => !rejected.contains(uuid)),
      );
    }
  }

  // ------------------------------------------------------------------ çek

  Future<void> _pull() async {
    final prefs = await SharedPreferences.getInstance();
    var cursor = prefs.getInt(_keyCursor) ?? 0;
    var hasMore = true;

    while (hasMore) {
      final response = await api.fetchChanges(cursor);

      for (final json
          in (response['reminders'] as List).cast<Map<String, Object?>>()) {
        await _db.upsertFromServer(Reminder.fromApi(json));
      }

      _pendingPhotos.addAll(
        (response['photos'] as List).cast<Map<String, Object?>>(),
      );

      final next = response['cursor'] as int;
      hasMore = (response['has_more'] as bool?) ?? false;

      // İmleç ilerlemiyorsa sonsuz döngüye girmeyiz.
      if (next <= cursor) break;
      cursor = next;
      await prefs.setInt(_keyCursor, cursor);
    }
  }

  final List<Map<String, Object?>> _pendingPhotos = [];

  // ------------------------------------------------------------ fotoğraflar

  Future<void> _syncPhotos() async {
    await _uploadMissing();
    await _downloadMissing();
  }

  /// Yerelde olup sunucuda olmayan fotoğrafları yükler.
  Future<void> _uploadMissing() async {
    final knownRemote = {
      for (final photo in _pendingPhotos) photo['id'] as String,
    };

    for (final reminder in await _db.fetchAll()) {
      for (final fileName in reminder.photoPaths) {
        final photoId = photoIdFromFileName(fileName);
        // Eski biçimli dosya adları (v2 öncesi) senkronize edilemez; yerelde
        // kalmaya devam ederler.
        if (photoId == null || knownRemote.contains(photoId)) continue;

        final file = File(await _photos.resolve(fileName));
        if (!await file.exists()) continue;

        try {
          await api.uploadPhoto(
            photoId: photoId,
            reminderId: reminder.uuid,
            file: file,
          );
        } on ApiException catch (e) {
          // Kota dolması veya reddedilen dosya turu tüm turu durdurmamalı.
          debugPrint('Fotoğraf yüklenemedi ($fileName): $e');
        }
      }
    }
  }

  /// Sunucuda olup yerelde olmayan fotoğrafları indirir.
  Future<void> _downloadMissing() async {
    for (final meta in _pendingPhotos) {
      final photoId = meta['id'] as String;
      final isDeleted = meta['is_deleted'] as bool? ?? false;
      final hasContent = meta['has_content'] as bool? ?? false;

      final fileName = 'belge_$photoId.jpg';
      final path = await _photos.resolve(fileName);
      final file = File(path);

      if (isDeleted) {
        if (await file.exists()) await file.delete();
        continue;
      }

      if (!hasContent || await file.exists()) continue;

      try {
        final bytes = await api.downloadPhoto(photoId);
        await file.writeAsBytes(bytes, flush: true);
        await _attachPhoto(meta['reminder_id'] as String, fileName);
      } on ApiException catch (e) {
        debugPrint('Fotoğraf indirilemedi ($photoId): $e');
      }
    }
    _pendingPhotos.clear();
  }

  /// İndirilen fotoğrafı ilgili hatırlatmanın listesine ekler.
  Future<void> _attachPhoto(String reminderUuid, String fileName) async {
    final reminder = await _db.findByUuid(reminderUuid);
    if (reminder == null || reminder.photoPaths.contains(fileName)) return;

    // Fotoğraf bağlama yerel bir düzeltmedir, kullanıcı düzenlemesi değil:
    // kaydı kirli işaretleyip sunucuya geri göndermeye gerek yok.
    await _db.upsertFromServer(
      Reminder.fromMap(
        reminder.toMap()
          ..['photo_paths'] = [...reminder.photoPaths, fileName].join('\n')
          ..['is_dirty'] = 0,
      ),
    );
  }

  /// Çıkış yapıldığında imleç sıfırlanır; sonraki girişte her şey yeniden
  /// çekilir.
  static Future<void> resetCursor() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCursor);
  }
}
