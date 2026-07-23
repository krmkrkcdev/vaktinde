import 'package:flutter_test/flutter_test.dart';
import 'package:vaktinde/models/payment_totals.dart';
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

    test('saat başı tekrar bir saat ileri taşır', () {
      expect(
        RepeatInterval.hourly.next(DateTime(2026, 3, 3, 23, 30)),
        DateTime(2026, 3, 4, 0, 30),
      );
    });

    test('günlük tekrar bildirim saatini korur', () {
      expect(
        RepeatInterval.daily.next(DateTime(2026, 12, 31, 9, 15)),
        DateTime(2027, 1, 1, 9, 15),
      );
    });

    test('haftalık tekrar yedi gün ekler', () {
      expect(
        RepeatInterval.weekly.next(DateTime(2026, 2, 25, 8, 0)),
        DateTime(2026, 3, 4, 8, 0),
      );
    });

    test('altı aylık tekrar yarım yıl ileri taşır', () {
      expect(
        RepeatInterval.semiannual.next(DateTime(2026, 8, 31)),
        // 31 Ağustos + 6 ay = 28 Şubat: ay sonu kırpılır.
        DateTime(2027, 2, 28),
      );
    });

    test('sürekli tekrar yalnızca saatlik, günlük ve haftalıktır', () {
      // Sürekli olanlar işletim sistemine tekrarlayan bildirim olarak kurulur;
      // son tarihli olanlar "kaç gün önce" mantığıyla tek tek planlanır.
      final continuous = RepeatInterval.values
          .where((r) => r.isContinuous)
          .toSet();
      expect(continuous, {
        RepeatInterval.hourly,
        RepeatInterval.daily,
        RepeatInterval.weekly,
      });
      expect(RepeatInterval.none.isContinuous, isFalse);
      expect(RepeatInterval.monthly.isContinuous, isFalse);
      expect(RepeatInterval.yearly.isContinuous, isFalse);
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
      expect(Reminder.fromMap(original.toMap()).photoPaths, [
        'belge_1.jpg',
        'belge_2.jpg',
      ]);
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
      expect(
        SyncService.photoIdFromFileName('belge_1784723118218_11369.jpg'),
        isNull,
      );
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

  _paymentTotalsTests();
}

void _paymentTotalsTests() {
  Reminder payment(double amount, RepeatInterval repeat) => Reminder.create(
    categoryId: 'fatura',
    title: 'Test',
    dueDate: DateTime(2026, 8, 1),
    leadDays: const [0],
    notifyHour: 9,
    notifyMinute: 0,
    repeat: repeat,
    amount: amount,
  );

  group('PaymentTotals', () {
    test('aylık ödeme yıllık karşılığına çevrilir', () {
      final totals = PaymentTotals.from([payment(700, RepeatInterval.monthly)]);
      expect(totals.yearly, 8400);
      expect(totals.monthly, closeTo(700, 0.01));
      expect(totals.countedReminders, 1);
    });

    test('farklı aralıklar ortak ölçekte toplanır', () {
      // Aylık 100 (yılda 1200) + yıllık 1200 = 2400
      final totals = PaymentTotals.from([
        payment(100, RepeatInterval.monthly),
        payment(1200, RepeatInterval.yearly),
      ]);
      expect(totals.yearly, 2400);
      expect(totals.monthly, closeTo(200, 0.01));
    });

    test('tek seferlik kayıtlar düzenli gidere sayılmaz', () {
      final totals = PaymentTotals.from([payment(500, RepeatInterval.none)]);
      expect(totals.isEmpty, isTrue);
      expect(totals.yearly, 0);
    });

    test('saat başı tekrar toplama dahil edilmez', () {
      // İlaç gibi kayıtlar ödeme değildir; yılda 8760 kez sayılması toplamı
      // anlamsız kılardı.
      final totals = PaymentTotals.from([payment(10, RepeatInterval.hourly)]);
      expect(totals.isEmpty, isTrue);
    });

    test('tutarsız hatırlatmalar atlanır', () {
      final noAmount = Reminder.create(
        categoryId: 'fatura',
        title: 'Tutarsız',
        dueDate: DateTime(2026, 8, 1),
        leadDays: const [0],
        notifyHour: 9,
        notifyMinute: 0,
        repeat: RepeatInterval.monthly,
      );
      expect(PaymentTotals.from([noAmount]).isEmpty, isTrue);
    });
  });

  group('tekrar hatırlatma (nag)', () {
    test('nag aralığı son gün içinde ek bildirimler üretir', () {
      final due = DateTime.now().add(const Duration(days: 2));
      final reminder = Reminder.create(
        categoryId: 'fatura',
        title: 'Kira',
        dueDate: DateTime(due.year, due.month, due.day),
        leadDays: const [0],
        notifyHour: 9,
        notifyMinute: 0,
        nagIntervalHours: 3,
        repeat: RepeatInterval.none,
      );

      final times = reminder.upcomingNotificationTimes();
      // 09:00 (asıl) + 12:00, 15:00, 18:00, 21:00 (tekrarlar)
      expect(times.length, greaterThan(1));
      expect(times.first.hour, 9);
      // Hiçbiri ertesi güne taşmamalı.
      expect(times.every((t) => t.day == due.day), isTrue);
    });

    test('nag kapalıyken yalnızca asıl bildirim kurulur', () {
      final due = DateTime.now().add(const Duration(days: 2));
      final reminder = Reminder.create(
        categoryId: 'fatura',
        title: 'Kira',
        dueDate: DateTime(due.year, due.month, due.day),
        leadDays: const [0],
        notifyHour: 9,
        notifyMinute: 0,
        repeat: RepeatInterval.none,
      );
      expect(reminder.upcomingNotificationTimes().length, 1);
    });
  });
}
