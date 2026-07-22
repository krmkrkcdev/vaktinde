import 'package:uuid/uuid.dart';

import 'reminder_category.dart';
import 'repeat_interval.dart';

const _uuidGenerator = Uuid();

/// Tek bir hatırlatma kaydı. Tamamı cihazdaki SQLite veritabanında saklanır.
class Reminder {
  const Reminder({
    this.id,
    required this.uuid,
    required this.updatedAt,
    this.isDeleted = false,
    this.isDirty = true,
    required this.categoryId,
    required this.title,
    this.note,
    required this.dueDate,
    required this.leadDays,
    required this.notifyHour,
    required this.notifyMinute,
    required this.repeat,
    this.isArchived = false,
    this.amount,
    this.photoPaths = const [],
    required this.createdAt,
  });

  /// Yerel SQLite satır kimliği. Yalnızca cihaz içinde anlamlıdır.
  final int? id;

  /// Cihazlar arası kalıcı kimlik. Kayıt çevrimdışı oluşturulabildiği için
  /// sunucu değil istemci üretir ve senkronizasyondan sonra da değişmez.
  final String uuid;

  /// Son yerel değişiklik zamanı. Sunucudaki çakışma çözümü (son yazan
  /// kazanır) bu değere bakar.
  final DateTime updatedAt;

  /// Mezar taşı. Kayıt silindiğinde satır hemen kaldırılmaz; diğer cihazlar
  /// silmeyi öğrensin diye senkronize edilene kadar işaretli kalır.
  final bool isDeleted;

  /// Sunucuya henüz gönderilmemiş değişiklik var mı?
  final bool isDirty;

  final String categoryId;
  final String title;
  final String? note;

  /// Son tarih (saat bileşeni yok sayılır, gün bazında değerlendirilir).
  final DateTime dueDate;

  /// Kaç gün önceden hatırlatılacağı. 0 = son gün. Örn: [30, 7, 1]
  final List<int> leadDays;

  /// Bildirimin gönderileceği saat.
  final int notifyHour;
  final int notifyMinute;

  final RepeatInterval repeat;
  final bool isArchived;

  /// İsteğe bağlı tutar (kira, fatura, aidat için).
  final double? amount;

  /// Belge fotoğraflarının uygulama dizinindeki dosya adları (fatura, garanti
  /// belgesi vb.). Tam yol çalışma zamanında çözülür — iOS uygulama dizininin
  /// mutlak yolu her güncellemede değişebildiği için mutlak yol saklanmaz.
  final List<String> photoPaths;

  final DateTime createdAt;

  /// Kullanıcının oluşturduğu yeni bir hatırlatma.
  ///
  /// Kimlik ve zaman damgaları burada üretilir; çağıranın senkronizasyon
  /// ayrıntılarıyla uğraşması gerekmez.
  factory Reminder.create({
    required String categoryId,
    required String title,
    String? note,
    required DateTime dueDate,
    required List<int> leadDays,
    required int notifyHour,
    required int notifyMinute,
    required RepeatInterval repeat,
    double? amount,
    List<String> photoPaths = const [],
  }) {
    final now = DateTime.now();
    return Reminder(
      uuid: _uuidGenerator.v4(),
      updatedAt: now,
      categoryId: categoryId,
      title: title,
      note: note,
      dueDate: dueDate,
      leadDays: leadDays,
      notifyHour: notifyHour,
      notifyMinute: notifyMinute,
      repeat: repeat,
      amount: amount,
      photoPaths: photoPaths,
      createdAt: now,
    );
  }

  ReminderCategory get category => ReminderCategory.byId(categoryId);

  /// Son tarihe kalan tam gün sayısı. Negatifse tarih geçmiştir.
  int get daysRemaining {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return due.difference(today).inDays;
  }

  bool get isOverdue => daysRemaining < 0;
  bool get isDueToday => daysRemaining == 0;

  /// Bu hatırlatma için planlanacak bildirim zamanları (yalnızca gelecektekiler).
  List<DateTime> upcomingNotificationTimes() {
    final now = DateTime.now();
    final times = <DateTime>[];
    for (final lead in leadDays) {
      final base = DateTime(dueDate.year, dueDate.month, dueDate.day)
          .subtract(Duration(days: lead));
      final at = DateTime(
        base.year,
        base.month,
        base.day,
        notifyHour,
        notifyMinute,
      );
      if (at.isAfter(now)) times.add(at);
    }
    return times;
  }

  Reminder copyWith({
    int? id,
    String? uuid,
    DateTime? updatedAt,
    bool? isDeleted,
    bool? isDirty,
    String? categoryId,
    String? title,
    String? note,
    bool clearNote = false,
    DateTime? dueDate,
    List<int>? leadDays,
    int? notifyHour,
    int? notifyMinute,
    RepeatInterval? repeat,
    bool? isArchived,
    double? amount,
    bool clearAmount = false,
    List<String>? photoPaths,
    DateTime? createdAt,
  }) {
    return Reminder(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      // Her düzenleme kaydı kirletir; çağıranın ayrıca belirtmesi gerekmez.
      updatedAt: updatedAt ?? DateTime.now(),
      isDeleted: isDeleted ?? this.isDeleted,
      isDirty: isDirty ?? true,
      categoryId: categoryId ?? this.categoryId,
      title: title ?? this.title,
      note: clearNote ? null : (note ?? this.note),
      dueDate: dueDate ?? this.dueDate,
      leadDays: leadDays ?? this.leadDays,
      notifyHour: notifyHour ?? this.notifyHour,
      notifyMinute: notifyMinute ?? this.notifyMinute,
      repeat: repeat ?? this.repeat,
      isArchived: isArchived ?? this.isArchived,
      amount: clearAmount ? null : (amount ?? this.amount),
      photoPaths: photoPaths ?? this.photoPaths,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'uuid': uuid,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'is_deleted': isDeleted ? 1 : 0,
      'is_dirty': isDirty ? 1 : 0,
      'category_id': categoryId,
      'title': title,
      'note': note,
      'due_date': dueDate.millisecondsSinceEpoch,
      'lead_days': leadDays.join(','),
      'notify_hour': notifyHour,
      'notify_minute': notifyMinute,
      'repeat_interval': repeat.id,
      'is_archived': isArchived ? 1 : 0,
      'amount': amount,
      // Dosya adları uygulama tarafından üretilir ve satır sonu içermez.
      'photo_paths': photoPaths.join('\n'),
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory Reminder.fromMap(Map<String, Object?> map) {
    final rawLeads = (map['lead_days'] as String?) ?? '';
    final leads = rawLeads
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    return Reminder(
      id: map['id'] as int?,
      uuid: map['uuid'] as String,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        map['updated_at'] as int? ?? 0,
      ),
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      isDirty: (map['is_dirty'] as int? ?? 1) == 1,
      categoryId: map['category_id'] as String,
      title: map['title'] as String,
      note: map['note'] as String?,
      dueDate: DateTime.fromMillisecondsSinceEpoch(map['due_date'] as int),
      leadDays: leads.isEmpty ? const [0] : leads,
      notifyHour: map['notify_hour'] as int? ?? 9,
      notifyMinute: map['notify_minute'] as int? ?? 0,
      repeat: RepeatInterval.fromId(map['repeat_interval'] as String? ?? 'none'),
      isArchived: (map['is_archived'] as int? ?? 0) == 1,
      amount: (map['amount'] as num?)?.toDouble(),
      photoPaths: ((map['photo_paths'] as String?) ?? '')
          .split('\n')
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  /// Sunucuya gönderilen gövde. Fotoğraflar ayrı uçtan yüklendiği için
  /// burada yer almaz.
  Map<String, Object?> toApi() {
    return {
      'id': uuid,
      'category_id': categoryId,
      'title': title,
      'note': note,
      'due_date': dueDate.toUtc().toIso8601String(),
      'lead_days': leadDays.join(','),
      'notify_hour': notifyHour,
      'notify_minute': notifyMinute,
      'repeat_interval': repeat.id,
      'is_archived': isArchived,
      'amount': amount,
      'created_at': createdAt.toUtc().toIso8601String(),
      'is_deleted': isDeleted,
      'client_updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  /// Sunucudan gelen kayıt. Yerel satır kimliği ve fotoğraf listesi
  /// çağıran tarafından eşleştirilir.
  factory Reminder.fromApi(Map<String, Object?> json) {
    final rawLeads = (json['lead_days'] as String?) ?? '';
    final leads = rawLeads
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    return Reminder(
      uuid: json['id'] as String,
      updatedAt: DateTime.parse(json['client_updated_at'] as String).toLocal(),
      isDeleted: json['is_deleted'] as bool? ?? false,
      // Sunucudan geldiği için gönderilecek bir değişiklik yok.
      isDirty: false,
      categoryId: json['category_id'] as String,
      title: json['title'] as String,
      note: json['note'] as String?,
      dueDate: DateTime.parse(json['due_date'] as String).toLocal(),
      leadDays: leads.isEmpty ? const [0] : leads,
      notifyHour: json['notify_hour'] as int? ?? 9,
      notifyMinute: json['notify_minute'] as int? ?? 0,
      repeat: RepeatInterval.fromId(json['repeat_interval'] as String? ?? 'none'),
      isArchived: json['is_archived'] as bool? ?? false,
      amount: (json['amount'] as num?)?.toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }
}
