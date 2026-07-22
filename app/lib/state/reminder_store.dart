import 'package:flutter/foundation.dart';

import '../data/reminder_database.dart';
import '../models/reminder.dart';
import '../models/repeat_interval.dart';
import '../services/notification_service.dart';
import '../services/photo_store.dart';
import 'settings_store.dart';

/// Ücretsiz sürüm hatırlatma limiti aşıldığında fırlatılır.
class ReminderLimitException implements Exception {
  const ReminderLimitException(this.limit);
  final int limit;
}

class ReminderStore extends ChangeNotifier {
  ReminderStore({
    required SettingsStore settings,
    ReminderDatabase? database,
    NotificationService? notifications,
    PhotoStore? photos,
  })  : _settings = settings,
        _db = database ?? ReminderDatabase.instance,
        _notifications = notifications ?? NotificationService.instance,
        _photos = photos ?? PhotoStore.instance;

  final SettingsStore _settings;
  final ReminderDatabase _db;
  final NotificationService _notifications;
  final PhotoStore _photos;

  List<Reminder> _reminders = const [];
  bool _isLoading = true;

  bool get isLoading => _isLoading;

  /// Son tarihe göre sıralı, arşivlenmemiş hatırlatmalar.
  List<Reminder> get active {
    final list = _reminders.where((r) => !r.isArchived).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return List.unmodifiable(list);
  }

  List<Reminder> get archived {
    final list = _reminders.where((r) => r.isArchived).toList()
      ..sort((a, b) => b.dueDate.compareTo(a.dueDate));
    return List.unmodifiable(list);
  }

  int get activeCount => active.length;

  /// Kalan ücretsiz hak. Premium'da `null` (sınırsız).
  int? get remainingFreeSlots {
    if (_settings.isPremium) return null;
    final left = SettingsStore.freeReminderLimit - activeCount;
    return left < 0 ? 0 : left;
  }

  bool get canAddReminder =>
      _settings.isPremium || activeCount < SettingsStore.freeReminderLimit;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    _reminders = await _db.fetchAll();
    _isLoading = false;
    notifyListeners();

    // Açılışta bildirimleri yeniden kur (saat dilimi / cihaz yeniden başlatma).
    await _notifications.rescheduleAll(_reminders);

    // Sihirbaz yarıda bırakıldıysa sahipsiz fotoğraflar kalmış olabilir.
    await _photos.pruneOrphans(_referencedPhotos);
  }

  Set<String> get _referencedPhotos =>
      {for (final r in _reminders) ...r.photoPaths};

  Future<Reminder> add(Reminder reminder) async {
    if (!canAddReminder) {
      throw const ReminderLimitException(SettingsStore.freeReminderLimit);
    }
    final saved = await _db.insert(reminder);
    _reminders = [..._reminders, saved];
    notifyListeners();
    await _notifications.schedule(saved);
    return saved;
  }

  Future<void> update(Reminder reminder) async {
    // Kayıttan çıkarılan fotoğrafları diskten de sil.
    final before = _reminders
        .firstWhere((r) => r.id == reminder.id, orElse: () => reminder)
        .photoPaths;
    final removed = before.toSet().difference(reminder.photoPaths.toSet());

    await _db.update(reminder);
    _reminders = [
      for (final r in _reminders) r.id == reminder.id ? reminder : r,
    ];
    notifyListeners();
    await _notifications.schedule(reminder);
    await _photos.deleteAll(removed);
  }

  /// Kaydı siler.
  ///
  /// Satır hemen kaldırılmaz: diğer cihazların silmeyi öğrenebilmesi için
  /// mezar taşı bırakılır ve senkronizasyondan sonra temizlenir. Fotoğraf
  /// dosyaları hemen silinir çünkü yer kaplayan asıl şey onlardır.
  Future<void> delete(Reminder reminder) async {
    final id = reminder.id;
    if (id == null) return;

    await _db.update(reminder.copyWith(isDeleted: true, isDirty: true));
    _reminders = _reminders.where((r) => r.id != id).toList();
    notifyListeners();
    await _notifications.cancel(id);
    await _photos.deleteAll(reminder.photoPaths);
  }

  /// "Tamamlandı" işareti.
  ///
  /// Tekrarlayan bir hatırlatmaysa son tarih bir sonraki döneme taşınır ve
  /// bildirimler yeniden planlanır; tekrar yoksa arşivlenir.
  /// Yanlışlıkla dokunma bir kaydı sessizce bir dönem ileri atabildiği için
  /// kaydın önceki hâli döndürülür; [undoCompleted] ile geri alınabilir.
  Future<Reminder> markCompleted(Reminder reminder) async {
    if (reminder.repeat == RepeatInterval.none) {
      await update(reminder.copyWith(isArchived: true));
      return reminder;
    }

    // Son tarih çok geride kaldıysa gelecekteki ilk döneme kadar ilerlet.
    var next = reminder.repeat.next(reminder.dueDate);
    final today = DateTime.now();
    var guard = 0;
    while (next.isBefore(today) && guard < 120) {
      next = reminder.repeat.next(next);
      guard++;
    }
    await update(reminder.copyWith(dueDate: next));
    return reminder;
  }

  /// [markCompleted] öncesindeki hâli geri yükler.
  Future<void> undoCompleted(Reminder previous) async {
    await update(previous);
  }

  Future<void> restore(Reminder reminder) async {
    if (!canAddReminder) {
      throw const ReminderLimitException(SettingsStore.freeReminderLimit);
    }
    await update(reminder.copyWith(isArchived: false));
  }

  /// Tüm kayıtları siler. Oturum açıksa silme sunucuya da yayılsın diye
  /// mezar taşı bırakılır.
  Future<void> deleteAll() async {
    final photos = _referencedPhotos;
    for (final reminder in _reminders) {
      await _db.update(reminder.copyWith(isDeleted: true, isDirty: true));
    }
    _reminders = const [];
    notifyListeners();
    await _notifications.cancelAll();
    await _photos.deleteAll(photos);
  }

  /// Senkronizasyon sonrası yerel veriyi tazeler ve bildirimleri yeniden kurar.
  Future<void> reloadAfterSync() async {
    _reminders = await _db.fetchAll();
    notifyListeners();
    await _notifications.rescheduleAll(_reminders);
  }
}
