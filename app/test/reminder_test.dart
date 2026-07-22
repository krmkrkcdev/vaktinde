import 'package:flutter_test/flutter_test.dart';
import 'package:vaktinde/models/reminder.dart';
import 'package:vaktinde/models/reminder_category.dart';
import 'package:vaktinde/models/repeat_interval.dart';
import 'package:vaktinde/services/sync_service.dart';

Reminder buildReminder({
  DateTime? dueDate,
  List<int> leadDays = const [30, 7, 1],
  int notifyHour = 9,
  RepeatInterval repeat = RepeatInterval.none,
  double? amount,
}) {
  return Reminder(
    id: 1,
    uuid: '11111111-2222-3333-4444-555555555555',
    updatedAt: DateTime(2026, 7, 1, 12),
    categoryId: 'bill',
    title: 'Elektrik faturası',
    dueDate: dueDate ?? DateTime(2026, 8, 20),
    leadDays: leadDays,
    notifyHour: notifyHour,
    notifyMinute: 0,
    repeat: repeat,
    amount: amount,
    createdAt: DateTime(2026, 7, 1),
  );
}

void main() {
  group('RepeatInterval.next', () {
    test('aylık tekrar bir sonraki aya taşır', () {
      expect(
        RepeatInterval.monthly.next(DateTime(2026, 1, 15)),
        DateTime(2026, 2, 15),
      );
    });

    test('ayın 31\'i kısa aya taşınırken ay sonuna kırpılır', () {
      expect(
        RepeatInterval.monthly.next(DateTime(2026, 1, 31)),
        DateTime(2026, 2, 28),
      );
    });

    test('yıllık tekrar yılı artırır, artık günü korur', () {
      expect(
        RepeatInterval.yearly.next(DateTime(2026, 12, 5)),
        DateTime(2027, 12, 5),
      );
    });

    test('üç aylık tekrar yıl sınırını aşabilir', () {
      expect(
        RepeatInterval.quarterly.next(DateTime(2026, 11, 10)),
        DateTime(2027, 2, 10),
      );
    });

    test('tekrar yoksa tarih değişmez', () {
      final date = DateTime(2026, 3, 3);
      expect(RepeatInterval.none.next(date), date);
    });
  });

  group('Reminder.daysRemaining', () {
    test('gelecekteki tarih için pozitif', () {
      final reminder = buildReminder(
        dueDate: DateTime.now().add(const Duration(days: 10)),
      );
      expect(reminder.daysRemaining, 10);
      expect(reminder.isOverdue, isFalse);
    });

    test('geçmiş tarih için negatif ve gecikmiş', () {
      final reminder = buildReminder(
        dueDate: DateTime.now().subtract(const Duration(days: 3)),
      );
      expect(reminder.daysRemaining, -3);
      expect(reminder.isOverdue, isTrue);
    });

    test('bugün için sıfır', () {
      expect(buildReminder(dueDate: DateTime.now()).isDueToday, isTrue);
    });
  });

  group('Reminder.upcomingNotificationTimes', () {
    test('yalnızca gelecekteki bildirimleri döndürür', () {
      final reminder = buildReminder(
        dueDate: DateTime.now().add(const Duration(days: 10)),
        leadDays: [30, 7, 1],
      );
      // 30 gün önce zaten geçti; 7 ve 1 gün önce hâlâ gelecekte.
      final times = reminder.upcomingNotificationTimes();
      expect(times.length, 2);
      expect(times.every((t) => t.isAfter(DateTime.now())), isTrue);
    });

    test('bildirim saati ayarlanan saate kurulur', () {
      final reminder = buildReminder(
        dueDate: DateTime.now().add(const Duration(days: 40)),
        leadDays: [7],
        notifyHour: 20,
      );
      final times = reminder.upcomingNotificationTimes();
      expect(times.single.hour, 20);
      expect(times.single.minute, 0);
    });

    test('tarihi tamamen geçmiş hatırlatma bildirim üretmez', () {
      final reminder = buildReminder(
        dueDate: DateTime.now().subtract(const Duration(days: 5)),
        leadDays: [30, 7, 1],
      );
      expect(reminder.upcomingNotificationTimes(), isEmpty);
    });
  });

  group('serileştirme', () {
    test('toMap/fromMap gidiş dönüşü alanları korur', () {
      final original = buildReminder(
        leadDays: [30, 7, 1],
        repeat: RepeatInterval.yearly,
        amount: 1250.5,
      );
      final restored = Reminder.fromMap(original.toMap());

      expect(restored.id, original.id);
      expect(restored.categoryId, original.categoryId);
      expect(restored.title, original.title);
      expect(restored.dueDate, original.dueDate);
      expect(restored.leadDays, original.leadDays);
      expect(restored.notifyHour, original.notifyHour);
      expect(restored.repeat, original.repeat);
      expect(restored.amount, original.amount);
    });

    test('lead_days azalan sırada okunur', () {
      final map = buildReminder().toMap()..['lead_days'] = '1,30,7';
      expect(Reminder.fromMap(map).leadDays, [30, 7, 1]);
    });

    test('boş lead_days aynı gün bildirimine düşer', () {
      final map = buildReminder().toMap()..['lead_days'] = '';
      expect(Reminder.fromMap(map).leadDays, [0]);
    });

    test('belge fotoğrafları gidiş dönüşte korunur', () {
      final original = buildReminder().copyWith(
        photoPaths: ['belge_1.jpg', 'belge_2.jpg'],
      );
      expect(
        Reminder.fromMap(original.toMap()).photoPaths,
        ['belge_1.jpg', 'belge_2.jpg'],
      );
    });

    test('fotoğrafsız kayıt boş liste olarak okunur', () {
      expect(Reminder.fromMap(buildReminder().toMap()).photoPaths, isEmpty);
    });

    test('v1 satırında photo_paths sütunu yoksa boş listeye düşer', () {
      // Şema v2'ye yükseltilmeden önce yazılmış kayıtlar.
      final legacy = buildReminder().toMap()..remove('photo_paths');
      expect(Reminder.fromMap(legacy).photoPaths, isEmpty);
    });
  });

  group('senkronizasyon', () {
    test('toApi/fromApi gidiş dönüşü alanları korur', () {
      final original = buildReminder(
        repeat: RepeatInterval.monthly,
        amount: 1250.5,
      );
      final restored = Reminder.fromApi(original.toApi());

      expect(restored.uuid, original.uuid);
      expect(restored.title, original.title);
      expect(restored.categoryId, original.categoryId);
      expect(restored.leadDays, original.leadDays);
      expect(restored.repeat, original.repeat);
      expect(restored.amount, original.amount);
      expect(restored.dueDate, original.dueDate);
      // Sunucudan gelen kayıtta gönderilecek değişiklik yoktur.
      expect(restored.isDirty, isFalse);
    });

    test('mezar taşı sunucuya silinmiş olarak gider', () {
      final silinmis = buildReminder().copyWith(isDeleted: true);
      expect(silinmis.toApi()['is_deleted'], isTrue);
      expect(Reminder.fromApi(silinmis.toApi()).isDeleted, isTrue);
    });

    test('yeni kayıt benzersiz uuid alır ve kirli başlar', () {
      final a = Reminder.create(
        categoryId: 'bill',
        title: 'A',
        dueDate: DateTime(2026, 9, 1),
        leadDays: const [7],
        notifyHour: 9,
        notifyMinute: 0,
        repeat: RepeatInterval.none,
      );
      final b = Reminder.create(
        categoryId: 'bill',
        title: 'B',
        dueDate: DateTime(2026, 9, 1),
        leadDays: const [7],
        notifyHour: 9,
        notifyMinute: 0,
        repeat: RepeatInterval.none,
      );

      expect(a.uuid, isNotEmpty);
      expect(a.uuid, isNot(b.uuid));
      expect(a.isDirty, isTrue);
      expect(a.isDeleted, isFalse);
    });

    test('copyWith kaydı kirletir ve updatedAt tazeler', () {
      // Temiz ve geçmiş zamanlı bir kayıt doğrudan kurulur: copyWith ile
      // kurulsaydı updatedAt de "şimdi" olur ve karşılaştırma anlamsızlaşırdı.
      final original = Reminder(
        id: 1,
        uuid: '11111111-2222-3333-4444-555555555555',
        updatedAt: DateTime(2026, 7, 1, 12),
        isDirty: false,
        categoryId: 'bill',
        title: 'Elektrik faturası',
        dueDate: DateTime(2026, 8, 20),
        leadDays: const [7],
        notifyHour: 9,
        notifyMinute: 0,
        repeat: RepeatInterval.none,
        createdAt: DateTime(2026, 7, 1),
      );
      final edited = original.copyWith(title: 'Yeni başlık');

      expect(edited.isDirty, isTrue);
      expect(edited.updatedAt.isAfter(original.updatedAt), isTrue);
      // Kimlik ve oluşturma zamanı düzenlemeyle değişmemeli.
      expect(edited.uuid, original.uuid);
      expect(edited.createdAt, original.createdAt);
    });

    test('fotoğraf dosya adından sunucu kimliği çıkarılır', () {
      const uuid = 'abcdef01-2345-6789-abcd-ef0123456789';
      expect(SyncService.photoIdFromFileName('belge_$uuid.jpg'), uuid);
      expect(SyncService.photoIdFromFileName('belge_$uuid.png'), uuid);
      // v3 öncesi zaman damgalı adlar senkronize edilemez.
      expect(SyncService.photoIdFromFileName('belge_1784723118218_11369.jpg'), isNull);
    });
  });

  group('kategoriler', () {
    test('her kategorinin benzersiz kimliği ve ipucu vardır', () {
      final ids = ReminderCategory.all.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final category in ReminderCategory.all) {
        expect(category.hint, isNotEmpty, reason: category.id);
      }
    });

    test('kullanıcı tarafından istenen kategoriler mevcut', () {
      final ids = ReminderCategory.all.map((c) => c.id).toSet();
      expect(ids, containsAll(['subscription', 'credit_card', 'loan']));
    });

    test('bilinmeyen kimlik "Diğer" kategorisine düşer', () {
      expect(ReminderCategory.byId('yok_boyle_bir_sey').id, 'other');
    });
  });

  test('copyWith ile not temizlenebilir', () {
    final withNote = buildReminder().copyWith(note: 'Poliçe 123');
    expect(withNote.copyWith(clearNote: true).note, isNull);
  });
}
